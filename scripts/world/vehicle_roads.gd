class_name VehicleRoads
extends RefCounted
## THE ROAD-NET SEAM of the vehicle layer (docs/CITY_GEN_PLAN.md Stage 0). Everything the vehicle code needs to know about road shape is asked HERE, through functions:
##   frontage(lot) / lane_route(...) / sidewalk_route(...)   lane polylines between lots and the junctions they pass (as [id.x, id.y, din, dout] visits)
##   junction_ids() / junction_center(i, j) / junction_at_point(p) / junction_tile(i, j) / right_of(d)    the junction list (ids are opaque pairs)
##   upstream_end(frontage) / downstream_end(frontage)   where traffic comes from / goes to past the end of a lot's street run
## Today's implementation is the straight lattice of data/map_layout.json; a city with curved roads replaces the bodies of these functions, not their callers.
## No other vehicle file reads the layout, the lattice indices or the quadrant zones.
##
## The road graph of the street grid (data/map_layout.json) for the vehicle layer: junction centres, the lane line of every directed street,
## where every lot meets the street, and the shortest lane route between two lot frontages. Traffic keeps to the RIGHT (the lane on the right
## of the heading); the lane in front of every lot flows WEST, which is why every route starts and ends heading west.
## Coordinates are tiles (x, z); a tile is a metre. Pure functions over the layout: no World state, no randomness.
##   VehicleRoads.frontage(lot_id) -> {lot, rc, c, jr, gate, hy, lane_z, curb_z}        VehicleRoads.lane_route(fa, start_x, fb, end_x) -> {pts, visits}
##   VehicleRoads.junction_center(i, j)                                                 VehicleRoads.sidewalk_route(...) same shape, on the sidewalk line

const E := 0
const S := 1
const W := 2
const N := 3
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const TURN_COST := 6.0


static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


static func lay() -> Dictionary:
	return MapBuilder.layout()


static func road_w() -> int:
	return int(lay().get("road_w", 6))


static func xs() -> Array:
	return lay().get("vroads_x", [])


static func ys() -> Array:
	return lay().get("hroads_y", [])


static func junction_center(i: int, j: int) -> Vector2:
	var half: float = float(road_w()) * 0.5
	return Vector2(float(xs()[i]) + half, float(ys()[j]) + half)


## Lot id -> where it meets the street (gate = x of the gate tile centre, hy = first street row below the lot, lane_z / curb_z = lane centre and sidewalk centre).
static func frontage(lot_id: String) -> Dictionary:
	var rc: Rect2i = NeighborhoodLots.rect_of(lot_id)
	if rc.size == Vector2i.ZERO:
		rc = MapBuilder.lot_rect(lot_id)
	if rc.size == Vector2i.ZERO:
		return {}
	var rw: int = road_w()
	var c: int = -1
	var jr: int = -1
	var vx: Array = xs()
	var hy: Array = ys()
	for k in vx.size():
		if int(vx[k]) + rw == rc.position.x:
			c = k
	for k2 in hy.size():
		if int(hy[k2]) == rc.end.y:
			jr = k2
	if c < 0 or jr < 0 or c >= vx.size() - 1:
		return {}
	var hyf: float = float(rc.end.y)
	return {"lot": lot_id, "rc": rc, "c": c, "jr": jr, "gate": float(rc.position.x + MapBuilder.GATE_X) + 0.5, "hy": hyf,
		"lane_z": hyf + float(rw) * 0.5 - float(SysUtil.table("vehicles").get("lane", 1.0)), "curb_z": hyf + 0.5}


## The lane point of the corner where a vehicle going `din` leaves junction centre `ctr` going `dout` (offset lane lines meet there).
static func corner(ctr: Vector2, din: int, dout: int, lane: float) -> Vector2:
	var a := Vector2(DIRS[din])
	var b := Vector2(DIRS[dout])
	if din == dout:
		return ctr + right_of(a) * lane
	return ctr + right_of(a) * lane + right_of(b) * lane


