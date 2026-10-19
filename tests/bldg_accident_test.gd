extends RefCounted
## Accidents in a building with floors: falls on the stairs (much likelier for elders, toddlers, the injured, the exhausted and the soaked),
## the consequence of a fall (Health.injure, a toast), and a lift that gets stuck: riders wait inside, help comes, the lift stays out of
## order until repaired, folk route around it meanwhile.

const Kit = preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _clock() -> Node:
	return Engine.get_main_loop().root.get_node("Clock")


func _setup() -> WorldGrid:
	TestFixture.reset()
	WorldIface.stub = null
	IncidentDefs.reset()
	SysContent.install_all()
	BuildingContent.install()
	LevelAccidents.reset()
	Kit.tower(3, true)
	return Kit.world()


func run() -> Array:
	fails = []
	_stairs()
	_lift()
	Kit.world().reset()
	LevelAccidents.reset()
	return fails


func _on_stairs(W: WorldGrid, f: Folk) -> void:
	# the first flight: stairs at (6, 6) level 0 -> its run tiles are (6, 6) and (7, 6)
	f.tile = Vector2i(6, 6)
	f.level = 0


func _stairs() -> void:
	var W := _setup()
	var adult := Folk.create("Ada")
	adult.household_id = 1
	W.add_folk(adult, Vector2i(6, 6), 0)
	_check(LevelInfo.on_stairs(adult), "standing on a flight of stairs")
	adult.tile = Vector2i(5, 6)
	_check(not LevelInfo.on_stairs(adult), "the landing beside the stairs is not the flight")
	_on_stairs(W, adult)
	var base := LevelAccidents.fall_chance(adult)
	var elder := Folk.create("Eli")
	elder.age_stage = "elder"
	var toddler := Folk.create("Tia")
	toddler.age_stage = "toddler"
	var hurt := Folk.create("Hal")
	hurt.add_buff("injured")
	var wet := Folk.create("Wen")
	wet.add_buff("soaked")
	var tired := Folk.create("Tom")
	tired.add_buff("exhausted")
	_check(LevelAccidents.fall_chance(elder) >= base * 4.0, "elders fall more (%.4f vs %.4f)" % [LevelAccidents.fall_chance(elder), base])
	_check(LevelAccidents.fall_chance(toddler) >= base * 4.0, "toddlers fall more")
	_check(LevelAccidents.fall_chance(hurt) >= base * 3.0, "the injured fall more")
	_check(LevelAccidents.fall_chance(wet) >= base * 2.0, "wet feet slip more")
	_check(LevelAccidents.fall_chance(tired) > base, "tired folk stumble more")
	# dice over many minutes (the chance is raised so a short run shows it); cooldown 0 so every minute can fall
	var lv: Dictionary = IncidentDefs.cfg("level_accidents", {})
	lv["fall_per_min"] = 0.08
	lv["fall_cooldown_min"] = 0
	lv["severity"] = [1.0, 0.0, 0.0]                      # light falls only: nobody leaves for the hospital in this loop
	IncidentDefs.config["level_accidents"] = lv
	LevelAccidents.rng.seed = 9
	var falls_adult := 0
	var falls_elder := 0
	W.add_folk(elder, Vector2i(6, 6), 0)
	for m in 300:
		for p in [adult, elder]:
			p.remove_buff("injured")
			var before := int(p.get_meta("lvl_fall_min", -1))
			LevelAccidents._stairs(p, m + 10)
			if int(p.get_meta("lvl_fall_min", -1)) != before:
				if p == adult:
					falls_adult += 1
				else:
					falls_elder += 1
	_check(falls_adult >= 1 and falls_elder > falls_adult * 2, "over 300 minutes on the stairs elders fall far more: %d vs %d" % [falls_elder, falls_adult])
	# a fall hurts through Health.injure and says so
	var notes: Array = []
	var ev = SimEnv.events()
	var cb := func(t, k): notes.append(str(t))
	ev.notification.connect(cb)
	var f2 := Folk.create("Fay")
	f2.household_id = 1
	W.add_folk(f2, Vector2i(6, 6), 0)
	var sev := LevelAccidents.fall(f2, -1, 1)
	_check(sev == 1 and f2.has_buff("injured"), "a light fall: injured")
	_check(not notes.is_empty() and str(notes[0]).contains("stairs"), "the household is told (%s)" % str(notes))
	ev.notification.disconnect(cb)
	var f3 := Folk.create("Gus")
	f3.household_id = 1
	W.add_folk(f3, Vector2i(6, 6), 0)
	LevelAccidents.fall(f3, -1, 3)
	_check(Hospital.is_in(f3) or f3.has_buff("injured"), "a bad fall goes to hospital / counts as injured")
	W.reset()


func _lift() -> void:
	var W := _setup()
	var lift = W.objects_of_def("elevator")[0]
	var f := Folk.create("Lia")
	f.household_id = 1
	W.add_folk(f, Vector2i(16, 9), 0)
	W.portals.elevators.book(lift.id, f.id, 0.0, 3.0)
	_check(W.portals.elevators.riders(lift.id) == 1, "one rider in the lift")
	var now := SysUtil.now()
	_check(LevelAccidents.get_stuck(lift.id, now), "the lift gets stuck")
	_check(bool(lift.state.get("out_of_order", false)) and LevelAccidents.is_stuck(lift.id), "out of order")
	_check(f.current != null and f.current.def_id == "stuck_in_lift" or not f.queue.is_empty(), "the rider waits inside")
	var route: Array = W.find_route(Vector3i(11, 12, 0), Vector3i(11, 8, 2))
	var by_lift := false
	for i in range(1, route.size()):
		by_lift = by_lift or (route[i].x == route[i - 1].x and route[i].y == route[i - 1].y and route[i].z != route[i - 1].z)
	_check(not route.is_empty() and not by_lift, "everyone else uses the stairs meanwhile")
	var rec: Dictionary = LevelAccidents.stuck[lift.id]
	# time passes: help comes, then the repair
	_clock().advance_minutes(int(rec["rescue_min"]) - now + 1)
	LevelAccidents.on_minute()
	_check(bool((LevelAccidents.stuck[lift.id] as Dictionary)["rescued"]), "help arrived: the rider is let out")
	_check(f.current == null or f.current.def_id != "stuck_in_lift", "no longer waiting")
	_check(bool(lift.state.get("out_of_order", false)), "but the lift is still out of service")
	_clock().advance_minutes(int(rec["fixed_min"]) - SysUtil.now() + 1)
	LevelAccidents.on_minute()
	_check(not bool(lift.state.get("out_of_order", false)) and not LevelAccidents.is_stuck(lift.id), "repaired")
	# save / load keeps a stuck lift
	LevelAccidents.get_stuck(lift.id, SysUtil.now())
	var d: Dictionary = JSON.parse_string(JSON.stringify(LevelAccidents.to_dict()))
	LevelAccidents.from_dict(d)
	_check(LevelAccidents.is_stuck(lift.id), "a stuck lift survives save / load")
	W.reset()
	LevelAccidents.reset()
