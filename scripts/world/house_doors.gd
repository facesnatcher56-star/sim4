class_name HouseDoors
extends RefCounted
## Front door, interior doors / open arches between room groups (spanning tree over the room-adjacency graph) and windows.

static func _key(a: String, b: String) -> Array:
	return [a + "-" + b, b + "-" + a]


static func _lookup(tbl: Dictionary, a: String, b: String, fallback: float) -> float:
	for k in _key(a, b):
		if tbl.has(k):
			return float(tbl[k])
	for k in _key(a, "*") + _key("*", b):
		if tbl.has(k):
			return float(tbl[k])
	return fallback


static func forbidden(rules: Dictionary, a: String, b: String) -> bool:
	var fb: Array = (rules["link_cost"] as Dictionary).get("forbid", [])
	for k in _key(a, b):
		if k in fb:
			return true
	return false


static func cost(rules: Dictionary, a: String, b: String) -> float:
	return _lookup(rules["link_cost"], a, b, float((rules["link_cost"] as Dictionary).get("default", 5)))


## Front door on the south wall of the shell, into an entry-capable room. Sets plan.entry.
static func front_door(plan: HousePlan, rules: Dictionary, rng: RandomNumberGenerator) -> bool:
	var sh := plan.shell
	var y := sh.end.y - 1
	var ok_types: Array = rules.get("entry_rooms", [])
	var cands: Array = []
	var x0 := sh.position.x + (1 if sh.size.x > 4 else 0)
	var x1 := sh.end.x - (1 if sh.size.x > 4 else 0)
	for x in range(x0, x1):
		var i: int = plan.room_of.get(Vector2i(x, y), -1)
		if i != -1 and str(plan.rooms[i]["type"]) in ok_types:
			cands.append(x)
	if cands.is_empty():
		return false
	var x: int = cands[rng.randi_range(0, cands.size() - 1)]
	plan.add_mount("door", Vector3i(x, y + 1, 0))
	plan.entry = Vector2i(x, y)
	plan.clear[plan.entry] = true
	plan.must.append(plan.entry)
	return true


## Pairs of adjacent room groups: key "a|b" (a<b) -> [{a: tile in group a, b: tile in group b, e: edge}].
static func adjacency(plan: HousePlan) -> Dictionary:
	var adj: Dictionary = {}
	for e in plan.walls:
		if str(plan.walls[e]) != "wall":
			continue
		var ts := HousePlan.edge_tiles(e)
		if not plan.shell.has_point(ts[0]) or not plan.shell.has_point(ts[1]):
			continue
		var ga := plan.group_at(ts[0])
		var gb := plan.group_at(ts[1])
		if ga == gb:
			continue
		var k := "%d|%d" % [mini(ga, gb), maxi(ga, gb)]
		if not adj.has(k):
			adj[k] = []
		(adj[k] as Array).append({"a": ts[0] if ga < gb else ts[1], "b": ts[1] if ga < gb else ts[0], "e": e})
	for k in adj:
		(adj[k] as Array).sort_custom(func(p, q): return p["a"].x * 100 + p["a"].y < q["a"].x * 100 + q["a"].y)
	return adj


