class_name LevelInfo
extends RefCounted
## Small questions about multi-floor buildings that the systems (fire, accidents, disasters, crime) share, so none of them does level math
## of its own. Everything degrades to "one floor, level 0" on worlds without buildings (the test stub, single-storey lots).
##   LevelInfo.building_at(tile) -> id (-1 none)    LevelInfo.range_of(tile) -> Vector2i(min, max)    LevelInfo.is_multi(tile)
##   LevelInfo.lifts_at(tile) -> Array of lift objects of the building on that tile
##   LevelInfo.on_stairs(f) -> true while a folk stands on a flight of stairs / a ladder
##   LevelInfo.has_basement(tile) / basement_level(tile) / top_level(tile)
##   LevelInfo.height_mult(kind, level) -> how much harder a hazard hits that floor (quake: higher floors worse; flood: basements first)

## Floor of an object or folk (0 for the stub objects of the unit tests, which have no floors).
static func lv(x) -> int:
	return int(x.level) if "level" in x else 0


static func _w():
	var w = WorldIface.world()
	return w if (w != null and "levels" in w and w.levels != null) else null


static func building_at(tile: Vector2i) -> int:
	var w = _w()
	return -1 if w == null else int(w.levels.building_at(tile))


static func range_of(tile: Vector2i) -> Vector2i:
	var w = _w()
	if w == null:
		return Vector2i.ZERO
	var b: int = int(w.levels.building_at(tile))
	if b < 0:
		return Vector2i.ZERO
	var d: Dictionary = w.levels.building(b)
	return Vector2i(int(d["min"]), int(d["max"]))


static func is_multi(tile: Vector2i) -> bool:
	var r := range_of(tile)
	return r.x < 0 or r.y > 0


static var _lot_multi: Dictionary = {}
static var _lot_gen: int = -1


## Does the LOT of this tile (not just the building footprint: the forecourt too) hold a building with floors? Cached per levels generation.
static func lot_is_multi(tile: Vector2i) -> bool:
	var w = _w()
	if w == null or not w.levels.any():
		return false
	if _lot_gen != int(w.levels.gen):
		_lot_multi.clear()
		_lot_gen = int(w.levels.gen)
	var rid: int = int(w.regions.region_at(tile)) if w.regions != null else -1
	if rid < 0:
		return is_multi(tile)
	if _lot_multi.has(rid):
		return bool(_lot_multi[rid])
	var rc: Rect2i = (w.regions.regions[rid] as Dictionary)["rect"]
	var multi := false
	for b in w.levels.buildings.values():
		if (int(b["min"]) < 0 or int(b["max"]) > 0) and rc.intersects(b["rect"]):
			multi = true
	_lot_multi[rid] = multi
	return multi


static func top_level(tile: Vector2i) -> int:
	return range_of(tile).y


static func basement_level(tile: Vector2i) -> int:
	return range_of(tile).x


static func has_basement(tile: Vector2i) -> bool:
	return range_of(tile).x < 0


## Lift objects of the building that contains `tile`.
static func lifts_at(tile: Vector2i) -> Array:
	var out: Array = []
	var w = _w()
	if w == null:
		return out
	var b: int = int(w.levels.building_at(tile))
	if b < 0:
		return out
	for rec in w.portals.portals.values():
		if str(rec["kind"]) == "elevator" and int(w.levels.building_at(rec["tile"])) == b:
			var o = w.objects.get(int(rec["id"]), null)
			if o != null:
				out.append(o)
	return out


## Stairs, ladders and fire escapes of a building (portal records that are not lifts).
static func stairs_at(tile: Vector2i) -> Array:
	var out: Array = []
	var w = _w()
	if w == null:
		return out
	var b: int = int(w.levels.building_at(tile))
	for rec in w.portals.portals.values():
		if str(rec["kind"]) != "elevator" and int(w.levels.building_at(rec["tile"])) == b:
			out.append(rec)
	return out


static func on_stairs(f) -> bool:
	var w = _w()
	if w == null or w.portals.portals.is_empty():
		return false
	return absf(float(w.portals.run_offset(f.tile, int(f.level)))) > 0.0


## 1.0 on the ground floor. Earthquakes shake upper floors harder, floods reach the basement first, storms hit the upper floors and the roof.
static func height_mult(kind: String, level: int) -> float:
	match kind:
		"quake":
			return 0.7 if level < 0 else 1.0 + 0.3 * float(level)
		"flood":
			return 3.0 if level < 0 else (1.0 if level == 0 else 0.0)
		"tornado", "hail", "storm":
			return 0.2 if level < 0 else 1.0 + 0.25 * float(level)
	return 1.0


## Is the tile in a lot that is somebody's home (the player's house, a townie house, a flat block)?
static func home_kind(tile: Vector2i) -> bool:
	var w = _w()
	if w == null or w.regions == null:
		return true
	var r: Dictionary = w.regions.region_of(tile)
	return r.is_empty() or str(r.get("kind", "")) in ["home", "townie_home"]


## May this folk use / walk to that object by itself (autonomy)? Same floor: yes, except inside somebody else's flat (and a free flat the folk
## is not standing in). Other floors: only in a home (the bed is upstairs), never in an office, hospital or school the folk works on another
## floor of; those places put people on their floor.
static func usable(f, o, units: Array = []) -> bool:
	var lv: int = int(o.level)
	var u: Dictionary = {} if units.is_empty() else ApartmentUnits.unit_in(units, o.tile, lv)
	if not u.is_empty():
		var owner := ApartmentUnits.owner_of(u)
		if owner > 0:
			if int(f.household_id) != owner:
				return false
		elif not (int(f.level) == lv and (u["rect"] as Rect2i).has_point(f.tile)):
			return false
	if lv == int(f.level):
		return true
	return home_kind(f.tile)
