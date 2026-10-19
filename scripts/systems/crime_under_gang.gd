class_name CrimeUnderGang
extends RefCounted
## Task 23: CRIME FAMILIES AND GANGS. A gang has a boss, ranked members (associate, soldier, lieutenant, boss by STANDING), territory (the dealing
## corners), loyalty and betrayal. Townie crews form from path members of the right rank; a player's folk is recruited, can rise (or challenge the boss)
## and can leave (traitor), turn informant or enter protection. WARS between gangs are rare: each war day writes violence into the town CRIME RATE
## (kind `gang_violence`), may cost lives or freedom, and ends by exhaustion or a police crackdown; the rate then decays with the 28-day window.
## Police busts follow tips (betrayals, informants, undercover evidence). Tier: gangs are a tiny table; everything is the daily pass or an instant command.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("gang")

static func get_gang(gid: int) -> Dictionary:
	return CrimeUnderState.gangs.get(gid, {})

static func ids() -> Array:
	var out: Array = CrimeUnderState.gangs.keys()
	out.sort()
	return out

static func of(pid: int) -> int:
	for gid in ids():
		for m in CrimeUnderState.gangs[gid]["members"]:
			if int(m["pid"]) == pid:
				return int(gid)
	return -1

static func member(gid: int, pid: int) -> Dictionary:
	for m in get_gang(gid).get("members", []):
		if int(m["pid"]) == pid:
			return m
	return {}

static func rank_of(gid: int, pid: int) -> Dictionary:
	var m: Dictionary = member(gid, pid)
	if m.is_empty():
		return {}
	var best: Dictionary = {}
	for r in cfg().get("ranks", []):
		if float(m.get("standing", 0.0)) >= float(r["standing"]):
			best = r
	return best

static func rank_label(pid: int) -> String:
	var gid: int = of(pid)
	return str(rank_of(gid, pid).get("label", "")) if gid >= 0 else ""

static func size(gid: int) -> int:
	return (get_gang(gid).get("members", []) as Array).size()

## Fighting strength a person brings to a scrap (0..0.25), from the crew behind them.
static func muscle(pid: int) -> float:
	var gid: int = of(pid)
	if gid < 0:
		return 0.0
	return minf(float(size(gid)) * 0.04, 0.25)

# ------------------------------------------------------------------ making and joining
static func found(boss: int, name: String = "") -> int:
	var k: Dictionary = cfg()
	if of(boss) >= 0 or not CrimeLifePath.is_member(boss) or CrimeUnderState.gangs.size() >= int(k.get("max_gangs", 3)):
		return -1
	var names: Array = k.get("names", ["the Crew"])
	if name == "":
		var used: Array = CrimeUnderState.gangs.values().map(func(g): return str(g["name"]))
		for n in names:
			if not used.has(str(n)):
				name = str(n)
				break
		if name == "":
			name = "the Third Street crew"
	var g: Dictionary = {"id": CrimeUnderState.next_gang, "name": name, "boss": boss, "members": [], "territory": [], "war": {}, "strength": 1.0, "day": SysUtil.day(), "tips": 0.0}
	CrimeUnderState.next_gang += 1
	CrimeUnderState.gangs[int(g["id"])] = g
	add_member(int(g["id"]), boss, 80.0)
	CrimeUnderState.count("gang_founded")
	ChronicleHook.note("gang", "%s is said to be running things on the wrong side of town." % name.capitalize() if name.begins_with("the") else name, [boss], "", 2, true)
	return int(g["id"])

static func add_member(gid: int, pid: int, standing: float = 0.0) -> bool:
	var g: Dictionary = get_gang(gid)
	if g.is_empty() or of(pid) >= 0 or (g["members"] as Array).size() >= int(cfg().get("max_members", 7)):
		return false
	(g["members"] as Array).append({"pid": pid, "standing": standing, "loyal": float(cfg().get("loyalty", {}).get("start", 0.6)), "since": SysUtil.day()})
	CrimeLifePath.add_cred(pid, float(cfg().get("cred_join", 3.0)), "gang")
	return true