## Choose door / arch links so every group is reachable; fills plan.mounts and removes arch walls. Returns the link list
## [{ga, gb, kind: "door"|"open"}] or [] when impossible.
static func links(plan: HousePlan, spec: Dictionary, rules: Dictionary, rng: RandomNumberGenerator) -> Array:
	var gtype: Dictionary = {}
	for r in plan.rooms:
		gtype[int(r["group"])] = str(r["gtype"])
	var adj := adjacency(plan)
	var chosen: Dictionary = {}       # "a|b" -> true
	var parent: Dictionary = {}
	for g in gtype:
		parent[g] = g
	var is_priv := func(g: int) -> bool: return str(gtype[g]) in HouseRooms.PRIV
	# 1) public groups: cheapest spanning tree
	var cand: Array = []
	for k in adj:
		var p := (k as String).split("|")
		var ga := int(p[0])
		var gb := int(p[1])
		if is_priv.call(ga) or is_priv.call(gb) or forbidden(rules, gtype[ga], gtype[gb]):
			continue
		cand.append([cost(rules, gtype[ga], gtype[gb]) + rng.randf() * 1.5, ga, gb, k])
	cand.sort_custom(func(p, q): return p[0] < q[0])
	for c in cand:
		if _find(parent, c[1]) != _find(parent, c[2]):
			parent[_find(parent, c[1])] = _find(parent, c[2])
			chosen[c[3]] = true
	var pub_roots: Dictionary = {}
	for g in gtype:
		if not is_priv.call(g):
			pub_roots[_find(parent, g)] = true
	if pub_roots.size() > 1:
		return []
	# extra loops between public rooms
	for c in cand:
		if not chosen.has(c[3]) and rng.randf() < float(spec.get("loops", 0.3)):
			chosen[c[3]] = true
	# 2) private rooms hang off their cheapest public neighbour (bathrooms may hang off a bedroom as ensuite)
	var order: Array = []
	for g in gtype:
		if is_priv.call(g):
			order.append(g)
	order.sort_custom(func(p, q): return (str(gtype[p]) in ["bath", "powder"]) and not (str(gtype[q]) in ["bath", "powder"]))
	order.reverse()
	for g in order:
		var best_k := ""
		var best_c := 1e9
		for k in adj:
			var p := (k as String).split("|")
			var ga := int(p[0])
			var gb := int(p[1])
			if ga != g and gb != g:
				continue
			var other := gb if ga == g else ga
			if is_priv.call(other) or forbidden(rules, gtype[g], gtype[other]):
				continue
			var c := cost(rules, gtype[g], gtype[other]) + rng.randf() * 1.5
			if c < best_c:
				best_c = c
				best_k = k
		if best_k == "":
			for k in adj:      # ensuite: a bathroom opening into a bedroom
				var p := (k as String).split("|")
				var ga := int(p[0])
				var gb := int(p[1])
				if (ga == g or gb == g) and str(gtype[g]) in ["bath", "powder"]:
					var other := gb if ga == g else ga
					if str(gtype[other]) in ["master", "bedroom", "kids"] and not forbidden(rules, gtype[g], gtype[other]):
						best_k = k
						break
		if best_k == "":
			return []
		chosen[best_k] = true
	# main bedroom ensuite
	for k in adj:
		var p := (k as String).split("|")
		var ga := int(p[0])
		var gb := int(p[1])
		var pair := [str(gtype[ga]), str(gtype[gb])]
		if "master" in pair and "bath" in pair and not chosen.has(k) and rng.randf() < float(spec.get("ensuite", 0.45)):
			chosen[k] = true
	# realise
	var out: Array = []
	var open_mult := float(spec.get("open", 1.0))
	for k in chosen:
		var p := (k as String).split("|")
		var ga := int(p[0])
		var gb := int(p[1])
		var op := _lookup(rules["open_prob"], gtype[ga], gtype[gb], float(spec.get("open_default", (rules["open_prob"] as Dictionary).get("default", 0.0)))) * open_mult
		var kind := "open" if (not is_priv.call(ga) and not is_priv.call(gb) and rng.randf() < op) else "door"
		if not _realise(plan, adj[k], kind, rng):
			kind = "door"
			if not _realise(plan, adj[k], kind, rng):
				return []
		out.append({"ga": ga, "gb": gb, "kind": kind})
	return out


static func _find(parent: Dictionary, g: int) -> int:
	while parent[g] != g:
		g = parent[g]
	return g


static func _realise(plan: HousePlan, edges: Array, kind: String, rng: RandomNumberGenerator) -> bool:
	var usable: Array = []
	for i in edges.size():
		var s: String = str(plan.walls.get(edges[i]["e"], ""))
		if s == "wall" and not _door_near(plan, edges[i]["e"]):
			usable.append(i)
	if usable.is_empty():
		return false
	var nice: Array = []        # doors of private rooms should not open into a kitchen or dining corner
	for i in usable:
		var ta: String = plan.type_at(edges[i]["a"])
		var tb: String = plan.type_at(edges[i]["b"])
		if not (ta in ["kitchen", "dining"] or tb in ["kitchen", "dining"]):
			nice.append(i)
	if not nice.is_empty() and kind == "door":
		usable = nice
	if kind == "open":
		var span := mini(edges.size(), rng.randi_range(2, 3) if rng.randf() < 0.7 else edges.size())
		if usable.size() < span:
			return false
		var start: int = usable[rng.randi_range(0, usable.size() - span)] if usable.size() > span else usable[0]
		for j in range(start, start + span):
			if j >= edges.size() or str(plan.walls.get(edges[j]["e"], "")) != "wall":
				return false
		for j in range(start, start + span):
			plan.walls.erase(edges[j]["e"])
			_must(plan, edges[j])
		return true
	var pick: int
	if usable.size() >= 3:
		pick = usable[rng.randi_range(1, usable.size() - 2)]
	else:
		pick = usable[rng.randi_range(0, usable.size() - 1)]
	plan.add_mount("door", edges[pick]["e"])
	_must(plan, edges[pick])
	return true


static func _must(plan: HousePlan, ed: Dictionary) -> void:
	for t in [ed["a"], ed["b"]]:
		plan.clear[t] = true
		if t not in plan.must:
			plan.must.append(t)


static func _door_near(plan: HousePlan, e: Vector3i) -> bool:
	var ts := HousePlan.edge_tiles(e)
	for t in ts:
		if plan.clear.has(t):
			return true
	return false


