class_name HouseDesks
extends RefCounted
## Every desk, computer and terminal of a generated home gets a chair on its use tile (the view sits the folk down on it:
## typing, writing and homework are seated). No rng draws, so the rest of the layout does not shift.

const TYPES := ["desk", "computer", "terminal"]


## Desk-like objects in the plan.
static func count(plan: HousePlan) -> int:
	var n := 0
	for o in plan.objects:
		if str(o["def"]) in TYPES:
			n += 1
	return n


## Places a chair on the first free use tile of each desk-like object. Returns how many were added.
static func add_chairs(plan: HousePlan, fz: HouseFurnish) -> int:
	var added := 0
	for i in plan.objects.size():
		var o: Dictionary = plan.objects[i]
		if not (str(o["def"]) in TYPES):
			continue
		var d := HousePlan.def_of(str(o["def"]))
		var fp := plan.fp_of(i)
		var ri: int = int(plan.room_of.get(fp[0], -1))
		if ri < 0:
			continue
		var rect: Rect2i = plan.rooms[ri]["rect"]
		var cands: Array = []
		for s in HousePlan.slot_tiles(d, o["tile"], int(o["rot"])):
			if s in fp or plan.occ.has(s):
				continue
			for t0 in fp:
				var dir: Vector2i = s - t0
				if absi(dir.x) + absi(dir.y) == 1:
					cands.append([1.0, s, HousePlan.FRONT.find(-dir)])
					break
		for c in cands:
			if c[1] == plan.entry or c[1] in plan.must or not plan.can_put("chair", c[1], c[2], rect, true):          # a use tile on a walkway is fine as long as every room stays reachable
				continue
			var idx := plan.put("chair", c[1], c[2])
			if not plan.valid():
				plan.pop()
				continue
			fz._record(ri, "chair", idx)
			added += 1
			break
	return added


# ------------------------------------------------------------------ finished templates (hand-made lots, generated venues and buildings)

## Puts a chair on the use tile of every desk / computer / terminal of a finished lot template (floors, walls, objects, optional `levels`) that has none,
## wherever that tile is free floor, not behind a wall, not an entry / spawn / stop tile and not the only link between two parts of the level (the walkable
## tiles of the level stay in as many pieces as before). Used by tools/add_template_chairs.gd on the shipped data and by the data check in visual_sim_test.
## Returns the chairs added (appended to t["objects"]). No rng, so it can be run again on its own output (it then adds nothing).
static func fix_template(t: Dictionary) -> int:
	var levels: Array = [0]
	for k in (t.get("levels", {}) as Dictionary):
		levels.append(int(k))
	var must := _must_tiles(t)
	var added := 0
	for lv in levels:
		added += _fix_level(t, lv, must)
	return added


