extends SceneTree
## Regenerate data/generated_lots.json (homes + venue alternates), deterministic per seed.
##   Godot --headless --path . --script res://tools/gen_houses.gd -- [--seed=N] [--only=small_01,cafe_v1] [--dry] [--report]
## --seed adds N to every spec seed (0 = the committed set). --dry prints without writing. Exit 1 when a lot failed.
var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_run(OS.get_cmdline_user_args()))
	return true

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for a in args:
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
		if a == key:
			return "1"
	return def

func _run(args: PackedStringArray) -> int:
	var bump := int(_arg(args, "--seed", "0"))
	var only := _arg(args, "--only", "")
	var res: Dictionary = HouseBatch.generate(bump, only.split(",") if only != "" else PackedStringArray())
	for id in res["reports"]:
		var r: Dictionary = res["reports"][id]
		print("%-12s %s" % [id, str(r)])
	print("generated %d lots, %d failed" % [(res["lots"] as Dictionary).size(), (res["failed"] as Array).size()])
	if (res["failed"] as Array).size() > 0:
		print("FAILED: ", res["failed"])
		return 1
	if _arg(args, "--dry", "") == "":
		HouseBatch.write(res["lots"], bump)
		print("wrote ", HouseGenerator.GENERATED_PATH)
	return 0
