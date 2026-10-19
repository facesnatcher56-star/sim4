class_name FireSmoke
extends RefCounted
## Smoke PER ROOM. Fires fill their own room (a big room dilutes it: config.fire.room_ref_tiles), smoke leaks to neighbouring rooms through
## doors (a closed door lets only a little through, one somebody just walked through lets much more) and out through windows (venting). Rooms
## come from the World (room_id / room_tiles; doors and windows are the wall edges between them). On a world without rooms (the test stub)
## the whole lot is one room. Also: who can hear a shout how many rooms away (hops), and who stands near a window (smoke dose is lower there).
## Results live in blaze["rs"] {room id -> 0..1}; blaze["smoke"] is the worst room (alarm, haze, buffs read it).

static var _nodes: Dictionary = {}      # room id -> {size, links {rid -> [door edge keys]}, wins [tiles], tile, built}
static var _open: Dictionary = {}       # door edge key -> game minute until which it stands open
static var _lv: Dictionary = {}         # room id -> floor level (room ids are unique over all floors of the world)

static func reset() -> void:
	_nodes.clear()
	_open.clear()
	_lv.clear()

static func _w():
	var w = WorldIface.world()
	return w if (w != null and w.has_method("room_tiles") and w.has_method("wall_at")) else null

static func room_of(tile: Vector2i, level: int = 0) -> int:
	var w = _w()
	if w == null:
		return 0
	var rid: int = int(w.room_id(tile, level))
	if level != 0 and rid >= 0:
		_lv[rid] = level
	return rid

## Room node (built lazily, cached 20 game minutes): size, doors to neighbours, window tiles.
static func node(rid: int, tile: Vector2i) -> Dictionary:
	var now: int = SysUtil.now()
	var n: Dictionary = _nodes.get(rid, {})
	if not n.is_empty() and now - int(n["built"]) < 20:
		return n
	n = {"size": 1, "links": {}, "wins": [], "tile": tile, "built": now, "outdoor": false}
	var w = _w()
	if w == null or rid < 0:
		n["outdoor"] = rid < 0
		n["size"] = 40
		_nodes[rid] = n
		return n
	var lvl: int = int(_lv.get(rid, 0))
	var tiles: Array = w.room_tiles(tile, lvl)
	n["outdoor"] = tiles.is_empty()
	n["size"] = maxi(tiles.size(), 1)
	for t in tiles:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = t + d
			var rn: int = int(w.room_id(nb, lvl))
			if rn == rid:
				continue
			var e: Vector3i = w.edge_between(t, nb)
			var kind: String = str(w.wall_at(e)) if lvl == 0 else str(w.levels.wall_at(e, lvl))
			if lvl != 0 and rn >= 0:
				_lv[rn] = lvl
			if kind == "door":
				if not (n["links"] as Dictionary).has(rn):
					(n["links"] as Dictionary)[rn] = {"keys": [], "tile": nb}
				((n["links"] as Dictionary)[rn]["keys"] as Array).append(str(e))
			elif kind == "window":
				(n["wins"] as Array).append(t)
	_nodes[rid] = n
	return n

static func _door_weight(keys: Array, now: int) -> float:
	var wsum: float = 0.0
	for k in keys:
		wsum += FireRules.num("door_open_flow", 0.5) if int(_open.get(k, -1)) > now else FireRules.num("door_closed_flow", 0.08)
	return wsum

static func _windows_vent() -> bool:
	return not ["rain", "thunderstorm", "snow", "cold_snap", "windy"].has(Weather.current())

## Aware folk standing at a door open it (neat or logical folk close it behind them: it stays shut).
static func _doors(b: Dictionary, now: int) -> void:
	var w = _w()
	if w == null:
		return
	for f in FireRules.folk_in_lot(str(b["lot"])):
		var r: Dictionary = FireFolk.rec(b, f)
		if not bool(r["aware"]) and not FireRules.asleep(f):
			continue
		if FireRules.asleep(f) or f.has_trait("neat") or f.skill_level("logic") >= 4:
			continue
		for e in w.edges_of_tile(f.tile):
			if str(w.wall_at(e)) == "door":
				_open[str(e)] = now + 3