static func join(pid: int, gid: int) -> Dictionary:
	if of(pid) >= 0:
		return {"ok": false, "msg": "Already in a crew."}
	if get_gang(gid).is_empty():
		return {"ok": false, "msg": "No such crew."}
	if CrimeLifePath.cred(pid) < float(cfg().get("join_cred", 22.0)):
		return {"ok": false, "msg": "They don't know you well enough to let you in."}
	if CrimeUnderState.protected.get(pid, -1) >= SysUtil.day():
		return {"ok": false, "msg": "Not while in protection."}
	if not add_member(gid, pid):
		return {"ok": false, "msg": "They have no room."}
	var m: Dictionary = member(gid, pid)
	m["loyal"] = float(cfg().get("loyalty", {}).get("player_base", 0.7)) if CrimePerson.is_player(pid) else m["loyal"]
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s is in with %s." % [CrimePerson.name_of(pid), str(get_gang(gid)["name"])], "story")
	return {"ok": true, "msg": ""}

static func remove(pid: int) -> void:
	var gid: int = of(pid)
	if gid < 0:
		return
	var g: Dictionary = get_gang(gid)
	var keep: Array = []
	for m in g["members"]:
		if int(m["pid"]) != pid:
			keep.append(m)
	g["members"] = keep
	if int(g["boss"]) == pid:
		_succession(g)

static func _succession(g: Dictionary) -> void:
	var best: Dictionary = {}
	for m in g["members"]:
		if best.is_empty() or float(m["standing"]) > float(best["standing"]):
			best = m
	if best.is_empty():
		CrimeUnderState.gangs.erase(int(g["id"]))
		CrimeUnderState.count("gang_ended")
		return
	g["boss"] = int(best["pid"])
	best["standing"] = maxf(float(best["standing"]), 60.0)

## Leaving is betrayal: the crew may put a price on a leaver who knows too much.
static func leave(pid: int, why: String = "left") -> Dictionary:
	var gid: int = of(pid)
	if gid < 0:
		return {"ok": false, "msg": "Not in a crew."}
	var g: Dictionary = get_gang(gid)
	var boss: int = int(g["boss"])
	remove(pid)
	CrimeLifePath.add_cred(pid, -8.0 if why == "left" else -2.0, "left_crew")
	if boss != pid and CrimePerson.alive(boss) and why == "left" and CrimeUnderState.chance(float(cfg().get("leave_traitor", 0.3))):
		CrimeUnderHit.post(boss, pid, "traitor")
		if CrimePerson.is_player(pid):
			SysUtil.notify("Word is that %s doesn't take leaving well." % CrimePerson.name_of(boss), "warn")
	return {"ok": true, "msg": "%s walks away from the crew." % CrimePerson.name_of(pid)}

## Take the top place: a lieutenant or better challenges the boss.
static func challenge(pid: int) -> Dictionary:
	var gid: int = of(pid)
	if gid < 0:
		return {"ok": false, "msg": "Not in a crew."}
	var g: Dictionary = get_gang(gid)
	var boss: int = int(g["boss"])
	if boss == pid or str(rank_of(gid, pid).get("id", "")) not in ["lieutenant", "boss"]:
		return {"ok": false, "msg": "You aren't high enough to try."}
	var k: Dictionary = cfg()
	var bm: Dictionary = member(gid, boss)
	var p: float = float(k.get("challenge_base", 0.3)) + (CrimeLifePath.cred(pid) - CrimeLifePath.cred(boss)) * float(k.get("challenge_cred", 0.004)) \
		+ (float(member(gid, pid)["standing"]) - float(bm.get("standing", 60.0))) * 0.004 + (float(member(gid, pid)["loyal"]) - float(bm.get("loyal", 0.5))) * 0.2
	CrimeUnderState.count("gang_challenge")
	if CrimeUnderState.chance(clampf(p, 0.05, 0.9)):
		g["boss"] = pid
		member(gid, pid)["standing"] = maxf(float(member(gid, pid)["standing"]), 60.0)
		bm["standing"] = 40.0
		bm["loyal"] = float(bm.get("loyal", 0.5)) * 0.5
		if CrimePerson.is_player(pid):
			SysUtil.notify("%s is the new boss of %s." % [CrimePerson.name_of(pid), str(g["name"])], "story")
		ChronicleHook.note("gang", "%s has taken over %s." % [CrimePerson.name_of(pid), str(g["name"])], [pid], "", 2, true)
		return {"ok": true, "msg": "Took the top place.", "won": true}
	var f = CrimePerson.folk(pid)
	if f != null and CrimeUnderState.chance(0.5):
		Health.injure(f, 1, "a beating")
	remove(pid)
	if CrimePerson.alive(boss) and CrimeUnderState.chance(0.3):
		CrimeUnderHit.post(boss, pid, "traitor")
	return {"ok": true, "msg": "The challenge failed. You are out.", "won": false}