## Shortest list of [i, j, din, dout] junction visits from (arriving at junction (i0, j0) heading west) to (leaving junction (i1, j1) heading west).
static func visits(i0: int, j0: int, i1: int, j1: int) -> Array:
	return search(Vector3i(i0, j0, W), func(cur: Vector3i) -> int: return W if cur.x == i1 and cur.y == j1 and cur.z != E else -1)


## Dijkstra over (junction, heading it was entered with). `goal` returns the heading to leave by when the state is a goal, else -1. Leaving the grid is never an expansion
## (the edge exits are goals). Turns cost TURN_COST tiles, U-turns do not exist.
static func search(start: Vector3i, goal: Callable) -> Array:
	var nx: int = xs().size()
	var ny: int = ys().size()
	var best: Dictionary = {}
	var prev: Dictionary = {}
	var open: Array = []
	best[start] = 0.0
	open.append(start)
	var found: Vector3i = Vector3i(-1, -1, -1)
	var goal_out: int = W
	while not open.is_empty():
		var bi: int = 0
		for k in open.size():
			if float(best[open[k]]) < float(best[open[bi]]):
				bi = k
		var cur: Vector3i = open[bi]
		open.remove_at(bi)
		var g: int = int(goal.call(cur))
		if g >= 0:
			found = cur
			goal_out = g
			break
		for dout in 4:
			if dout == (cur.z + 2) % 4:
				continue
			var nxt: Vector2i = Vector2i(cur.x, cur.y) + DIRS[dout]
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= nx or nxt.y >= ny:
				continue
			var len: float = float(int(xs()[nxt.x]) - int(xs()[cur.x])) if DIRS[dout].y == 0 else float(int(ys()[nxt.y]) - int(ys()[cur.y]))
			var cost: float = float(best[cur]) + absf(len) + (TURN_COST if dout != cur.z else 0.0)
			var ns: Vector3i = Vector3i(nxt.x, nxt.y, dout)
			if not best.has(ns) or cost < float(best[ns]):
				best[ns] = cost
				prev[ns] = cur
				if not open.has(ns):
					open.append(ns)
	if found.x < 0:
		return []
	var chain: Array = [found]
	while prev.has(chain[0]):
		chain.push_front(prev[chain[0]])
	var out: Array = []
	for k2 in chain.size():
		var st: Vector3i = chain[k2]
		var dout2: int = chain[k2 + 1].z if k2 + 1 < chain.size() else goal_out
		out.append([st.x, st.y, st.z, dout2])
	return out


## Lane polyline from the lane in front of lot A at x = start_x to the lane in front of lot B at x = end_x (both heading west) and the junctions passed.
static func lane_route(fa: Dictionary, start_x: float, fb: Dictionary, end_x: float, lane: float = 1.0) -> Dictionary:
	var pts: Array = [Vector2(start_x, float(fa["lane_z"]))]
	var vs: Array = []
	var straight: bool = int(fa["c"]) == int(fb["c"]) and int(fa["jr"]) == int(fb["jr"]) and end_x < start_x
	if not straight:
		vs = visits(int(fa["c"]), int(fa["jr"]), int(fb["c"]) + 1, int(fb["jr"]))
		for v in vs:
			pts.append(corner(junction_center(int(v[0]), int(v[1])), int(v[2]), int(v[3]), lane))
	pts.append(Vector2(end_x, float(fb["lane_z"])))
	return {"pts": pts, "visits": vs}


## Same route on the right-hand sidewalk line (bikes): the lateral offset is the sidewalk lane.
static func sidewalk_route(fa: Dictionary, start_x: float, fb: Dictionary, end_x: float, side: float = 2.5) -> Dictionary:
	var r: Dictionary = lane_route(fa, start_x, fb, end_x, side)
	var pts: Array = r["pts"]
	pts[0] = Vector2(start_x, float(fa["hy"]) + 0.5)
	pts[pts.size() - 1] = Vector2(end_x, float(fb["hy"]) + 0.5)
	return r


static var _leg_cache: Dictionary = {}

