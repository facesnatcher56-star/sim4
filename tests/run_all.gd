extends SceneTree
## Headless test runner.
##
##   Godot --headless --path . --script res://tests/run_all.gd                     FAST tier (default, well under a minute)
##   Godot --headless --path . --script res://tests/run_all.gd -- --slow           fast tier + the long simulations (~5 min)
##   Godot --headless --path . --script res://tests/run_all.gd -- --shuffle        random file order (prints the seed)
##   Godot --headless --path . --script res://tests/run_all.gd -- --shuffle=123    reproducible shuffled order
##   Godot --headless --path . --script res://tests/run_all.gd -- --only=sim_basic,world_test   (use `+` instead of `,` when the command goes through tools/godot_guard.ps1)
##   Godot --headless --path . --script res://tests/run_all.gd -- --list           print the file list and exit
##   Godot --headless --path . --script res://tests/run_all.gd -- --shard=2/6      the 3rd of 6 balanced slices of the file list (tools/run_fast.ps1 runs them side by side)
##   Godot --headless --path . --script res://tests/run_one.gd -- <test file base name>      a single test file
##
## (`--all` is an alias of `--slow`; flags can be combined; `--budget=<s>` = wall-clock limit, default 900 fast / 2400 slow, per file 300 / 1200 for SLOW; see tests/watchdog.gd.)
## Discovers tests/*_test.gd, tests/sim_*.gd and tests/world_*.gd. A file is a test when its script has a `run()` method that
## returns an Array of failure strings (empty = pass); other files (kits, shots, helpers) are skipped. Exit code 1 on any failure.
## Every file starts from the same state: TestFixture.reset() runs before and after it. Long tests read `TestFixture.fast`
## (true unless --slow) and shorten their simulation in the fast tier.

## Long simulations: only run with --slow / --all.
const SLOW := [
	"systems_family_integration_test.gd", "systems_integration_test.gd", "hood_sim_test.gd", "weather_longrun_test.gd", "social_autonomy_test.gd", "sim_longrun.gd", "incidents_longrun_test.gd", "crime_longrun_test.gd", "accident_longrun_test.gd", "health_longrun_test.gd", "disaster_longrun_test.gd", "fire_longrun_test.gd", "commute_longrun_test.gd", "econ_longrun_test.gd", "crime_rates_test.gd", "crime_child_abuse_rates_test.gd", "bldg_apartments_run_test.gd", "story_pacing_longrun_test.gd", "cruise_longrun_test.gd", "romance_longrun_test.gd", "townie_growth_longrun_test.gd", "succession_longrun_test.gd", "edu_longrun_test.gd", "health_life_longrun_test.gd", "culture_longrun_test.gd", "pets_longrun_test.gd",
]

const Watchdog := preload("res://tests/watchdog.gd")

## Seconds a file took on a quiet machine (2026-10-19); everything else counts as 2. Only used to balance the shards: a wrong guess costs balance, never correctness.
const WEIGHT := {"traffic_flow_test.gd": 36, "coop_net_test.gd": 56, "cruise_needs_test.gd": 30, "romance_run_test.gd": 28, "townie_needs_test.gd": 25, "coop_skip_run_test.gd": 22,
	"circadian_test.gd": 16, "content_run_test.gd": 15, "determinism_test.gd": 14, "vacation_trip_test.gd": 13, "commute_test.gd": 12, "crowd_floor_test.gd": 11,
	"hood_lots_test.gd": 11, "map_walk_test.gd": 10, "hood_travel_test.gd": 10, "weather_effects_test.gd": 10, "start_solo_run_test.gd": 9, "social_drama_test.gd": 9,
	"bldg_gen_test.gd": 9, "map_lots_test.gd": 8, "coop_home_lot_test.gd": 8, "fire_survival_test.gd": 8, "vacation_life_test.gd": 7, "romance_autonomy_test.gd": 7,
	"incidents_death_test.gd": 7, "incidents_core_test.gd": 6, "disaster_town_test.gd": 5, "fire_people_test.gd": 5, "social_autonomy_run_test.gd": 5}
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

## Slice k of n: the files are dealt heaviest first to the lightest slice (WEIGHT), so the slices finish together; deterministic for a given file list.
func _shard(files: Array[String], k: int, n: int) -> Array[String]:
	var order: Array = files.duplicate()
	order.sort_custom(func(a, b): return int(WEIGHT.get(a, 2)) > int(WEIGHT.get(b, 2)) or (int(WEIGHT.get(a, 2)) == int(WEIGHT.get(b, 2)) and a < b))
	var load: Array = []
	var mine: Dictionary = {}
	for _i in n:
		load.append(0)
	for f in order:
		var best := 0
		for i in n:
			if int(load[i]) < int(load[best]):
				best = i
		load[best] = int(load[best]) + int(WEIGHT.get(f, 2))
		if best == k % n:
			mine[f] = true
	var out: Array[String] = []
	for f in files:
		if mine.has(f):
			out.append(f)
	return out

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
	var shard := _arg_value(args, "--shard")
	if shard != "\u0000" and shard.find("/") > 0:
		files = _shard(files, int(shard.get_slice("/", 0)), maxi(int(shard.get_slice("/", 1)), 1))
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
