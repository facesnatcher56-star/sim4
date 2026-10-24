class_name Involve
extends RefCounted
## Task 66: the involvement director, never shown (data/director.json). The town runs on its own (TownLife); this keeps the player in it. While the
## pawn is awake and free with nothing open, each game hour raises the chance that something in the town touches them; it picks from a pool of
## real situations (people they know first, ripples of what happened to their friends), and resets when one lands. It only ever tilts the odds of
## real things done by real people: a visit, a favour, a scene where they are, the neighbour's party, the background's next moment, someone angry
## with them, someone they helped, the police asking about what they saw. Never while a prompt is open; at most max_open things open at once.
##   Involve.on_hour(h)   Involve.landed(what, people)   Involve.open_count(f)   Involve.log (every pull, for the 66 log)   reset() / to_dict() / from_dict()

static var pressure: float = 0.0
static var last_pull: int = -100000
static var idle_since: int = -1            # the minute the pawn last had nothing open (-1 = something open now)
static var longest_idle: int = 0           # minutes, awake with nothing open (the 66 log)
static var log: Array = []                 # [{min, what, people}]
static var _thanked: Dictionary = {}       # townie id -> true
static var _asked: Dictionary = {}         # "questions|tid" -> true
static var _kind_at: Dictionary = {}       # kind -> minute it last landed (cooldown_h per kind)
static var _person_at: Dictionary = {}     # townie id -> minute they were last in a pull (person_gap_h)

static func reset() -> void:
	pressure = 0.0
	last_pull = -100000
	idle_since = -1
	longest_idle = 0
	log = []
	_thanked = {}
	_asked = {}
	_kind_at = {}
	_person_at = {}

static func cfg() -> Dictionary:
	return SysUtil.table("director")

static func _line(k: String, v: Dictionary) -> String:
	var ls: Array = (cfg().get("lines", {}) as Dictionary).get(k, [""])
	var t: String = str(ls[PlayerPrompt._pick("involve|" + k, ls.size())])
	for key in v:
		t = t.replace("{%s}" % key, str(v[key]))
	return t

## Not in a pull lately (variety: the same person does not lose a wallet, ask for money and come to thank you in one afternoon).
static func fresh(tid: int) -> bool:
	return SysUtil.now() - int(_person_at.get(tid, -100000)) >= int(float(cfg().get("person_gap_h", 20)) * 60.0)

## Something reached the player (a pull, or a town event that happened in front of them): the pressure resets.
static func landed(what: String, people: Array = []) -> void:
	pressure = 0.0
	last_pull = SysUtil.now()
	for p in people:
		if int(p) >= 0:
			_person_at[int(p)] = SysUtil.now()
	log.append({"min": SysUtil.now(), "what": what, "people": people.filter(func(p): return int(p) >= 0).map(func(p): return Story.name_of(int(p)))})
	while log.size() > 200:
		log.pop_front()
	SysUtil.game_event("involve_pull", {"what": what})

# ------------------------------------------------------------------ what is open
static func open_count(f) -> int:
	var n: int = JusticePlayer.open
	var now: int = SysUtil.now()
	if now - last_pull < int(cfg().get("settle_min", 45)):
		n += 1
	if StreetScenes.busy():
		n += 1
	for sit in Story.situations:
		if str(sit["state"]) in ["door", "arrive", "mingle"] and (sit["host_ids"] as Array).has(int(f.id)):
			n += 1
	var soon: int = int(cfg().get("soon_hours", 3)) * 60
	for a in JobApps.pending(int(f.id)):
		if str(a["state"]) in ["interview", "in_scene"] and int(a["iv_min"]) - now < soon:
			n += 1
	if not SoloOpening.checkin.is_empty() and int(SoloOpening.checkin.get("day", -1)) == SysUtil.day():
		n += 1
	for b in Economy.outstanding(int(f.household_id)):
		if bool(b.get("late", false)):
			n += 1
			break
	return n

# ------------------------------------------------------------------ the clock
static func on_hour(_h: int) -> void:
	if not SoloHome.active or Pawn.of() < 0:
		return
	var f = SysUtil.folk(Pawn.of())
	var now: int = SysUtil.now()
	if f == null or CrimePlace.is_asleep(f) or SysUtil.is_away(f) or JusticeState.inmates.has(int(f.id)):
		idle_since = -1          # asleep, at work, away, held: not the player's idle time
		return
	var open: int = open_count(f)
	if open > 0:
		if idle_since >= 0:
			longest_idle = maxi(longest_idle, now - idle_since)
		idle_since = -1
		return
	if idle_since < 0:
		idle_since = now
	longest_idle = maxi(longest_idle, now - idle_since)
	if JusticePlayer.open > 0 or open >= int(cfg().get("max_open", 2)):
		return
	pressure = minf(pressure + float(cfg().get("pressure_step", 0.4)), 1.0)
	if SysUtil.rng.randf() >= pressure:
		return
	if _pull(f):
		longest_idle = maxi(longest_idle, now - idle_since)
		idle_since = -1

