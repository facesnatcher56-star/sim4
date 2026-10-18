extends SceneTree
## Standalone runner for the world tests:
##   Godot --headless --path . --script res://tests/run_world.gd


func _initialize() -> void:
	await process_frame
	var t = load("res://tests/world_test.gd").new()
	var f: Array = t.run()
	if f.is_empty():
		print("WORLD TESTS PASSED")
		quit(0)
	else:
		for m in f:
			printerr("FAIL: ", m)
		print("WORLD TESTS FAILED: %d" % f.size())
		quit(1)
