class_name HouseYard
extends RefCounted
## Everything outside the house walls: front path, fence + gate, garden door patio, yard objects (garden, grill, mailbox...).

static func yard_rect(plan: HousePlan, fp: Dictionary) -> Rect2i:
	var f: Variant = fp.get("fence")
	if f is Array:
		return Rect2i(int(f[0]), int(f[1]), int(f[2]) - int(f[0]), int(f[3]) - int(f[1]))
	var sh := plan.shell
	return Rect2i(sh.position.x - 3, sh.position.y - 1, sh.size.x + 6, sh.size.y + 1 + 5).intersection(plan.lot)


## Adds yard objects to the plan; returns {floors, walls} (path, patio, fence, gate) for the export.
static func build(plan: HousePlan, fz: HouseFurnish, spec: Dictionary, fp: Dictionary, rules: Dictionary, back: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var sh := plan.shell
	var yard := yard_rect(plan, fp)
	var floors: Array = []
	var walls: Array = []
	var px := plan.entry.x
	var pw := mini(int(fp.get("path_w", 1)), maxi(1, yard.end.x - px))
	var door_out := Vector2i(px, sh.end.y)
	# fence + gate
	var f: Variant = fp.get("fence")
	var bottom := plan.lot.end.y - 1
	if f is Array:
		var x0 := int(f[0]); var y0 := int(f[1]); var x1 := int(f[2]); var y1 := int(f[3])
		walls.append({"a": [x0, y0], "b": [x1, y0], "type": "fence"})
		walls.append({"a": [x1, y0], "b": [x1, y1], "type": "fence"})
		walls.append({"a": [x0, y1], "b": [x1, y1], "type": "fence"})
		walls.append({"a": [x0, y0], "b": [x0, y1], "type": "fence"})
		walls.append({"a": [px, y1], "b": [px + pw, y1], "type": "door"})
		for x in range(x0, x1):
			plan.walls[Vector3i(x, y0, 0)] = "fence"
			plan.walls[Vector3i(x, y1, 0)] = "fence" if (x < px or x >= px + pw) else "door"
		for y in range(y0, y1):
			plan.walls[Vector3i(x0, y, 1)] = "fence"
			plan.walls[Vector3i(x1, y, 1)] = "fence"
	floors.append({"rect": [px, sh.end.y, px + pw - 1, bottom], "type": "stone"})
	plan.bounds = yard
	plan.entry = door_out
	for y in range(sh.end.y, yard.end.y):
		for x in range(px, px + pw):
			plan.clear[Vector2i(x, y)] = true
	if not back.is_empty():
		var o: Vector2i = back["outer"]
		var dir: Vector2i = back["dir"]
		var lat := Vector2i(dir.y, dir.x)
		var a := o
		var b := o + dir + lat
		if not yard.has_point(b):
			lat = -lat
			b = o + dir + lat
		var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
		floors.append({"rect": [lo.x, lo.y, hi.x, hi.y], "type": "stone"})
		for yy in range(lo.y, hi.y + 1):
			for xx in range(lo.x, hi.x + 1):
				plan.clear[Vector2i(xx, yy)] = true
		plan.must.append(o)
	# walkway ring around the house stays free
	for y in range(sh.position.y - 1, sh.end.y + 1):
		for x in range(sh.position.x - 1, sh.end.x + 1):
			if yard.has_point(Vector2i(x, y)):
				plan.clear[Vector2i(x, y)] = true
	var list: Array = []
	for e in (rules["yard"][str(spec["size"])]["items"] as Array):
		for k in rng.randi_range(int(e[1]), int(e[2])):
			list.append(str(e[0]))
	for d in spec.get("yard", []):
		list.append(str(d))
	if not (f is Array):
		list = list.filter(func(d): return d != "hot_tub" and d != "fishing_spot")
	_mailbox(plan, fz, yard, px, pw, sh.end.y + 2, rng)
	for did in list:
		var d := HousePlan.def_of(did)
		var cands: Array = []
		for rot in 4:
			for y in range(yard.position.y, yard.end.y):
				for x in range(yard.position.x, yard.end.x):
					var fpr := HousePlan.footprint(d, Vector2i(x, y), rot)
					if HouseCands.fits(yard, fpr):
						var sc: float = rng.randf() * 0.6 - 0.35 * _edge_dist(Vector2i(x, y), yard, sh)
						if _slots_open(plan, d, Vector2i(x, y), rot, fpr, yard):
							cands.append([sc, Vector2i(x, y), rot])
		var placed: bool = fz.try_place(-1, did, cands, yard)
		if placed and did != "table":          # (a table's slots are its chairs, placed next)
			_reserve_slots(plan, plan.objects.size() - 1)
		if placed and did == "table":
			for k in rng.randi_range(2, 4):
				fz.try_place(-1, "dining_chair", HouseCands.seat(fz, -1, "dining_chair", {"ref": "table"}), yard)
	return {"floors": floors, "walls": walls, "yard": yard}


## Every use slot of a yard piece is inside the yard, free, and on its own side of any fence (so nobody stands in the bed to use it).
static func _slots_open(plan: HousePlan, d: Dictionary, tile: Vector2i, rot: int, fp: Array, yard: Rect2i) -> bool:
	if HousePlan.is_floor_layer(d) or str(d.get("mount", "")) == "wall":
		return true
	for s in HousePlan.slot_tiles(d, tile, rot):
		if s in fp:
			continue
		if not yard.has_point(s) or plan.occ.has(s):
			return false
		for ft in fp:
			if absi(ft.x - s.x) + absi(ft.y - s.y) == 1 and plan.blocked_edge(ft, s):
				return false
	return true


## A placed yard piece keeps its use tiles free: nothing placed later may stand on them.
static func _reserve_slots(plan: HousePlan, idx: int) -> void:
	var o: Dictionary = plan.objects[idx]
	var d := HousePlan.def_of(str(o["def"]))
	var fp := HousePlan.footprint(d, o["tile"], int(o["rot"]))
	for s in HousePlan.slot_tiles(d, o["tile"], int(o["rot"])):
		if not (s in fp):
			plan.clear[s] = true


## Distance to the nearest fence line or house wall: yard pieces hug the edges instead of floating in the lawn.
static func _edge_dist(t: Vector2i, yard: Rect2i, sh: Rect2i) -> float:
	var df := mini(mini(t.x - yard.position.x, yard.end.x - 1 - t.x), mini(t.y - yard.position.y, yard.end.y - 1 - t.y))
	var dx := maxi(maxi(sh.position.x - t.x, t.x - (sh.end.x - 1)), 0)
	var dy := maxi(maxi(sh.position.y - t.y, t.y - (sh.end.y - 1)), 0)
	return float(mini(df, dx + dy))


static func _mailbox(plan: HousePlan, fz: HouseFurnish, yard: Rect2i, px: int, pw: int, y0: int, rng: RandomNumberGenerator) -> void:
	var cands: Array = []
	for y in range(y0, mini(y0 + 4, yard.end.y)):
		if px - 1 >= yard.position.x:
			cands.append([rng.randf(), Vector2i(px - 1, y), 3])
		if px + pw < yard.end.x:
			cands.append([rng.randf(), Vector2i(px + pw, y), 1])
	var saved := plan.clear.duplicate()
	for c in cands:
		plan.clear.erase(c[1])
	fz.try_place(-1, "mailbox", cands, yard)
	for t in saved:
		plan.clear[t] = true
