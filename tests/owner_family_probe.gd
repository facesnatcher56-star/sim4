extends SceneTree
## Not a unit test: the owner's family (Kenneth + Madrina, a baby and a toddler) for N game days; prints how often the care / job / hosting / travel
## problems show up. godot --headless --path . --script res://tests/owner_family_probe.gd -- days [seed] --budget=<s>
var _main: Node = null
var _frames := 0
var _days := 10
var _toasts: Array = []
var _quits := 0
var _ids: Dictionary = {}
var _low := 100.0

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0 and args[0].is_valid_int(): _days = int(args[0])
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var k: Dictionary = HouseholdSetup.random_folk("adult", "none", [])
		k["name"] = "Kenneth Fernwood"; k["sex"] = "male"; k["color"] = Color("#3d85c6")
		var m: Dictionary = HouseholdSetup.random_folk("adult", "partner", ["Kenneth Fernwood"])
		m["name"] = "Madrina Fernwood"; m["sex"] = "female"; m["color"] = Color("#e07a5f"); m["homemaker"] = true
		_main.start_new_game({"name": "Fernwood", "folk": [k, m]})
		var ev = root.get_node("Events")
		ev.notification.connect(func(t, kind): _toasts.append([int(root.get_node("Clock").day()), str(t), str(kind)]))
		ev.game_event.connect(func(n, p): if n == "left_job": _quits += 1)
	if _frames == 30:
		var folk: Array = root.get_node("World").all_folk()
		var mom = null
		var dad = null
		for f in folk:
			if str(f.name).begins_with("Madrina"): mom = f
			if str(f.name).begins_with("Kenneth"): dad = f
		Careers.hire(dad, "handyperson", 1)
		for nm in ["Sisi", "Yennifer"]:
			Aging._birth(int(mom.id), int(dad.id))
			var kids: Array = Aging.children_of(int(mom.id))
			var b = SysUtil.folk(int(kids[kids.size() - 1]))
			PregnancyNaming.rename(int(b.id), nm)
			_ids[int(b.id)] = nm
			if nm == "Yennifer":
				b.age_stage = "toddler"
				(Aging.records[int(b.id)] as Dictionary)["age_days"] = 7.0
				Aging.apply_stage_buff(b)
		var clock = root.get_node("Clock")
		var t0 := Time.get_ticks_msec()
		for m2 in range(_days * 1440):
			clock.advance_minutes(1)
			if m2 % 60 == 0:
				for f2 in root.get_node("World").all_folk():
					if int(f2.household_id) == 1 and str(f2.age_stage) in ["baby", "toddler", "child"]:
						for n in ["hunger", "hygiene", "energy", "bladder"]:
							_low = minf(_low, float(f2.needs[n].value))
		print("simulated %d days in %d ms" % [_days, Time.get_ticks_msec() - t0])
		_report()
		quit(0)
	return false

func _count(frag: String) -> int:
	var n := 0
	for t in _toasts:
		if str(t[1]).find(frag) >= 0:
			n += 1
	return n

func _report() -> void:
	print("RESULT neglect_warnings=", _count("looked after properly") + _count("child services"), " faint_with_hunger=", _count("faint with hunger"),
		" is_now_a=", _count(" is now a "), " job_offers=", _count("got a job offer"), " left_job_events=", _quits, " hosting=", _count("is hosting"),
		" hospital_met=", _count("Hospital"), " head_toasts=", _count("head to") + _count("head home"), " food_poisoning=", _count("food poison"),
		" lowest_kid_need=", snappedf(_low, 0.1))
	for t in _toasts:
		var s: String = str(t[1])
		if s.find("looked after") >= 0 or s.find("faint") >= 0 or s.find("is now a") >= 0 or s.find("child services") >= 0:
			print("  d%d %s" % [t[0], s])
