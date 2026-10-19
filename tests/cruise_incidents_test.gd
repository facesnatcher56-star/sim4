extends RefCounted
## Task 22: every rare cruise incident, forced through the Incidents framework (data/incidents/22_cruise.json): storm at sea (seasick), stomach bug
## outbreak (Health illness, spreads), fire on board (Fire.ignite, the crew put it out), overboard (search and rescue, rescued or lost), cabin theft and a
## brawl (cases held by ship security, police take over at the port), plus the schema of the new data file.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var errs: Array = IncidentDefs.validate_all()
	var mine: Array = errs.filter(func(e): return str(e).contains("cruise") or str(e).contains("serial_killer_aboard") or str(e).contains("norovirus"))
	_check(mine.is_empty(), "the 22_cruise.json schema is valid: %s" % str(mine))
	_storm_and_bug()
	_fire()
	_overboard()
	_crimes()
	K.teardown()
	return fails

func _at_sea(seed_value: int = 5) -> Dictionary:
	K.new_game("small", 8000, false, seed_value)
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 7, "cabin_class": "inside", "seed": seed_value})
	var t: Dictionary = Vacation.trip(int(res["trip"]))
	K.warp(int(res["boarding"]["sail_min"]) - K.now() + 5 * 60)
	return t

func _storm_and_bug() -> void:
	var t: Dictionary = _at_sea()
	var r: Dictionary = Incidents.force("cruise_storm", {"lot": "home:1"})
	_check(bool(r["ok"]), "storm forced")
	_check(int(t["cruise"]["storm_until"]) > K.now() and str(t["cruise"]["sea"]) == "rough", "the storm is on")
	_check(VacationLog.count("incident") >= 1, "the storm is in the story")
	var seasick := 0
	for f in VacationTrip.members(t):
		if f.has_buff("seasick"):
			seasick += 1
	_check(seasick >= 1, "somebody is seasick in a storm (%d)" % seasick)
	Incidents.force("cruise_norovirus", {"lot": "home:1"})
	_check(int(t["cruise"]["noro_until"]) > K.now(), "an outbreak began")
	var sick0: int = CruiseIncidents.ill_count(t)
	_check(sick0 >= 1, "a first case (%d)" % sick0)
	K.warp(36 * 60)
	_check(CruiseIncidents.ill_count(t) >= sick0, "it spreads or at least holds (%d)" % CruiseIncidents.ill_count(t))
	_check(VacationLog.count("incident") >= 2, "outbreak logged")
	K.teardown()

func _fire() -> void:
	var t: Dictionary = _at_sea(6)
	var r: Dictionary = Incidents.force("cruise_fire", {"lot": "home:1"})
	_check(bool(r["ok"]), "fire forced")
	_check(not Fire.fires_in(str(t["lot"])).is_empty(), "a fire burns on the ship")
	K.run(3)
	K.warp(40)
	_check(Fire.fires_in(str(t["lot"])).is_empty(), "the crew put it out (ship rules)")
	_check(VacationLog.count("incident") >= 2, "fire and its end are in the story")
	K.teardown()

func _overboard() -> void:
	var t: Dictionary = _at_sea(7)
	var pax: Array = CruiseCrew.passengers(t)
	_check(pax.size() >= 3, "passengers aboard")
	var a = pax[0]
	var b = pax[1]
	Incidents.force("cruise_overboard", {"lot": "home:1", "victim": int(a.id), "rescued": true})
	_check(not t["cruise"].get("search", {}).is_empty(), "search and rescue under way")
	_check(SysUtil.folk(int(a.id)) == null, "the passenger is in the water, not on deck")
	K.warp(4 * 60)
	_check(Story.townies[int(a.id)]["alive"] == true, "rescued: alive")
	_check(VacationLog.count("incident") >= 2, "rescue logged")
	Incidents.force("cruise_overboard", {"lot": "home:1", "victim": int(b.id), "rescued": false})
	K.warp(4 * 60)
	_check(not bool(Story.townies[int(b.id)].get("alive", true)), "the other was lost at sea (a very rare outcome)")
	_check(VacationLog.count("death") >= 1, "a death is in the story")
	K.teardown()

func _crimes() -> void:
	var t: Dictionary = _at_sea(8)
	var coins0: int = Economy.balance(1)
	Incidents.force("cruise_cabin_theft", {"lot": "home:1"})
	var cases: Array = t["cruise"].get("cases", [])
	_check(cases.size() == 1, "a case was opened")
	var cs: Dictionary = CaseStore.get_case(int(cases[0]))
	_check(str(cs["kind"]) == "theft" and bool(cs["ship_hold"]) and str(cs["scene"]).begins_with("ship:"), "a theft case held by the ship")
	_check(Economy.balance(1) < coins0, "coins were taken")
	Incidents.force("cruise_brawl", {"lot": "home:1"})
	_check((t["cruise"]["cases"] as Array).size() == 2, "a brawl case too")
	K.warp(3 * 60)
	_check(str(cs["state"]) == "open", "ship security has it (open, held)")
	# the town police do not work a held case
	var arrested: int = CaseInvestigation.work(cs)
	_check(arrested == -1 and float(cs["progress"]) < 0.3, "no police work on a held case")
	CruiseCrime.handover(t, "Test Harbour")
	_check(not bool(cs.get("ship_hold", false)), "the police took over at the port")
	K.teardown()
