class_name MapBuilder
extends RefCounted
## Builds the deterministic starter neighbourhood on the World's big grid (World.MAP_W x World.MAP_H), from data/map_layout.json:
## a grid of 6-wide roads (4 asphalt + a sidewalk each side, crosswalks at every junction arm, centre lines as region `lines`),
## reserved LOT RECTANGLES (floor "lawn") with a region record per lot of data/neighborhood.json, a green with a pond and a
## wooded south strip. The lots' CONTENT is placed by MapLots (which calls build() first).
##
##   MapBuilder.build(World)        -> report {regions, lots, roads, seconds}
##   MapBuilder.lot_rect(lot_id) / layout() / tree_density() / tree_seed()

const LAYOUT_PATH := "res://data/map_layout.json"
const HOOD_PATH := "res://data/neighborhood.json"
const GATE_X := 15                    # street-side gate tile column inside every lot (template doors/gates sit at x = 15)

static var _layout: Dictionary = {}
static var _hood: Dictionary = {}
## Benchmarks only (tests/perf_town.gd): a bigger generated map. Vector2i.ZERO = the game's World.MAP_W x MAP_H. Never set by the game.
static var size_override: Vector2i = Vector2i.ZERO


static func layout() -> Dictionary:
	if _layout.is_empty():
		_layout = _json(LAYOUT_PATH)
	return _layout


static func _hood_lots() -> Array:
	if _hood.is_empty():
		_hood = _json(HOOD_PATH)
	return _hood.get("lots", [])


static func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func tree_density() -> float:
	return float(layout().get("tree_density", 0.12))


static func tree_seed() -> int:
	return int(layout().get("tree_seed", 1))


static func _road_w() -> int:
	return int(layout().get("road_w", 6))


## Top-left tile of block slot (col,row).
static func slot_origin(slot: Array) -> Vector2i:
	var lay := layout()
	return Vector2i(int((lay["vroads_x"] as Array)[int(slot[0])]) + _road_w(), int((lay["hroads_y"] as Array)[int(slot[1])]) + _road_w())


static func lot_size() -> Vector2i:
	var s: Array = layout().get("lot_size", [32, 24])
	return Vector2i(int(s[0]), int(s[1]))


## Rect of a neighborhood lot id on the map (Rect2i() when it has no slot).
static func lot_rect(lot_id: String) -> Rect2i:
	var slot: Variant = (layout().get("lots", {}) as Dictionary).get(lot_id, null)
	if slot == null:
		return Rect2i()
	return Rect2i(slot_origin(slot), lot_size())


# ------------------------------------------------------------------ build

static func build(w) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var lay := layout()
	if size_override != Vector2i.ZERO:
		w.reset(size_override.x, size_override.y)
	else:
		w.reset(w.MAP_W, w.MAP_H)
	w.regions.enforce = false
	_paint_lots(w)
	_paint_green(w, lay)
	var roads := _paint_roads(w, lay)
	_add_regions(w, lay, roads)
	w.regions.enforce = true
	w.rooms.invalidate_all()
	w._emit("floors_changed")
	w._emit("world_reset")
	return {"regions": w.regions.regions.size(), "lots": w.regions.of_kind("home").size() + w.regions.of_kind("venue").size() + w.regions.of_kind("townie_home").size(),
		"roads": roads.size(), "seconds": float(Time.get_ticks_usec() - t0) / 1.0e6}


static func _paint_lots(w) -> void:
	for slot in (layout()["lots"] as Dictionary).values():
		var o := slot_origin(slot)
		w.set_floor_rect_raw(o, o + lot_size() - Vector2i.ONE, "lawn")
	for slot2 in plots().values():
		var o2 := slot_origin(slot2)
		w.set_floor_rect_raw(o2, o2 + lot_size() - Vector2i.ONE, "lawn")


## Reserved empty blocks where town-planning projects build (task 12b): plot id -> slot [col, row].
static func plots() -> Dictionary:
	return layout().get("plots", {})


static func plot_rect(plot_id: String) -> Rect2i:
	var slot: Variant = plots().get(plot_id, null)
	return Rect2i() if slot == null else Rect2i(slot_origin(slot), lot_size())


static func _paint_green(w, lay: Dictionary) -> void:
	var g: Dictionary = lay.get("green", {})
	if g.is_empty():
		return
	var o := slot_origin(g["slot"])
	var p: Array = g["pond"]
	w.set_floor_rect_raw(o + Vector2i(int(p[0]) - 1, int(p[1]) - 1), o + Vector2i(int(p[2]) + 1, int(p[3]) + 1), "sand")
	w.set_floor_rect_raw(o + Vector2i(int(p[0]), int(p[1])), o + Vector2i(int(p[2]), int(p[3])), "water")


# ------------------------------------------------------------------ roads