static func _must_tiles(t: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in ["entry", "bedroom"]:
		if t.has(k):
			out[Vector2i(int(t[k][0]), int(t[k][1]))] = true
	for s in t.get("spawn", []):
		out[Vector2i(int(s[0]), int(s[1]))] = true
	for k in (t.get("stops", {}) as Dictionary):
		out[Vector2i(int(t["stops"][k][0]), int(t["stops"][k][1]))] = true
	for s in t.get("staff", []):
		if s is Dictionary and s.has("tile"):
			out[Vector2i(int(s["tile"][0]), int(s["tile"][1]))] = true
		elif s is Array and s.size() >= 2 and (s[0] is float or s[0] is int):
			out[Vector2i(int(s[0]), int(s[1]))] = true
	return out


## Floors, walls and objects of one level of a template.
static func _level_part(t: Dictionary, lv: int) -> Array:
	if lv == 0:
		return [t.get("floors", []), t.get("walls", [])]
	var l: Dictionary = (t.get("levels", {}) as Dictionary).get(str(lv), {})
	return [l.get("floors", []), l.get("walls", [])]


static func _fix_level(t: Dictionary, lv: int, must: Dictionary) -> int:
	var part := _level_part(t, lv)
	var floors: Dictionary = {}
	for f in (part[0] as Array):
		var r: Array = f["rect"]
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				floors[Vector2i(x, y)] = true
	var edges: Dictionary = {}
	for w in (part[1] as Array):
		if str(w["type"]) not in HousePlan.BLOCK:
			continue
		var a := Vector2i(int(w["a"][0]), int(w["a"][1]))
		var b := Vector2i(int(w["b"][0]), int(w["b"][1]))
		if a.y == b.y:
			for x in range(mini(a.x, b.x), maxi(a.x, b.x)):
				edges[Vector3i(x, a.y, 0)] = true
		else:
			for y in range(mini(a.y, b.y), maxi(a.y, b.y)):
				edges[Vector3i(a.x, y, 1)] = true
	var occ: Dictionary = {}
	var desks: Array = []
	var objs: Array = t["objects"]
	for o in objs:
		if int(o.get("level", 0)) != lv:
			continue
		var d := HousePlan.def_of(str(o["def"]))
		var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
		if str(d.get("mount", "")) == "wall":
			if str(d.get("wall_type", "")) == "door":
				edges.erase(HousePlan.mount_edge(tile, int(o.get("rot", 0))))
			elif str(d.get("wall_type", "")) == "window":
				edges[HousePlan.mount_edge(tile, int(o.get("rot", 0)))] = true
			continue
		if d.is_empty() or HousePlan.is_floor_layer(d):
			continue
		for ft in HousePlan.footprint(d, tile, int(o.get("rot", 0))):
			occ[ft] = o
		if str(o["def"]) in TYPES:
			desks.append(o)
	var added := 0
	var seats: Array[Vector2i] = []                              # chairs of this level (kept reachable) incl. the ones added now
	for o in objs:
		if int(o.get("level", 0)) == lv and str(o["def"]) == "chair":
			var ct := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
			if _seats_reachable(floors, occ, edges, [ct], Vector2i(-9999, -9999)):
				seats.append(ct)                                # (a chair that is already walled in is not our concern)
	for o in desks:
		var d := HousePlan.def_of(str(o["def"]))
		var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
		var fp := HousePlan.footprint(d, tile, int(o.get("rot", 0)))
		for s in HousePlan.slot_tiles(d, tile, int(o.get("rot", 0))):
			if occ.has(s) and "seat" in (HousePlan.def_of(str((occ[s] as Dictionary)["def"])).get("tags", []) as Array):
				break                                               # already has a seat
			if s in fp or occ.has(s) or not floors.has(s) or must.has(s):
				continue
			var from := Vector2i.ZERO
			var ok := false
			for t0 in fp:
				var dir: Vector2i = s - t0
				if absi(dir.x) + absi(dir.y) == 1 and not edges.has(HousePlan.edge(t0, s)):
					from = dir
					ok = true
					break
			if not ok:
				continue
			var before := _pieces(floors, occ, edges, Vector2i(-9999, -9999))
			if _pieces(floors, occ, edges, s) > before:
				continue                                            # the use tile is a link (a corridor): leave it open
			seats.append(s)
			if not _seats_reachable(floors, occ, edges, seats, s):
				seats.pop_back()
				continue                                            # the chair (or an earlier one) would be walled in: nobody could walk up to it
			var chair := {"def": "chair", "tile": [s.x, s.y], "rot": HousePlan.FRONT.find(-from)}
			if lv != 0:
				chair["level"] = lv
			objs.append(chair)
			occ[s] = chair
			added += 1
			break
	return added


## Number of separate walkable pieces of a level (4-neighbour, walls and closed edges between), with tile `skip` counted as blocked.
static func _pieces(floors: Dictionary, occ: Dictionary, edges: Dictionary, skip: Vector2i) -> int:
	var seen: Dictionary = {}
	var n := 0
	for start in floors:
		if seen.has(start) or occ.has(start) or start == skip:
			continue
		n += 1
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for dd in HousePlan.DIRS4:
				var nb: Vector2i = c + dd
				if seen.has(nb) or not floors.has(nb) or occ.has(nb) or nb == skip or edges.has(HousePlan.edge(c, nb)):
					continue
				seen[nb] = true
				stack.append(nb)
	return n


## Every chair in `seats` (the last one is not in `occ` yet; `extra` is its tile) has a free neighbour in the biggest walkable piece of the level.
static func _seats_reachable(floors: Dictionary, occ: Dictionary, edges: Dictionary, seats: Array, extra: Vector2i) -> bool:
	var comp: Dictionary = {}
	var sizes: Array = []
	for start in floors:
		if comp.has(start) or occ.has(start) or start == extra:
			continue
		var id := sizes.size()
		var n := 1
		var stack: Array = [start]
		comp[start] = id
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for dd in HousePlan.DIRS4:
				var nb: Vector2i = c + dd
				if comp.has(nb) or not floors.has(nb) or occ.has(nb) or nb == extra or edges.has(HousePlan.edge(c, nb)):
					continue
				comp[nb] = id
				n += 1
				stack.append(nb)
		sizes.append(n)
	var main := 0
	for i in sizes.size():
		if int(sizes[i]) > int(sizes[main]):
			main = i
	for st in seats:
		var ok := false
		for dd in HousePlan.DIRS4:
			var nb: Vector2i = st + dd
			if comp.get(nb, -1) == main and not edges.has(HousePlan.edge(st, nb)):
				ok = true
				break
		if not ok:
			return false
	return true
