class_name VehicleBays
extends RefCounted
## Parking bays of a lot for the vehicle layer: car-sized strips of the front yard, beside the walkway from the gate, that are open ground (no object,
## no wall, outdoors). Read from the World when asked and cached per lot until the map is rebuilt. No bay = no visible parked car at that lot.
##   VehicleBays.of(lot_id) -> [{x, z, pos}]      VehicleBays.forget()      VehicleBays.length_of(bay)

static var _cache: Dictionary = {}


static func cfg() -> Dictionary:
	return SysUtil.table("vehicles").get("bays", {})


static func forget() -> void:
	_cache.clear()


static func of(lot_id: String) -> Array:
	if _cache.has(lot_id):
		return _cache[lot_id]
	var out: Array = []
	var rc: Rect2i = NeighborhoodLots.rect_of(lot_id)
	var w = WorldIface.world()
	if rc.size != Vector2i.ZERO and w != null and w.get("width") != null and rc.position.x > 0:
		var c: Dictionary = cfg()
		var zc: float = float(rc.end.y) - float(c.get("rows_from_edge", 2.0))
		for ox in c.get("x_offsets", [3.0, 9.0, 22.0, 28.0]):
			var cx: float = float(rc.position.x) + float(ox)
			if _free(w, cx, zc):
				out.append({"x": cx, "z": zc, "pos": Vector2(cx, zc)})
		var cap: int = int(c.get("max_per_lot", 4))
		if out.size() > cap:
			out.resize(cap)
	_cache[lot_id] = out
	return out


static func _free(w, cx: float, zc: float) -> bool:
	for tx in range(int(floorf(cx - 2.4)), int(floorf(cx + 2.4)) + 1):
		for ty in [int(floorf(zc - 0.9)), int(floorf(zc + 0.85))]:
			var t := Vector2i(tx, ty)
			if not w.in_bounds(t) or not w.is_walkable(t) or w.object_at(t) != null:
				return false
			var f: String = w.get_floor(t)
			if f == "" or f == "water" or f == "asphalt" or f == "sidewalk" or f == "crosswalk":
				return false
			if not w.is_outdoor(t):
				return false
			for e in w.edges_of_tile(t):
				if w.wall_at(e) != "":
					return false
	return true
