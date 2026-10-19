class_name LeisureServices
extends RefCounted
## The handlers (PlaceHandlers) of the culture and leisure places:
##   perform       a set at the concert hall or a part in the play (args: skill, min_level, base, per_level, fame, label): pays by skill, can go wrong, adds fame
##   exhibit       the gallery buys the household's paintings at 1.5x the market price (args: kind, mult, fame, max)
##   score         bowling and the arcade: a score, a personal best, a town record on the wall (args: game, base, spread, label)
##   league_join / league_play / league_watch   the local league (LeagueState)
##   club_join / club_meet                      the community hall's clubs (ClubState)

static func check(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> String:
	var a: Dictionary = svc.get("args", {})
	var id: int = int(f.id)
	match handler:
		"perform":
			var lvl: int = f.skill_level(str(a.get("skill", "")))
			if lvl < int(a.get("min_level", 1)):
				return "Needs %s level %d (%s is at %d)." % [str(a.get("skill", "")), int(a.get("min_level", 1)), f.name, lvl]
		"exhibit":
			if MarketWork.craft_count(int(f.household_id), str(a.get("kind", "painting"))) <= 0:
				return "%s has no paintings to show." % f.name
		"league_join":
			if LeagueState.team_of(id) != "":
				return "%s already plays for the %s." % [f.name, LeagueState.team_label(LeagueState.team_of(id))]
		"league_play":
			if LeagueState.team_of(id) == "":
				return "Join a team first."
			if int(LeagueState.played.get(id, -1)) == SysUtil.day():
				return "%s already played today." % f.name
		"club_join":
			if ClubState.is_member(id, str(a.get("club", ""))):
				return "%s is already in the %s." % [f.name, ClubState.label(str(a.get("club", "")))]
		"club_meet":
			if not ClubState.is_member(id, str(a.get("club", ""))):
				return "Join the %s first." % ClubState.label(str(a.get("club", "")))
	return ""

static func finish(handler: String, f, pid: String, _sid: String, svc: Dictionary) -> Dictionary:
	var a: Dictionary = svc.get("args", {})
	var id: int = int(f.id)
	match handler:
		"perform":
			return _perform(f, pid, a)
		"exhibit":
			return _exhibit(f, a)
		"score":
			return _score(f, pid, a)
		"league_join":
			var team: String = LeagueState.join(id)
			return {"text": str(svc.get("text", "")).replace("{team}", LeagueState.team_label(team))}
		"league_play":
			LeagueState.played[id] = SysUtil.day()
			return {"text": str(svc.get("text", "")).replace("{team}", LeagueState.team_label(LeagueState.team_of(id)))}
		"league_watch":
			var t: Array = LeagueState.standings()
			return {"text": "%s watched the match. The %s lead the table." % [f.name, str(t[0]["label"])] if not t.is_empty() else ""}
		"club_join":
			ClubState.join(id, str(a.get("club", "")))
			return {"text": "%s joined the %s." % [f.name, ClubState.label(str(a.get("club", "")))]}
		"club_meet":
			var met: Array = ClubState.meet(id, str(a.get("club", "")))
			var names: Array = met.map(func(x): return Story.name_of(int(x)))
			return {"text": "%s went to the %s%s." % [f.name, ClubState.label(str(a.get("club", ""))), "" if names.is_empty() else " and got talking with " + " and ".join(names)]}
	return {}

static func _perform(f, pid: String, a: Dictionary) -> Dictionary:
	var pc: Dictionary = LifeFame.cfg().get("perform", {})
	var lvl: int = f.skill_level(str(a.get("skill", "")))
	var p: float = clampf(float(pc.get("success_base", 0.55)) + float(pc.get("success_per_level", 0.07)) * float(lvl - int(a.get("min_level", 1))), 0.1, 0.95)
	var ok: bool = LifeFame.rng.randf() < p
	var pay: int = int((float(a.get("base", 20)) + float(a.get("per_level", 10)) * float(lvl)) * (1.0 if ok else float(pc.get("fail_pay", 0.4))))
	Economy.deposit(int(f.household_id), pay, "performance: %s" % str(a.get("label", "set")))
	if ok:
		LifeFame.add(int(f.id), float(a.get("fame", 2.0)))
		f.add_buff("proud_performer")
		if lvl >= 6:
			LifeNote.say("performance", "%s wowed the audience at %s." % [f.name, Places.label(pid)], [int(f.id)], 1, false)
		return {"text": "%s played the %s well and earned %d coins." % [f.name, str(a.get("label", "set")), pay]}
	f.add_buff("embarrassed")
	return {"text": "%s fluffed the %s and was paid only %d coins." % [f.name, str(a.get("label", "set")), pay], "kind": "warn"}

static func _exhibit(f, a: Dictionary) -> Dictionary:
	var hid: int = int(f.household_id)
	var kind: String = str(a.get("kind", "painting"))
	var n: int = mini(MarketWork.craft_count(hid, kind), int(a.get("max", 3)))
	var skill: int = f.skill_level(str((MarketWork.cfg().get("crafts", {}) as Dictionary).get(kind, {}).get("skill", "painting")))
	var total := 0
	for _i in n:
		total += int(round(MarketWork.craft_price(kind, skill) * float(a.get("mult", 1.5))))
		MarketWork.sold_today[kind] = int(MarketWork.sold_today.get(kind, 0)) + 1
	MarketWork.crafts[hid][kind] = MarketWork.craft_count(hid, kind) - n
	Economy.deposit(hid, total, "gallery sale")
	LifeFame.add(int(f.id), float(a.get("fame", 2.0)) * float(n))
	if n >= 2:
		LifeNote.say("gallery_sale", "%s sold %d paintings at the Oak Street Gallery." % [f.name, n], [int(f.id)], 1, false)
	return {"text": "The gallery bought %d of %s's paintings for %d coins." % [n, f.name, total]}

static func _score(f, pid: String, a: Dictionary) -> Dictionary:
	var game: String = str(a.get("game", "bowling"))
	var raw: float = float(a.get("base", 60)) + LifeFame.rng.randf() * float(a.get("spread", 80))
	if game == "bowling":
		raw += HealthLife.meter(int(f.id), "fitness") * 0.3
	else:
		raw += float(f.skill_level("logic")) * 300.0
	var score: int = int(minf(raw, 300.0 if game == "bowling" else 99999.0))
	var r: Dictionary = LifeFame.note_score(int(f.id), game, score, str(f.name))
	var text := "%s scored %d at %s." % [f.name, score, str(a.get("label", game))]
	if bool(r["record"]):
		LifeNote.say("record", "%s set a new %s record: %d." % [f.name, str(a.get("label", game)), score], [int(f.id)], 1, true, "good")
		text += " A new record for the town!"
	elif bool(r["personal"]):
		text += " A personal best."
	return {"text": text}
