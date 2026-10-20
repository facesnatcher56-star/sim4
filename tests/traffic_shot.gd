extends SceneTree
## Not a unit test: windowed pictures for task 37 (junction types, a bus at its stop with the timetable, rush hour against night). Works on the old and the new build alike.
## godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/traffic_shot.gd -- out_prefix scenario [more]
## scenarios: junctions (big light, quiet light with a crossing, stop sign, roundabout, uncontrolled T), bus (a bus at the market stop), rush (08:00 wide), night (03:00 wide), flash (a quiet light at 02:00)
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(prefix: String, name: String) -> void:
	await create_timer(0.2).timeout
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
	var prefix: String = args[0] if args.size() > 0 else "user://traf"
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
		match args[i]:
			"junctions":
				for jn in [["big_light", Vector2i(3, 2)], ["quiet_light_crossing", Vector2i(1, 2)], ["stop_sign", Vector2i(2, 2)], ["roundabout", Vector2i(4, 3)], ["roundabout_b", Vector2i(2, 3)], ["uncontrolled_T", Vector2i(0, 1)]]:
					var c: Vector2 = VehicleRoads.junction_center(jn[1].x, jn[1].y)
					_look(lv, c, 17.0)
					var turned: bool = str(jn[0]).begins_with("roundabout")
					if turned:
						lv.rotate_camera(2)                       # look from the north: the building south of the junction would hide it
					await create_timer(3.0).timeout
					await _shot(prefix, "junction_" + str(jn[0]))
					if turned:
						lv.rotate_camera(2)
			"flash":
				clock.total_minutes = 2 * 60
				var c2: Vector2 = VehicleRoads.junction_center(1, 2)
				_look(lv, c2, 17.0)
				await create_timer(3.0).timeout
				await _shot(prefix, "quiet_light_night")
			"bus":
				# jump to a few minutes before a bus reaches the market stop (in the old build: whatever comes next)
				var now: int = SysUtil.now()
				var target: int = -1
				for r in TransportBus.routes():
					var ts: Array = TransportBus.next_times(str(r["id"]), "market", 1, now + 1)
					if not ts.is_empty() and (target < 0 or int(ts[0]) < target):
						target = int(ts[0])
				if target > 0:
					clock.total_minutes = target - 3
				var fr: Dictionary = VehicleRoads.frontage("market")
				_look(lv, Vector2(float(fr["gate"]) + 6.0, float(fr["hy"]) - 2.0), 15.0)
				for k in 6:
					await create_timer(1.5).timeout
					await _shot(prefix, "bus_stop_%d" % k)
			"rush":
				clock.total_minutes = 2 * 1440 + 8 * 60
				_look(lv, Vector2(115, 60), 80.0)
				await create_timer(25.0).timeout
				await _shot(prefix, "rush_0800")
			"night":
				clock.total_minutes = 2 * 1440 + 3 * 60
				_look(lv, Vector2(115, 60), 80.0)
				await create_timer(25.0).timeout
				await _shot(prefix, "night_0300")
	quit(0)
