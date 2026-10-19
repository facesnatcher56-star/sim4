class_name ApartmentUnits
extends RefCounted
## The flats of an apartment building (a template `units` list written by BuildingGen: id, level, rect, door, kind, bedrooms; lot-local tiles).
## Each flat is a lockable home: assign() gives it to a household (the flat's furniture and its entrance door are owned by that household, the
## door is locked), and autonomy / visitors never use another household's flat (LevelInfo.usable).
##   ApartmentUnits.units_of(lot_id) -> [{id, level, rect (world tiles), door (world tile), kind, bedrooms, lot}]
##   unit_at(tile, level) -> unit dict ({} outside every flat)      owner_of(unit) -> household id (0 = free)
##   door_of(unit) -> the entrance door object                      free_units(lot_id) / assign(unit, hid) / release(unit)
##   units_of_household(hid) -> the flats a household holds

static var _cache: Dictionary = {}          # "lot|template|x,y" -> units


static func units_of(lot_id: String) -> Array:
	var rc := NeighborhoodLots.rect_of(lot_id)
	if rc.size == Vector2i.ZERO:
		return []
	var tid := Neighborhood.template_of(lot_id)
	var key := "%s|%s|%d,%d" % [lot_id, tid, rc.position.x, rc.position.y]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	for u in LotLoader.template(tid).get("units", []):
		var r: Array = u["rect"]
		var d: Array = u["door"]
		out.append({"id": str(u["id"]), "level": int(u["level"]), "rect": Rect2i(Vector2i(int(r[0]), int(r[1])) + rc.position, Vector2i(int(r[2]), int(r[3]))),
			"door": Vector2i(int(d[0]), int(d[1])) + rc.position, "kind": str(u["kind"]), "bedrooms": int(u["bedrooms"]), "lot": lot_id})
	_cache[key] = out
	return out


static func unit_at(tile: Vector2i, level: int) -> Dictionary:
	var lot := NeighborhoodLots.lot_at(tile)
	return {} if lot == "" else unit_in(units_of(lot), tile, level)


## The flat of `units` (a units_of() list) that contains the tile on that floor.
static func unit_in(units: Array, tile: Vector2i, level: int) -> Dictionary:
	for u in units:
		if int(u["level"]) == level and (u["rect"] as Rect2i).has_point(tile):
			return u
	return {}


## The door object between the flat and the corridor.
static func door_of(unit: Dictionary):
	var cached = WorldIface.get_object(int(unit.get("door_id", -1)))
	if cached != null and str(cached.def_id) == "door":
		return cached
	var rc: Rect2i = unit["rect"]
	for o in SysUtil.all_world_objects():
		if str(o.def_id) != "door" or int(o.level) != int(unit["level"]):
			continue
		var ts := HousePlan.edge_tiles(HousePlan.mount_edge(o.tile, int(o.rot)))
		if rc.has_point(ts[0]) != rc.has_point(ts[1]):
			if rc.grow(1).has_point(o.tile):
				unit["door_id"] = int(o.id)
				return o
	return null


static func owner_of(unit: Dictionary) -> int:
	var d = door_of(unit)
	return 0 if d == null else int(Economy.owner.get(int(d.id), 0))


static func free_units(lot_id: String) -> Array:
	var out: Array = []
	for u in units_of(lot_id):
		if owner_of(u) <= 0:
			out.append(u)
	return out


## Does the household hold a flat in this lot?
static func lives_in(hid: int, lot_id: String) -> bool:
	for u in units_of(lot_id):
		if owner_of(u) == hid:
			return true
	return false


static func units_of_household(hid: int) -> Array:
	var out: Array = []
	for l in Neighborhood.lots():
		for u in units_of(str(l["id"])):
			if owner_of(u) == hid:
				out.append(u)
	return out


## Give the flat to a household: its furniture and the entrance door belong to them, and the door is locked.
static func assign(unit: Dictionary, hid: int) -> bool:
	var door = door_of(unit)
	if door == null or hid <= 0:
		return false
	var rc: Rect2i = unit["rect"]
	for o in SysUtil.all_world_objects():
		if int(o.level) == int(unit["level"]) and rc.has_point(o.tile):
			Economy.owner[int(o.id)] = hid
	Economy.owner[int(door.id)] = hid
	WorldIface.state_set(door, "locked", true)
	return true


static func release(unit: Dictionary) -> void:
	var rc: Rect2i = unit["rect"]
	for o in SysUtil.all_world_objects():
		if int(o.level) == int(unit["level"]) and rc.has_point(o.tile):
			Economy.owner.erase(int(o.id))
	var door = door_of(unit)
	if door != null:
		WorldIface.state_set(door, "locked", false)


static func reset() -> void:
	_cache.clear()
