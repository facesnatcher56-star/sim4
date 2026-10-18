class_name WorldLevels
extends RefCounted
## Multi-floor data of the map (`World.levels`). Level 0 (the ground) stays in the World's own grid / dictionaries exactly as
## before; every OTHER level (1.. above, -1.. basements, no limit) is a sparse LevelLayer. A BUILDING is a record
## {id, rect, min, max, roof, label, region} saying which tiles have extra levels and how many; layers are global per level number
## (buildings never overlap in x / y), so memory is proportional to what is built, not to levels x map size.
##
## Level-aware queries all take `level` (default 0 = old behaviour):  is_walkable(tile, level), floor_at, wall_at, edge_open,
## set_edge, plus portals (stairs / elevators ...) in LevelPortals (`World.portals`) and routing in LevelRouter (`World.router`).
## Position = Vector3i(x, y, level) (LPos).  Edits that cost coins / have undo live in LevelBuild (`World.lbuild`).

const MAX_LEVELS := 64                 # sanity bound for the data (nothing in the game needs more than a tall tower)

var world: WorldGrid
var buildings: Dictionary = {}         # id -> {id, rect: Rect2i, min: int, max: int, roof: String, label: String, region: int}
var layers: Dictionary = {}            # level (int, != 0) -> LevelLayer
var ground_holes: Dictionary = {}      # Vector2i -> true: ground tiles with a stairwell from a basement below (blocked, no floor drawn)
var gen: int = 0                       # bumped on any structural change (route + view caches)
var _next_bid: int = 1


func _init(w: WorldGrid) -> void:
	world = w


func reset() -> void:
	buildings.clear()
	layers.clear()
	_next_bid = 1
	gen += 1


func touch() -> void:
	gen += 1


## True once any building is registered: cheap guard for hot paths.
func any() -> bool:
	return not buildings.is_empty()


# ------------------------------------------------------------------ buildings

## Register a building footprint. `lo` / `hi` = lowest / highest level that exist (0 / 0 = ground only).
func add_building(rect: Rect2i, lo: int = 0, hi: int = 0, extra: Dictionary = {}) -> int:
	var b: Dictionary = {"id": _next_bid, "rect": rect, "min": mini(lo, 0), "max": maxi(hi, 0), "roof": "flat", "label": "", "region": -1}
	for k in extra:
		b[k] = extra[k]
	var id: int = int(b["id"])
	_next_bid = maxi(_next_bid, id + 1)
	buildings[id] = b
	gen += 1
	return id


func building(id: int) -> Dictionary:
	return buildings.get(id, {})


## Building whose footprint covers the tile (-1 none). Few buildings: a linear scan beats any index.
func building_at(tile: Vector2i) -> int:
	for b in buildings.values():
		if (b["rect"] as Rect2i).has_point(tile):
			return int(b["id"])
	return -1


## Building of the lot region `rid` (-1 none).
func building_of_region(rid: int) -> int:
	for b in buildings.values():
		if int(b["region"]) == rid:
			return int(b["id"])
	return -1


func has_level(bid: int, level: int) -> bool:
	var b: Dictionary = buildings.get(bid, {})
	return not b.is_empty() and level >= int(b["min"]) and level <= int(b["max"])


## (lowest, highest) level of the building at a tile; (0, 0) when there is none.
func range_at(tile: Vector2i) -> Vector2i:
	var b: Dictionary = buildings.get(building_at(tile), {})
	return Vector2i(0, 0) if b.is_empty() else Vector2i(int(b["min"]), int(b["max"]))


func level_count(bid: int) -> int:
	var b: Dictionary = buildings.get(bid, {})
	return 1 if b.is_empty() else int(b["max"]) - int(b["min"]) + 1


## Height in metres of the building above the ground (for shells and the camera).
func height_of(bid: int) -> float:
	var b: Dictionary = buildings.get(bid, {})
	return LPos.H if b.is_empty() else float(int(b["max"]) + 1) * LPos.H


func set_range(bid: int, lo: int, hi: int) -> void:
	if buildings.has(bid):
		buildings[bid]["min"] = mini(lo, 0)
		buildings[bid]["max"] = maxi(hi, 0)
		gen += 1


# ------------------------------------------------------------------ layers

## The layer of a level != 0 (created on demand), null for level 0.
func layer(level: int, create: bool = true) -> LevelLayer:
	if level == 0:
		return null
	if not layers.has(level):
		if not create:
			return null
		layers[level] = LevelLayer.new(level)
	return layers[level]


func active_levels() -> Array:
	var out: Array = layers.keys()
	out.sort()
	return out


