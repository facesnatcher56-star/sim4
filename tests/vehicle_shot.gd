extends SceneTree
## Not a unit test: windowed screenshots of the vehicle layer (task 12b).
## godot --path . --resolution 1600x900 --script res://tests/vehicle_shot.gd -- out_prefix scenario [more scenarios]
## scenarios: ambient (parked and passing cars), bus (a timetable bus at a stop), car (a player's car trip), taxi, bike, fire (engine to a call), crash (two cars, hazards, tow), night
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(prefix: String, name: String) -> void:
	await create_timer(0.15).timeout
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved ", name)


func _look(lv, at: Vector2, zoom: float) -> void:
	lv.frame_home()
	lv._target = Vector3(at.x, 0, at.y)
	lv.set_zoom(zoom)
	lv._zoom = zoom
	lv._update_daylight()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://veh"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7})
	await _frames(20)
	var clock = root.get_node("Clock")
	var lv = _main.lot_view
	_main.hud.visible = false
	clock.set_speed(1)
	Weather.force("sunny", 0.0)
	clock.total_minutes = 12 * 60
	for f in SysUtil.residents():
		f.idle_until_min = 1 << 30
	lv.select("none", -1)
	var vv = lv.get_node("VehicleView")
	for i in range(1, args.size()):
		var sc: String = args[i]
		match sc:
			"ambient":
				var home: Dictionary = VehicleRoads.frontage("home")
				_look(lv, Vector2(float(home["gate"]), float(home["hy"]) - 2.0), 34.0)
				await create_timer(5.0).timeout
				print("focus ", vv.focus_points(), " map_ready ", Workplace.map_ready(), " active ", vv.active, " stats ", vv.stats(), " speed ", clock.speed)
				await _shot(prefix, "ambient_1")
				await create_timer(4.0).timeout
				await _shot(prefix, "ambient_2")
				print("stats ", vv.stats())
			"wide":
				_look(lv, Vector2(60, 60), 70.0)
				await create_timer(5.0).timeout
				await _shot(prefix, "wide")
				print("stats ", vv.stats())
			"night":
				clock.total_minutes = 23 * 60
				var home2: Dictionary = VehicleRoads.frontage("home")
				_look(lv, Vector2(float(home2["gate"]), float(home2["hy"]) - 2.0), 34.0)
				await create_timer(4.0).timeout
				await _shot(prefix, "night")
	quit(0)
