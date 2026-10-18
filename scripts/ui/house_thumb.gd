class_name HouseThumb
extends Control
## Top-down floor plan of a lot template DICTIONARY (generated or hand-made): floors, walls, doors, windows, furniture with
## a short label and a tick showing which way each piece faces. Used by the contact-sheet harness (tests/house_sheet_shot.gd).

const FLOOR := {"grass": "#4f7d3f", "dirt": "#7a5c3b", "stone": "#8a8a8a", "concrete": "#6f7478", "wood": "#b08a5a", "tile": "#c3d2da", "carpet": "#8a739e"}

var tmpl: Dictionary = {}
var crop := Rect2i(0, 0, 32, 24)
var labels := true
var title := ""


func _color_of(d: Dictionary) -> Color:
	var tags: Array = d.get("tags", [])
	for pair in [["bed", "#4f78c9"], ["seat", "#9b5fc0"], ["kitchen", "#e8e8e8"], ["bathroom", "#4fc3d9"], ["plumbing", "#4fc3d9"], ["storage", "#8a5a2b"],
			["plant", "#4fa04f"], ["decor", "#c9b84f"], ["electronics", "#333840"], ["dining", "#b07a3a"], ["fitness", "#d9694f"], ["art", "#e07ab0"]]:
		if pair[0] in tags:
			return Color(pair[1])
	return Color("#a08060")


func _draw() -> void:
	var k: float = minf(size.x / crop.size.x, (size.y - 16.0) / crop.size.y)
	var o := Vector2(0, 16)
	var P := func(v: Vector2) -> Vector2: return o + (v - Vector2(crop.position)) * k
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(2, 12), title, HORIZONTAL_ALIGNMENT_LEFT, size.x, 12, Color.WHITE)
	draw_rect(Rect2(o, Vector2(crop.size) * k), Color(FLOOR["grass"]))
	for fl in tmpl.get("floors", []):
		var r: Array = fl["rect"]
		draw_rect(Rect2(P.call(Vector2(r[0], r[1])), Vector2(r[2] - r[0] + 1, r[3] - r[1] + 1) * k), Color(FLOOR.get(str(fl["type"]), "#888888")))
	var defs := HousePlan.defs()
	for ob in tmpl.get("objects", []):
		var id := str(ob["def"])
		if id == "door" or id == "window":
			continue
		var d: Dictionary = defs.get(id, {})
		var rot := int(ob.get("rot", 0))
		var t := Vector2i(int(ob["tile"][0]), int(ob["tile"][1]))
		var fp := HousePlan.footprint(d, t, rot)
		var floor_layer := HousePlan.is_floor_layer(d)
		var col := _color_of(d)
		if floor_layer:
			col = Color(0.9, 0.85, 0.6, 0.35) if id == "rug" else Color(1, 1, 0.6, 0.0)
		var cen := Vector2.ZERO
		for c in fp:
			draw_rect(Rect2(P.call(Vector2(c)) + Vector2(1, 1), Vector2(k - 2, k - 2)), col)
			cen += Vector2(c) + Vector2(0.5, 0.5)
		cen /= float(fp.size())
		if not floor_layer:
			var f: Vector2i = HousePlan.FRONT[rot]
			var base: Vector2 = P.call(cen)
			draw_line(base, base + Vector2(f) * k * 0.45, Color.BLACK, 2.0)
			if labels and k >= 22.0:
				draw_string(font, base - Vector2(k * 0.3, -3), id.substr(0, 3), HORIZONTAL_ALIGNMENT_LEFT, k, 9, Color.BLACK)
	for wl in tmpl.get("walls", []):
		var a: Vector2 = P.call(Vector2(wl["a"][0], wl["a"][1]))
		var b: Vector2 = P.call(Vector2(wl["b"][0], wl["b"][1]))
		var ty := str(wl["type"])
		draw_line(a, b, Color("#f1ece2") if ty == "wall" else (Color("#d9c9a8") if ty == "fence" else Color("#c8863c")), 3.0 if ty == "wall" else 1.5)
	for ob in tmpl.get("objects", []):
		var id := str(ob["def"])
		if id != "door" and id != "window":
			continue
		var e := HousePlan.mount_edge(Vector2i(int(ob["tile"][0]), int(ob["tile"][1])), int(ob.get("rot", 0)))
		var a2: Vector2 = P.call(Vector2(e.x, e.y))
		var b2: Vector2 = P.call(Vector2(e.x + (1 if e.z == 0 else 0), e.y + (1 if e.z == 1 else 0)))
		draw_line(a2, b2, Color("#7a4a1c") if id == "door" else Color("#69b7e8"), 5.0 if id == "door" else 3.5)
