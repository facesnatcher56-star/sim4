extends RefCounted
## Task 22b: Incidents.force("serial_killer_aboard", {ship}) puts a killer among the passengers of a cruise. The normal serial-killer track runs on the
## ship: isolated victims at night (hidden disappearances), noticed at dinner or the morning headcount, passengers frightened, the captain
## restricts movement, ship security investigates (the town police are held off at sea), the police take over at the next port and an arrest
## leads to charges and a trial like in town. Non-graphic. The same seed gives the same story twice.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var a: Dictionary = _voyage(8)
	var b: Dictionary = _voyage(8)
	_check(a["victims"] == b["victims"] and a["phase"] == b["phase"] and a["killer"] == b["killer"], "same seed, same story: %s vs %s" % [str(a), str(b)])
	_check(a["st_seed"] == b["st_seed"], "both plays start with the same storyteller stream (%s vs %s)" % [str(a["st_seed"]), str(b["st_seed"])])
	var c: Dictionary = _voyage(31)
	_check(int(c["killer"]) >= 1000, "another seed also runs")
	K.teardown()
	return fails

## Returns a small summary used for the repeatability check.
func _voyage(seed_value: int) -> Dictionary:
	# Every play starts from the same master seed: Kit.new_game only seeds SysUtil, and Storyteller.master_seed (which survives reset_all) would
	# otherwise leak from whatever ran before (the first play of a process had 0, the second the fixture's 4242: different storyteller dice, different
	# SysUtil draws on day 3, a different victim).
	TestFixture.reset()
	K.new_game("small", 9000, false, seed_value)
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 5, "cabin_class": "inside", "seed": seed_value})
	var tid: int = int(res["trip"])
	var t: Dictionary = Vacation.trip(tid)
	var sail1: int = 0
	for e in t["cruise"]["timeline"]:
		if str(e["kind"]) == "sail" and int(e["day"]) == 1:
			sail1 = int(e["min"])
	K.warp(sail1 - K.now() + 40)
	_check(str(t["cruise"]["phase"]) == "sailing", "at sea after the first port")
	var r: Dictionary = Incidents.force("serial_killer_aboard", {"ship": tid, "delay_hours": 3})
	_check(bool(r["ok"]), "forced through the incident framework")
	var k: Dictionary = t["cruise"]["killer"]
	_check(not k.is_empty() and Story.townies.has(int(k["pid"])) and bool(Story.townies[int(k["pid"])]["alive"]), "a killer was chosen among the passengers")
	_check(CruiseCrew.passengers(t).any(func(x): return int(x.id) == int(k["pid"])), "the killer is aboard")
	_check(JusticeState.serial.get("pid", -1) == k["pid"] and bool(JusticeState.serial.get("active", false)), "the town's serial state knows them")
	_check(int(JusticeState.serial.get("next_kill", 0)) > SysUtil.day() + 100, "the town waits while the killer is at sea")
	var seen_hidden: bool = false
	var reported: bool = false
	var guard: int = 0
	while guard < 120 and str(k["phase"]) in ["hunting", "detained"] and str(t.get("state", "")) == "there":
		K.warp(60)
		guard += 1
		for cid in k["cases"]:
			var cs: Dictionary = CaseStore.get_case(int(cid))
			if str(cs["state"]) == "hidden" and bool(cs.get("ship_hold", false)):
				seen_hidden = true
			if bool(cs.get("ship_hold", false)):
				_check(str(cs["scene"]).begins_with("ship:") and str(cs["kind"]) == "serial", "ship cases are serial cases with a ship scene")
				if str(cs["state"]) == "open":
					reported = true
	_check((k["victims"] as Array).size() >= 1, "at least one victim (%d)" % (k["victims"] as Array).size())
	_check(seen_hidden or reported, "a disappearance stayed hidden until it was noticed")
	_check(VacationLog.count("crime") >= 3, "the story log has the crimes")
	var missing_logged := false
	for e2 in VacationLog.entries():
		if str(e2["text"]).contains("did not turn up") or str(e2["text"]).contains("found dead"):
			missing_logged = true
	_check(missing_logged or reported, "somebody noticed at dinner / the headcount")
	_check(bool(t["cruise"].get("restricted", false)) or str(k["phase"]) in ["police", "caught", "detained"], "the captain restricted movement (or the case moved on)")
	_check(VacationLog.count("incident") >= 1, "the programme was cancelled or restricted")
	_check(str(k["phase"]) in ["police", "caught"], "the police took over at a port (phase %s)" % str(k["phase"]))
	if str(k["phase"]) == "caught":
		_check(JusticeState.inmates.has(int(k["pid"])), "the killer is in custody")
		var main: Dictionary = {}
		for cid2 in k["cases"]:
			var c2: Dictionary = CaseStore.get_case(int(cid2))
			# the arrest charges ONE main case; the other victims' cases are joined to it (CrimeSerial.mark_caught) and stay open
			if int(c2.get("accused", -1)) == int(k["pid"]) and (main.is_empty() or c2.has("joined")):
				main = c2
		_check(not main.is_empty() and str(main["state"]) in ["arrested", "charged", "trial", "closed"], "charged and heading for trial (%s)" % str(main.get("state", "?")))
		if main.has("joined"):
			_check((main["joined"] as Array).size() + 1 == (k["cases"] as Array).size(), "every victim's case is joined to the main one")
		_check(not bool(JusticeState.serial.get("active", true)) and bool(JusticeState.serial.get("caught", false)), "the serial run is over")
	for cid3 in k["cases"]:
		_check(not bool(CaseStore.get_case(int(cid3)).get("ship_hold", false)) or str(k["phase"]) == "hunting", "no case stays held after the handover")
	var out: Dictionary = {"killer": int(k["pid"]), "victims": (k["victims"] as Array).duplicate(), "phase": str(k["phase"]), "st_seed": Storyteller.rng.seed}
	# the rest of the cruise ends normally
	K.warp(int(t["return_min"]) - K.now() + 120)
	_check(Vacation.trip(tid).is_empty(), "the cruise ended")
	K.teardown()
	return out