# ------------------------------------------------------------------ money
## A member's takings pay dues to the boss (instant, called by the trades).
static func dues(pid: int, earned: int) -> void:
	var gid: int = of(pid)
	if gid < 0 or earned <= 0:
		return
	var g: Dictionary = get_gang(gid)
	var boss: int = int(g["boss"])
	var m: Dictionary = member(gid, pid)
	m["standing"] = float(m["standing"]) + float(cfg().get("standing_job", 1.0)) * 0.3
	m["loyal"] = minf(float(m["loyal"]) + float(cfg().get("loyalty", {}).get("paid", 0.01)), 1.0)
	if boss == pid:
		return
	var due: int = maxi(int(float(earned) * 0.1), 1)
	var paid: int = CrimePerson.pay(pid, due, "dues")
	if paid > 0:
		CrimePerson.add_coins(boss, paid, "dues")

static func dealer_lost(pid: int) -> void:
	var gid: int = of(pid)
	if gid >= 0:
		var g: Dictionary = get_gang(gid)
		g["tips"] = float(g.get("tips", 0.0)) + 0.5

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	var k: Dictionary = cfg()
	_clean()
	_found_dice(k)
	for gid in ids():
		var g: Dictionary = CrimeUnderState.gangs[gid]
		_loyalty(g, k)
		_recruit(g, k)
		_territory(g)
		_income(g, k)
		_boss_orders(g)
	_war_day(k)
	_bust_dice(k)
	_offers(k)
	_informants(k)

static func _clean() -> void:
	for gid in ids():
		var g: Dictionary = CrimeUnderState.gangs[gid]
		var keep: Array = []
		for m in g["members"]:
			if CrimePerson.alive(int(m["pid"])):
				keep.append(m)                      # locked up members stay theirs; loyalty falls while the boss is away
		g["members"] = keep
		if keep.is_empty():
			CrimeUnderState.gangs.erase(gid)
			continue
		if not CrimePerson.alive(int(g["boss"])):
			_succession(g)

static func _found_dice(k: Dictionary) -> void:
	if CrimeUnderState.gangs.size() >= int(k.get("max_gangs", 3)) or not CrimeUnderState.chance(float(k.get("found_daily", 0.01)) * CrimeRate.crime_mult()):
		return
	var need: int = CrimeLifePath.rank_index_of_id(str(k.get("found_rank", "crew_boss")))
	var founders: Array = []
	var others: Array = []
	for pid in CrimeLifeState.members.keys():
		var p: int = int(pid)
		if CrimePerson.is_player(p) or of(p) >= 0 or not CrimePerson.alive(p) or CrimePerson.in_custody(p):
			continue
		if CrimeLifePath.rank_index(p) >= need:
			founders.append(p)
		elif CrimeLifePath.rank_index(p) >= 1:
			others.append(p)
	founders.sort()
	others.sort()
	if founders.is_empty() or others.size() < int(k.get("min_members", 2)) - 1:
		return
	var boss: int = int(founders[CrimeUnderState.rng.randi_range(0, founders.size() - 1)])
	var gid: int = found(boss)
	if gid < 0:
		return
	for o in others.slice(0, int(k.get("min_members", 2)) + 1):
		add_member(gid, int(o))

