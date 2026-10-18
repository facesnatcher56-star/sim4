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

const DEFAULT_W := 32
const DEFAULT_H := 24
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
var _undo: Array = []
var _rooms_dirty: bool = true
var _room_of: Dictionary = {}             # tile -> room index
var _rooms: Array = []                    # {id, tiles:Array[Vector2i], outdoor:bool}
var _stat_script: Script = null
var _stat_checked: bool = false


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
	for i in floors.size():
		floors[i] = "grass"
	walls.clear()
	mounts.clear()
	objects.clear()
	mess.clear()
	_occ.clear()
	_occ_floor.clear()
	_blocked.clear()
	_undo.clear()
	folk_pose.clear()
	_next_id = 1
	_rooms_dirty = true
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


# ------------------------------------------------------------------ pathfinding

func _step_ok(a: Vector2i, d: Vector2i, goal: Vector2i) -> bool:
	var b := a + d
	if not in_bounds(b):
		return false
	if _blocked.has(b) and b != goal:
		return false
	if d.x == 0 or d.y == 0:
		return edge_open(a, b)
	# diagonal: no corner cutting
	var hx := a + Vector2i(d.x, 0)
	var hy := a + Vector2i(0, d.y)
	if not is_walkable(hx) or not is_walkable(hy):
		return false
	return edge_open(a, hx) and edge_open(hx, b) and edge_open(a, hy) and edge_open(hy, b)


## A* path of steps: EXCLUDES the start tile, INCLUDES the goal (size == number of steps).
## Empty array if unreachable OR if from == to (use has_path() to tell them apart).
## The goal tile may itself be blocked (e.g. a slot inside furniture); start tile is never checked.
func find_path(from: Vector2i, to: Vector2i, diagonals: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(from) or not in_bounds(to):
		return out
	if from == to:
		return out
	var n := width * height
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	if diagonals:
		dirs.append_array([Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)])
	# binary heap of [f, idx] pairs
	var heap: Array = []
	var si := from.y * width + from.x
	var gi := to.y * width + to.x
	g[si] = 0.0
	_heap_push(heap, [_h(from, to), si])
	var found := false
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var ci: int = top[1]
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		if ci == gi:
			found = true
			break
		var cur := Vector2i(ci % width, floori(float(ci) / width))
		for d in dirs:
			if not _step_ok(cur, d, to):
				continue
			var nb := cur + d
			var ni := nb.y * width + nb.x
			if closed[ni] == 1:
				continue
			var cost := 1.0 if (d.x == 0 or d.y == 0) else 1.4142
			var ng: float = g[ci] + cost
			if ng < g[ni]:
				g[ni] = ng
				came[ni] = ci
				_heap_push(heap, [ng + _h(nb, to), ni])
	if not found:
		return out
	var idx := gi
	while idx != -1:
		out.append(Vector2i(idx % width, floori(float(idx) / width)))
		idx = came[idx]
	out.reverse()
	out.remove_at(0)
	return out


## Number of steps (0 when from == to), -1 if unreachable.
func path_length(from: Vector2i, to: Vector2i) -> float:
	if from == to:
		return 0.0
	var p := find_path(from, to)
	if p.is_empty():
		return -1.0
	return float(p.size())


func has_path(from: Vector2i, to: Vector2i) -> bool:
	return from == to or not find_path(from, to).is_empty()


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(a.x - b.x)
	var dy := absf(a.y - b.y)
	return (dx + dy) + (1.4142 - 2.0) * minf(dx, dy)


func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and h[l][0] < h[m][0]:
				m = l
			if r < n and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var tmp = h[m]
			h[m] = h[i]
			h[i] = tmp
			i = m
	return top


