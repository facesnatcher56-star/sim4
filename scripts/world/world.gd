class_name WorldGrid
extends Node
## World autoload: grid, edge walls, floors, objects, pathfinding, rooms, folk registry,
## build tools (with undo), save/load. No rendering here.
##
## Conventions
##  - tile = Vector2i (x, y); 3D position = Vector3(x+0.5, 0, y+0.5).
##  - Walls live on tile EDGES. Edge key = Vector3i(x, y, dir):
##      dir 0 -> horizontal edge on the NORTH side of tile (x,y)  (spans vertex (x,y)-(x+1,y))
##      dir 1 -> vertical edge on the WEST side of tile (x,y)     (spans vertex (x,y)-(x,y+1))
##  - Wall types: "wall", "window", "fence" block movement; "door" does not.
##  - Object rot 0..3: front (slot offset [0,1]) faces +y(S), 1 faces -x(W), 2 faces -y(N), 3 faces +x(E).
##    Wall-mounted objects (door/window) use rot as the edge: 0=N, 1=E, 2=S, 3=W edge of the tile.

const WorldObjectScript := preload("res://scripts/world/world_object.gd")
const StarterHouse := preload("res://scripts/world/starter_house.gd")

const DEFAULT_W := 32            # legacy single lot
const DEFAULT_H := 24
const MAP_W := 160               # the one continuous neighbourhood (MapBuilder): change the size HERE only
const MAP_H := 120
const BLOCKING_WALLS := ["wall", "window", "fence"]
const WALL_TYPES := ["wall", "door", "window", "fence"]
const WALL_PRICE := 5
const FLOOR_PRICE := 2
const UNDO_LIMIT := 50
const SELL_RATIO := 0.5

## floor type -> {decor, color}
const FLOOR_DEFS := {
	"grass": {"decor": 0.3, "color": "#6aa84f"},
	"dirt": {"decor": 0.0, "color": "#8a6a45"},
	"stone": {"decor": 0.3, "color": "#9a9a9a"},
	"concrete": {"decor": 0.0, "color": "#b0b0b0"},
	"wood": {"decor": 0.6, "color": "#b8864e"},
	"tile": {"decor": 0.5, "color": "#d9e4ea"},
	"carpet": {"decor": 0.8, "color": "#8a6f9e"},
	# map terrain (MapBuilder): "terrain": true = not meant for the player's paint palette
	"asphalt": {"decor": 0.0, "color": "#4a4d55", "terrain": true, "srgb": true},   # "srgb": colour is exact (the mesher converts it to linear)
	"sidewalk": {"decor": 0.1, "color": "#b9b6ae", "terrain": true, "srgb": true},
	"crosswalk": {"decor": 0.0, "color": "#4a4d55", "terrain": true, "srgb": true},   # asphalt + white bars drawn by the chunk mesher
	"lawn": {"decor": 0.3, "color": "#86c35f", "terrain": true},        # empty reserved lot ground (lighter than block grass)
	"sand": {"decor": 0.0, "color": "#d8c690", "terrain": true, "srgb": true},
	"water": {"decor": 0.4, "color": "#3f7fc0", "terrain": true, "srgb": true, "blocks": true},
}

signal world_reset
signal walls_changed
signal floors_changed

var width: int = DEFAULT_W
var height: int = DEFAULT_H

var defs: Dictionary = {}                 # object defs (data/objects.json)
var floors: PackedStringArray = PackedStringArray()
var walls: Dictionary = {}                # Vector3i -> String type
var mounts: Dictionary = {}               # Vector3i edge -> object id (door/window objects)
var objects: Dictionary = {}              # id -> WorldObject
var mess: Dictionary = {}                 # Vector2i -> float (puddles, crumbs...)
var folk: Dictionary = {}                 # id -> Folk
var folk_pose: Dictionary = {}            # folk_id -> {"pose":String,"face":Vector2i} optional overrides

var starter_spawn_tiles: Array[Vector2i] = []
var starter_bedroom_tile: Vector2i = Vector2i.ZERO

var current_household_id: int = 0
var coin_spend: Callable = Callable()     # (household_id:int, amount:int) -> bool
var coin_refund: Callable = Callable()    # (household_id:int, amount:int) -> void
var last_error: String = ""

