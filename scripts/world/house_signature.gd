class_name HouseSignature
extends RefCounted
## Layout fingerprints that ignore position, mirroring and rotation (a flipped copy of a home counts as a duplicate).
##   plan_sig   - wall geometry only (the floor plan: where rooms are)
##   layout_sig - walls + doors + windows + furniture cells
##   similarity - 0..1 overlap of the interior (interior walls + furniture cells), best over the 8 symmetries

## Parse a template dict into {w, h, edges: [Vector3i], mounts: [[Vector3i, "door"|"window"]], cells: [[Vector2i, def]]}
## in shell space (origin at the north-west corner of the outer walls).
static func parse(t: Dictionary) -> Dictionary:
	var edges: Dictionary = {}
	for wl in t.get("walls", []):
		if str(wl["type"]) != "wall":
			continue
		var a: Array = wl["a"]
		var b: Array = wl["b"]
		if int(a[1]) == int(b[1]):
			for x in range(mini(int(a[0]), int(b[0])), maxi(int(a[0]), int(b[0]))):
				edges[Vector3i(x, int(a[1]), 0)] = true
		else:
			for y in range(mini(int(a[1]), int(b[1])), maxi(int(a[1]), int(b[1]))):
				edges[Vector3i(int(a[0]), y, 1)] = true
	var x0 := 9999
	var y0 := 9999
	var x1 := -9999
	var y1 := -9999
	for e in edges:
		x0 = mini(x0, e.x)
		y0 = mini(y0, e.y)
		x1 = maxi(x1, e.x + (1 if e.z == 0 else 0))
		y1 = maxi(y1, e.y + (1 if e.z == 1 else 0))
	if edges.is_empty():
		x0 = 0
		y0 = 0
		x1 = 32
		y1 = 24
	var out_edges: Array = []
	for e in edges:
		out_edges.append(Vector3i(e.x - x0, e.y - y0, e.z))
	var mounts: Array = []
	var cells: Array = []
	var defs := HousePlan.defs()
	for o in t.get("objects", []):
		var id := str(o["def"])
		var tile := Vector2i(int(o["tile"][0]) - x0, int(o["tile"][1]) - y0)
		var rot := int(o.get("rot", 0))
		if id == "door" or id == "window":
			mounts.append([HousePlan.mount_edge(tile, rot), id])
		else:
			var d: Dictionary = defs.get(id, {})
			if HousePlan.is_floor_layer(d):
				continue            # rugs and ceiling lights: decor, not structure
			for c in HousePlan.footprint(d, tile, rot):
				if c.x >= 0 and c.y >= 0 and c.x < x1 - x0 and c.y < y1 - y0:
					cells.append([c, id])
	return {"w": x1 - x0, "h": y1 - y0, "edges": out_edges, "mounts": mounts, "cells": cells}


static func _edge(e: Vector3i, m: int, w: int, h: int) -> Vector3i:
	if m & 4:
		e = Vector3i(e.y, e.x, 1 - e.z)
		var s := w
		w = h
		h = s
	if m & 1:
		e = Vector3i(w - 1 - e.x, e.y, 0) if e.z == 0 else Vector3i(w - e.x, e.y, 1)
	if m & 2:
		e = Vector3i(e.x, h - e.y, 0) if e.z == 0 else Vector3i(e.x, h - 1 - e.y, 1)
	return e


static func _cell(c: Vector2i, m: int, w: int, h: int) -> Vector2i:
	if m & 4:
		c = Vector2i(c.y, c.x)
		var s := w
		w = h
		h = s
	if m & 1:
		c = Vector2i(w - 1 - c.x, c.y)
	if m & 2:
		c = Vector2i(c.x, h - 1 - c.y)
	return c


static func _modes(p: Dictionary) -> Array:
	return [0, 1, 2, 3, 4, 5, 6, 7] if int(p["w"]) == int(p["h"]) else [0, 1, 2, 3]


