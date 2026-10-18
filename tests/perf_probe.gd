extends SceneTree
## Reusable profiler (not a unit test): boots the real game (main.start_new_game), advances N game days minute by minute and
## times every Clock listener (minute / hour / day) separately, plus SimDirector's inner phases.
##   godot --headless --path . --script res://tests/perf_probe.gd -- [days=2]
## Prints a table sorted by total time. Run through tools/godot_guard.ps1 (see docs/PERFORMANCE.md).
var _main: Node = null
var _frames := 0
var _days := 2
var _acc: Dictionary = {}       # label -> [usec, calls]

func _label(c: Callable) -> String:
	var o = c.get_object()
	var n: String = o.get_script().get_global_name() if o != null and o.get_script() != null and o.get_script().get_global_name() != "" else (o.name if o is Node else str(o))
	return "%s.%s" % [n, c.get_method()]

func _wrap(sig: Signal, tag: String) -> void:
	for conn in sig.get_connections():
		var orig: Callable = conn["callable"]
		var label := "%s %s" % [tag, _label(orig)]
		sig.disconnect(orig)
		sig.connect(func(a):
			var t := Time.get_ticks_usec()
			orig.call(a)
			var rec: Array = _acc.get(label, [0, 0])
			rec[0] += Time.get_ticks_usec() - t
			rec[1] += 1
			_acc[label] = rec)

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0:
			_days = int(args[0])
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		seed(4242)
		_main.start_new_game(_main.default_household())
	if _frames == 30:
		var clock = root.get_node("Clock")
		var dir = root.get_node("SimDirector")
		for pair in [[clock.minute_passed, "min "], [clock.hour_passed, "hour"], [clock.day_passed, "day "]]:
			_wrap(pair[0], pair[1])
		dir.prof.clear()
		SystemsManager.instance.prof.clear()
		SystemsManager.instance.prof_on = true
		dir.prof_on = true
		var t0 := Time.get_ticks_msec()
		var folk_ticks := 0
		for m in range(_days * 1440):
			folk_ticks += root.get_node("World").all_folk().size()
			clock.advance_minutes(1)
		var total := Time.get_ticks_msec() - t0
		dir.prof_on = false
		SystemsManager.instance.prof_on = false
		print("== perf_probe: %d game days in %d ms (avg folk per minute %.1f)" % [_days, total, float(folk_ticks) / float(_days * 1440)])
		var rows: Array = []
		for k in _acc:
			rows.append([k, _acc[k][0] / 1000.0, _acc[k][1]])
		var sp: Dictionary = SystemsManager.instance.prof
		for k in sp:
			rows.append(["  systems/" + k, sp[k][0] / 1000.0, sp[k][1]])
		for k in dir.prof:
			rows.append(["  director/" + k, dir.prof[k][0] / 1000.0, dir.prof[k][1]])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		for r in rows:
			if r[1] >= 20.0:
				print("%-48s %9.0f ms  %7d calls  %8.3f ms/call" % [r[0], r[1], r[2], r[1] / maxi(r[2], 1)])
		quit(0)
	return false