static func _recruit(g: Dictionary, k: Dictionary) -> void:
	if size(int(g["id"])) >= int(k.get("max_members", 7)) or not CrimeUnderState.chance(float(k.get("recruit_daily", 0.03))):
		return
	var pool: Array = []
	for pid in CrimeLifeState.members.keys():
		var p: int = int(pid)
		if not CrimePerson.is_player(p) and of(p) < 0 and CrimePerson.alive(p) and not CrimePerson.in_custody(p) and CrimeLifePath.cred(p) >= float(k.get("join_cred", 22.0)) * 0.6 \
				and not bool(CrimeLifeState.members[pid].get("snitch", false)):
			pool.append(p)
	pool.sort()
	if not pool.is_empty():
		add_member(int(g["id"]), int(pool[CrimeUnderState.rng.randi_range(0, pool.size() - 1)]))

static func _loyalty(g: Dictionary, k: Dictionary) -> void:
	var lc: Dictionary = k.get("loyalty", {})
	var boss_in: bool = CrimePerson.in_custody(int(g["boss"]))
	for m in g["members"].duplicate():
		var pid: int = int(m["pid"])
		m["standing"] = float(m["standing"]) + float(k.get("standing_day", 0.15))
		m["loyal"] = clampf(float(m["loyal"]) - float(lc.get("cut_day", 0.004)) + (float(lc.get("boss_jailed", -0.25)) * 0.05 if boss_in else 0.0), 0.0, 1.0)
		if pid != int(g["boss"]) and float(m["loyal"]) < float(lc.get("betray_below", 0.28)) and CrimeUnderState.chance(float(lc.get("betray_daily", 0.01))):
			_betray(g, m)
	# a leaderless (jailed) boss loses the crew's respect slowly; nothing else to do here

static func _betray(g: Dictionary, m: Dictionary) -> void:
	var pid: int = int(m["pid"])
	g["tips"] = float(g.get("tips", 0.0)) + float(cfg().get("informant", {}).get("bust_tip", 0.25)) * 2.0
	CrimeUnderState.count("gang_betrayal")
	var lm: Dictionary = CrimeLifePath.member(pid)
	if not lm.is_empty():
		lm["snitch"] = true
	remove(pid)
	if CrimePerson.alive(int(g["boss"])) and CrimeUnderState.chance(0.35):
		CrimeUnderHit.post(int(g["boss"]), pid, "traitor")

static func _territory(g: Dictionary) -> void:
	var t: Array = []
	for cid in CrimeUnderState.corners:
		var o: int = int(CrimeUnderState.corners[cid].get("owner", -1))
		if o >= 0 and of(o) == int(g["id"]) and float(CrimeUnderState.corners[cid].get("hold", 0.0)) > 0.05:
			t.append(cid)
	t.sort()
	g["territory"] = t

static func _income(g: Dictionary, k: Dictionary) -> void:
	var boss: int = int(g["boss"])
	if CrimePerson.alive(boss):
		CrimePerson.add_coins(boss, int(float(k.get("territory_income", 6.0)) * float((g["territory"] as Array).size())), "territory")

static func _boss_orders(g: Dictionary) -> void:
	var boss: int = int(g["boss"])
	if CrimePerson.is_player(boss) or not CrimePerson.alive(boss) or CrimePerson.in_custody(boss):
		return
	var p: float = float(CrimeUnderState.sect("hit").get("boss_daily", 0.0015)) * (6.0 if not (g.get("war", {}) as Dictionary).is_empty() else 1.0)
	if not CrimeUnderState.chance(p):
		return
	var rivals: Array = []
	for oid in ids():
		if int(oid) != int(g["id"]):
			for m in CrimeUnderState.gangs[oid]["members"]:
				rivals.append(int(m["pid"]))
	rivals.sort()
	if not rivals.is_empty():
		CrimeUnderHit.post(boss, int(rivals[CrimeUnderState.rng.randi_range(0, rivals.size() - 1)]), "gang")

# ------------------------------------------------------------------ wars
static func at_war() -> Array:
	var out: Array = []
	for gid in ids():
		var w: Dictionary = CrimeUnderState.gangs[gid].get("war", {})
		if not w.is_empty() and int(gid) < int(w["with"]):
			out.append(int(gid))
	return out

