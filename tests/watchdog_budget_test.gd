extends RefCounted
## Watchdog helper basics (the kill paths are covered by tools/test_guard.ps1): budget parsing and a clean start/stop.
const Watchdog := preload("res://tests/watchdog.gd")

func run() -> Array:
	var f: Array = []
	if Watchdog.budget_from(PackedStringArray(["x", "--budget=7"]), 300.0) != 7.0:
		f.append("--budget=7 not parsed")
	if Watchdog.budget_from(PackedStringArray(["x"]), 300.0) != 300.0:
		f.append("default budget not used")
	var wd = Watchdog.start(60.0, "watchdog_budget_test")
	wd.set_label("a", 30.0)
	wd.stop()
	return f
