class_name HouseRooms
extends RefCounted
## Room layout of one lot: a treemap of room rectangles inside the shell (optionally around a hall strip),
## open-plan "zones" inside one room group, then the wall edges between different groups.

const PRIV := ["bedroom", "master", "kids", "nursery", "bath", "powder"]


## Spec lists -> layout items {type, area, min, gkey?, gtype?}. An open-plan group {"zones": [...]} becomes one item per zone
## sharing a gkey (they end up in one wall-less group, possibly L-shaped).
static func program(spec: Dictionary, rules: Dictionary) -> Dictionary:
	var rt: Dictionary = rules["rooms"]
	var out := {"pub": [], "priv": []}
	var n := 0
	for side in ["pub", "priv"]:
		for e in spec.get("public" if side == "pub" else "private", []):
			if e is Dictionary:
				n += 1
				for z in (e["zones"] as Array):
					(out[side] as Array).append({"type": str(z), "area": float(rt[z]["area"]), "min": 2, "gkey": "g%d" % n, "gtype": str((e["zones"] as Array)[0])})
			else:
				(out[side] as Array).append({"type": str(e), "area": float(rt[str(e)]["area"]), "min": int(rt[str(e)]["min_dim"])})
	return out


## Fill plan.rooms / room_of / walls. Returns false when the program does not fit the shell.
static func layout(plan: HousePlan, prog: Dictionary, hall: int, rules: Dictionary, rng: RandomNumberGenerator, band: bool = false) -> bool:
	var leaves: Array = []     # {item, rect}
	var pub: Array = _shuffle_units(prog["pub"], rng)
	var priv: Array = _shuffle_units(prog["priv"], rng)
	var sh := plan.shell
	plan.scale = float(sh.size.x * sh.size.y) / maxf(1.0, _area(pub) + _area(priv) + (8.0 if hall > 0 else 0.0))
	if hall <= 0 and not band:
		var all: Array = _shuffle_units(pub + priv, rng)
		if not _treemap(sh, all, rng, leaves):
			return false
	else:
		var horizontal := rng.randf() < (0.75 if sh.size.x >= sh.size.y else 0.25)
		var total: int = sh.size.y if horizontal else sh.size.x
		var pa := _area(pub)
		var qa := _area(priv)
		var dp := roundi(float(total - hall) * pa / maxf(1.0, pa + qa))
		dp = clampi(dp, 3, total - hall - 3)
		var dq := total - hall - dp
		if dq < 3 or dp < 3:
			return false
		var pub_r: Rect2i
		var hall_r: Rect2i
		var priv_r: Rect2i
		var flip := rng.randf() < 0.5
		if horizontal:       # pub south, priv north (entry is on the south wall)
			priv_r = Rect2i(sh.position.x, sh.position.y, sh.size.x, dq)
			hall_r = Rect2i(sh.position.x, sh.position.y + dq, sh.size.x, hall)
			pub_r = Rect2i(sh.position.x, sh.position.y + dq + hall, sh.size.x, dp)
		elif flip:
			pub_r = Rect2i(sh.position.x, sh.position.y, dp, sh.size.y)
			hall_r = Rect2i(sh.position.x + dp, sh.position.y, hall, sh.size.y)
			priv_r = Rect2i(sh.position.x + dp + hall, sh.position.y, dq, sh.size.y)
		else:
			priv_r = Rect2i(sh.position.x, sh.position.y, dq, sh.size.y)
			hall_r = Rect2i(sh.position.x + dq, sh.position.y, hall, sh.size.y)
			pub_r = Rect2i(sh.position.x + dq + hall, sh.position.y, dp, sh.size.y)
		if hall > 0:
			leaves.append({"item": {"type": "hall", "zones": [], "area": 1.0, "min": 1}, "rect": hall_r})
		if not _slice(priv_r, priv, horizontal, leaves):
			return false
		if not _treemap(pub_r, pub, rng, leaves):
			return false
	_flatten(plan, leaves)
	plan.index_rooms()
	if not contiguous(plan):
		return false
	_walls(plan)
	return true


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## Shuffle whole rooms; the zones of one open-plan group stay next to each other.
static func _shuffle_units(items: Array, rng: RandomNumberGenerator) -> Array:
	var units: Array = []
	var by_key: Dictionary = {}
	for it in items:
		var gk := str(it.get("gkey", ""))
		if gk != "" and by_key.has(gk):
			(by_key[gk] as Array).append(it)
		else:
			var u: Array = [it]
			units.append(u)
			if gk != "":
				by_key[gk] = u
	_shuffle(units, rng)
	var out: Array = []
	for u in units:
		var z: Array = u
		if z.size() > 1:
			_shuffle(z, rng)
		out.append_array(z)
	return out


static func _area(items: Array) -> float:
	var a := 0.0
	for it in items:
		a += float(it["area"])
	return a


static func _maxmin(items: Array) -> int:
	var m := 1
	for it in items:
		m = maxi(m, int(it["min"]))
	return m


