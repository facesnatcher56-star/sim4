class_name CruiseCrime
extends RefCounted
## Crime aboard (task 22), on the normal justice track (04 / 09 / 09b / 20): a case record with scene "ship:<trip>", kept SHIP-HELD
## (`ship_hold`, so the town police do not work it while the ship is at sea; hook in CaseInvestigation.work). Ship security investigates by
## itself (an hourly check, "fewer places to hide, fewer police"); the police take over at the next port (`handover`): the case is reported, an
## arrest made on board is processed (charges, trial) and the normal investigation continues in town.
##   CruiseCrime.open(trip, kind, culprit, victim, opts) -> case
##   CruiseCrime.security_hour(trip)              every hour while the ship sails
##   CruiseCrime.handover(trip, where)            at the next dock / the home quay

static func cfg() -> Dictionary:
	return (CruiseRoute.cfg().get("crime", {}) as Dictionary)

static func open(t: Dictionary, kind: String, culprit: int, victim: int, opts: Dictionary = {}) -> Dictionary:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	var vh: int = CrimePerson.hid(victim)
	var cs: Dictionary = CaseStore.create(kind, culprit, victim, "ship:%d" % int(t["id"]), {"vhid": vh, "trace": r.randf_range(0.2, 0.5), "witnessed": false,
		"stolen_coins": int(opts.get("coins", 0)), "loot_value": int(opts.get("coins", 0)), "serial": int(opts.get("serial", -1))})
	cs["ship_hold"] = true
	cs["ship_trip"] = int(t["id"])
	if not c.has("cases"):
		c["cases"] = []
	(c["cases"] as Array).append(int(cs["id"]))
	CrimePlace.place_at_scene(culprit, "ship:%d" % int(t["id"]))
	return cs

## A crime that is known at once (reported to the purser): state open, but still held by the ship.
static func report_aboard(t: Dictionary, cs: Dictionary, reporter: int, how: String) -> void:
	CaseDiscovery.report(cs, reporter, how)
	cs["ship_hold"] = true
	cs["security_since"] = SysUtil.now()

## Hourly: security works every open ship case; a good suspect is detained (the brig).
static func security_hour(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	for cid in c.get("cases", []):
		var cs: Dictionary = CaseStore.get_case(int(cid))
		if cs.is_empty() or not bool(cs.get("ship_hold", false)) or str(cs["state"]) != "open" or int(cs.get("detained", -1)) >= 0:
			continue
		var found: bool = bool(cs.get("found", true))
		var step: float = r.randf_range(0.03, 0.06) * (1.0 if found else 0.3) * (1.0 + 0.3 * float(c.get("killer", {}).get("victims", []).size()))
		cs["progress"] = minf(float(cs["progress"]) + step, 1.0)
		if not found:
			continue
		var rows: Array = CaseEvidence.suspects(cs, 2)
		if rows.is_empty():
			continue
		var top: Dictionary = rows[0]
		var bonus: float = 0.0
		if str(cs["kind"]) == "serial" and int(top["pid"]) == int(cs["culprit"]):
			bonus = 0.1 + 0.12 * float(c.get("killer", {}).get("victims", []).size())      # a small ship: everybody's movements are in the log
		if float(top["score"]) + float(cs["progress"]) * 0.2 + bonus >= 0.62 and r.randf() < float(CruiseRoute.cfg().get("killer", {}).get("security_find_chance", 0.18)) * 3.0:
			detain(t, cs, int(top["pid"]))

static func detain(t: Dictionary, cs: Dictionary, pid: int) -> void:
	cs["detained"] = pid
	cs["accused"] = pid
	var nm: String = CrimePerson.name_of(pid)
	VacationLog.note(t, "crime", "Ship security detained %s in the brig over %s. The police will meet the ship in port." % [nm, CaseText.neutral(cs)], [pid], 3, true)
	SysUtil.notify("Ship security has detained %s." % nm, "story")
	SysUtil.game_event("ship_detained", {"trip": int(t["id"]), "person": pid, "case": int(cs["id"])})
	if str(t["cruise"].get("killer", {}).get("pid", -1)) == str(pid):
		CruiseKiller.on_detained(t, pid)

## The ship reaches a port with police: they take the cases over.
static func handover(t: Dictionary, where: String) -> void:
	var c: Dictionary = t["cruise"]
	var done: int = 0
	var lead: Dictionary = {}
	for cid in c.get("cases", []):
		var cs: Dictionary = CaseStore.get_case(int(cid))
		if cs.is_empty() or not bool(cs.get("ship_hold", false)):
			continue
		cs.erase("ship_hold")
		if str(cs["state"]) == "hidden":
			continue                                     # nobody on board knew: the town's normal discovery takes over from here
		var det: int = int(cs.get("detained", -1))
		if det >= 0 and CrimePerson.alive(det) and not CrimePerson.in_custody(det):
			VacationLog.note(t, "crime", "The police met the ship at %s and took %s into custody." % [where, CrimePerson.name_of(det)], [det], 4, true)
			CruiseKiller.remove_person(t, det)
			JusticeProcess.arrest(cs, det)
		else:
			VacationLog.note(t, "crime", "The police boarded at %s and took over the investigation of %s." % [where, CaseText.neutral(cs)], [], 3, true)
			CaseStore.note(cs, "The ship reached %s. The police took over the case." % where, "", 2)
		done += 1
		lead = cs
	c["cases"] = (c.get("cases", []) as Array).filter(func(x): return CaseStore.has_case(int(x)) and bool(CaseStore.get_case(int(x)).get("ship_hold", false)))
	if done > 0:
		SysUtil.game_event("ship_handover", {"trip": int(t["id"]), "where": where, "cases": done})
		CruiseKiller.on_handover(t)
