extends SceneTree
## Not a unit test: frame cost of the wear layer (task 41a). Windowed Forward+ on the real map.
## godot --path . --rendering-method forward_plus --resolution 1600x900 --script res://tests/art41a_perf.gd -- <scenario>   (SIM_LOOK=<look> picks the look)
## scenarios: plain (home view), poor (home lot poor + mess: clutter, walls, dressing), district (camera on the rough lot townie_b), far (zoomed out, poor home)
var _main: Node = null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _measure(label: String, n: int = 240) -> void:
	await _frames(90)
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var draws := 0.0
	var prims := 0.0
	var gpu := 0.0
	var cpu := 0.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	print("PERF %-34s look %s: %.2f ms/frame, script %.2f ms, render cpu %.2f gpu %.2f ms, draw calls %.0f, prims %.0fk" % [label, Looks.current_id(), ms, proc / n * 1000.0, cpu / n, gpu / n, draws / n, prims / n / 1000.0])


func _initialize() -> void:
	_run()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scenario: String = OS.get_cmdline_user_args()[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W = root.get_node("World")
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7, "home_state": "furnished"})
	await _frames(40)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	_main.hud.visible = false
	Weather.force("sunny", 0.0)
	clock.total_minutes = 12 * 60
	lv.select("none", -1)
	lv.frame_home()
	var wl := load("res://scripts/world/wear_layer.gd") as GDScript
	var t_build := 0.0
	match scenario:
		"poor", "far":
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for i in 60:
				W.add_mess(Vector2i(rng.randi_range(50, 64), rng.randi_range(72, 82)), rng.randf_range(2.0, 8.0))
			var t0 := Time.get_ticks_usec()
			wl.call("set_lot_override", "home", 0.9, 0.85)
			await _frames(5)
			t_build = float(Time.get_ticks_usec() - t0) / 1000.0
			if scenario == "far":
				lv.set_zoom(46.0)
		"district":
			lv._target = Vector3(137, 0, 79)
			lv.set_zoom(20.0)
			lv._zoom = lv._zoom_target
			var t1 := Time.get_ticks_usec()
			await _frames(150)                     # WearView builds the lot within 2 s
			t_build = float(Time.get_ticks_usec() - t1) / 1000.0
	var wv = lv.get_node("WearView")
	print("PERF scenario %s: built lots %s, five frames after the change took %.0f ms" % [scenario, str(wv.built_lots()), t_build])
	await _measure(scenario)
	OS.kill(OS.get_process_id())