var _next_id: int = 1
var _occ: Dictionary = {}                 # tile -> object id (main layer)
var _occ_floor: Dictionary = {}           # tile -> object id (floor layer, rugs)
var _blocked: Dictionary = {}             # tile -> true (blocking objects)

var paths: WorldPaths
var edit: WorldEdit
var objs: WorldObjects
var rooms: WorldRooms
var build: WorldBuild
var saver: WorldSave
var regions: WorldRegions
var nav: WorldNav


func _init() -> void:
	paths = WorldPaths.new(self)
	edit = WorldEdit.new(self)
	objs = WorldObjects.new(self)
	rooms = WorldRooms.new(self)
	build = WorldBuild.new(self)
	saver = WorldSave.new(self)
	regions = WorldRegions.new(self)
	nav = WorldNav.new(self)


func _ready() -> void:
	_load_defs()
	reset(DEFAULT_W, DEFAULT_H)


# ------------------------------------------------------------------ setup

func _load_defs() -> void:
	defs = {}
	var path := "res://data/objects.json"
	if not FileAccess.file_exists(path):
		push_warning("World: data/objects.json missing")
		return
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		for k in parsed:
			if parsed[k] is Dictionary:
				defs[k] = parsed[k]
	else:
		push_error("World: failed to parse objects.json")


func get_def(def_id: String) -> Dictionary:
	if defs.is_empty():
		_load_defs()
	return defs.get(def_id, {})


## Clear everything and create an empty grass lot.
func reset(w: int = DEFAULT_W, h: int = DEFAULT_H) -> void:
	if defs.is_empty():
		_load_defs()
	width = w
	height = h
	floors = PackedStringArray()
	floors.resize(w * h)
	floors.fill("grass")
	regions.reset()
	nav.reset()
	walls.clear()
	mounts.clear()
	objects.clear()
	mess.clear()
	_occ.clear()
	_occ_floor.clear()
	_blocked.clear()
	build.clear_undo()
	folk_pose.clear()
	_next_id = 1
	rooms.invalidate_all()
	starter_spawn_tiles.clear()
	_emit("world_reset")


func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null


func _ev() -> Node:
	var r := _root()
	return r.get_node_or_null("Events") if r != null else null


func _emit(sig: String, a: Variant = null, b: Variant = null) -> void:
	if sig == "world_reset" or sig == "walls_changed" or sig == "floors_changed":
		emit_signal(sig)
		return
	var ev := _ev()
	if ev == null or not ev.has_signal(sig):
		return
	if a == null:
		ev.emit_signal(sig)
	elif b == null:
		ev.emit_signal(sig, a)
	else:
		ev.emit_signal(sig, a, b)


# ------------------------------------------------------------------ grid helpers

func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func tile_to_pos(t: Vector2i) -> Vector3:
	return Vector3(t.x + 0.5, 0.0, t.y + 0.5)


func pos_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func is_walkable(t: Vector2i) -> bool:
	return in_bounds(t) and not _blocked.has(t)


func get_floor(t: Vector2i) -> String:
	if not in_bounds(t):
		return ""
	return floors[t.y * width + t.x]


func edge_between(a: Vector2i, b: Vector2i) -> Vector3i:
	if a.x == b.x:
		return Vector3i(a.x, maxi(a.y, b.y), 0)
	return Vector3i(maxi(a.x, b.x), a.y, 1)


func edge_valid(e: Vector3i) -> bool:
	if e.z == 0:
		return e.x >= 0 and e.x < width and e.y >= 0 and e.y <= height
	return e.x >= 0 and e.x <= width and e.y >= 0 and e.y < height


func wall_at(e: Vector3i) -> String:
	return walls.get(e, "")


## True if movement between orthogonally adjacent tiles is not stopped by a wall edge.
func edge_open(a: Vector2i, b: Vector2i) -> bool:
	var t: String = walls.get(edge_between(a, b), "")
	return t == "" or not (t in BLOCKING_WALLS)


func edges_of_tile(t: Vector2i) -> Array[Vector3i]:
	return [Vector3i(t.x, t.y, 0), Vector3i(t.x, t.y + 1, 0), Vector3i(t.x, t.y, 1), Vector3i(t.x + 1, t.y, 1)]