## Reachable non-blocked neighbour of a tile closest to `from` (for approaching blocked tiles).
func nearest_reachable_neighbor(from: Vector2i, target: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_len := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = target + d
		if not is_walkable(nb) or not edge_open(target, nb):
			continue
		var l := path_length(from, nb)
		if l >= 0.0 and l < best_len:
			best_len = l
			best = nb
	return best


# ------------------------------------------------------------------ walls / floors

## Wall segment along a vertex line (vertex coords 0..width / 0..height). Axis-aligned only.
func add_wall(a: Vector2i, b: Vector2i) -> void:
	_apply_wall_line(a, b, "wall", null)


func _line_edges(a: Vector2i, b: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if a.y == b.y:
		for x in range(mini(a.x, b.x), maxi(a.x, b.x)):
			out.append(Vector3i(x, a.y, 0))
	elif a.x == b.x:
		for y in range(mini(a.y, b.y), maxi(a.y, b.y)):
			out.append(Vector3i(a.x, y, 1))
	return out


## Set one edge. type "" or "none" erases. Handles wall-mounted objects. Returns true if changed.
func set_edge(e: Vector3i, type: String) -> bool:
	if not edge_valid(e):
		return false
	if type == "none":
		type = ""
	var old: String = walls.get(e, "")
	if old == type:
		return false
	if mounts.has(e):
		remove_object(mounts[e])
	if type == "":
		walls.erase(e)
	else:
		walls[e] = type
	_rooms_dirty = true
	_emit("walls_changed")
	return true


func _apply_wall_line(a: Vector2i, b: Vector2i, type: String, rec: Variant) -> int:
	var count := 0
	for e in _line_edges(a, b):
		var old: String = walls.get(e, "")
		var new_t := "" if type == "none" else type
		if old == new_t:
			continue
		var obj_data: Dictionary = {}
		if mounts.has(e):
			obj_data = objects[mounts[e]].to_dict()
		if set_edge(e, type):
			count += 1
			if rec != null:
				(rec as Array).append({"e": e, "old": old, "new": new_t, "obj": obj_data})
	return count


## Build tool: draw (or erase with "none") a wall line. Charges coins when an economy exists.
## Returns number of edges changed (0 if nothing/can't afford).
func set_wall_line(a: Vector2i, b: Vector2i, type: String = "wall", household_id: int = -1) -> int:
	var hid := current_household_id if household_id < 0 else household_id
	if type != "none" and not (type in WALL_TYPES):
		last_error = "bad wall type"
		return 0
	# count edges that would change for pricing
	var would := 0
	for e in _line_edges(a, b):
		if walls.get(e, "") != ("" if type == "none" else type):
			would += 1
	if would == 0:
		return 0
	var cost := 0 if type == "none" else would * WALL_PRICE
	if cost > 0 and not _spend(hid, cost):
		last_error = "not enough coins"
		return 0
	var rec: Array = []
	var n := _apply_wall_line(a, b, type, rec)
	_push_undo({"t": "walls", "changes": rec, "cost": cost, "hid": hid})
	return n


func paint_floor(t: Vector2i, type: String, household_id: int = -1) -> bool:
	return paint_floor_rect(t, t, type, household_id) > 0


func paint_floor_rect(a: Vector2i, b: Vector2i, type: String, household_id: int = -1) -> int:
	if not FLOOR_DEFS.has(type):
		last_error = "bad floor type"
		return 0
	var hid := current_household_id if household_id < 0 else household_id
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var changes: Array = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var t := Vector2i(x, y)
			if in_bounds(t) and get_floor(t) != type:
				changes.append({"t": t, "old": get_floor(t)})
	if changes.is_empty():
		return 0
	var cost: int = changes.size() * FLOOR_PRICE
	if not _spend(hid, cost):
		last_error = "not enough coins"
		return 0
	for c in changes:
		floors[c["t"].y * width + c["t"].x] = type
	_rooms_dirty = true
	_emit("floors_changed")
	_push_undo({"t": "floor", "changes": changes, "new": type, "cost": cost, "hid": hid})
	return changes.size()


## Raw floor set (no coins/undo) used by loaders and the starter house.
func set_floor_raw(t: Vector2i, type: String) -> void:
	if in_bounds(t):
		floors[t.y * width + t.x] = type
		_rooms_dirty = true


func set_floor_rect_raw(a: Vector2i, b: Vector2i, type: String) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			set_floor_raw(Vector2i(x, y), type)
	_emit("floors_changed")


# ------------------------------------------------------------------ objects

func can_place(def_id: String, tile: Vector2i, rot: int = 0) -> bool:
	last_error = ""
	var d := get_def(def_id)
	if d.is_empty():
		last_error = "unknown object"
		return false
	rot = posmod(rot, 4)
	if str(d.get("mount", "")) == "wall":
		if not in_bounds(tile):
			last_error = "out of bounds"
			return false
		var e := mount_edge(tile, rot)
		if walls.get(e, "") != "wall":
			last_error = "needs a wall"
			return false
		if mounts.has(e):
			last_error = "edge taken"
			return false
		return true
	var fp := WorldObjectScript.footprint_of(d, tile, rot)
	var floor_layer := str(d.get("layer", "")) == "floor"
	for t in fp:
		if not in_bounds(t):
			last_error = "out of bounds"
			return false
		if floor_layer:
			if _occ_floor.has(t):
				last_error = "occupied"
				return false
		elif _occ.has(t):
			last_error = "occupied"
			return false
	# no wall may cut through the footprint
	for t in fp:
		for dd in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nb: Vector2i = t + dd
			if nb in fp and not edge_open(t, nb):
				last_error = "wall in the way"
				return false
	return true


func place_object(def_id: String, tile: Vector2i, rot: int = 0) -> int:
	if not can_place(def_id, tile, rot):
		return -1
	return _create_object(def_id, tile, posmod(rot, 4), -1)


func _create_object(def_id: String, tile: Vector2i, rot: int, force_id: int) -> int:
	var d := get_def(def_id)
	var o = WorldObjectScript.new()
	o.id = force_id if force_id >= 0 else _next_id
	_next_id = maxi(_next_id, o.id + 1)
	o.def_id = def_id
	o.def = d
	o.tile = tile
	o.rot = rot
	o.init_state_from_def()
	_mirror_stats(o)
	objects[o.id] = o
	if o.is_wall_mounted():
		var e := mount_edge(tile, rot)
		mounts[e] = o.id
		var wt := str(d.get("wall_type", "door"))
		walls[e] = wt
	else:
		for t in o.footprint():
			if o.is_floor_layer():
				_occ_floor[t] = o.id
			else:
				_occ[t] = o.id
				if o.blocks():
					_blocked[t] = true
	_rooms_dirty = true
	_emit("object_placed", o.id)
	return o.id


func remove_object(object_id: int) -> bool:
	if not objects.has(object_id):
		return false
	var o = objects[object_id]
	if o.is_wall_mounted():
		var e: Vector3i = mount_edge(o.tile, o.rot)
		mounts.erase(e)
		if walls.has(e):
			walls[e] = "wall"
	else:
		for t in o.footprint():
			if o.is_floor_layer():
				if _occ_floor.get(t, -1) == object_id:
					_occ_floor.erase(t)
			else:
				if _occ.get(t, -1) == object_id:
					_occ.erase(t)
				_blocked.erase(t)
	objects.erase(object_id)
	_rooms_dirty = true
	_emit("object_removed", object_id)
	return true


func get_object(object_id: int):
	return objects.get(object_id, null)


func all_objects() -> Array:
	return objects.values()


func object_at(t: Vector2i):
	var id: int = _occ.get(t, -1)
	if id == -1:
		id = _occ_floor.get(t, -1)
	return objects.get(id, null)


func objects_with_tag(tag: String) -> Array:
	var out: Array = []
	for o in objects.values():
		if o.has_tag(tag):
			out.append(o)
	return out


func objects_of_def(def_id: String) -> Array:
	var out: Array = []
	for o in objects.values():
		if o.def_id == def_id:
			out.append(o)
	return out


func objects_in_radius(tile: Vector2i, r: float) -> Array:
	var scored: Array = []
	for o in objects.values():
		var best := INF
		if o.is_wall_mounted():
			best = Vector2(o.tile).distance_to(Vector2(tile))
		else:
			for t in o.footprint():
				best = minf(best, Vector2(t).distance_to(Vector2(tile)))
		if best <= r:
			scored.append([best, o])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for s in scored:
		out.append(s[1])
	return out


func set_object_state(object_id: int, key: String, value: Variant) -> void:
	var o = objects.get(object_id, null)
	if o == null:
		return
	var sd: Dictionary = (o.def.get("state", {}) as Dictionary).get(key, {})
	if sd.has("max") and (value is float or value is int):
		value = clampf(float(value), float(sd.get("min", 0.0)), float(sd["max"]))
	if o.state.get(key) == value:
		return
	o.state[key] = value
	if o.stats.has(key):
		o.stats[key].set("value", float(value))
	_rooms_dirty = true   # decor/mess depend on state
	_emit("object_state_changed", object_id, key)


func add_object_state(object_id: int, key: String, delta: float) -> void:
	var o = objects.get(object_id, null)
	if o == null:
		return
	set_object_state(object_id, key, float(o.state.get(key, 0.0)) + delta)


func _mirror_stats(o) -> void:
	if not _stat_checked:
		_stat_checked = true
		if ResourceLoader.exists("res://scripts/sim/stat.gd"):
			var s: Script = load("res://scripts/sim/stat.gd")
			if s != null and s.can_instantiate():
				var ok := true
				for m in s.get_script_method_list():
					if m["name"] == "_init":
						ok = (m["args"] as Array).size() == (m["default_args"] as Array).size()
				if ok:
					_stat_script = s
	if _stat_script == null:
		return
	var sd: Dictionary = o.def.get("state", {})
	for k in sd:
		var e: Dictionary = sd[k]
		if e.has("max"):
			var st = _stat_script.new()
			st.set("id", k)
			st.set("min", float(e.get("min", 0.0)))
			st.set("max", float(e["max"]))
			st.set("value", float(o.state.get(k, 0.0)))
			o.stats[k] = st


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
	_rooms_dirty = true
	_emit("object_state_changed", -1, "mess")


# ------------------------------------------------------------------ rooms

func _rebuild_rooms() -> void:
	_rooms.clear()
	_room_of.clear()
	for y in height:
		for x in width:
			var start := Vector2i(x, y)
			if _room_of.has(start):
				continue
			var idx := _rooms.size()
			var tiles: Array[Vector2i] = []
			var outdoor := false
			var stack: Array[Vector2i] = [start]
			_room_of[start] = idx
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				tiles.append(c)
				if c.x == 0 or c.y == 0 or c.x == width - 1 or c.y == height - 1:
					outdoor = true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = c + d
					if not in_bounds(nb):
						continue
					var wt: String = walls.get(edge_between(c, nb), "")
					if wt != "":
						if wt == "fence":
							outdoor = true   # fenced-only areas are still outdoors
						continue   # any wall type incl. door separates rooms
					if _room_of.has(nb):
						continue
					_room_of[nb] = idx
					stack.append(nb)
			_rooms.append({"id": idx, "tiles": tiles, "outdoor": outdoor})
	_rooms_dirty = false
	# compute scores
	for r in _rooms:
		r["decor"] = 0.0
		r["mess"] = 0.0
		r["objects"] = []
		var fl := 0.0
		for t in r["tiles"]:
			fl += float((FLOOR_DEFS.get(get_floor(t), {}) as Dictionary).get("decor", 0.0))
			r["mess"] += float(mess.get(t, 0.0))
		r["floor_decor"] = fl / maxf(1.0, float(r["tiles"].size()))
	for o in objects.values():
		var rid := -1
		if o.is_wall_mounted():
			# belongs to the room on the side it was placed from
			rid = _room_of.get(o.tile, -1)
		else:
			rid = _room_of.get(o.tile, -1)
		if rid == -1:
			continue
		var c: Vector2 = o.env_contribution()
		_rooms[rid]["decor"] += c.x
		_rooms[rid]["mess"] += c.y
		_rooms[rid]["objects"].append(o.id)
	for r in _rooms:
		r["score"] = float(r["decor"]) + float(r["floor_decor"]) * 3.0 - float(r["mess"])
		r["cleanliness"] = 1.0 / (1.0 + float(r["mess"]) / 4.0)


func _ensure_rooms() -> void:
	if _rooms_dirty:
		_rebuild_rooms()


func room_id(tile: Vector2i) -> int:
	_ensure_rooms()
	return _room_of.get(tile, -1)


func room_tiles(tile: Vector2i) -> Array[Vector2i]:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	if rid == -1:
		return []
	return _rooms[rid]["tiles"]


func is_outdoor(tile: Vector2i) -> bool:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	return rid != -1 and _rooms[rid]["outdoor"]


func room_count() -> int:
	_ensure_rooms()
	return _rooms.size()


func room_info(tile: Vector2i) -> Dictionary:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	if rid == -1:
		return {}
	var r: Dictionary = _rooms[rid]
	return {"id": rid, "size": r["tiles"].size(), "outdoor": r["outdoor"], "decor": r["decor"],
		"mess": r["mess"], "floor_decor": r["floor_decor"], "score": r["score"],
		"cleanliness": r["cleanliness"], "objects": (r["objects"] as Array).duplicate()}


## Environment score of the room containing `tile`: sum(decor) + floor bonus - mess. ~ -10..+20.
func room_score(tile: Vector2i) -> float:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	return 0.0 if rid == -1 else float(_rooms[rid]["score"])


## 0..1 (1 = spotless)
func room_cleanliness(tile: Vector2i) -> float:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	return 1.0 if rid == -1 else float(_rooms[rid]["cleanliness"])


# ------------------------------------------------------------------ economy guard

func _economy() -> Node:
	var r := _root()
	return r.get_node_or_null("Economy") if r != null else null


func can_afford(household_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var eco := _economy()
	if eco != null:
		if eco.has_method("can_afford"):
			return bool(eco.call("can_afford", household_id, amount))
		if eco.has_method("get_coins"):
			return int(eco.call("get_coins", household_id)) >= amount
	return true


func _spend(household_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if coin_spend.is_valid():
		return bool(coin_spend.call(household_id, amount))
	var eco := _economy()
	if eco != null:
		if eco.has_method("spend"):
			return bool(eco.call("spend", household_id, amount))
		if eco.has_method("can_afford") and not bool(eco.call("can_afford", household_id, amount)):
			return false
	return true


func _refund(household_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if coin_refund.is_valid():
		coin_refund.call(household_id, amount)
		return
	var eco := _economy()
	if eco != null:
		for m in ["refund", "earn", "add_coins"]:
			if eco.has_method(m):
				eco.call(m, household_id, amount)
				return


# ------------------------------------------------------------------ build tools + undo

func object_price(def_id: String) -> int:
	return int(get_def(def_id).get("price", 0))


## Buy and place. Returns object id, or -1 (see last_error).
func buy_place(def_id: String, tile: Vector2i, rot: int = 0, household_id: int = -1) -> int:
	var hid := current_household_id if household_id < 0 else household_id
	if not can_place(def_id, tile, rot):
		return -1
	var price := object_price(def_id)
	if not _spend(hid, price):
		last_error = "not enough coins"
		return -1
	var id := _create_object(def_id, tile, posmod(rot, 4), -1)
	_push_undo({"t": "place", "id": id, "price": price, "hid": hid})
	return id


## Sell (delete) an object for SELL_RATIO of its price.
func sell_object(object_id: int, household_id: int = -1) -> bool:
	var o = objects.get(object_id, null)
	if o == null:
		return false
	var hid := current_household_id if household_id < 0 else household_id
	var refund := int(floor(object_price(o.def_id) * SELL_RATIO))
	var data: Dictionary = o.to_dict()
	if not remove_object(object_id):
		return false
	_refund(hid, refund)
	_push_undo({"t": "remove", "data": data, "refund": refund, "hid": hid})
	return true


func sell_object_at(t: Vector2i, household_id: int = -1) -> bool:
	var o = object_at(t)
	return o != null and sell_object(o.id, household_id)


func _push_undo(op: Dictionary) -> void:
	_undo.append(op)
	while _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func undo_count() -> int:
	return _undo.size()


func clear_undo() -> void:
	_undo.clear()


## Undo the most recent build operation. Refunds / re-charges coins accordingly.
func undo_last() -> bool:
	if _undo.is_empty():
		return false
	var op: Dictionary = _undo.pop_back()
	match op["t"]:
		"place":
			remove_object(op["id"])
			_refund(op["hid"], op["price"])
		"remove":
			var d: Dictionary = op["data"]
			_spend(op["hid"], op["refund"])
			var t: Array = d["tile"]
			var nid := _create_object(d["def_id"], Vector2i(t[0], t[1]), int(d["rot"]), int(d["id"]))
			if nid != -1:
				objects[nid].state = (d["state"] as Dictionary).duplicate(true)
		"walls":
			var changes: Array = op["changes"]
			for i in range(changes.size() - 1, -1, -1):
				var c: Dictionary = changes[i]
				set_edge(c["e"], c["old"])
				var od: Dictionary = c["obj"]
				if not od.is_empty():
					var t2: Array = od["tile"]
					var nid2 := _create_object(od["def_id"], Vector2i(t2[0], t2[1]), int(od["rot"]), int(od["id"]))
					if nid2 != -1:
						objects[nid2].state = (od["state"] as Dictionary).duplicate(true)
			_refund(op["hid"], op["cost"])
		"floor":
			for c in op["changes"]:
				floors[c["t"].y * width + c["t"].x] = c["old"]
			_rooms_dirty = true
			_emit("floors_changed")
			_refund(op["hid"], op["cost"])
	return true


# ------------------------------------------------------------------ starter lot

## Furnished 2-bedroom house + yard. Fills starter_spawn_tiles / starter_bedroom_tile.
func load_starter_house() -> void:
	reset(DEFAULT_W, DEFAULT_H)
	StarterHouse.build(self)
	_undo.clear()
	_rooms_dirty = true
	_emit("world_reset")


# ------------------------------------------------------------------ save / load

func save_dict(include_folk: bool = false) -> Dictionary:
	var wl: Array = []
	for e in walls:
		var is_mount: bool = mounts.has(e)
		if is_mount:
			continue   # the mounted object recreates its edge
		wl.append([e.x, e.y, e.z, walls[e]])
	var ol: Array = []
	for o in objects.values():
		for sk in o.stats:      # WorldIface.state_set updates the Stat mirror only; persist its value
			if o.state.has(sk) and o.stats[sk] != null:
				o.state[sk] = float(o.stats[sk].get("value"))
		ol.append(o.to_dict())
	var ml: Array = []
	for t in mess:
		ml.append([t.x, t.y, mess[t]])
	var d := {
		"version": 1, "width": width, "height": height,
		"floors": Array(floors), "walls": wl, "objects": ol, "mess": ml, "next_id": _next_id,
		"spawn": starter_spawn_tiles.map(func(t): return [t.x, t.y]),
		"bedroom": [starter_bedroom_tile.x, starter_bedroom_tile.y],
	}
	if include_folk:
		var fl: Array = []
		for f in folk.values():
			if f.has_method("to_dict"):
				fl.append(f.to_dict())
		d["folk"] = fl
	return d


func load_dict(d: Dictionary) -> void:
	reset(int(d.get("width", DEFAULT_W)), int(d.get("height", DEFAULT_H)))
	var fl: Array = d.get("floors", [])
	for i in mini(fl.size(), floors.size()):
		floors[i] = str(fl[i])
	for w in d.get("walls", []):
		walls[Vector3i(int(w[0]), int(w[1]), int(w[2]))] = str(w[3])
	for od in d.get("objects", []):
		var t: Array = od["tile"]
		var nid := _create_object(str(od["def_id"]), Vector2i(int(t[0]), int(t[1])), int(od["rot"]), int(od["id"]))
		if nid != -1:
			var st: Dictionary = od.get("state", {})
			for k in st:
				objects[nid].state[k] = st[k]
				if objects[nid].stats.has(k):
					objects[nid].stats[k].set("value", float(st[k]))
	for m in d.get("mess", []):
		mess[Vector2i(int(m[0]), int(m[1]))] = float(m[2])
	_next_id = maxi(_next_id, int(d.get("next_id", 1)))
	starter_spawn_tiles.clear()
	for s in d.get("spawn", []):
		starter_spawn_tiles.append(Vector2i(int(s[0]), int(s[1])))
	var b: Array = d.get("bedroom", [0, 0])
	starter_bedroom_tile = Vector2i(int(b[0]), int(b[1]))
	if d.has("folk") and ResourceLoader.exists("res://scripts/sim/folk.gd"):
		var fs: Script = load("res://scripts/sim/folk.gd")
		for fd in d["folk"]:
			var f = fs.from_dict(fd)
			if f != null:
				folk[f.id] = f
				_emit("folk_added", f.id)
	_rooms_dirty = true
	_emit("world_reset")
