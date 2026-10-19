extends RefCounted
## Real commutes (task 11): a household folk leaves home early enough, walks the road graph to the workplace door, is hidden INSIDE
## that building, and walks home afterwards; late departures / snow make them late; townie coworkers turn up at the same building;
## pay is unchanged; a teen walks to school; visible jobs work on the lot; a save in the middle of the commute resumes it.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []
var full: bool = false          # commute_longrun_test sets it: also play the whole shifts (8 h of clock minutes each)

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	full = false
	return _all()

func _all() -> Array:
	_on_time_and_back()
	_late_departure()
	_snow_slows()
	_townie_coworker()
	_school_teen()
	_visible_jobs()
	_save_mid_commute()
	_missed_shift()
	Kit.teardown()
	return fails

## New game where only the folk a test hires has a job: the housemates would otherwise wander to the terminal ("Look for Jobs") on
## their own, and their commutes (left_for_work / late toasts at 6:00 shifts) would pollute the global event and toast counts.
func _new(start_id: String) -> Array:
	var folk: Array = Kit.new_game(start_id)
	StoryPacing.enabled = false
	for i in range(1, folk.size()):
		Careers.retired[int(folk[i].id)] = {"career": "", "level": 1, "pension": 0}      # Careers.hire refuses retired folk
	return folk

func _hire(f: Folk, cid: String, level: int = 1) -> void:
	Careers.hire(f, cid, level)
	WorldIface.coins[int(f.household_id)] = 0

func _expected_pay(f: Folk, hours: float) -> int:
	var j: Dictionary = Careers.jobs[int(f.id)]
	var ld: Dictionary = Careers.level_def(str(j["career"]), int(j["level"]), str(j.get("branch", "")))
	return int(round(hours * float(ld.get("pay", 0)) * CareerProgress.pay_multiplier(float(j["performance"]))))

func _on_time_and_back() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "coder")                                     # 09:00 - 17:00 at the office
	Kit.set_time(2, 6, 30)                                   # Tuesday
	var pay: int = _expected_pay(mira, 8.0)
	_check(Workplace.lot_of_folk(mira) == "office" and Workplace.entry_tile("coder")["tile"] == NeighborhoodLots.entry_tile("office"), "a coder works at the office door")
	var plan: float = Workplace.commute_minutes(mira, NeighborhoodLots.entry_tile("office"))
	print("  [commute] home -> office: %.0f min walk planned (lead %.0f min incl. buffer)" % [plan, Commute.lead_hours(mira) * 60.0])
	var left_at := -1
	var arrived_at := -1
	for m in 3 * 60:
		Kit.run(1)
		if left_at < 0 and Kit.count_events("left_for_work") > 0:
			left_at = SimEnv.now_min() % 1440
		if arrived_at < 0 and Kit.count_events("arrived_at_work") > 0:
			arrived_at = SimEnv.now_min() % 1440
			break
	_check(left_at >= 0 and left_at < 9 * 60 - 10, "left home early (at minute %d of the day)" % left_at)
	_check(left_at >= 9 * 60 - int(plan) - 30, "but not at dawn: the lead follows the route (%d)" % left_at)
	_check(not SysUtil.is_away(mira) or arrived_at >= 0, "walking on the street, not hidden while on the way")
	_check(arrived_at >= 0 and arrived_at <= 9 * 60 + 5, "arrived on time (minute %d)" % arrived_at)
	_check(Kit.count_events("late_for_work") == 0 and not Kit.has_note("late"), "no lateness, no toast")
	Kit.run(3)
	_check(SysUtil.is_away(mira) and mira.has_buff("away"), "away once inside")
	_check(NeighborhoodLots.lot_at(mira.tile) == "office", "away INSIDE the office lot, not at home (lot %s)" % NeighborhoodLots.lot_at(mira.tile))
	_check(Commute.on_shift(mira.id) and Away.info(mira.id).get("reason", "") == "work", "on shift")
	Kit.run(60)
	_check(SysUtil.is_away(mira) and NeighborhoodLots.lot_at(mira.tile) == "office", "still inside at 10:30")
	if full:
		for _m in 8 * 60:                                        # the real shift: clock minutes pass inside the building
			Kit.run(1)
			if Kit.count_events("returned_from_work") > 0:
				break
		Kit.run(2)
		_check(not SysUtil.is_away(mira) and Kit.count_events("returned_from_work") == 1, "shift over: back on the street")
		var ev: Dictionary = {}
		for e in Kit.events:
			if e[0] == "returned_from_work":
				ev = e[1]
		pay = int(round(8.0 * float(Careers.level_def("coder", 1).get("pay", 0)) * CareerProgress.pay_multiplier(float(ev.get("performance", 50.0)) - float(ev.get("delta", 0.0)))))
		_check(int(ev.get("pay", -1)) == pay, "the shift pays the same as before: 8 h x wage x performance multiplier (%d vs %d)" % [int(ev.get("pay", -1)), pay])
		_check(Commute.trips.has(mira.id) and str(Commute.trips[mira.id]["state"]) == "home", "walking home")
		_check(NeighborhoodLots.lot_at(mira.tile) == "office" or NeighborhoodLots.lot_at(mira.tile) == "", "she starts the walk from the office")
		Kit.run(int(plan) + 25)
		_check(NeighborhoodLots.lot_at(mira.tile) == "home" and Kit.count_events("returned_home") == 1, "home again (lot %s)" % NeighborhoodLots.lot_at(mira.tile))
		_check(not Commute.trips.has(mira.id) and Economy.balance(1) >= pay, "trip closed, wages deposited")
		_check(not Kit.has_note("closed") and not Kit.has_note("Entry costs"), "no venue refusal for staff")