## Floor of a road tile ("" when the tile is not part of the road grid).
static func road_floor(lay: Dictionary, x: int, y: int) -> String:
	var rw := _road_w()
	var vx: Array = lay["vroads_x"]
	var hy: Array = lay["hroads_y"]
	var vi := -1
	var hi := -1
	for k in vx.size():
		if x >= int(vx[k]) and x < int(vx[k]) + rw:
			vi = k
	for k in hy.size():
		if y >= int(hy[k]) and y < int(hy[k]) + rw:
			hi = k
	var in_x: bool = x >= int(vx[0]) and x < int(vx[vx.size() - 1]) + rw
	var in_y: bool = y >= int(hy[0]) and y < int(hy[hy.size() - 1]) + rw
	if vi >= 0 and hi < 0 and in_y:
		var i := x - int(vx[vi])
		return "asphalt" if i >= 1 and i <= rw - 2 else "sidewalk"
	if hi >= 0 and vi < 0 and in_x:
		var j := y - int(hy[hi])
		return "asphalt" if j >= 1 and j <= rw - 2 else "sidewalk"
	if vi >= 0 and hi >= 0:
		var i2 := x - int(vx[vi])
		var j2 := y - int(hy[hi])
		var inner_i: bool = i2 >= 1 and i2 <= rw - 2
		var inner_j: bool = j2 >= 1 and j2 <= rw - 2
		if inner_i and inner_j:
			return "asphalt"
		if inner_i and ((j2 == 0 and hi > 0) or (j2 == rw - 1 and hi < hy.size() - 1)):
			return "asphalt"
		if inner_j and ((i2 == 0 and vi > 0) or (i2 == rw - 1 and vi < vx.size() - 1)):
			return "asphalt"
		return "sidewalk"
	return ""


static func _paint_roads(w, lay: Dictionary) -> Array:
	var rw := _road_w()
	var vx: Array = lay["vroads_x"]
	var hy: Array = lay["hroads_y"]
	var x0 := int(vx[0])
	var x1 := int(vx[vx.size() - 1]) + rw
	var y0 := int(hy[0])
	var y1 := int(hy[hy.size() - 1]) + rw
	for y in range(y0, y1):
		for x in range(x0, x1):
			var f := road_floor(lay, x, y)
			if f != "":
				w.set_floor_raw(Vector2i(x, y), f)
	# crosswalks: the 4 asphalt tiles just outside every junction arm
	for a in vx.size():
		for b in hy.size():
			var jx := int(vx[a])
			var jy := int(hy[b])
			for k in range(1, rw - 1):
				if b > 0:
					w.set_floor_raw(Vector2i(jx + k, jy - 1), "crosswalk")
				if b < hy.size() - 1:
					w.set_floor_raw(Vector2i(jx + k, jy + rw), "crosswalk")
				if a > 0:
					w.set_floor_raw(Vector2i(jx - 1, jy + k), "crosswalk")
				if a < vx.size() - 1:
					w.set_floor_raw(Vector2i(jx + rw, jy + k), "crosswalk")
	# road region records (verticals first, then horizontals; they overlap at the junctions)
	var roads: Array = []
	for a in vx.size():
		var lines: Array = []
		for b in range(hy.size() - 1):
			lines.append([int(vx[a]) + rw / 2, int(hy[b]) + rw + 1, int(vx[a]) + rw / 2, int(hy[b + 1]) - 1])
		roads.append({"rect": Rect2i(int(vx[a]), y0, rw, y1 - y0), "axis": "v", "lines": lines, "label": "Street %d" % (a + 1)})
	for b in hy.size():
		var lines2: Array = []
		for a in range(vx.size() - 1):
			lines2.append([int(vx[a]) + rw + 1, int(hy[b]) + rw / 2, int(vx[a + 1]) - 1, int(hy[b]) + rw / 2])
		roads.append({"rect": Rect2i(x0, int(hy[b]), x1 - x0, rw), "axis": "h", "lines": lines2, "label": "Avenue %d" % (b + 1)})
	return roads


# ------------------------------------------------------------------ regions

static func _add_regions(w, lay: Dictionary, roads: Array) -> void:
	var size := lot_size()
	for l in _hood_lots():
		var rc := lot_rect(str(l["id"]))
		if rc.size == Vector2i.ZERO:
			continue
		var type := str(l.get("type", "venue"))
		var kind := "venue"
		var owner := "public"
		if type == "home":
			kind = "home"
			owner = "player"
		elif type == "townie_home":
			kind = "townie_home"
			owner = "npc"
		var tpl := str(l.get("template", ""))
		if kind == "home" and tpl == "":
			tpl = LotLoader.CLASSIC
		w.regions.add_region({"rect": rc, "kind": kind, "venue_type": "" if kind != "venue" else type, "owner": owner, "template": tpl,
			"label": str(l.get("label", l["id"])), "lot": str(l["id"]),
			"entry": Vector2i(rc.position.x + GATE_X, rc.end.y - 1), "door": rc.position + Vector2i(GATE_X, size.y - 8)})
	var g: Dictionary = lay.get("green", {})
	if not g.is_empty():
		w.regions.add_region({"rect": Rect2i(slot_origin(g["slot"]), size), "kind": "park", "owner": "public", "label": str(g.get("label", "Green")), "lot": "green"})
	for pid in plots():
		w.regions.add_region({"rect": plot_rect(str(pid)), "kind": "park", "owner": "public", "label": "Empty plot", "lot": str(pid)})
	var ss: Dictionary = lay.get("south_strip", {})
	if not ss.is_empty():
		var sy := int(ss["y"])
		w.regions.add_region({"rect": Rect2i(1, sy, w.width - 2, w.height - sy), "kind": "park", "owner": "public", "label": str(ss.get("label", "Woods")), "lot": "south"})
	for r in roads:
		var d: Dictionary = r
		d["kind"] = "road"
		d["owner"] = "public"
		w.regions.add_region(d)