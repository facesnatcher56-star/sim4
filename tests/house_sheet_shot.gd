extends SceneTree
## Not a unit test: contact sheet of generated lots as top-down floor plans.
## godot --path . --resolution 1600x900 --script res://tests/house_sheet_shot.gd -- out.png [--cols=4] [--ids=small_01,medium_02] [--set=small|medium|large|classic|townie|venues] [--legacy]
## No --ids/--set = every generated lot. --legacy appends the hand-made lot_templates.json lots for comparison.
func _initialize() -> void:
	_run()

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for a in args:
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
		if a == key:
			return "1"
	return def

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://house_sheet.png"
	var cols := int(_arg(args, "--cols", "4"))
	var ids: Array = []
	var ids_arg := _arg(args, "--ids", "")
	var set_arg := _arg(args, "--set", "")
	for id in HouseGenerator.ids():
		var sid := str(id)
		if ids_arg != "" and sid not in ids_arg.split(","):
			continue
		if set_arg != "" and ids_arg == "":
			var t: Dictionary = HouseGenerator.template(sid)
			var ok: bool = (set_arg == "venues" and str(t.get("kind", "")) == "venue") or (set_arg == "townie" and sid.begins_with("townie")) \
				or (set_arg != "venues" and set_arg != "townie" and sid.begins_with(set_arg + "_"))
			if not ok:
				continue
		ids.append(sid)
	ids.sort()
	var lots: Dictionary = {}
	for id in ids:
		lots[id] = HouseGenerator.template(id)
	if _arg(args, "--legacy", "") != "":
		var leg := HouseSignature.legacy_templates()
		for id in leg:
			if lots.size() < 40 and not lots.has("legacy_" + id):
				lots["legacy_" + id] = leg[id]
	var rows := int(ceil(float(lots.size()) / float(cols)))
	await process_frame
	await process_frame
	var vp := Vector2(root.size)
	var cell := Vector2(vp.x / cols, vp.y / maxi(rows, 1))
	var bg := ColorRect.new()
	bg.color = Color("#20242a")
	bg.size = vp
	root.add_child(bg)
	var i := 0
	for id in lots:
		var th := HouseThumb.new()
		var t: Dictionary = lots[id]
		th.tmpl = t
		th.clip_contents = true
		th.title = "%s  %s" % [id, str(t.get("label", ""))]
		th.crop = _crop(t)
		th.position = Vector2(i % cols, i / cols) * cell + Vector2(4, 4)
		th.size = cell - Vector2(8, 8)
		bg.add_child(th)
		i += 1
	for f in 4:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out, " (", lots.size(), " lots)")
	quit(0)

## Crop = walls bounding box (+ yard margin for homes), keeping the fence if there is one.
func _crop(t: Dictionary) -> Rect2i:
	var x0 := 99
	var y0 := 99
	var x1 := -1
	var y1 := -1
	for w in t.get("walls", []):
		if str(w["type"]) == "fence" and str(t.get("kind", "home")) != "home":
			continue
		for p in [w["a"], w["b"]]:
			x0 = mini(x0, int(p[0]))
			y0 = mini(y0, int(p[1]))
			x1 = maxi(x1, int(p[0]))
			y1 = maxi(y1, int(p[1]))
	if x1 < 0:
		return Rect2i(0, 0, 32, 24)
	var m := 2 if str(t.get("kind", "home")) == "home" else 1
	var r := Rect2i(x0 - m, y0 - m, x1 - x0 + 2 * m, y1 - y0 + 2 * m + (4 if m == 2 else 2))
	return r.intersection(Rect2i(0, 0, 32, 24))