## One minute of smoke for the blaze `b`.
static func step(b: Dictionary, fires: Array) -> void:
	var now: int = SysUtil.now()
	var rs: Dictionary = b["rs"]
	var w = _w()
	var full: float = FireRules.num("smoke_full_at", 3.0)
	var gen: Dictionary = {}
	for f in fires:
		var rid: int = room_of(f["tile"], int(f.get("level", 0)))
		gen[rid] = float(gen.get(rid, 0.0)) + FireRules.at("smoke_weight", int(f["stage"]) - 1, 1.0)
		if not rs.has(rid):
			rs[rid] = 0.0
	if w == null:
		var target: float = minf(float(gen.get(0, 0.0)) / full, 1.0)
		rs[0] = clampf(float(rs.get(0, 0.0)) + clampf(target - float(rs.get(0, 0.0)), -0.05, 0.15), 0.0, 1.0)
		b["smoke"] = float(rs[0])
		return
	_doors(b, now)
	var ref: float = FireRules.num("room_ref_tiles", 30.0)
	for rid2 in gen:
		var nd: Dictionary = node(int(rid2), _tile_of(fires, int(rid2)))
		var target2: float = minf(float(gen[rid2]) / (full * maxf(1.0, float(nd["size"]) / ref)), 1.0)
		rs[rid2] = clampf(float(rs[rid2]) + clampf(target2 - float(rs[rid2]), -0.05, 0.15), 0.0, 1.0)
	# leaking through doors (rooms that already hold smoke push it on)
	var delta: Dictionary = {}
	for rid3 in rs.keys():
		var a: float = float(rs[rid3])
		if a < 0.02:
			continue
		var nd3: Dictionary = node(int(rid3), _any_tile(int(rid3), fires))
		for rn in (nd3["links"] as Dictionary):
			var lk: Dictionary = nd3["links"][rn]
			var other: Dictionary = node(int(rn), lk["tile"])
			if bool(other["outdoor"]):
				continue
			var bb: float = float(rs.get(rn, 0.0))
			var flow: float = clampf(_door_weight(lk["keys"], now) * (a - bb) * 0.25, 0.0, a * 0.5) / maxf(1.0, float(other["size"]) / ref)
			if flow > 0.0:
				delta[rid3] = float(delta.get(rid3, 0.0)) - flow
				delta[rn] = float(delta.get(rn, 0.0)) + flow
	for k in delta:
		rs[k] = clampf(float(rs.get(k, 0.0)) + float(delta[k]), 0.0, 1.0)
	FireLevels.smoke_up(rs, fires)                      # smoke rises into the rooms above a burning room
	# windows vent, rooms without a fire clear slowly
	var vent: bool = _windows_vent()
	var worst: float = 0.0
	for rid4 in rs.keys():
		var lv: float = float(rs[rid4])
		var nd4: Dictionary = node(int(rid4), _any_tile(int(rid4), fires))
		if vent:
			lv *= 1.0 - minf(float((nd4["wins"] as Array).size()) * FireRules.num("window_vent", 0.03), 0.3)
		if not gen.has(rid4):
			lv = maxf(lv - 0.01, 0.0)
		rs[rid4] = lv
		worst = maxf(worst, lv)
	b["smoke"] = worst

static func _tile_of(fires: Array, rid: int) -> Vector2i:
	for f in fires:
		if room_of(f["tile"], int(f.get("level", 0))) == rid:
			return f["tile"]
	return Vector2i.ZERO

## A tile known to lie in room `rid` (a fire's, else the cached node's).
static func _any_tile(rid: int, fires: Array) -> Vector2i:
	if _nodes.has(rid):
		return _nodes[rid]["tile"]
	return _tile_of(fires, rid)

## Smoke level in the room of `tile` (0 when the smoke has not reached it).
static func at(b: Dictionary, tile: Vector2i, level: int = 0) -> float:
	var rs: Dictionary = b.get("rs", {})
	return float(rs.get(room_of(tile, level), 0.0))

## Rooms between two tiles through DOORS (0 = same room); 99 when only walls separate them. Without rooms: 1 per 6 tiles.
static func hops(a: Vector2i, c: Vector2i) -> int:
	var w = _w()
	if w == null:
		return FireRules.dist(a, c) / 6
	var ra: int = room_of(a)
	var rc: int = room_of(c)
	if ra == rc:
		return 0
	var seen: Dictionary = {ra: 0}
	var queue: Array = [[ra, a]]
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		var depth: int = int(seen[cur[0]])
		if depth >= 4:
			continue
		var nd: Dictionary = node(int(cur[0]), cur[1])
		for rn in (nd["links"] as Dictionary):
			if seen.has(rn):
				continue
			seen[rn] = depth + 1
			if int(rn) == rc:
				return depth + 1
			queue.append([rn, nd["links"][rn]["tile"]])
	return 99

## Is the folk within 2 tiles of a window (or the room's way out)? Dose is lower there.
static func near_vent(f) -> bool:
	var w = _w()
	if w == null:
		return false
	var nd: Dictionary = node(room_of(f.tile), f.tile)
	for t in nd["wins"]:
		if FireRules.dist(t, f.tile) <= 2:
			return _windows_vent()
	return false