extends RefCounted
## Shared helpers for house_* tests (no run(), so the runner skips it): apply a generated template dictionary to the REAL
## World with the same placement logic as LotLoader.apply (which only knows templates by id), and per-layout statistics.

static func world() -> Node:
	return Engine.get_main_loop().root.get_node("World")


static func _wall_line(w, a: Vector2i, b: Vector2i, type: String) -> void:
	if a.y == b.y:
		for x in range(mini(a.x, b.x), maxi(a.x, b.x)):
			w.set_edge(Vector3i(x, a.y, 0), type)
	elif a.x == b.x:
		for y in range(mini(a.y, b.y), maxi(a.y, b.y)):
			w.set_edge(Vector3i(a.x, y, 1), type)


## Same steps as LotLoader.apply: floors, walls, wall-mounted pieces first, then the rest, spawn tiles. Returns {failed, placed}.
static func apply(t: Dictionary, w) -> Dictionary:
	var rep := {"failed": [], "placed": 0}
	w.reset(32, 24)
	for fl in t.get("floors", []):
		var r: Array = fl["rect"]
		w.set_floor_rect_raw(Vector2i(int(r[0]), int(r[1])), Vector2i(int(r[2]), int(r[3])), str(fl["type"]))
	for wl in t.get("walls", []):
		_wall_line(w, Vector2i(int(wl["a"][0]), int(wl["a"][1])), Vector2i(int(wl["b"][0]), int(wl["b"][1])), str(wl["type"]))
	for pass_i in 2:
		for o in t.get("objects", []):
			var mounted: bool = str(w.get_def(str(o["def"])).get("mount", "")) == "wall"
			if (pass_i == 0) != mounted:
				continue
			var id: int = w.place_object(str(o["def"]), Vector2i(int(o["tile"][0]), int(o["tile"][1])), int(o.get("rot", 0)))
			if id == -1:
				(rep["failed"] as Array).append("%s at %s rot %d: %s" % [o["def"], str(o["tile"]), int(o.get("rot", 0)), str(w.last_error)])
			else:
				rep["placed"] = int(rep["placed"]) + 1
	w.starter_spawn_tiles.clear()
	for sp in t.get("spawn", []):
		w.starter_spawn_tiles.append(Vector2i(int(sp[0]), int(sp[1])))
	w.rooms.dirty = true
	w.clear_undo()
	w.emit_signal("world_reset")        # views rebuild (LotLoader.apply does the same)
	return rep


## Counts for the report: {objects, kinds, windows, doors, baths, bedrooms, beds}.
static func stats(t: Dictionary) -> Dictionary:
	var kinds: Dictionary = {}
	var n := 0
	var win := 0
	var doors := 0
	var beds := 0
	for o in t.get("objects", []):
		var id := str(o["def"])
		n += 1
		kinds[id] = true
		if id == "window":
			win += 1
		elif id == "door":
			doors += 1
		elif id in ["bed", "single_bed", "bunk_bed", "crib"]:
			beds += 1
	var toilets := 0
	for o in t.get("objects", []):
		if str(o["def"]) == "toilet":
			toilets += 1
	return {"objects": n, "kinds": kinds.size(), "windows": win, "doors": doors, "beds": beds, "toilets": toilets}


## Bounding box (tile rect) of the type "wall" lines = the shell of the building.
static func shell_of(t: Dictionary) -> Rect2i:
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
		return Rect2i(0, 0, 32, 24)     # no walls (park)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)