## Try the pool by weight (early game and connections count); the first kind that really lands wins.
static func _pull(f) -> bool:
	var pool: Dictionary = cfg().get("pool", {})
	var early: bool = SysUtil.day() - SoloOpening.start_day < int(cfg().get("early_days", 7))
	var kinds: Array = []
	var ws: Array = []
	for k in pool:
		var e: Dictionary = pool[k]
		if SysUtil.now() - int(_kind_at.get(str(k), -100000)) < int(float(e.get("cooldown_h", 0)) * 60.0):
			continue
		kinds.append(str(k))
		ws.append(float(e.get("weight", 1.0)) * (float(e.get("early", 1.0)) if early else 1.0) * float(e.get("connect", 1.0)))
	while not kinds.is_empty():
		var k2 = SysUtil.pick_weighted(kinds, ws)
		var i: int = kinds.find(k2)
		kinds.remove_at(i)
		ws.remove_at(i)
		var r: Dictionary = _try(str(k2), f)
		if not r.is_empty():
			_kind_at[str(k2)] = SysUtil.now()
			if bool(r.get("lands", true)):
				landed(str(k2) + (": " + str(r["what"]) if r.has("what") else ""), r.get("people", []))
				return true
	return false

## One kind: {} when it has no real cause right now, else {what, people, lands}.
static func _try(kind: String, f) -> Dictionary:
	var pid: int = int(f.id)
	var lot: String = Neighborhood.lot_of(f)
	var home: bool = lot == Neighborhood.HOME
	var h: float = SysUtil.hour_f()
	match kind:
		"visit":
			if not home or h < 9.0 or h >= 21.0:
				return {}
			var tid: int = _known(pid, 5.0, true)
			if tid < 0 and _can_come(SoloOpening.neighbour):
				tid = SoloOpening.neighbour
			if tid < 0:
				return {}
			StoryVisits.schedule_visit([tid], pid, SysUtil.now() + 15, SysUtil.rng.randi_range(60, 120), "visit")
			return {"people": [tid]}
		"favour":
			return {"people": []} if DailyHook.favour(f) else {}
		"call":
			return _call(f)
		"ripple":
			var rp: Dictionary = TownLife.ripple(pid)
			if rp.is_empty() or not DailyHook.favour(f, int(rp["tid"]), "favour_ripple"):
				return {}
			return {"what": str(rp["kind"]), "people": [int(rp["tid"])]}
		"wallet":
			return {"people": []} if not home and DailyHook.wallet(f) else {}
		"scene":
			return {"people": []} if not home and lot != "" and StreetScenes.play(f, lot) else {}
		"party":
			return {"people": [SoloOpening.neighbour]} if StreetScenes.party(f) else {}
		"background":
			var bs: Array = SoloOpening.beats(pid)
			if bs.is_empty() or not SoloOpening.fire_beat(pid, str(bs[0])):
				return {}
			return {"what": str(bs[0])}
		"grudge":
			return _grudge(f, home) if h >= 9.0 and h < 21.0 else {}
		"approach":
			return _approach(f)
		"neighbourly":
			return _neighbourly(f) if home and h >= 9.0 and h < 21.0 else {}
		"thanks":
			return _thanks(f)
		"questions":
			return _questions(f)
		"problem":
			return {"lands": false} if DailyHook.problem(f) else {}
	return {}

## The townie the pawn knows best (friendship >= at_least) who is free and not in a pull lately, else -1. come = they can walk over now
## (not on the map somewhere, not visited today).
static func _known(pid: int, at_least: float, come: bool = false) -> int:
	var best: int = -1
	var best_v: float = at_least
	for t in Story.free_townies():
		var tid: int = int(t["id"])
		var v: float = RelationshipService.value(pid, tid, "friendship")
		if v >= best_v and StreetScenes._free(tid) and fresh(tid) and (not come or _can_come(tid)):
			best_v = v
			best = tid
	return best

static func _can_come(tid: int) -> bool:
	if tid < 0 or not Story.townies.has(tid) or not StreetScenes._free(tid) or not fresh(tid) or int(Story.townies[tid].get("last_visit_day", -99)) == SysUtil.day():
		return false
	var on = SysUtil.folk(tid)
	return on == null or on.has_meta("crowd")          # at home, or out at a venue (they leave it to come over: StoryVisits)