static func start_war(a: int, b: int) -> bool:
	var ga: Dictionary = get_gang(a)
	var gb: Dictionary = get_gang(b)
	if ga.is_empty() or gb.is_empty() or a == b or not (ga["war"] as Dictionary).is_empty() or not (gb["war"] as Dictionary).is_empty():
		return false
	var w: Array = cfg().get("war", {}).get("days", [8, 16])
	var until: int = SysUtil.day() + CrimeUnderState.range_i(w)
	ga["war"] = {"with": b, "since": SysUtil.day(), "until": until}
	gb["war"] = {"with": a, "since": SysUtil.day(), "until": until}
	CrimeUnderState.count("gang_war")
	ChronicleHook.note("gang_war", "Trouble between %s and %s has turned into open war on the streets." % [str(ga["name"]), str(gb["name"])], [], "", 3, true)
	for pid in _player_members(ga) + _player_members(gb):
		SysUtil.notify("The crews are at war. %s's name is in it now." % CrimePerson.name_of(pid), "bad")
	return true

static func _player_members(g: Dictionary) -> Array:
	var out: Array = []
	for m in g["members"]:
		if CrimePerson.is_player(int(m["pid"])):
			out.append(int(m["pid"]))
	return out

static func _war_day(k: Dictionary) -> void:
	var wc: Dictionary = k.get("war", {})
	var gs: Array = ids()
	if at_war().is_empty() and gs.size() >= 2 and CrimeUnderState.chance(float(wc.get("daily", 0.004)) * CrimeRate.crime_mult()):
		var a: int = int(gs[CrimeUnderState.rng.randi_range(0, gs.size() - 1)])
		var b: int = int(gs[(gs.find(a) + 1) % gs.size()])
		start_war(a, b)
	for aid in at_war():
		var ga: Dictionary = get_gang(aid)
		var gb: Dictionary = get_gang(int(ga["war"]["with"]))
		if gb.is_empty() or SysUtil.day() >= int(ga["war"]["until"]) or size(aid) < 2 or size(int(gb["id"])) < 2:
			end_war(aid, "burned out")
			continue
		if CrimeUnderState.chance(float(wc.get("truce_chance", 0.03))):
			end_war(aid, "truce")
			continue
		if CrimeUnderState.chance(float(wc.get("police_end", 0.06)) * Police.strength() * (CrimeRate.value() / 50.0)):
			end_war(aid, "crackdown")
			continue
		_violence(ga, gb, wc)

static func _violence(ga: Dictionary, gb: Dictionary, wc: Dictionary) -> void:
	var n: int = CrimeUnderState.range_i(wc.get("incidents_day", [1, 3]))
	for i in n:
		JusticeState.year_log.append({"day": SysUtil.day(), "kind": str(wc.get("points", "gang_violence")), "solved": false, "case": -1})
		CrimeUnderState.count("war_incident")
		var all: Array = []
		for g in [ga, gb]:
			for m in g["members"]:
				all.append(int(m["pid"]))
		all.sort()
		if all.is_empty():
			return
		var victim: int = int(all[CrimeUnderState.rng.randi_range(0, all.size() - 1)])
		if CrimePerson.is_player(victim):
			continue                                     # the player's folk is hurt only through the prompt below
		if CrimeUnderState.chance(float(wc.get("casualty", 0.04))):
			remove(victim)
			CrimeLifeState.members.erase(victim)
			CrimeUnderState.count("war_death")
			Aging.kill(victim, "gang_violence")
		elif CrimeUnderState.chance(float(wc.get("jail", 0.05))):
			var c: Dictionary = CaseStore.create("assault", victim, -1, "street", {"witnessed": true, "trace": 0.7})
			c["severity"] = 2
			c["state"] = "open"
			c["disc_day"] = SysUtil.day()
			JusticeProcess.arrest(c, victim)
	for pid in _player_members(ga) + _player_members(gb):
		_player_war(pid, wc)

static func _player_war(pid: int, wc: Dictionary) -> void:
	var gid: int = of(pid)
	var m: Dictionary = member(gid, pid)
	if SysUtil.day() - int(m.get("war_day", -99)) < int(wc.get("player_prompt_gap", 3)):
		return
	m["war_day"] = SysUtil.day()
	JusticePlayer.ask(pid, "The crews are at war", "Trouble has found %s. The crew expects them to stand with it." % CrimePerson.name_of(pid),
		[{"id": "fight", "label": "Stand with the crew"}, {"id": "hide", "label": "Keep your head down"}], _war_choice.bind(pid, wc), "hide")