## Treemap: split the item list in two halves of equal area, cut the rect proportionally along its long side.
static func _treemap(rect: Rect2i, items: Array, rng: RandomNumberGenerator, out: Array) -> bool:
	if items.is_empty():
		return false
	if items.size() == 1:
		if rect.size.x < int(items[0]["min"]) or rect.size.y < int(items[0]["min"]):
			return false
		out.append({"item": items[0], "rect": rect})
		return true
	var total := _area(items)
	var k := 1
	var best := 1e9
	var cum := 0.0
	for i in items.size() - 1:
		cum += float(items[i]["area"])
		var dev := absf(cum - total * 0.5)
		if dev < best:
			best = dev
			k = i + 1
	var ga := items.slice(0, k)
	var gb := items.slice(k)
	var share := _area(ga) / total
	var cut_x := rect.size.x >= rect.size.y
	if rng.randf() < 0.2:
		cut_x = not cut_x
	for attempt in 2:
		var length: int = rect.size.x if cut_x else rect.size.y
		var depth: int = rect.size.y if cut_x else rect.size.x
		var lo := _maxmin(ga)
		var hi := _maxmin(gb)
		if depth >= maxi(lo, hi) and length >= lo + hi:
			var cut := clampi(roundi(float(length) * share), lo, length - hi)
			var ra: Rect2i
			var rb: Rect2i
			if cut_x:
				ra = Rect2i(rect.position.x, rect.position.y, cut, rect.size.y)
				rb = Rect2i(rect.position.x + cut, rect.position.y, rect.size.x - cut, rect.size.y)
			else:
				ra = Rect2i(rect.position.x, rect.position.y, rect.size.x, cut)
				rb = Rect2i(rect.position.x, rect.position.y + cut, rect.size.x, rect.size.y - cut)
			return _treemap(ra, ga, rng, out) and _treemap(rb, gb, rng, out)
		cut_x = not cut_x
	return false


## One row of rooms along a strip; every room touches the strip's long side (and so the hall).
static func _slice(rect: Rect2i, items: Array, along_x: bool, out: Array) -> bool:
	if items.is_empty():
		return false
	var length: int = rect.size.x if along_x else rect.size.y
	var depth: int = rect.size.y if along_x else rect.size.x
	if depth < _maxmin(items):
		return false
	var used := 0
	var weights := 0.0
	for it in items:
		used += int(it["min"])
		weights += float(it["area"])
	if used > length:
		return false
	var extra := length - used
	var sizes: Array = []
	var given := 0
	for it in items:
		var s := int(it["min"]) + int(floor(float(extra) * float(it["area"]) / weights))
		sizes.append(s)
		given += s
	var i := 0
	while given < length:
		sizes[i % sizes.size()] += 1
		given += 1
		i += 1
	var pos := 0
	for n in items.size():
		var r: Rect2i
		if along_x:
			r = Rect2i(rect.position.x + pos, rect.position.y, sizes[n], rect.size.y)
		else:
			r = Rect2i(rect.position.x, rect.position.y + pos, rect.size.x, sizes[n])
		out.append({"item": items[n], "rect": r})
		pos += int(sizes[n])
	return true


## Leaves -> plan.rooms (leaves with the same gkey share a group = one open room).
static func _flatten(plan: HousePlan, leaves: Array) -> void:
	plan.rooms.clear()
	var gmap: Dictionary = {}
	var next := 0
	for lf in leaves:
		var it: Dictionary = lf["item"]
		var gk := str(it.get("gkey", ""))
		var g: int
		if gk != "":
			if not gmap.has(gk):
				gmap[gk] = next
				next += 1
			g = gmap[gk]
		else:
			g = next
			next += 1
		plan.rooms.append({"id": plan.rooms.size(), "type": it["type"], "gtype": it.get("gtype", it["type"]), "rect": lf["rect"], "group": g, "zone": gk != ""})


## Every open-plan group must be one connected region.
static func contiguous(plan: HousePlan) -> bool:
	var tiles: Dictionary = {}
	for t in plan.room_of:
		var g := plan.group_at(t)
		if not tiles.has(g):
			tiles[g] = []
		tiles[g].append(t)
	for g in tiles:
		var all: Array = tiles[g]
		var seen := {all[0]: true}
		var stack: Array = [all[0]]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in HousePlan.DIRS4:
				var nb: Vector2i = c + d
				if not seen.has(nb) and plan.group_at(nb) == g:
					seen[nb] = true
					stack.append(nb)
		if seen.size() != all.size():
			return false
	return true


## Wall edges around the shell and between different groups.
static func _walls(plan: HousePlan) -> void:
	var sh := plan.shell
	plan.walls.clear()
	for y in range(sh.position.y, sh.end.y):
		for x in range(sh.position.x, sh.end.x):
			var t := Vector2i(x, y)
			var g := plan.group_at(t)
			if x == sh.position.x:
				plan.walls[Vector3i(x, y, 1)] = "wall"
			if y == sh.position.y:
				plan.walls[Vector3i(x, y, 0)] = "wall"
			if x == sh.end.x - 1 or plan.group_at(t + Vector2i(1, 0)) != g:
				plan.walls[Vector3i(x + 1, y, 1)] = "wall"
			if y == sh.end.y - 1 or plan.group_at(t + Vector2i(0, 1)) != g:
				plan.walls[Vector3i(x, y + 1, 0)] = "wall"
