class_name VehicleBays
extends RefCounted
## The places a car of the vehicle layer can stand at a lot (task 42): the driveway, forecourt bays or lay-by built by LotParking when the map was made, checked against the
## live world (a tile that is no longer paved or free, e.g. the player built on it, drops the place). Cached per lot until the map is rebuilt. No place = no visible parked car at that lot.
##   VehicleBays.of(lot_id) -> [place]  (place: kind, pos, face, rect, kerb, back, carport, entry_x, x, z)      VehicleBays.forget()      VehicleBays.valid(place)

static var _cache: Dictionary = {}


static func cfg() -> Dictionary:
	return SysUtil.table("vehicles").get("bays", {})


static func forget() -> void:
	_cache.clear()


static func of(lot_id: String) -> Array:
	if _cache.has(lot_id):
		return _cache[lot_id]
	var out: Array = []
	var w = WorldIface.world()
	if w != null and w.get("width") != null and NeighborhoodLots.rect_of(lot_id).position.x > 0:
		for pl in LotParking.places_of(lot_id):
			if valid(pl):
				var p: Dictionary = (pl as Dictionary).duplicate()
				p["x"] = (p["pos"] as Vector2).x
				p["z"] = (p["pos"] as Vector2).y
				out.append(p)
	var cap: int = int(cfg().get("max_per_lot", 8))
	if out.size() > cap:
		out.resize(cap)
	_cache[lot_id] = out
	return out


## Still paved (or forecourt) and free of objects and walls.
static func valid(place: Dictionary) -> bool:
	var w = WorldIface.world()
	var rc: Rect2 = place["rect"]
	var pc: Dictionary = LotParking.cfg()
	var floors: Array = [LotParking.floor_name(), "concrete"]
	if str(place["kind"]) != "driveway":
		floors.append_array((pc.get("bay", {}) as Dictionary).get("floors", []))
	for tx in range(int(floorf(rc.position.x)), int(ceilf(rc.end.x))):
		for ty in range(int(floorf(rc.position.y)), int(ceilf(rc.end.y))):
			var t := Vector2i(tx, ty)
			if not w.in_bounds(t) or w.object_at(t) != null or not floors.has(w.get_floor(t)):
				return false
	return true
