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
	var nx: int = xs().size()
	var ny: int = ys().size()
	var best: Dictionary = {}
	var prev: Dictionary = {}
	var open: Array = []
	var start: Vector3i = Vector3i(i0, j0, W)
	best[start] = 0.0
	open.append(start)
	var goal: Vector3i = Vector3i(-1, -1, -1)
	while not open.is_empty():
		var bi: int = 0
		for k in open.size():
			if float(best[open[k]]) < float(best[open[bi]]):
				bi = k
		var cur: Vector3i = open[bi]
		open.remove_at(bi)
		if cur.x == i1 and cur.y == j1 and cur.z != E:
			goal = cur
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
	if goal.x < 0:
		return []
	var chain: Array = [goal]
	while prev.has(chain[0]):
		chain.push_front(prev[chain[0]])
	var out: Array = []
	for k2 in chain.size():
		var st: Vector3i = chain[k2]
		var dout2: int = chain[k2 + 1].z if k2 + 1 < chain.size() else W
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