func mount_edge(t: Vector2i, rot: int) -> Vector3i:
	match posmod(rot, 4):
		0: return Vector3i(t.x, t.y, 0)
		1: return Vector3i(t.x + 1, t.y, 1)
		2: return Vector3i(t.x, t.y + 1, 0)
	return Vector3i(t.x, t.y, 1)


# ------------------------------------------------------------------ slots / reservations

func slot_tile(obj_or_id: Variant, slot_idx: int) -> Vector2i:
	var o = obj_or_id if obj_or_id is RefCounted else objects.get(int(obj_or_id), null)
	if o == null:
		return Vector2i(-1, -1)
	return o.slot_tile(slot_idx)


func reserve(object_id: int, slot_idx: int, folk_id: int) -> bool:
	var o = objects.get(object_id, null)
	if o == null or slot_idx < 0 or slot_idx >= o.slot_count():
		return false
	if o.slots_reserved.has(slot_idx):
		return o.slots_reserved[slot_idx] == folk_id
	o.slots_reserved[slot_idx] = folk_id
	return true


func release(object_id: int, slot_idx: int, folk_id: int) -> void:
	var o = objects.get(object_id, null)
	if o == null:
		return
	if o.slots_reserved.get(slot_idx, -999) == folk_id:
		o.slots_reserved.erase(slot_idx)


func release_all(folk_id: int) -> void:
	for o in objects.values():
		for k in o.slots_reserved.keys():
			if o.slots_reserved[k] == folk_id:
				o.slots_reserved.erase(k)


func is_slot_free(object_id: int, slot_idx: int) -> bool:
	var o = objects.get(object_id, null)
	return o != null and slot_idx >= 0 and slot_idx < o.slot_count() and not o.slots_reserved.has(slot_idx)


## First free slot index or -1.
func free_slot(object_id: int) -> int:
	var o = objects.get(object_id, null)
	return -1 if o == null else o.free_slot()


## (object_id, slot_idx) currently reserved by the folk, or null.
func reservation_of(folk_id: int) -> Variant:
	for o in objects.values():
		for k in o.slots_reserved:
			if o.slots_reserved[k] == folk_id:
				return [o.id, k]
	return null


# ------------------------------------------------------------------ folk registry

func add_folk(f, tile: Vector2i) -> void:
	f.tile = tile
	folk[f.id] = f
	_emit("folk_added", f.id)


func remove_folk(folk_id: int) -> void:
	if not folk.has(folk_id):
		return
	release_all(folk_id)
	folk.erase(folk_id)
	folk_pose.erase(folk_id)
	_emit("folk_removed", folk_id)


func get_folk(folk_id: int):
	return folk.get(folk_id, null)


func all_folk() -> Array:
	return folk.values()


## Optional visual hints (renderer reads these). pose: stand|walk|sit|lie|""
func set_folk_pose(folk_id: int, pose: String, face: Vector2i = Vector2i.ZERO) -> void:
	if pose == "":
		folk_pose.erase(folk_id)
	else:
		folk_pose[folk_id] = {"pose": pose, "face": face}


# ------------------------------------------------------------------ mess

func add_mess(t: Vector2i, amount: float) -> void:
	if not in_bounds(t):
		return
	mess[t] = clampf(float(mess.get(t, 0.0)) + amount, 0.0, 10.0)
	if mess[t] <= 0.0:
		mess.erase(t)
	rooms.mark_dirty(t)
	regions.mark_floor_dirty(t)      # mess tints the floor
	_emit("object_state_changed", -1, "mess")