## Length in tiles of the lane route from the bus kerb of lot `a` to the bus kerb of lot `b` (what a bus really drives, west-flowing lanes and all), or -1 without a map.
## The timetable of TransportBus is built from it, so the bus in the picture and the minutes on the sign agree.
static func leg_length(a: String, b: String) -> float:
	var key := a + ">" + b
	if _leg_cache.has(key):
		return _leg_cache[key]
	var fa: Dictionary = frontage(a)
	var fb: Dictionary = frontage(b)
	var out: float = -1.0
	if not fa.is_empty() and not fb.is_empty():
		var veh: Dictionary = SysUtil.table("vehicles")
		var bx: float = float((veh.get("bus_stop", {}) as Dictionary).get("bus_x_from_gate", 8.5))
		var lane: float = float(veh.get("lane", 1.0))
		var leg: Dictionary = lane_route(fa, float(fa["gate"]) + bx, fb, float(fb["gate"]) + bx, lane)
		out = VehiclePath.make(leg["pts"], float(veh.get("corner_radius", 1.8))).length
	_leg_cache[key] = out
	return out


## Every junction id of the net (today: lattice column, row).
static func junction_ids() -> Array:
	var out: Array = []
	for i in xs().size():
		for j in ys().size():
			out.append(Vector2i(i, j))
	return out


## A tile inside the junction (for the zone the lights belong to).
static func junction_tile(i: int, j: int) -> Vector2i:
	var c: Vector2 = junction_center(i, j)
	return Vector2i(int(c.x), int(c.y))


## The junction whose box contains the world point, or Vector2i(-1, -1).
static func junction_at_point(p: Vector2) -> Vector2i:
	var half: float = float(road_w()) * 0.5 - 0.6
	var ci: int = -1
	var cj: int = -1
	var vx: Array = xs()
	var hy: Array = ys()
	for i in vx.size():
		if absf(p.x - (float(vx[i]) + half + 0.6)) < half:
			ci = i
	for j in hy.size():
		if absf(p.y - (float(hy[j]) + half + 0.6)) < half:
			cj = j
	return Vector2i(ci, cj) if ci >= 0 and cj >= 0 else Vector2i(-1, -1)


## Past the east end of a lot's street run: {pt (lane point well up the street), visits} for a vehicle that drives in from out of the picture.
static func upstream_end(fr: Dictionary, reach: float = 20.0) -> Dictionary:
	var i: int = int(fr["c"]) + 1
	var x: float = minf(float(xs()[i]) + float(road_w()) * 0.5 + reach, float(WorldIface.world().width) - 3.0)
	return {"pt": Vector2(x, float(fr["lane_z"])), "visits": [[i, int(fr["jr"]), W, W]]}


## Past the west end of a lot's street run: where a vehicle that drives out of the picture ends.
static func downstream_end(fr: Dictionary, reach: float = 28.0) -> Dictionary:
	var i: int = int(fr["c"])
	var x: float = maxf(float(xs()[i]) + float(road_w()) * 0.5 - reach, 3.5)
	return {"pt": Vector2(x, float(fr["lane_z"])), "visits": [[i, int(fr["jr"]), W, W]]}


## Which axis (0 = east-west, 1 = north-south) a heading uses.
static func axis_of(dir: int) -> int:
	return 0 if dir == E or dir == W else 1


# ------------------------------------------------------------------ the ends of the road net (through traffic)
const EDGE_PAD := 8.0      # tiles outside the road end where through traffic enters and leaves: past the map edge, never on a picture

## Every road end where traffic can come in or go out: {key, i, j, dir (heading when coming in), out (heading when leaving), main (a main road ends here)}.
## Today: the lattice ends east, west and north (the south ends meet the woods).
static func edge_ends() -> Array:
	var out: Array = []
	var nx: int = xs().size()
	var ny: int = ys().size()
	for j in ny:
		out.append({"key": "E%d" % j, "i": nx - 1, "j": j, "dir": W, "out": E})
		out.append({"key": "W%d" % j, "i": 0, "j": j, "dir": E, "out": W})
	for i in nx:
		out.append({"key": "N%d" % i, "i": i, "j": 0, "dir": S, "out": N})
	return out


