extends SceneTree
## Reusable profiler (not a unit test): boots the real game (main.start_new_game), advances N game days minute by minute and
## times every SimScheduler job (minute / hour / day) separately, plus SimDirector's inner phases.
##   godot --headless --path . --script res://tests/perf_probe.gd -- [days=2]
## Prints a table sorted by total time. Run through tools/godot_guard.ps1 (see docs/PERFORMANCE.md).
const Watchdog := preload("res://tests/watchdog.gd")
var _wd = null
var _main: Node = null
var _frames := 0
var _days := 2
var _acc: Dictionary = {}       # label -> [usec, calls]

func _process(_d: float) -> bool:
	var args := Watchdog.user_args()
	if _main == null:
		_wd = Watchdog.start(Watchdog.budget_from(OS.get_cmdline_user_args(), 600.0), "perf_probe")
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
		var sched := SimScheduler.of(clock)
		sched.reset_stats()
		sched.profile = true
		dir.prof.clear()
		dir.prof_on = true
		PerfProf.totals.clear()
		PerfProf.on = true
		var t0 := Time.get_ticks_msec()
		var folk_ticks := 0
		for m in range(_days * 1440):
			folk_ticks += root.get_node("World").all_folk().size()
			clock.advance_minutes(1)
		var total := Time.get_ticks_msec() - t0
		dir.prof_on = false
		PerfProf.on = false
		sched.profile = false
		print("== perf_probe: %d game days in %d ms (avg folk per minute %.1f)" % [_days, total, float(folk_ticks) / float(_days * 1440)])
		var rows: Array = []
		for k in _acc:
			rows.append([k, _acc[k][0] / 1000.0, _acc[k][1]])
		var st: Dictionary = sched.stats()
		for r in st["rows"]:
			rows.append(["  job %s %s" % [str(r["cadence"]), r["name"]], float(r["usec"]) / 1000.0, r["calls"]])
		print("scheduler: %d jobs, %d ticks, deferred %d, timed fired %d" % [st["jobs"], st["ticks"], st["deferred_total"], st["timed_fired"]])
		for k in dir.prof:
			rows.append(["  director/" + k, dir.prof[k][0] / 1000.0, dir.prof[k][1]])
		for k in PerfProf.totals:
			rows.append(["    " + k, PerfProf.totals[k][0] / 1000.0, PerfProf.totals[k][1]])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		for r in rows:
			if r[1] >= 20.0:
				print("%-48s %9.0f ms  %7d calls  %8.3f ms/call" % [r[0], r[1], r[2], r[1] / maxi(r[2], 1)])
		_wd.stop()
		quit(0)
	return false