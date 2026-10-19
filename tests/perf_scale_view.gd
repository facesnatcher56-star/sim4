extends SceneTree
## Scale benchmark WITH the views (not a unit test): boots the real main scene (LotView, FolkView rigs, HUD), starts a new game on the
## generated town (tests/perf_town.gd) and plays N game days at speed-3 pace (1 game minute every 5 frames = 12 game minutes per second at 60 fps),
## frame by frame. Reports frame time (wall, and net of the empty-frame floor), node / object counts and memory. Headless = no GPU: draw calls and GPU
## time are not measured, but every script and node cost of the views is. Appends a section to docs/PERF_SCALE_RESULTS.md.
##   powershell -File tools/run_scale.ps1 -Views [-Profile big|today|mini] [-Days 1]
##   godot --headless --path . --script res://tests/perf_scale_view.gd -- [profile=big] [days=1] [--no-write]
const Town = preload("res://tests/perf_town.gd")
const FRAMES_PER_MIN := 5

func _initialize() -> void:
	_run()

func _run() -> void:
	var profile := "big"
	var days := 1
	var write := true
	for a in OS.get_cmdline_user_args():
		if a == "--no-write":
			write = false
		elif a.is_valid_int():
			days = int(a)
		else:
			profile = a
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in 10:
		await process_frame
	var t_floor := Time.get_ticks_usec()
	for i in 200:
		await process_frame
	var floor_ms := float(Time.get_ticks_usec() - t_floor) / 1000.0 / 200.0      # an empty frame on this machine / load (headless pacing + autoloads)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var t_build := Time.get_ticks_usec()
	if profile != "today":
		Town.install(profile)
	seed(4242)
	main.start_new_game(main.default_household())
	var info := Town.populate(profile)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	print("== view run '%s': built %s, %d lots, %d townies, %d objects in %.1f s; nodes after build %d" % [profile, str(info["map"]), info["lots"], info["townies"], info["objects"], float(Time.get_ticks_usec() - t_build) / 1.0e6, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	for i in 120:
		await process_frame
		if i % FRAMES_PER_MIN == 0:
			clock.advance_minutes(1)
	var W = root.get_node("World")
	var frames := days * 1440 * FRAMES_PER_MIN
	var times := PackedInt32Array()
	times.resize(frames)
	var node_max := 0
	var folk_max := 0
	var folk_sum := 0
	var t_prev := Time.get_ticks_usec()
	var t_start := t_prev
	var nodes_day1 := 0
	for f in frames:
		if f % FRAMES_PER_MIN == 0:
			clock.advance_minutes(1)
		await process_frame
		var now := Time.get_ticks_usec()
		times[f] = now - t_prev
		t_prev = now
		if f % 300 == 0:
			node_max = maxi(node_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			var nf: int = W.folk.size()
			folk_max = maxi(folk_max, nf)
			folk_sum += nf
		if (f + 1) % (360 * FRAMES_PER_MIN) == 0:
			print("   %s: %.2f ms/frame so far, %d nodes, %d folk" % [clock.time_string(), float(now - t_start) / 1000.0 / float(f + 1), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), W.folk.size()])
		if f + 1 == 1440 * FRAMES_PER_MIN:
			nodes_day1 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var wall_ms := float(Time.get_ticks_usec() - t_start) / 1000.0
	var sorted := Array(times)
	sorted.sort()
	var avg := wall_ms / float(frames)
	var res := "%.2f ms/frame avg wall, NET of the %.2f ms empty-frame floor %.2f ms (p99 %.1f, worst %.1f ms wall); nodes max %d end %d (day 1: %d), orphans %d, objects %d, static mem %.0f MB, folk avg %.1f max %d" % [avg, floor_ms, avg - floor_ms, float(sorted[int(frames * 0.99)]) / 1000.0, float(sorted[frames - 1]) / 1000.0, node_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), nodes_day1, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, float(folk_sum) / float(maxi(frames / 300, 1)), folk_max]
	print("== VIEW RUN '%s', %d game days at speed-3 pace: %s" % [profile, days, res])
	print("   budget: simulation + views under 4 ms avg / 12 ms worst per frame (simulation alone is in the headless run); headless = no GPU")
	if write:
		var path := ProjectSettings.globalize_path("res://docs/PERF_SCALE_RESULTS.md")
		var old := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(old + "\n## %s  VIEWS %s  (%d lots, %d townies, map %s, %d day(s), main scene + LotView + FolkView, headless)\n\n- %s\n" % [Time.get_datetime_string_from_system(false, true), profile, info["lots"], info["townies"], str(info["map"]), days, res])
			f.close()
	quit(0)