func _late_departure() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "coder")
	var p0: float = CareerProgress.performance_of(mira.id)
	Kit.set_time(2, 8, 55)                                   # the clock starts inside the lead time: leaves 5 min before the start
	Kit.run(2)
	_check(Kit.count_events("left_for_work") == 1 and Kit.has_note("running late"), "leaves late and says so")
	Kit.run(75)
	_check(Kit.count_events("arrived_at_work") == 1 and Kit.count_events("late_for_work") == 1, "arrives late")
	var late_min := 0
	for e in Kit.events:
		if e[0] == "late_for_work":
			late_min = int(e[1]["minutes"])
	_check(late_min >= 10, "late by %d min" % late_min)
	_check(CareerProgress.performance_of(mira.id) < p0, "lateness costs performance (%.1f -> %.1f)" % [p0, CareerProgress.performance_of(mira.id)])
	_check(Kit.has_note("late for work"), "late toast")
	_check(Kit.count_events("missed_shift") == 0, "late is not missed")

func _plan_minutes(f: Folk) -> float:
	return Workplace.commute_minutes(f, NeighborhoodLots.entry_tile("office"))

func _snow_slows() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "coder")
	Kit.set_time(2, 6, 0)
	Weather.force("sunny", 0.0)
	var clear_plan: float = _plan_minutes(mira)
	Weather.force("snow", 1.0)
	var snow_plan: float = _plan_minutes(mira)
	_check(snow_plan > clear_plan * 1.1, "snow lengthens the planned walk (%.1f vs %.1f min)" % [snow_plan, clear_plan])
	# the real walk is slower too
	var ir := Interaction.create_goto(mira, NeighborhoodLots.entry_tile("office"), false)
	mira.enqueue(ir)
	Kit.run(1)
	var snow_total: float = mira.current.travel_total if mira.current != null else -1.0
	mira.cancel_current("test")
	mira.clear_queue()
	Weather.force("sunny", 0.0)
	var ir2 := Interaction.create_goto(mira, NeighborhoodLots.entry_tile("office"), false)
	mira.enqueue(ir2)
	Kit.run(1)
	var clear_total: float = mira.current.travel_total if mira.current != null else -1.0
	_check(snow_total > clear_total * 1.1 and clear_total > 0.0, "the walk itself takes longer in snow (%.1f vs %.1f min)" % [snow_total, clear_total])
	Weather.force("sunny", 0.0)

