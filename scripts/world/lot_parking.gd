class_name LotParking
extends RefCounted
## The parking places of the lots (task 42), made when the map is made (MapLots calls `add` after every lot template is placed). Data: data/parking.json.
## Cause: a car stands where a person would park it, so every lot gets a real place for its cars:
##   home / townie home  a DRIVEWAY: a paved strip (floor "driveway") from the kerb through the front fence (the fence is opened there) to the house, with a dropped kerb over the
##                       footway; a house with a garage room (a workbench) has a carport at the head of it; large houses get a double-width drive. No room for one: a LAY-BY of parallel bays
##                       paved into the front verge beside the kerb.
##   shop, office, car park...  marked BAYS on the forecourt (paved where it was lawn), keeping the walkway from the gate to the door clear.
## A place is {kind: driveway|bay|layby, lot, pos (car centre), face (heading when parked), rect (the marked area, tile units), kerb (dropped kerb over the footway), back (reverses out),
## carport}. The places are kept in the lot's region (`region["parking"]`); VehicleBays validates them against the live world, so a player who builds over a driveway just loses it.
## Changes sim state (floors and fence walls of the lots): a new map has "driveway" floors and gaps in the front fences; nothing else.
##   LotParking.add(world, region)      LotParking.places_of(lot_id) -> Array      LotParking.floor_name()

const BODY_L := 4.2
const BODY_W := 1.8


static func cfg() -> Dictionary:
	return SysUtil.table("parking")


static func floor_name() -> String:
	return str(cfg().get("floor", "driveway"))


static func places_of(lot_id: String) -> Array:
	var w = WorldIface.world()
	if w == null or w.get("regions") == null:
		return []
	return (w.regions.by_lot(lot_id) as Dictionary).get("parking", [])


## Plan and build the places of one lot (floors, fence gaps) and store them in the region.
static func add(w, r: Dictionary) -> void:
	var rc: Rect2i = r["rect"]
	var kind: String = str(r["kind"])
	var places: Array = []
	if kind == "home" or kind == "townie_home":
		places = _home(w, r, rc)
	elif kind == "venue" and not (str(r.get("venue_type", "")) in (cfg().get("bay", {}) as Dictionary).get("skip_venues", [])):
		places = _forecourt(w, r, rc)
	r["parking"] = places
	VehicleBays.forget()
	ParkingMarks.forget()


# ------------------------------------------------------------------ tiles

static func _tile_ok(w, t: Vector2i, floors: Array) -> bool:
	if not w.in_bounds(t) or w.object_at(t) != null:
		return false
	return floors.has(w.get_floor(t))


## Every interior edge of the tile rectangle is free of walls (a fence on a horizontal edge is allowed: `fence_ok`, it is opened later); no mounted object on it.
static func _edges_ok(w, x0: int, y0: int, x1: int, y1: int, fence_ok: bool) -> bool:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if y > y0:
				var e := Vector3i(x, y, 0)
				var wt: String = w.wall_at(e)
				if wt != "" and not (fence_ok and wt == "fence"):
					return false
				if w.mounts.has(e):
					return false
			if x > x0:
				var e2 := Vector3i(x, y, 1)
				if w.wall_at(e2) != "" or w.mounts.has(e2):
					return false
	return true


static func _rect_ok(w, x0: int, y0: int, x1: int, y1: int, floors: Array, fence_ok: bool) -> bool:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not _tile_ok(w, Vector2i(x, y), floors):
				return false
	return _edges_ok(w, x0, y0, x1, y1, fence_ok)


static func _pave(w, x0: int, y0: int, x1: int, y1: int, open_fence: bool) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			w.set_floor_raw(Vector2i(x, y), floor_name())
			if open_fence and y > y0 and w.wall_at(Vector3i(x, y, 0)) == "fence":
				w.set_edge(Vector3i(x, y, 0), "")


static func _has_garage(w, rc: Rect2i) -> bool:
	var names: Array = cfg().get("garage_objects", [])
	for o in w.all_objects():
		if rc.has_point(o.tile) and names.has(str(o.def_id)):
			return true
	return false


## x of the gate of a fenced home (a "door" wall in the front fence), or -1.
static func _gate_x(w, rc: Rect2i) -> int:
	for y in range(rc.position.y + 14, rc.end.y + 1):
		for x in range(rc.position.x, rc.end.x):
			if w.wall_at(Vector3i(x, y, 0)) == "door":
				return x
	return -1


# ------------------------------------------------------------------ homes

static func _home(w, r: Dictionary, rc: Rect2i) -> Array:
	var dc: Dictionary = cfg().get("driveway", {})
	var tpl: String = str(r.get("template", ""))
	var two: bool = false
	for p in dc.get("two_for", []):
		if tpl.begins_with(str(p)):
			two = true
	var found: Dictionary = {}
	for wid in ([int(dc.get("width_two", 6)), int(dc.get("width", 3))] if two else [int(dc.get("width", 3))]):
		found = _find_drive(w, rc, wid, dc)
		if not found.is_empty():
			break
	if found.is_empty():
		return _layby(w, r, rc)
	var x0: int = int(found["x0"])
	var wid2: int = int(found["w"])
	var yl: int = rc.end.y - 1
	var y0: int = yl - int(found["d"]) + 1
	var carport: bool = _has_garage(w, rc)
	_pave(w, x0, y0, x0 + wid2 - 1, yl, true)
	var out: Array = []
	var cars: int = maxi(1, wid2 / 3)
	for k in cars:
		var cx: float = float(x0) + 1.5 + 3.0 * float(k)
		var cz: float = float(y0) + 0.35 + BODY_L * 0.5 + 0.2
		out.append({"kind": "driveway", "lot": str(r["lot"]), "pos": Vector2(cx, cz), "face": Vector2(0, -1), "back": true, "carport": carport and k == 0,
			"rect": Rect2(cx - 1.5, float(y0), 3.0, float(yl + 1 - y0)), "kerb": Rect2(cx - 1.5, float(rc.end.y), 3.0, 1.0), "entry_x": cx})
	return out