# ------------------------------------------------------------------ windows
static func _tall(plan: HousePlan, t: Vector2i) -> bool:
	var i: int = plan.occ.get(t, -1)
	if i == -1:
		return false
	var d := HousePlan.def_of(str(plan.objects[i]["def"]))
	return float(d.get("height", 1.0)) >= 1.5 and not ("decor" in (d.get("tags", []) as Array))


## Windows on exterior walls of every room, away from doors and tall furniture. `skip` = room types without windows.
static func windows(plan: HousePlan, rules: Dictionary, rng: RandomNumberGenerator) -> void:
	var sh := plan.shell
	for r in plan.rooms:
		var rt: Dictionary = rules["rooms"].get(str(r["type"]), {})
		var win := float(rt.get("win", 1.0))
		var rect: Rect2i = r["rect"]
		for side in 4:
			var run: Array = []        # [edge, inner tile]
			match side:
				0:
					if rect.position.y == sh.position.y:
						for x in range(rect.position.x, rect.end.x):
							run.append([Vector3i(x, sh.position.y, 0), Vector2i(x, sh.position.y)])
				1:
					if rect.end.y == sh.end.y:
						for x in range(rect.position.x, rect.end.x):
							run.append([Vector3i(x, sh.end.y, 0), Vector2i(x, sh.end.y - 1)])
				2:
					if rect.position.x == sh.position.x:
						for y in range(rect.position.y, rect.end.y):
							run.append([Vector3i(sh.position.x, y, 1), Vector2i(sh.position.x, y)])
				3:
					if rect.end.x == sh.end.x:
						for y in range(rect.position.y, rect.end.y):
							run.append([Vector3i(sh.end.x, y, 1), Vector2i(sh.end.x - 1, y)])
			if run.is_empty():
				continue
			var want := roundi(float(run.size()) / 4.0 * win + 0.2)
			if win >= 0.75:
				want = maxi(want, 1)
			want = mini(want, 3)
			var idx: Array = range(run.size())
			HouseRooms._shuffle(idx, rng)
			var placed: Array = []
			for i in idx:
				if placed.size() >= want:
					break
				var e: Vector3i = run[i][0]
				if str(plan.walls.get(e, "")) != "wall" or _tall(plan, run[i][1]):
					continue
				if run.size() >= 4 and (i == 0 or i == run.size() - 1):
					continue
				var close := false
				for j in placed:
					if absi(j - i) < 2:
						close = true
				if close:
					continue
				placed.append(i)
				plan.add_mount("window", e)


## Count windows per room (for the quality gate): rooms that need one but have none.
static func missing_windows(plan: HousePlan, rules: Dictionary) -> Array:
	var bad: Array = []
	var sh := plan.shell
	for r in plan.rooms:
		if not bool(rules["rooms"].get(str(r["type"]), {}).get("hab", false)):
			continue
		var rect: Rect2i = r["rect"]
		var ext := rect.position.x == sh.position.x or rect.end.x == sh.end.x or rect.position.y == sh.position.y or rect.end.y == sh.end.y
		if not ext:
			continue
		var n := 0
		for m in plan.mounts:
			if str(m["def"]) == "window" and rect.has_point(m["tile"]):
				n += 1
		if n == 0:
			bad.append(str(r["type"]))
	return bad


## Garden door on a non-front wall of a day room. Returns {inner, outer, dir} or {} when nothing fits `yard`.
static func back_door(plan: HousePlan, rules: Dictionary, yard: Rect2i, rng: RandomNumberGenerator) -> Dictionary:
	var sh := plan.shell
	var ok_types: Array = rules.get("back_rooms", [])
	var cands: Array = []
	for x in range(sh.position.x + 1, sh.end.x - 1):
		cands.append([Vector2i(x, sh.position.y), Vector3i(x, sh.position.y, 0), Vector2i(0, -1)])
		cands.append([Vector2i(x, sh.end.y - 1), Vector3i(x, sh.end.y, 0), Vector2i(0, 1)])
	for y in range(sh.position.y + 1, sh.end.y - 1):
		cands.append([Vector2i(sh.position.x, y), Vector3i(sh.position.x, y, 1), Vector2i(-1, 0)])
		cands.append([Vector2i(sh.end.x - 1, y), Vector3i(sh.end.x, y, 1), Vector2i(1, 0)])
	HouseRooms._shuffle(cands, rng)
	for c in cands:
		var t: Vector2i = c[0]
		if plan.type_at(t) not in ok_types or str(plan.walls.get(c[1], "")) != "wall":
			continue
		var near := false
		for d in [Vector2i.ZERO] + HousePlan.DIRS4:
			if plan.clear.has(t + d):
				near = true
		if near or absi(t.x - plan.entry.x) < 3 and t.y == plan.entry.y:
			continue
		var outer: Vector2i = t + c[2]
		if not yard.has_point(outer) or not yard.has_point(outer + c[2]):
			continue
		plan.add_mount("door", c[1])
		plan.clear[t] = true
		plan.must.append(t)
		return {"inner": t, "outer": outer, "dir": c[2]}
	return {}
