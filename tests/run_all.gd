extends SceneTree
## Headless test runner:  Godot --headless --path . --script res://tests/run_all.gd
## Discovers tests/*_test.gd, tests/sim_*.gd and tests/world_*.gd. Each file's script is instantiated and, if it has a
## `run()` method, called; run() returns an Array of failure strings (empty = pass). Exit code 1 on any failure.

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var code := _run()
	quit(code)
	return true

func _run() -> int:
	var files: Array[String] = []
	var d := DirAccess.open("res://tests")
	if d == null:
		print("FAIL: cannot open res://tests")
		return 1
	for f in d.get_files():
		if not f.ends_with(".gd") or f == "run_all.gd":
			continue
		if f.ends_with("_test.gd") or f.begins_with("sim_") or f.begins_with("world_"):
			files.append(f)
	files.sort()
	var total_fail := 0
	var ran := 0
	for f in files:
		var path := "res://tests/" + f
		var script: Variant = load(path)
		if script == null or not (script is GDScript):
			print("FAIL  %s  (could not load script)" % f)
			total_fail += 1
			continue
		var inst: Variant = (script as GDScript).new()
		if inst == null or not inst.has_method("run"):
			continue   # helper file, not a test
		ran += 1
		var t0 := Time.get_ticks_msec()
		var failures: Variant = inst.run()
		var ms := Time.get_ticks_msec() - t0
		if inst is Node:
			(inst as Node).free()
		if failures is Array and (failures as Array).is_empty():
			print("PASS  %s  (%d ms)" % [f, ms])
		else:
			total_fail += 1
			print("FAIL  %s  (%d ms)" % [f, ms])
			if failures is Array:
				for m in failures:
					print("      - " + str(m))
	print("---- %d test files, %d failed ----" % [ran, total_fail])
	print("RESULT: " + ("PASS" if total_fail == 0 and ran > 0 else "FAIL"))
	return 0 if (total_fail == 0 and ran > 0) else 1
