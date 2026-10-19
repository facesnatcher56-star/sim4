class_name HouseAudit
extends RefCounted
## Generator check on a finished lot template ({floors, walls, objects, ...}): no two objects overlap and every use slot is walkable
## (inside the lot, not under another object, not behind a wall or fence from its own object). Returns problem strings; empty = clean.
## Used by HouseGenerator.make_home (a layout that fails is rejected and the next sub-seed tried) and by the house tests.

static func _wall_edges(t: Dictionary) -> Dictionary:
	var e: Dictionary = {}
	for w in t.get("walls", []):
		var a := Vector2i(int(w["a"][0]), int(w["a"][1]))
		var b := Vector2i(int(w["b"][0]), int(w["b"][1]))
		var ty := str(w["type"])
		if a.y == b.y:
			for x in range(mini(a.x, b.x), maxi(a.x, b.x)):
				e[Vector3i(x, a.y, 0)] = ty
		else:
			for y in range(mini(a.y, b.y), maxi(a.y, b.y)):
				e[Vector3i(a.x, y, 1)] = ty
	return e


static func _blocked(e: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return str(e.get(HousePlan.edge(a, b), "")) in HousePlan.BLOCK


static func audit(t: Dictionary, lot: Rect2i = Rect2i(0, 0, 32, 24)) -> Array:
	var out: Array = []
	var edges := _wall_edges(t)
	var occ: Dictionary = {}                 # tile -> object index (blocking layer)
	var objs: Array = t.get("objects", [])
	var fps: Array = []
	for i in objs.size():
		var o: Dictionary = objs[i]
		var d := HousePlan.def_of(str(o["def"]))
		fps.append([])
		if d.is_empty() or str(d.get("mount", "")) == "wall" or HousePlan.is_floor_layer(d):
			continue
		var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
		var fp := HousePlan.footprint(d, tile, int(o.get("rot", 0)))
		fps[i] = fp
		for ft in fp:
			if occ.has(ft):
				out.append("%s overlaps %s at %s" % [o["def"], objs[int(occ[ft])]["def"], str(ft)])
			else:
				occ[ft] = i
	var shell := _shell_of(t, lot)
	for i in objs.size():
		if (fps[i] as Array).is_empty():
			continue
		var yard_piece := false                  # outdoors: every slot must be usable (indoors one usable slot is enough, HousePlan.valid)
		for ft in (fps[i] as Array):
			if not shell.has_point(ft):
				yard_piece = true
		if not yard_piece:
			continue
		var o: Dictionary = objs[i]
		var d := HousePlan.def_of(str(o["def"]))
		var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
		for s in HousePlan.slot_tiles(d, tile, int(o.get("rot", 0))):
			if not lot.has_point(s):
				out.append("%s at %s: use slot %s outside the lot" % [o["def"], str(tile), str(s)])
			elif s in (fps[i] as Array):
				continue                         # a seat or bed: the slot is the object's own tile
			elif occ.has(s) and "seat" in (HousePlan.def_of(str(objs[int(occ[s])]["def"])).get("tags", []) as Array):
				continue                         # the slot is a chair tile (dining set)
			elif occ.has(s):
				out.append("%s at %s: use slot %s is under a %s" % [o["def"], str(tile), str(s), objs[int(occ[s])]["def"]])
			else:
				for ft in (fps[i] as Array):
					if absi(ft.x - s.x) + absi(ft.y - s.y) == 1 and _blocked(edges, ft, s):
						out.append("%s at %s: use slot %s is behind a wall or fence" % [o["def"], str(tile), str(s)])
						break
	return out


## The house shell: the box of the "wall" lines (the whole lot when there are none, as in a park).
static func _shell_of(t: Dictionary, lot: Rect2i) -> Rect2i:
	var x0 := 999
	var y0 := 999
	var x1 := -1
	var y1 := -1
	for wl in t.get("walls", []):
		if str(wl["type"]) != "wall":
			continue
		for p in [wl["a"], wl["b"]]:
			x0 = mini(x0, int(p[0]))
			y0 = mini(y0, int(p[1]))
			x1 = maxi(x1, int(p[0]))
			y1 = maxi(y1, int(p[1]))
	if x1 < 0:
		return lot
	return Rect2i(x0, y0, x1 - x0, y1 - y0)