## Someone who lives nearby knocks for an ordinary reason (to borrow something, a parcel left with them, a lost cat): no friendship needed.
static func _neighbourly(f) -> Dictionary:
	var pid: int = int(f.id)
	var best: int = -1
	var best_d: float = 1.0e9
	var home: Vector2i = Neighborhood.entry_tile(Neighborhood.HOME)
	for t in Story.free_townies():
		var tid: int = int(t["id"])
		var hl: String = Neighborhood.home_of_townie(tid)
		if hl == "" or Story.stage_of(t) not in ["adult", "elder"] or not _can_come(tid):
			continue
		var d: float = float((Neighborhood.entry_tile(hl) - home).length_squared())
		if d < best_d:
			best_d = d
			best = tid
	if best < 0:
		return {}
	var sit: Dictionary = StoryVisits.schedule_visit([best], pid, SysUtil.now() + 10, 25, "visit")
	sit["line"] = _line("neighbourly", {"n": Story.name_of(best).get_slice(" ", 0)})
	return {"people": [best]}

## A friend rings: fancy meeting up somewhere that is open now? Yes = a real meet-up at that place (NeighborhoodService.invite_to_venue).
static func _call(f) -> Dictionary:
	var pid: int = int(f.id)
	if PhoneOwn.block(pid) != "" or SysUtil.hour_f() < 10.0 or SysUtil.hour_f() >= 21.0:
		return {}
	var tid: int = _known(pid, 10.0)
	if tid < 0:
		return {}
	var places: Array = ["cafe", "park", "gym"].filter(func(l): return Neighborhood.lot_ids().has(l) and Venues.is_open(l, SysUtil.now() + 60))
	if places.is_empty():
		return {}
	var lot: String = str(places[SysUtil.rng.randi_range(0, places.size() - 1)])
	var v: Dictionary = {"n": Story.name_of(tid).get_slice(" ", 0), "place": Neighborhood.label_of(lot)}
	JusticePlayer.ask(pid, "Your phone", _line("call", v), [{"id": "yes", "label": "See you there"}, {"id": "no", "label": "Not today"}],
		func(ch):
			if str(ch) == "yes":
				NeighborhoodService.invite_to_venue(tid, pid, lot, 45, 120)
			else:
				RelationshipService.add_both(pid, tid, "friendship", -1.0), "no")
	return {"people": [tid]}

static func _grudge(f, home: bool) -> Dictionary:
	var pid: int = int(f.id)
	var who: int = -1
	for t in Story.free_townies():
		var tid: int = int(t["id"])
		if RelationshipService.value(tid, pid, "friendship") <= -10.0 and StreetScenes._free(tid) and fresh(tid) and (not home or _can_come(tid)):
			who = tid
			break
	if who < 0:
		return {}
	var v: Dictionary = {"n": Story.name_of(who).get_slice(" ", 0)}
	if home:
		var sit: Dictionary = StoryVisits.schedule_visit([who], pid, SysUtil.now() + 10, 30, "visit")
		sit["line"] = _line("grudge_door", v)
		return {"what": "at the door", "people": [who]}
	if Neighborhood.lot_of(f) == "":
		return {}
	StreetScenes._bring(who, Neighborhood.lot_of(f), f.tile + Vector2i(2, 1))
	JusticePlayer.ask(pid, StreetScenes.TITLE, _line("grudge_out", v),
		[{"id": "sorry", "label": "Apologise"}, {"id": "stand", "label": "Stand your ground"}, {"id": "walk", "label": "Walk off"}],
		func(ch):
			if str(ch) == "sorry":
				RelationshipService.add_both(pid, who, "friendship", 8.0)
				RelationshipService.add_value(who, pid, "tension", -25.0)
				SysUtil.notify(_line("grudge_sorry", v), "story")
			elif str(ch) == "stand":
				RelationshipService.add_both(pid, who, "friendship", -5.0)
				RelationshipService.add_value(who, pid, "tension", 15.0)
				SysUtil.notify(_line("grudge_stand", v), "bad"), "walk")
	return {"what": "out", "people": [who]}