static func _war_choice(ch, pid: int, wc: Dictionary) -> void:
	var m: Dictionary = member(of(pid), pid)
	if m.is_empty():
		return
	var f = CrimePerson.folk(pid)
	if str(ch) == "fight":
		CrimeLifePath.add_cred(pid, float(wc.get("player_cred", 1.5)), "war")
		m["standing"] = float(m["standing"]) + 2.0
		if f != null and CrimeUnderState.chance(float(wc.get("player_hurt", 0.15))):
			Health.injure(f, 1, "a street fight")
	else:
		m["standing"] = float(m["standing"]) - 1.0
		m["loyal"] = float(m["loyal"]) - 0.05

static func end_war(gid: int, how: String) -> void:
	var ga: Dictionary = get_gang(gid)
	if ga.is_empty() or (ga["war"] as Dictionary).is_empty():
		return
	var gb: Dictionary = get_gang(int(ga["war"]["with"]))
	ga["war"] = {}
	if not gb.is_empty():
		gb["war"] = {}
	var text: String = {"burned out": "The gang war has burned itself out.", "truce": "The crews have made a truce.", "crackdown": "A police crackdown has ended the gang war."}.get(how, "The gang war is over.")
	ChronicleHook.note("gang_war_end", text, [], "", 2, true)
	CrimeUnderState.count("war_end_" + how.replace(" ", "_"))

# ------------------------------------------------------------------ busts, offers, informants
static func _bust_dice(k: Dictionary) -> void:
	var b: Dictionary = k.get("bust", {})
	if SysUtil.day() - CrimeUnderState.last_bust_day < int(b.get("cooldown_days", 20)):
		return
	for gid in ids():
		var g: Dictionary = CrimeUnderState.gangs[gid]
		var p: float = (float(b.get("base", 0.002)) + float(g.get("tips", 0.0)) * float(b.get("per_tip", 0.04))) * Police.strength() * float(b.get("strength", 1.0))
		if CrimeUnderState.chance(minf(p, 0.5)):
			bust(int(gid))
			return
		g["tips"] = maxf(float(g.get("tips", 0.0)) - 0.05, 0.0)

## The police take down a gang: the boss and a share of the members are arrested for conspiracy.
static func bust(gid: int) -> int:
	var g: Dictionary = get_gang(gid)
	if g.is_empty():
		return 0
	var share: float = float(cfg().get("bust", {}).get("arrest_share", 0.6))
	var n: int = 0
	var list: Array = []
	for m in g["members"]:
		list.append(int(m["pid"]))
	list.sort()
	for pid in list:
		if (pid == int(g["boss"]) or CrimeUnderState.chance(share)) and CrimePerson.alive(pid) and not CrimePerson.in_custody(pid):
			if _holds_immunity(pid):
				continue
			var c: Dictionary = CaseStore.create("racket", pid, -1, "street", {"witnessed": true, "trace": 0.7})
			c["charge_hint"] = "conspiracy"
			c["state"] = "open"
			c["disc_day"] = SysUtil.day()
			CaseStore.note(c, "The police broke up %s." % str(g["name"]), "arrest", 3)
			JusticeProcess.arrest(c, pid)
			n += 1
	CrimeUnderState.last_bust_day = SysUtil.day()
	g["tips"] = 0.0
	CrimeUnderState.count("gang_bust")
	ChronicleHook.note("gang_bust", "The police have broken up %s: %d arrested." % [str(g["name"]), n], [], "", 3, true)
	return n

static func _holds_immunity(pid: int) -> bool:
	var inf: Dictionary = CrimeUnderState.informant.get(pid, {})
	return not inf.is_empty() and SysUtil.day() - int(inf.get("day", -999)) <= int(cfg().get("informant", {}).get("immunity_days", 20))