func _townie_coworker() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "coder")
	var t: Dictionary = Story.add_townie(-1.0, "Pip Marlow", [], "coder", 1)
	var tid: int = int(t["id"])
	_check(Workplace.coworkers(mira).has(tid), "the townie is a coworker of Mira")
	Kit.set_time(2, 7, 30)
	_check(CommuteTownies.lot_now(tid) == "", "not at work at 07:30")
	Kit.set_time(2, 8, 5)
	Neighborhood.travel([folk[1].id], "office", {"instant": true, "free": true, "quiet": true})      # a visible resident wakes the office lot up
	Kit.run(40)
	_check(CommuteTownies.lot_now(tid) == "office", "statistically at the office from ~08:45")
	for _m in 60:
		var seen = SysUtil.folk(tid)
		if seen != null and seen.has_meta("coworker"):
			break
		Kit.run(1)
	var npc = SysUtil.folk(tid)
	_check(npc != null and npc.has_meta("coworker") and NeighborhoodLots.lot_at(npc.tile) == "office", "the townie shows up at the office (%s)" % (str(npc.tile) if npc != null else "absent"))
	var spot: Vector2i = mira.tile
	mira.tile = npc.tile + Vector2i(1, 0)
	Workplace.greet_coworkers(mira, "office")                # what happens when she walks in past a coworker
	mira.tile = spot
	_check(Kit.has_note("met a coworker"), "Mira met a coworker at the door")
	# home in the evening: the coworker leaves at the end of the shift
	Kit.set_time(2, 17, 5)
	Kit.run(30)
	_check(SysUtil.folk(tid) == null or not SysUtil.folk(tid).has_meta("coworker"), "the townie is no longer on shift after 17:00")
	_check(CommuteTownies.lot_now(tid) == "", "and is no longer at work")
	# a townie whose job is the office cannot be a cafe customer during working hours
	Kit.set_time(3, 11, 0)
	_check(CommuteTownies.busy_elsewhere(t, "cafe", SimEnv.now_min()), "at work, so not available for the cafe crowd")

func _school_teen() -> void:
	var folk: Array = _new("small")
	var kid: Folk = folk[1]
	Aging.set_age_days(kid, 82.0)
	kid.age_stage = "teen"
	Careers.enroll_school()
	Kit.set_time(2, 7, 0)
	_check(Careers.school.has(kid.id), "the teen is enrolled")
	_check(Workplace.lot_of_folk(kid) == "school", "school is the school lot")
	Kit.run(150)
	_check(Kit.count_events("left_for_school") == 1 and Kit.count_events("arrived_at_school") == 1, "the teen walked to school")
	_check(SysUtil.is_away(kid) and NeighborhoodLots.lot_at(kid.tile) == "school", "and is inside the school (%s)" % NeighborhoodLots.lot_at(kid.tile))
	if full:
		for _m in 7 * 60:
			Kit.run(1)
			if Kit.count_events("returned_from_school") > 0:
				break
		Kit.run(2)
		_check(Kit.count_events("returned_from_school") == 1, "school is out")
		Kit.run(70)
		_check(NeighborhoodLots.lot_at(kid.tile) == "home" and Kit.count_events("returned_home") >= 1, "the teen walked home (%s)" % NeighborhoodLots.lot_at(kid.tile))