## Lane point of a road end: `inward` true = where traffic appears (outside the map, on its lane), false = where it is gone.
static func end_point(e: Dictionary, inward: bool, lane: float = 1.0) -> Vector2:
	var ctr: Vector2 = junction_center(int(e["i"]), int(e["j"]))
	var d: int = int(e["dir"]) if inward else int(e["out"])
	var sgn: float = -1.0 if inward else 1.0
	return ctr + Vector2(DIRS[d]) * (sgn * (float(road_w()) * 0.5 + EDGE_PAD)) + right_of(Vector2(DIRS[d])) * lane


static func _pts_of(vs: Array, lane: float) -> Array:
	var pts: Array = []
	for v in vs:
		pts.append(corner(junction_center(int(v[0]), int(v[1])), int(v[2]), int(v[3]), lane))
	return pts


## Through traffic: from the road end `a` to the road end `b`. {pts, visits}; empty when there is no way.
static func through_route(a: Dictionary, b: Dictionary, lane: float = 1.0) -> Dictionary:
	var ie: int = int(b["i"])
	var je: int = int(b["j"])
	var oe: int = int(b["out"])
	var vs: Array = search(Vector3i(int(a["i"]), int(a["j"]), int(a["dir"])), func(c: Vector3i) -> int: return oe if c.x == ie and c.y == je and c.z != (oe + 2) % 4 else -1)
	if vs.is_empty():
		return {}
	var pts: Array = [end_point(a, true, lane)]
	pts.append_array(_pts_of(vs, lane))
	pts.append(end_point(b, false, lane))
	return {"pts": pts, "visits": vs}


## From the road end `a` to the lane in front of lot `fb` at x = end_x (heading west).
static func entry_route(a: Dictionary, fb: Dictionary, end_x: float, lane: float = 1.0) -> Dictionary:
	var i1: int = int(fb["c"]) + 1
	var j1: int = int(fb["jr"])
	var vs: Array = search(Vector3i(int(a["i"]), int(a["j"]), int(a["dir"])), func(c: Vector3i) -> int: return W if c.x == i1 and c.y == j1 and c.z != E else -1)
	if vs.is_empty():
		return {}
	var pts: Array = [end_point(a, true, lane)]
	pts.append_array(_pts_of(vs, lane))
	pts.append(Vector2(end_x, float(fb["lane_z"])))
	return {"pts": pts, "visits": vs}


## From the lane in front of lot `fa` at x = start_x (heading west) to the road end `b`.
static func exit_route(fa: Dictionary, start_x: float, b: Dictionary, lane: float = 1.0) -> Dictionary:
	var ie: int = int(b["i"])
	var je: int = int(b["j"])
	var oe: int = int(b["out"])
	var vs: Array = search(Vector3i(int(fa["c"]), int(fa["jr"]), W), func(c: Vector3i) -> int: return oe if c.x == ie and c.y == je and c.z != (oe + 2) % 4 else -1)
	if vs.is_empty():
		return {}
	var pts: Array = [Vector2(start_x, float(fa["lane_z"]))]
	pts.append_array(_pts_of(vs, lane))
	pts.append(end_point(b, false, lane))
	return {"pts": pts, "visits": vs}


## The nearest road end for a car leaving the lane in front of lot `fa` (by lane route length).
static func nearest_end(fa: Dictionary, lane: float = 1.0) -> Dictionary:
	var best: Dictionary = {}
	var best_len: float = 1.0e9
	for e in edge_ends():
		var r: Dictionary = exit_route(fa, float(fa["gate"]), e, lane)
		if r.is_empty():
			continue
		var l: float = 0.0
		var pts: Array = r["pts"]
		for k in range(1, pts.size()):
			l += (pts[k] as Vector2).distance_to(pts[k - 1])
		if l < best_len:
			best_len = l
			best = e
	return best
