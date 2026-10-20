extends SceneTree
## Not a unit test: frame cost of the vehicle lamps (task 42), windowed (Forward+). A night street with 40 cars and 4 ambulances in view; frame times with the lamps on (beam decals, lamps,
## real low beams for the nearest 6, flashing lights for the nearest 3) against the lamps off (VehicleLights.disabled), alternating every 6 s so machine load cancels out.
## godot --path . --rendering-method forward_plus --script res://tests/lights_bench.gd -- <WxH> <rounds>
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var res := (args[0] if args.size() > 0 else "1600x900").split("x")
	var rounds: int = int(args[1]) if args.size() > 1 else 3
	var size := Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7})
	await _frames(30)
	var clock = root.get_node("Clock")
	var lv = _main.lot_view
	_main.hud.visible = false
	clock.set_speed(1)
	for f in SysUtil.residents():
		f.idle_until_min = 1 << 30
	var vv = lv.get_node("VehicleView")
	vv.cfg["ambient"]["max_moving"] = 0
	vv.cfg["filler"]["per_hour_max"] = 0.0
	vv.cfg["filler"]["floor_per_hour"] = 0.0
	Weather.force("sunny", 0.0)
	clock.total_minutes = 2 * 1440 + 22 * 60
	clock.minute_passed.emit(clock.total_minutes)
	var fr: Dictionary = VehicleRoads.frontage("market")
	var z: float = float(fr["lane_z"])
	var cx: float = float(fr["gate"])
	lv.select("none", -1)
	lv.set_zoom(40.0)
	lv._target = Vector3(cx - 10.0, 0, float(fr["hy"]) + 2.0)
	lv._zoom = lv._zoom_target
	lv._update_daylight()
	await _frames(20)
	vv.sim.vehicles.clear()
	vv.nodes.clear()
	for k in 40:
		var west: bool = k % 2 == 0
		var x0: float = cx + 60.0 - float(k / 2) * 6.0 if west else cx - 70.0 + float(k / 2) * 6.0
		var zz: float = z if west else float(fr["hy"]) + 4.05
		var pts: Array = [Vector2(x0, zz), Vector2(x0 - 400.0, zz)] if west else [Vector2(x0, zz), Vector2(x0 + 400.0, zz)]
		var v: Dictionary = vv.sim.add("car", ["car_hatchback_red", "car_sedan_blue", "car_van_white", "car_sedan_yellow"][k % 4], VehiclePath.make(pts, 1.8), {"end": "dead", "tag": "bench", "vmax": 1.2})
		v["ignore_signals"] = true
		if k % 5 == 0:
			v["stops"] = [{"s": 40.0 + float(k), "hold": true, "tag": "stop"}]
	for k2 in 4:
		var x1: float = cx + 40.0 - float(k2) * 20.0
		var a: Dictionary = vv.sim.add("ambulance", "ambulance", VehiclePath.make([Vector2(x1, z + 0.0), Vector2(x1 - 400.0, z)], 1.8), {"end": "dead", "tag": "bench", "vmax": 1.0})
		a["ignore_signals"] = true
		a["lights"]["siren"] = true
	await _frames(30)
	var VL = load("res://scripts/world/vehicle_lights.gd")
	var on_ms: Array = []
	var off_ms: Array = []
	for r in rounds:
		for mode in [true, false]:
			VL.disabled = not mode
			await create_timer(1.0).timeout
			var t_end: int = Time.get_ticks_msec() + 6000
			var last: int = Time.get_ticks_usec()
			var acc: Array = []
			while Time.get_ticks_msec() < t_end:
				await process_frame
				var now: int = Time.get_ticks_usec()
				acc.append(float(now - last) / 1000.0)
				last = now
			(on_ms if mode else off_ms).append(_mean(acc))
			print("round %d lamps %s: %.2f ms/frame (%d frames)" % [r, "ON " if mode else "OFF", _mean(acc), acc.size()])
	print("vehicles in layer: ", vv.sim.vehicles.size(), " lights: ", vv.nodes.rigs.count())
	print("MEAN lamps ON %.2f ms  OFF %.2f ms  delta %.2f ms" % [_mean(on_ms), _mean(off_ms), _mean(on_ms) - _mean(off_ms)])
	OS.kill(OS.get_process_id())


func _mean(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t / maxf(float(a.size()), 1.0)