## Someone on the same lot right now comes over: a friend says hello, an acquaintance asks how it's going, a stranger strikes up a conversation.
## The most ordinary pull there is, and always real: the person is standing there.
static func _approach(f) -> Dictionary:
	var lot: String = Neighborhood.lot_of(f)
	if lot == "" or lot == Neighborhood.HOME:
		return {}
	var pid: int = int(f.id)
	var best = null
	var best_d: float = 18.0
	for p in Crowd.crowd_folk(lot):
		var tid: int = int(p.get_meta("townie_id", -1))
		if tid < 0 or p.has_meta("leaving") or not fresh(tid) or Story.stage_of(Story.townies.get(tid, {})) not in ["adult", "elder", "teen"]:
			continue
		var d: float = (p.tile - f.tile).length()
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		return {}
	var tid2: int = int(best.get_meta("townie_id"))
	var fr: float = RelationshipService.value(tid2, pid, "friendship")
	var key: String = "approach_friend" if fr >= 20.0 else ("approach_known" if RelationshipService.knows(pid, tid2) else "approach_stranger")
	var v: Dictionary = {"n": str(best.name).get_slice(" ", 0)}
	best.clear_queue()
	var go := Interaction.create_goto(best, Crowd.free_near(f.tile + Vector2i(1, 1)), false)
	if go != null:
		go.def = go.def.duplicate(true)
		go.def["priority"] = "high"
		best.enqueue(go)
	JusticePlayer.ask(pid, StreetScenes.TITLE, _line(key, v), [{"id": "talk", "label": "Talk"}, {"id": "no", "label": "Excuse yourself"}],
		func(ch):
			if str(ch) == "talk":
				var chat := Interaction.create("chat", f, int(best.id), true)
				if chat != null:
					f.enqueue(chat)
			else:
				RelationshipService.add_both(pid, tid2, "friendship", -1.0), "no")
	return {"people": [tid2]}

## Someone the pawn stood up for, comforted, helped up or lent money to comes back to say thanks.
static func _thanks(f) -> Dictionary:
	var pid: int = int(f.id)
	for t in Story.free_townies():
		var tid: int = int(t["id"])
		if _thanked.has(tid) or not StreetScenes._free(tid) or not fresh(tid):
			continue
		var helped: bool = RelationshipService.history_for(pid, tid).any(func(e): return str(e.get("kind", "")) == "stepped_in" and float(e.get("sentiment", 0.0)) > 0.3 and int(e.get("day", 99)) < SysUtil.day())
		if not helped:
			continue
		_thanked[tid] = true
		var v: Dictionary = {"n": Story.name_of(tid).get_slice(" ", 0)}
		JusticePlayer.ask(pid, "A thank-you", _line("thanks", v), [{"id": "yes", "label": "Go for that coffee"}, {"id": "no", "label": "Not now"}],
			func(ch):
				if str(ch) == "yes":
					RelationshipService.add_both(pid, tid, "friendship", 8.0)
					SysUtil.notify(_line("thanks_yes", v), "relationship"), "no")
		return {"people": [tid]}
	return {}

## The pawn watched something the police are looking into: an officer asks what they saw.
static func _questions(f) -> Dictionary:
	var pid: int = int(f.id)
	for c in CaseStore.open_cases():
		var cul: int = int(c.get("culprit", -1))
		if cul < 0 or _asked.has("q|%d" % int(c["id"])):
			continue
		var saw: bool = RelationshipService.history_for(pid, cul).any(func(e): return str(e.get("kind", "")) == "saw_scene" and SysUtil.day() - int(e.get("day", -99)) <= 5)
		if not saw:
			continue
		_asked["q|%d" % int(c["id"])] = true
		var v: Dictionary = {"a": Story.name_of(cul).get_slice(" ", 0)}
		JusticePlayer.ask(pid, "The police", _line("questions", v), [{"id": "tell", "label": "Tell them what you saw"}, {"id": "quiet", "label": "Say you saw nothing"}],
			func(ch):
				if str(ch) == "tell":
					c["tips"] = minf(float(c.get("tips", 0.0)) + 0.3, 0.9)
					CaseStore.note(c, "A witness, %s, told the police what they saw." % str(f.name), "", 1, false)
					RelationshipService.add_both(pid, cul, "friendship", -6.0)
					SysUtil.notify(_line("questions_tell", v), "story")
				else:
					SysUtil.notify(_line("questions_quiet", v), "story"), "quiet")
		return {"people": [cul]}
	return {}

static func to_dict() -> Dictionary:
	return {"pressure": pressure, "last": last_pull, "thanked": _thanked.keys(), "asked": _asked.keys()}

static func from_dict(d: Dictionary) -> void:
	reset()
	pressure = float(d.get("pressure", 0.0))
	last_pull = int(d.get("last", -100000))
	for k in d.get("thanked", []):
		_thanked[int(k)] = true
	for k2 in d.get("asked", []):
		_asked[str(k2)] = true
