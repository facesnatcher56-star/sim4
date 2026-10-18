extends SceneTree
## Not a unit test: frame-time probe (vsync off) with N extra folk and a weather type. Prints avg ms / fps and script-process share.
## godot --path . --resolution 1600x900 --script res://tests/perf_shot.gd -- [extra_folk=6] [weather=rain] [hour=12]
var _main: Node = null

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _measure(label: String, n: int = 240) -> void:
	await _frames(20)
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var rend := 0.0
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		rend += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	print("%-22s %.2f ms/frame (%.0f fps)  script-process %.2f ms  draw calls %.0f" % [label, ms, 1000.0 / ms, proc / n * 1000.0, rend / n])

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	var extra := int(args[0]) if args.size() > 0 else 6
	var wx: String = args[1] if args.size() > 1 else "rain"
	var hour := float(args[2]) if args.size() > 2 else 12.0
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(20)
	var W = root.get_node("World")
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	clock.total_minutes = int(hour * 60.0)
	for i in extra:
		var f := Folk.create("X%d" % i)
		W.add_folk(f, Vector2i(10 + i, 14))
	await _measure("%d folk, sunny" % W.all_folk().size())
	Weather.force(wx, 0.0)
	await _measure("%d folk, %s" % [W.all_folk().size(), wx])
	clock.set_speed(3)
	await _measure("speed 3, %s" % wx)
	quit(0)
