extends SceneTree
## Headless test runner.
##
##   Godot --headless --path . --script res://tests/run_all.gd                     FAST tier (default, well under a minute)
##   Godot --headless --path . --script res://tests/run_all.gd -- --slow           fast tier + the long simulations (~5 min)
##   Godot --headless --path . --script res://tests/run_all.gd -- --shuffle        random file order (prints the seed)
##   Godot --headless --path . --script res://tests/run_all.gd -- --shuffle=123    reproducible shuffled order
##   Godot --headless --path . --script res://tests/run_all.gd -- --only=sim_basic,world_test   (use `+` instead of `,` when the command goes through tools/godot_guard.ps1)
##   Godot --headless --path . --script res://tests/run_all.gd -- --list           print the file list and exit
##   Godot --headless --path . --script res://tests/run_one.gd -- <test file base name>      a single test file
##
## (`--all` is an alias of `--slow`; flags can be combined; `--budget=<s>` = wall-clock limit, default 900 fast / 2400 slow, per file 300 / 1200 for SLOW; see tests/watchdog.gd.)
## Discovers tests/*_test.gd, tests/sim_*.gd and tests/world_*.gd. A file is a test when its script has a `run()` method that
## returns an Array of failure strings (empty = pass); other files (kits, shots, helpers) are skipped. Exit code 1 on any failure.
## Every file starts from the same state: TestFixture.reset() runs before and after it. Long tests read `TestFixture.fast`
## (true unless --slow) and shorten their simulation in the fast tier.

## Long simulations: only run with --slow / --all.
const SLOW := [
	"systems_family_integration_test.gd", "systems_integration_test.gd", "hood_sim_test.gd", "weather_longrun_test.gd",
	"social_autonomy_test.gd", "sim_longrun.gd", "incidents_longrun_test.gd", "crime_longrun_test.gd", "accident_longrun_test.gd", "health_longrun_test.gd", "disaster_longrun_test.gd", "fire_longrun_test.gd", "commute_longrun_test.gd", "econ_longrun_test.gd", "crime_rates_test.gd", "crime_child_abuse_rates_test.gd", "bldg_apartments_run_test.gd", "story_pacing_longrun_test.gd",
	"social_autonomy_test.gd", "sim_longrun.gd", "incidents_longrun_test.gd", "crime_longrun_test.gd", "accident_longrun_test.gd", "health_longrun_test.gd", "disaster_longrun_test.gd", "fire_longrun_test.gd", "commute_longrun_test.gd", "econ_longrun_test.gd",
	"social_autonomy_test.gd", "sim_longrun.gd", "incidents_longrun_test.gd", "crime_longrun_test.gd", "accident_longrun_test.gd", "health_longrun_test.gd", "disaster_longrun_test.gd", "fire_longrun_test.gd", "commute_longrun_test.gd", "cruise_longrun_test.gd",
	"systems_family_integration_test.gd", "systems_integration_test.gd", "hood_sim_test.gd", "weather_longrun_test.gd", "social_autonomy_test.gd", "sim_longrun.gd", "incidents_longrun_test.gd", "crime_longrun_test.gd", "accident_longrun_test.gd", "health_longrun_test.gd", "disaster_longrun_test.gd", "fire_longrun_test.gd", "commute_longrun_test.gd", "econ_longrun_test.gd", "cruise_longrun_test.gd",
]

const Watchdog := preload("res://tests/watchdog.gd")
const FILE_BUDGET_S := 300.0       # per test file (fast tier)
const SLOW_FILE_BUDGET_S := 1200.0 # per test file in the SLOW list

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var code := _run(OS.get_cmdline_user_args())
	quit(code)
	return true

func _arg_value(args: PackedStringArray, key: String) -> String:
	for a in args:
		if a == key:
			return ""
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return "\u0000"

func _has_flag(args: PackedStringArray, key: String) -> bool:
	return _arg_value(args, key) != "\u0000"

func _discover(slow: bool, only: Array) -> Array[String]:
	var files: Array[String] = []
	var d := DirAccess.open("res://tests")
	if d == null:
		return files
	for f in d.get_files():
		if not f.ends_with(".gd") or f == "run_all.gd":
			continue
		if not (f.ends_with("_test.gd") or f.begins_with("sim_") or f.begins_with("world_")):
			continue
		if not only.is_empty():
			if only.has(f.get_basename()) or only.has(f):
				files.append(f)
			continue
		if (SLOW.has(f) or f.ends_with("_longrun_test.gd")) and not slow:      # any *_longrun_test.gd is slow by name
			continue
		files.append(f)
	files.sort()
	return files

func _run(args: PackedStringArray) -> int:
	var slow := _has_flag(args, "--slow") or _has_flag(args, "--all")
	var only_arg := _arg_value(args, "--only")
	var only: Array = [] if only_arg == "\u0000" or only_arg == "" else Array(only_arg.replace("+", ",").split(","))
	var files := _discover(slow, only)
	var fixture := _arg_value(args, "--fixture")   # run only tests/fixtures/<name>.gd (watchdog tests); never discovered otherwise
	if fixture != "\u0000" and fixture != "":
		files = ["fixtures/" + fixture + ".gd"]
	var shuffle_arg := _arg_value(args, "--shuffle")
	if shuffle_arg != "\u0000":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(shuffle_arg) if shuffle_arg != "" else int(Time.get_ticks_usec())
		for i in range(files.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := files[i]
			files[i] = files[j]
			files[j] = tmp
		print("shuffled order, seed %d  (rerun with --shuffle=%d)" % [rng.seed, rng.seed])
	if _has_flag(args, "--list"):
		for f in files:
			print(f)
		return 0
	TestFixture.fast = not slow
	print("tier: %s, %d test files" % ["SLOW (all)" if slow else "fast", files.size()])
	var total_fail := 0
	var ran := 0
	var t_all := Time.get_ticks_msec()
	var wd = Watchdog.start(Watchdog.budget_from(args, 2400.0 if slow else 900.0), "run_all")
	for f in files:
		var file_budget := SLOW_FILE_BUDGET_S if SLOW.has(f) else FILE_BUDGET_S
		wd.set_label(f, file_budget)
		var script: Variant = load("res://tests/" + f)
		if script == null or not (script is GDScript):
			print("FAIL  %s  (could not load script)" % f)
			total_fail += 1
			continue
		var inst: Variant = (script as GDScript).new()
		if inst == null or not inst.has_method("run"):
			continue   # helper file, not a test
		ran += 1
		TestFixture.reset()
		var t0 := Time.get_ticks_msec()
		var failures: Variant = inst.run()
		var ms := Time.get_ticks_msec() - t0
		if inst is Node:
			(inst as Node).free()
		TestFixture.reset()
		if ms > file_budget * 1000.0:
			failures = ["TIMEOUT in %s: took %d s, per-file budget %d s" % [f, ms / 1000, int(file_budget)]]
		if failures is Array and (failures as Array).is_empty():
			print("PASS  %s  (%d ms)" % [f, ms])
		else:
			total_fail += 1
			print("FAIL  %s  (%d ms)" % [f, ms])
			if failures is Array:
				for m in failures:
					print("      - " + str(m))
	wd.stop()
	print("---- %d test files, %d failed, %.1f s ----" % [ran, total_fail, float(Time.get_ticks_msec() - t_all) / 1000.0])
	print("RESULT: " + ("PASS" if total_fail == 0 and ran > 0 else "FAIL"))
	return 0 if (total_fail == 0 and ran > 0) else 1
