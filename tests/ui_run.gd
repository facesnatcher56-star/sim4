extends SceneTree
## Standalone runner for UI tests: godot --headless --path . --script res://tests/ui_run.gd
var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var total := 0
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("ui_") and f.ends_with("_test.gd"):
			var t = load("res://tests/" + f).new()
			var fails: Array = t.run()
			total += fails.size()
			print("%s: %s" % [f, "OK" if fails.is_empty() else "FAIL"])
			for m in fails:
				print("  - ", m)
	print("UI TESTS: %d failure(s)" % total)
	quit(1 if total > 0 else 0)
	return true
