extends SceneTree
## Adds a chair to every desk / computer / terminal use tile of the shipped templates that can take one (HouseDesks.fix_template):
## data/lot_templates.json (hand made), data/generated_lots.json, data/generated_buildings.json. Run again after regenerating the lots.
##   Godot --headless --path . --script res://tools/add_template_chairs.gd -- [--dry]
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_run("--dry" in OS.get_cmdline_user_args()))
	return true


## JSON numbers parse as floats: whole numbers back to int so the files keep their look.
static func _ints(v: Variant) -> Variant:
	if v is Dictionary:
		for k in v:
			v[k] = _ints(v[k])
	elif v is Array:
		for i in v.size():
			v[i] = _ints(v[i])
	elif v is float and is_equal_approx(v, round(v)) and absf(v) < 1.0e9:
		return int(v)
	return v


## Python json.dumps(indent=1) layout (what data/lot_templates.json was written with), keys in file order.
static func _pretty(v: Variant, depth: int = 0) -> String:
	var pad := " ".repeat(depth + 1)
	if v is Dictionary:
		if (v as Dictionary).is_empty():
			return "{}"
		var rows: Array = []
		for k in v:
			rows.append("%s%s: %s" % [pad, JSON.stringify(str(k)), _pretty(v[k], depth + 1)])
		return "{
" + ",
".join(rows) + "
" + " ".repeat(depth) + "}"
	if v is Array:
		if (v as Array).is_empty():
			return "[]"
		var rows2: Array = []
		for x in v:
			rows2.append(pad + _pretty(x, depth + 1))
		return "[
" + ",
".join(rows2) + "
" + " ".repeat(depth) + "]"
	return JSON.stringify(v)


func _run(dry: bool) -> int:
	for path in ["res://data/lot_templates.json", "res://data/generated_lots.json", "res://data/generated_buildings.json"]:
		var txt := FileAccess.get_file_as_string(path)
		var data: Dictionary = JSON.parse_string(txt)
		var lots: Dictionary = data["lots"]
		var total := 0
		var out_txt := txt
		for id in lots:
			var before: int = (lots[id]["objects"] as Array).size()
			var t: Dictionary = _ints(lots[id])
			var n := HouseDesks.fix_template(t)
			total += n
			if n == 0:
				continue
			print("%s: %s +%d chairs" % [path.get_file(), id, n])
			if not path.ends_with("lot_templates.json"):
				# one lot per line: swap just that line
				var key := '"%s": ' % id
				var a := out_txt.find("\n" + key)
				var b := out_txt.find("\n", a + 1)
				out_txt = out_txt.substr(0, a + 1) + key + JSON.stringify(t) + ("," if out_txt.substr(b - 1, 1) == "," else "") + out_txt.substr(b)
		if path.ends_with("lot_templates.json") and total > 0:
			out_txt = _pretty(_ints(data)) + "\n"
		print("%s: %d chairs added" % [path.get_file(), total])
		if total > 0 and not dry:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(out_txt)
			f.close()
	return 0