static func _offers(k: Dictionary) -> void:
	if CrimeUnderState.gangs.is_empty():
		return
	for f in SysUtil.residents():
		var pid: int = int(f.id)
		if of(pid) >= 0 or not CrimeLifePath.is_member(pid) or CrimeLifePath.cred(pid) < float(k.get("join_cred", 22.0)) or not CrimePerson.is_adult(pid):
			continue
		if SysUtil.day() - int(CrimeUnderState.offered_gang.get(pid, -999)) < int(k.get("offer_gap_days", 14)) or not CrimeUnderState.chance(0.1):
			continue
		CrimeUnderState.offered_gang[pid] = SysUtil.day()
		var gid: int = int(ids()[CrimeUnderState.rng.randi_range(0, ids().size() - 1)])
		JusticePlayer.ask(pid, "An offer from a crew", "%s's name has got round. %s are looking for people they can trust. Join them?" % [CrimePerson.name_of(pid), str(get_gang(gid)["name"]).capitalize()],
			[{"id": "join", "label": "Join them"}, {"id": "no", "label": "No thanks"}], func(ch): if str(ch) == "join": join(pid, gid), "no")

## A player informant may be exposed.
static func _informants(k: Dictionary) -> void:
	var ic: Dictionary = k.get("informant", {})
	for pid in CrimeUnderState.informant.keys():
		var inf: Dictionary = CrimeUnderState.informant[pid]
		if not CrimePerson.alive(int(pid)):
			CrimeUnderState.informant.erase(pid)
			continue
		if CrimeUnderState.chance(float(ic.get("exposed_daily", 0.02))) and not bool(inf.get("exposed", false)):
			inf["exposed"] = true
			var f = CrimePerson.folk(int(pid))
			if f != null and CrimeUnderState.chance(float(ic.get("exposed_hurt", 0.4))):
				Health.injure(f, 2, "an attack")
			var boss: int = int(get_gang(int(inf["gang"])).get("boss", -1))
			if boss >= 0 and CrimePerson.alive(boss) and boss != int(pid):
				CrimeUnderHit.post(boss, int(pid), "informant")
			if CrimePerson.is_player(int(pid)):
				SysUtil.notify("Someone worked out who has been talking to the police about %s." % str(get_gang(int(inf["gang"])).get("name", "the crew")), "bad")

## The player's folk (in a crew) talks to the police: a reward, short immunity, and the crew's trouble grows. Risk of exposure.
static func inform(pid: int) -> Dictionary:
	var gid: int = of(pid)
	if gid < 0 or CrimeUnderState.informant.has(pid):
		return {"ok": false, "msg": "Nothing to tell."}
	var ic: Dictionary = cfg().get("informant", {})
	var g: Dictionary = get_gang(gid)
	g["tips"] = float(g.get("tips", 0.0)) + float(ic.get("bust_tip", 0.25)) * 4.0
	CrimeUnderState.informant[pid] = {"gang": gid, "day": SysUtil.day(), "exposed": false}
	var reward: int = CrimeUnderState.range_i(ic.get("reward", [150, 450]))
	CrimePerson.add_coins(pid, reward, "an informant's fee")
	CrimeLifePath.add_cred(pid, float(ic.get("cred", -40.0)) * 0.25, "informing")
	CrimeUnderRep.deed(pid, "betray")
	CrimeUnderState.count("informant")
	return {"ok": true, "msg": "%s gives the detectives names (%d coins)." % [CrimePerson.name_of(pid), reward], "reward": reward}

## Witness protection: leave the crew, the lines and the path; the old world cannot reach them for a time.
static func protect(pid: int) -> Dictionary:
	if not CrimeUnderState.informant.has(pid):
		return {"ok": false, "msg": "Only a witness who has helped can be protected."}
	var ic: Dictionary = cfg().get("informant", {})
	remove(pid)
	CrimeUnderState.lines.erase(pid)
	if CrimeLifePath.is_member(pid):
		CrimeLifePath.leave(pid, "protected")
	CrimeUnderState.protected[pid] = SysUtil.day() + int(ic.get("protect_days", 56))
	CrimeUnderState.informant.erase(pid)
	for c in CrimeUnderHit.against(pid):
		c["state"] = "cancelled"
	CrimeUnderState.count("protected")
	return {"ok": true, "msg": "%s starts again somewhere nobody knows the name." % CrimePerson.name_of(pid)}