# ------------------------------------------------------------------ level-aware tile queries

func floor_at(tile: Vector2i, level: int = 0) -> String:
	if level == 0:
		return world.get_floor(tile)
	var lay := layer(level, false)
	return "" if lay == null else str(lay.floors.get(tile, ""))


## Something to stand on: a floor tile that is not blocked (level 0: the usual rule).
func is_walkable(tile: Vector2i, level: int = 0) -> bool:
	if level == 0:
		return world.is_walkable(tile)
	var lay := layer(level, false)
	return lay != null and lay.floors.has(tile) and not lay.blocked.has(tile)


## A floor of a higher level of the building lies over this tile (a roof / ceiling for the weather).
func covered(tile: Vector2i, level: int = 0) -> bool:
	var bid := building_at(tile)
	if bid < 0:
		return false
	for m in range(level + 1, int(buildings[bid]["max"]) + 1):
		var lay := layer(m, false)
		if lay != null and lay.floors.has(tile) and not lay.holes.has(tile):
			return true
	return false


func blocked_set(level: int) -> Dictionary:
	if level == 0:
		return world._blocked
	return layer(level).blocked


func walls_of(level: int) -> Dictionary:
	if level == 0:
		return world.walls
	return layer(level).walls


func mounts_of(level: int) -> Dictionary:
	if level == 0:
		return world.mounts
	return layer(level).mounts


func wall_at(e: Vector3i, level: int = 0) -> String:
	if level == 0:
		return world.wall_at(e)
	var lay := layer(level, false)
	return "" if lay == null else str(lay.walls.get(e, ""))


func edge_open(a: Vector2i, b: Vector2i, level: int = 0) -> bool:
	if level == 0:
		return world.edge_open(a, b)
	var lay := layer(level, false)
	if lay == null:
		return true
	var t: String = lay.walls.get(world.edge_between(a, b), "")
	return t == "" or not (t in world.BLOCKING_WALLS)


## Raw set of a floor tile on a level (loaders, tests, LevelBuild). type "" erases.
func set_floor_raw(tile: Vector2i, type: String, level: int) -> void:
	if level == 0:
		world.set_floor_raw(tile, type)
		return
	var lay := layer(level)
	if type == "":
		lay.floors.erase(tile)
	else:
		lay.floors[tile] = type
	lay.touch()
	gen += 1
	world.rooms.mark_dirty(tile, level)


func set_floor_rect_raw(a: Vector2i, b: Vector2i, type: String, level: int) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			set_floor_raw(Vector2i(x, y), type, level)
	world._emit("floors_changed")


func set_edge(e: Vector3i, type: String, level: int = 0) -> bool:
	if level == 0:
		return world.set_edge(e, type)
	if not world.edge_valid(e):
		return false
	if type == "none":
		type = ""
	var lay := layer(level)
	var old: String = lay.walls.get(e, "")
	if old == type:
		return false
	if lay.mounts.has(e):
		world.remove_object(lay.mounts[e])
	if type == "":
		lay.walls.erase(e)
	else:
		lay.walls[e] = type
	lay.touch()
	gen += 1
	world.rooms.mark_dirty_edge(e, level)
	world._emit("walls_changed")
	return true


# ------------------------------------------------------------------ save / load

func to_dict() -> Dictionary:
	var bl: Array = []
	for b in buildings.values():
		var rc: Rect2i = b["rect"]
		bl.append({"id": b["id"], "rect": [rc.position.x, rc.position.y, rc.size.x, rc.size.y], "min": b["min"], "max": b["max"],
			"roof": b["roof"], "label": b["label"], "region": b["region"]})
	var ll: Array = []
	for lv in active_levels():
		var lay: LevelLayer = layers[lv]
		if not lay.is_empty():
			ll.append(lay.to_dict())
	return {"buildings": bl, "layers": ll, "next": _next_bid}


## Objects are recreated afterwards by WorldSave (they carry their own level), which refills occupancy / mounts / holes.
func from_dict(d: Dictionary) -> void:
	for bd in d.get("buildings", []):
		var a: Array = bd["rect"]
		add_building(Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])), int(bd.get("min", 0)), int(bd.get("max", 0)),
			{"id": int(bd["id"]), "roof": str(bd.get("roof", "flat")), "label": str(bd.get("label", "")), "region": int(bd.get("region", -1))})
	for ld in d.get("layers", []):
		var lay := layer(int(ld["level"]))
		lay.load_dict(ld)
	_next_bid = maxi(_next_bid, int(d.get("next", 1)))
	gen += 1