## The best strip of `wid` columns open from the last row of the lot up to the house: deepest first, far from the gate.
static func _find_drive(w, rc: Rect2i, wid: int, dc: Dictionary) -> Dictionary:
	var floors: Array = dc.get("floors", ["lawn", "grass", "dirt"])
	var yl: int = rc.end.y - 1
	var min_d: int = int(dc.get("min_depth", 6))
	var max_d: int = int(dc.get("max_depth", 9))
	var gx: int = _gate_x(w, rc)
	var gap: int = int(dc.get("min_gate_gap", 2))
	var best: Dictionary = {}
	var best_score: float = -1.0e9
	for x0 in range(rc.position.x + 1, rc.end.x - wid):
		if gx >= 0 and x0 - gap < gx and gx < x0 + wid + gap:
			continue
		var d: int = 0
		while d < max_d and _rect_ok(w, x0, yl - d, x0 + wid - 1, yl, floors, true):
			d += 1
		if d < min_d:
			continue
		var cx: float = float(x0) + float(wid) * 0.5
		var far: float = absf(cx - float(gx)) if gx >= 0 else 0.0
		var score: float = float(d) * 4.0 + minf(far, 14.0) - float(x0 - rc.position.x) * 0.01
		if score > best_score:
			best_score = score
			best = {"x0": x0, "w": wid, "d": d}
	return best


# ------------------------------------------------------------------ lay-by (parallel bays beside the kerb)

static func _layby(w, r: Dictionary, rc: Rect2i) -> Array:
	var lc: Dictionary = cfg().get("layby", {})
	var floors: Array = lc.get("floors", [])
	var len_t: int = int(ceil(float(lc.get("len", 6.0))))
	var dep: int = int(lc.get("d", 2.0))
	var yl: int = rc.end.y - 1
	var walk: Array = lc.get("walkway", [12.0, 20.0])
	var out: Array = []
	var x: int = rc.position.x + 1
	while x + len_t <= rc.end.x - 1 and out.size() < int(lc.get("max", 3)):
		var cxx: float = float(x) + float(len_t) * 0.5
		var inx: float = cxx - float(rc.position.x)
		var in_walk: bool = inx + float(len_t) * 0.5 > float(walk[0]) and inx - float(len_t) * 0.5 < float(walk[1])
		if not in_walk and _rect_ok(w, x, yl - dep + 1, x + len_t - 1, yl, floors, false):
			_pave(w, x, yl - dep + 1, x + len_t - 1, yl, false)
			out.append({"kind": "layby", "lot": str(r["lot"]), "pos": Vector2(cxx, float(yl + 1) - float(dep) * 0.5), "face": Vector2(-1, 0), "back": false, "carport": false,
				"rect": Rect2(float(x), float(yl + 1 - dep), float(len_t), float(dep)), "kerb": Rect2(float(x), float(rc.end.y), float(len_t), 1.0), "entry_x": cxx + float(len_t) * 0.5 + 1.0})
			x += len_t
		else:
			x += 1
	return out


# ------------------------------------------------------------------ forecourt (marked bays of a shop, office, car park...)

static func _forecourt(w, r: Dictionary, rc: Rect2i) -> Array:
	var bc: Dictionary = cfg().get("bay", {})
	var floors: Array = bc.get("floors", [])
	var bw: float = float(bc.get("w", 2.8))
	var dep: int = int(ceil(float(bc.get("d", 5.0))))
	var yl: int = rc.end.y - 1
	var walk: Array = bc.get("walkway", [12.0, 20.0])
	var out: Array = []
	var maxn: int = int(bc.get("max", 8))
	var sides: Array = [[float(bc.get("margin", 1.0)), float(walk[0])], [float(walk[1]), float(rc.size.x) - float(bc.get("margin", 1.0))]]
	for sd in sides:
		var x: float = float(sd[0])
		while x + bw <= float(sd[1]) + 0.01 and out.size() < maxn:
			var xi0: int = int(floor(float(rc.position.x) + x))
			var xi1: int = int(floor(float(rc.position.x) + x + bw - 0.01))
			if _rect_ok(w, xi0, yl - dep + 1, xi1, yl, floors, false):
				var cx: float = float(rc.position.x) + x + bw * 0.5
				_pave_bay(w, xi0, yl - dep + 1, xi1, yl)
				out.append({"kind": "bay", "lot": str(r["lot"]), "pos": Vector2(cx, float(rc.end.y) - float(dep) * 0.5 - 0.25), "face": Vector2(0, -1), "back": true, "carport": false,
					"rect": Rect2(float(rc.position.x) + x, float(yl + 1 - dep), bw, float(dep)), "kerb": Rect2(float(rc.position.x) + x, float(rc.end.y), bw, 1.0), "entry_x": cx})
				x += bw
			else:
				x += 1.0
	return out


## Bay tiles: paved when they were soft ground; a concrete forecourt stays as it is.
static func _pave_bay(w, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var f: String = w.get_floor(Vector2i(x, y))
			if f == "lawn" or f == "grass" or f == "dirt":
				w.set_floor_raw(Vector2i(x, y), floor_name())
