extends SceneTree
## Regenerate data/generated_buildings.json (multi-floor buildings: houses with upstairs / basement, apartments, towers, hospital, ...).
##   Godot --headless --path . --script res://tools/gen_buildings.gd -- [--seed=N] [--only=tower_01] [--dry]
## Deterministic per spec seed (data/building_specs.json); layouts differ from every home / venue in generated_lots.json and lot_templates.json.
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
	var taken: Dictionary = BuildingGen.taken_registry()
	var res: Dictionary = BuildingGen.make_all(bump, taken, only.split(",") if only != "" else PackedStringArray())
	for id in res["reports"]:
		print("%-12s %s" % [id, str(res["reports"][id])])
	print("generated %d buildings, %d failed" % [(res["lots"] as Dictionary).size(), (res["failed"] as Array).size()])
	if (res["failed"] as Array).size() > 0:
		print("FAILED: ", res["failed"])
		return 1
	if _arg(args, "--dry", "") == "":
		BuildingGen.write(res["lots"], bump)
		print("wrote ", BuildingGen.GENERATED_PATH)
	return 0