# ------------------------------------------------------------------ delegates to the helper classes
func sell_object(object_id: int, household_id: int = -1) -> bool: return build.sell_object(object_id, household_id)
func undo_last() -> bool: return build.undo_last()
func sell_object_at(t: Vector2i, household_id: int = -1) -> bool: return build.sell_object_at(t, household_id)
func can_afford(household_id: int, amount: int) -> bool: return build.can_afford(household_id, amount)
func clear_undo() -> void: build.clear_undo()
func undo_count() -> int: return build.undo_count()
func buy_place(def_id: String, tile: Vector2i, rot: int = 0, household_id: int = -1) -> int: return build.buy_place(def_id, tile, rot, household_id)
func _spend(household_id: int, amount: int) -> bool: return build._spend(household_id, amount)
func object_price(def_id: String) -> int: return build.object_price(def_id)
func _push_undo(op: Dictionary) -> void: build._push_undo(op)
func set_floor_rect_raw(a: Vector2i, b: Vector2i, type: String) -> void: edit.set_floor_rect_raw(a, b, type)
func _line_edges(a: Vector2i, b: Vector2i) -> Array[Vector3i]: return edit._line_edges(a, b)
func set_floor_raw(t: Vector2i, type: String) -> void: edit.set_floor_raw(t, type)
func set_edge(e: Vector3i, type: String) -> bool: return edit.set_edge(e, type)
func add_wall(a: Vector2i, b: Vector2i) -> void: edit.add_wall(a, b)
func set_wall_line(a: Vector2i, b: Vector2i, type: String = "wall", household_id: int = -1) -> int: return edit.set_wall_line(a, b, type, household_id)
func paint_floor(t: Vector2i, type: String, household_id: int = -1) -> bool: return edit.paint_floor(t, type, household_id)
func paint_floor_rect(a: Vector2i, b: Vector2i, type: String, household_id: int = -1) -> int: return edit.paint_floor_rect(a, b, type, household_id)
func _create_object(def_id: String, tile: Vector2i, rot: int, force_id: int) -> int: return objs._create_object(def_id, tile, rot, force_id)
func place_object(def_id: String, tile: Vector2i, rot: int = 0) -> int: return objs.place_object(def_id, tile, rot)
func objects_in_radius(tile: Vector2i, r: float) -> Array: return objs.objects_in_radius(tile, r)
func all_objects() -> Array: return objs.all_objects()
func objects_in_lot_of(tile: Vector2i, r: float) -> Array: return objs.objects_in_lot_of(tile, r)
func object_at(t: Vector2i): return objs.object_at(t)
func objects_of_def(def_id: String) -> Array: return objs.objects_of_def(def_id)
func set_object_state(object_id: int, key: String, value: Variant) -> void: objs.set_object_state(object_id, key, value)
func objects_with_tag(tag: String) -> Array: return objs.objects_with_tag(tag)
func get_object(object_id: int): return objs.get_object(object_id)
func remove_object(object_id: int) -> bool: return objs.remove_object(object_id)
func can_place(def_id: String, tile: Vector2i, rot: int = 0) -> bool: return objs.can_place(def_id, tile, rot)
func add_object_state(object_id: int, key: String, delta: float) -> void: objs.add_object_state(object_id, key, delta)
func find_path(from: Vector2i, to: Vector2i, diagonals: bool = true) -> Array[Vector2i]: return nav.find_path(from, to, diagonals)
func path_length(from: Vector2i, to: Vector2i) -> float: return nav.path_length(from, to)
func has_path(from: Vector2i, to: Vector2i) -> bool: return nav.has_path(from, to)
func nearest_reachable_neighbor(from: Vector2i, target: Vector2i) -> Vector2i: return paths.nearest_reachable_neighbor(from, target)
func room_cleanliness(tile: Vector2i) -> float: return rooms.room_cleanliness(tile)
func room_tiles(tile: Vector2i) -> Array[Vector2i]: return rooms.room_tiles(tile)
func room_info(tile: Vector2i) -> Dictionary: return rooms.room_info(tile)
func room_id(tile: Vector2i) -> int: return rooms.room_id(tile)
func room_count() -> int: return rooms.room_count()
func is_outdoor(tile: Vector2i) -> bool: return rooms.is_outdoor(tile)
func can_build(tile: Vector2i) -> bool: return regions.can_build(tile)
func region_at(tile: Vector2i) -> int: return regions.region_at(tile)
func chunk_of(tile: Vector2i) -> Vector2i: return regions.chunk_of(tile)
func room_score(tile: Vector2i) -> float: return rooms.room_score(tile)
func load_dict(d: Dictionary) -> void: saver.load_dict(d)
func save_dict(include_folk: bool = false) -> Dictionary: return saver.save_dict(include_folk)
func load_starter_house() -> void: saver.load_starter_house()