## Token list (sorted strings) of a parsed template under symmetry m.
static func _tokens(p: Dictionary, m: int, with_mounts: bool, with_cells: bool, interior_only: bool) -> Array:
	var w := int(p["w"])
	var h := int(p["h"])
	var toks: Array = []
	for e in p["edges"]:
		var onb: bool = (e.z == 0 and (e.y == 0 or e.y == h)) or (e.z == 1 and (e.x == 0 or e.x == w))
		if interior_only and onb:
			continue
		var t := _edge(e, m, w, h)
		toks.append("e%d,%d,%d" % [t.x, t.y, t.z])
	if with_mounts:
		for mt in p["mounts"]:
			var t := _edge(mt[0], m, w, h)
			toks.append("%s%d,%d,%d" % [str(mt[1]).substr(0, 1), t.x, t.y, t.z])
	if with_cells:
		for c in p["cells"]:
			var t := _cell(c[0], m, w, h)
			toks.append("o%s:%d,%d" % [c[1], t.x, t.y])
	toks.sort()
	return toks


static func _canon(p: Dictionary, with_mounts: bool, with_cells: bool) -> String:
	var best := ""
	for m in _modes(p):
		var s := "%dx%d|" % [p["w"], p["h"]] if m & 4 == 0 else "%dx%d|" % [p["h"], p["w"]]
		s += ";".join(_tokens(p, m, with_mounts, with_cells, false))
		if best == "" or s < best:
			best = s
	return best.sha1_text().substr(0, 16)


static func plan_sig(t: Dictionary) -> String:
	return _canon(parse(t), false, false)


static func layout_sig(t: Dictionary) -> String:
	var sig := _canon(parse(t), true, true)
	if t.has("levels"):           # multi-floor: the upper floors count too (walls / floors / objects of other levels)
		var upper: Array = []
		for o in t.get("objects", []):
			if int(o.get("level", 0)) != 0:
				upper.append("%s%s%d%d" % [o["def"], str(o["tile"]), int(o.get("rot", 0)), int(o["level"])])
		sig = (sig + JSON.stringify(t["levels"]) + ";".join(upper)).sha1_text().substr(0, 16)
	return sig


## Best overlap (Jaccard) of interior walls + furniture cells over all symmetries; 0 when the footprints differ.
static func similarity(a: Dictionary, b: Dictionary) -> float:
	var pa := parse(a)
	var pb := parse(b)
	if not ((pa["w"] == pb["w"] and pa["h"] == pb["h"]) or (pa["w"] == pb["h"] and pa["h"] == pb["w"])):
		return 0.0
	var tb: Dictionary = {}
	for tk in _tokens(pb, 0, false, true, true):
		tb[tk] = true
	var best := 0.0
	for m in _modes(pa):
		var ta: Array = _tokens(pa, m, false, true, true)
		var inter := 0
		for tk in ta:
			if tb.has(tk):
				inter += 1
		var union := ta.size() + tb.size() - inter
		if union > 0:
			best = maxf(best, float(inter) / float(union))
	return best


## Template-like dict from the live World (used for the hand-built classic starter house).
static func from_world(w, verts: Rect2i = Rect2i(0, 0, 33, 25)) -> Dictionary:
	var walls: Array = []
	for e in w.walls:
		var ty := str(w.walls[e])
		var far: Vector2i = Vector2i(e.x + (1 if e.z == 0 else 0), e.y + (1 if e.z == 1 else 0))
		if ty == "fence" or not verts.has_point(Vector2i(e.x, e.y)) or not verts.has_point(far):
			continue
		if e.z == 0:
			walls.append({"a": [e.x, e.y], "b": [e.x + 1, e.y], "type": "wall"})
		else:
			walls.append({"a": [e.x, e.y], "b": [e.x, e.y + 1], "type": "wall"})
	var objs: Array = []
	for o in w.all_objects():
		objs.append({"def": o.def_id, "tile": [o.tile.x, o.tile.y], "rot": o.rot})
	return {"walls": walls, "objects": objs}


## Every hand-made lot: data/lot_templates.json plus the classic starter house (built into a scratch WorldGrid).
static func legacy_templates() -> Dictionary:
	var out: Dictionary = {}
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lot_templates.json"))
	if p is Dictionary:
		for k in (p["lots"] as Dictionary):
			out[k] = p["lots"][k]
	var w := WorldGrid.new()
	w.reset(32, 24)
	w.load_starter_house()
	out["classic"] = from_world(w, Rect2i(4, 4, 17, 13))
	w.free()
	return out