extends SceneTree
## Run a single test file:  Godot --headless --path . --script res://tests/run_one.gd -- systems_family_genetics_test
const Watchdog := preload("res://tests/watchdog.gd")
var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var args := Watchdog.user_args()   # without --budget=<s> (default 300)
	if args.is_empty():
		print("usage: -- <test file base name>")
		quit(2)
		return true
	TestFixture.isolate_user_files()
	var wd = Watchdog.start(Watchdog.budget_from(OS.get_cmdline_user_args(), 300.0), args[0])
	var script: Variant = load("res://tests/%s.gd" % args[0])
	var inst: Variant = (script as GDScript).new()
	var t0 := Time.get_ticks_msec()
	var failures: Array = inst.run()
	if failures.is_empty():
		print("PASS  %s  (%d ms)" % [args[0], Time.get_ticks_msec() - t0])
	else:
		print("FAIL  %s" % args[0])
		for m in failures:
			print("      - " + str(m))
	wd.stop()
	TestFixture.clean_user_files()
	quit(0 if failures.is_empty() else 1)
	return true