func _visible_jobs() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "barista")
	_check(Workplace.visible_job("barista") == "work_counter" and Workplace.lot_of_folk(mira) == "cafe", "the barista works at the cafe, visibly")
	var j: Dictionary = Careers.jobs[mira.id]
	Kit.set_time(2, 5, 0)                                    # 06:00 - 12:00
	for m in 3 * 60:
		Kit.run(1)
		if Kit.count_events("arrived_at_work") > 0:
			break
	_check(Kit.count_events("arrived_at_work") == 1, "the barista arrived")
	Kit.run(30)
	_check(not SysUtil.is_away(mira) and Away.is_visible(mira.id), "visible: on the map, not hidden")
	_check(NeighborhoodLots.lot_at(mira.tile) == "cafe", "on the cafe lot")
	var worked := false
	for m in 90:
		Kit.run(1)
		if mira.current != null and mira.current.def_id == "work_counter":
			worked = true
			break
	_check(worked, "she works the counter (%s)" % (mira.current.def_id if mira.current != null else "idle"))
	_check(Kit.count_events("skipped_work") == 0, "no skip")
	# the shift ends like any other: paid, then she walks home
	if full:
		for _m in 8 * 60:
			Kit.run(1)
			if Kit.count_events("returned_from_work") > 0:
				break
		Kit.run(2)
		_check(Kit.count_events("returned_from_work") == 1 and not Away.is_visible(mira.id), "the visible shift ended and was paid")
		_check(Commute.trips.has(mira.id), "and she heads home")

func _save_mid_commute() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "coder")
	Kit.set_time(2, 7, 0)
	var plan: float = _plan_minutes(mira)
	for m in 240:
		Kit.run(1)
		if Commute.trips.has(mira.id) and (Commute.trips[mira.id]["state"] == "out") and WorldIface.path_length(mira.tile, NeighborhoodLots.entry_tile("office")) < int(plan / 0.3 * 0.6):
			break
	_check(Commute.trips.has(mira.id) and str(Commute.trips[mira.id]["state"]) == "out", "mid commute (%s)" % str(Commute.trips.get(mira.id, {})))
	var tile_before: Vector2i = mira.tile
	var snap: Dictionary = SaveLoad.snapshot("commute")
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	_check(parsed is Dictionary and ((parsed as Dictionary)["systems"] as Dictionary).has("commute"), "the commute is in the save")
	_new("large")
	_check(SaveLoad.restore(parsed), "restore works")
	var m2 = SysUtil.folk(mira.id)
	_check(m2 != null and m2.tile == tile_before and Commute.trips.has(mira.id), "position and trip restored")
	Kit.run(int(plan) + 15)
	_check(Kit.count_events("arrived_at_work") >= 1 and SysUtil.is_away(m2), "she carried on and arrived (%s)" % str(Commute.trips.get(mira.id, {})))
	# and a save INSIDE the building
	var snap2: Variant = JSON.parse_string(JSON.stringify(SaveLoad.snapshot("inside")))
	_new("large")
	SaveLoad.restore(snap2)
	var m3 = SysUtil.folk(mira.id)
	_check(m3 != null and SysUtil.is_away(m3) and NeighborhoodLots.lot_at(m3.tile) == "office" and Commute.on_shift(mira.id), "a save inside the office restores the shift")
	if full:
		Kit.run(8 * 60)
		_check(Kit.count_events("returned_from_work") >= 1, "and the shift ends normally after loading")

func _missed_shift() -> void:
	var folk: Array = _new("small")
	var mira: Folk = folk[0]
	_hire(mira, "coder")
	Kit.set_time(2, 8, 10)
	Kit.run(8)
	_check(Commute.trips.has(mira.id), "on the way")
	var p0: float = CareerProgress.performance_of(mira.id)
	# the player calls her away mid-walk: counts as a skipped shift (skipping is a decision now, SkipRules; make it certain here)
	Careers.cfg()["skip"]["base_work"] = 1.0
	Careers.cfg()["skip"]["max"] = 1.0
	var sofa_cmd := Interaction.create_goto(mira, mira.tile + Vector2i(1, 0), true)
	mira.enqueue(sofa_cmd)
	Kit.run(2)
	_check(Kit.count_events("missed_shift") == 1 and CareerProgress.performance_of(mira.id) < p0, "a player command on the way = missed shift")
	_check(Kit.has_note("skip"), "toast says so")
