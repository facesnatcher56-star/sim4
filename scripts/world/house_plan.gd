class_name HousePlan
extends RefCounted
## Working model of one lot while a layout is generated (no World needed). Same conventions as WorldGrid:
## tile = Vector2i, edge key Vector3i(x, y, 0) = NORTH edge of tile (x,y), Vector3i(x, y, 1) = WEST edge,
## object rot 0..3 has its front facing S, W, N, E (FRONT[rot]).

const FRONT: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
const BLOCK := ["wall", "window", "fence"]
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static var _defs: Dictionary = {}

var lot := Rect2i(0, 0, 32, 24)
var shell := Rect2i()
var bounds := Rect2i()                 # tiles objects may use (the shell for the house, the yard for the garden pass)
var rooms: Array = []                  # {id, type, rect: Rect2i, group: int, zone: bool}
var room_of: Dictionary = {}           # tile -> index into rooms
var walls: Dictionary = {}             # edge -> "wall" | "door" | "window" | "fence"
var objects: Array = []                # {def, tile, rot}
var mounts: Array = []                 # wall-mounted doors / windows {def, tile, rot}
var occ: Dictionary = {}               # tile -> index into objects (blocking layer)
var occf: Dictionary = {}              # tile -> index (floor layer: rugs, ceiling lights)
var clear: Dictionary = {}             # tiles that must stay free (in front of doors, path)
var yard_out: Dictionary = {}          # {floors, walls, yard} from HouseYard
var scale := 1.0                       # shell area / total room weight (big shells give big rooms)
var paths: Dictionary = {}             # tile -> true: footpaths (parks); never built on
var must: Array[Vector2i] = []         # tiles that must stay reachable from `entry`
var entry := Vector2i.ZERO


# ------------------------------------------------------------------ definitions
static func defs() -> Dictionary:
	if not _defs.is_empty():
		return _defs
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/objects.json"))
	if base is Dictionary:
		_defs = (base as Dictionary).duplicate(true)
	for path in ["res://data/venues.json", "res://data/building_rules.json", "res://data/careers_works.json"]:        # cloned objects of the venues and of the multi-floor buildings
		var ven: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if ven is Dictionary:
			var objs: Dictionary = (ven.get("content", {}) as Dictionary).get("objects", {})
			for k in objs:
				var e: Dictionary = objs[k]
				var d: Dictionary = (_defs.get(str(e.get("clone", "")), {}) as Dictionary).duplicate(true)
				for ok in (e.get("override", {}) as Dictionary):
					d[ok] = e["override"][ok]
				if not d.is_empty():
					_defs[k] = d
	var city: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/incidents/12_city.json"))          # task 63: the public toilet in the cafe, gym and park
	if city is Dictionary:
		var cobjs: Dictionary = (city.get("content", {}) as Dictionary).get("objects", {})
		for k2 in cobjs:
			if (cobjs[k2] as Dictionary).has("def") and not _defs.has(k2):
				_defs[k2] = (cobjs[k2]["def"] as Dictionary).duplicate(true)
	return _defs


static func def_of(id: String) -> Dictionary:
	return defs().get(id, {})


static func is_floor_layer(d: Dictionary) -> bool:
	return str(d.get("layer", "")) == "floor"


static func footprint(d: Dictionary, tile: Vector2i, rot: int) -> Array[Vector2i]:
	return WorldObject.footprint_of(d, tile, rot)


static func slot_tiles(d: Dictionary, tile: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in (d.get("slots", []) as Array):
		var o: Array = s.get("offset", [0, 0])
		out.append(tile + WorldObject.rotate_offset(Vector2i(int(o[0]), int(o[1])), rot))
	return out


static func edge(a: Vector2i, b: Vector2i) -> Vector3i:
	if a.x == b.x:
		return Vector3i(a.x, maxi(a.y, b.y), 0)
	return Vector3i(maxi(a.x, b.x), a.y, 1)


## Edge key of a wall-mounted piece: rot 0 = N edge of tile, 1 = E, 2 = S, 3 = W.
static func mount_edge(t: Vector2i, rot: int) -> Vector3i:
	match posmod(rot, 4):
		0: return Vector3i(t.x, t.y, 0)
		1: return Vector3i(t.x + 1, t.y, 1)
		2: return Vector3i(t.x, t.y + 1, 0)
	return Vector3i(t.x, t.y, 1)


# ------------------------------------------------------------------ geometry
func blocked_edge(a: Vector2i, b: Vector2i) -> bool:
	return str(walls.get(edge(a, b), "")) in BLOCK


func is_wall_edge(a: Vector2i, b: Vector2i) -> bool:
	return str(walls.get(edge(a, b), "")) == "wall"


func group_at(t: Vector2i) -> int:
	var i: int = room_of.get(t, -1)
	return -1 if i == -1 else int(rooms[i]["group"])


func type_at(t: Vector2i) -> String:
	var i: int = room_of.get(t, -1)
	return "" if i == -1 else str(rooms[i]["type"])


func index_rooms() -> void:
	room_of.clear()
	for i in rooms.size():
		var r: Rect2i = rooms[i]["rect"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				room_of[Vector2i(x, y)] = i


# ------------------------------------------------------------------ objects
func can_put(def_id: String, tile: Vector2i, rot: int, rect: Rect2i, allow_clear: bool = false) -> bool:
	var d := def_of(def_id)
	if d.is_empty():
		return false
	var fp := footprint(d, tile, rot)
	var fl := is_floor_layer(d)
	for t in fp:
		if not rect.has_point(t):
			return false
		if fl:
			if occf.has(t):
				return false
		else:
			if occ.has(t) or (clear.has(t) and not allow_clear):
				return false
	for t in fp:
		for dd in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nb: Vector2i = t + dd
			if nb in fp and blocked_edge(t, nb):
				return false
	return true


func put(def_id: String, tile: Vector2i, rot: int) -> int:
	var d := def_of(def_id)
	var idx := objects.size()
	objects.append({"def": def_id, "tile": tile, "rot": rot})
	for t in footprint(d, tile, rot):
		if is_floor_layer(d):
			occf[t] = idx
		else:
			occ[t] = idx
	return idx


## Mount a door or window on wall edge `e` (owner tile = the tile inside the shell, like the hand-made templates).
func add_mount(def_id: String, e: Vector3i) -> void:
	var tile: Vector2i
	var rot: int
	if e.z == 0:
		var n := Vector2i(e.x, e.y - 1)
		var s := Vector2i(e.x, e.y)
		if shell.has_point(s) and not shell.has_point(n):
			tile = s
			rot = 0
		else:
			tile = n
			rot = 2
	else:
		var w := Vector2i(e.x - 1, e.y)
		var ea := Vector2i(e.x, e.y)
		if shell.has_point(w) and not shell.has_point(ea):
			tile = w
			rot = 1
		else:
			tile = ea
			rot = 3
	walls[e] = "door" if def_id == "door" else "window"
	mounts.append({"def": def_id, "tile": tile, "rot": rot})


## The two tiles on either side of an edge.
static func edge_tiles(e: Vector3i) -> Array[Vector2i]:
	if e.z == 0:
		return [Vector2i(e.x, e.y - 1), Vector2i(e.x, e.y)]
	return [Vector2i(e.x - 1, e.y), Vector2i(e.x, e.y)]


## Remove the last object (undo of put when a validity check fails).
func pop() -> void:
	var idx := objects.size() - 1
	var o: Dictionary = objects[idx]
	var d := def_of(str(o["def"]))
	for t in footprint(d, o["tile"], int(o["rot"])):
		if is_floor_layer(d):
			occf.erase(t)
		else:
			occ.erase(t)
	objects.remove_at(idx)


func fp_of(idx: int) -> Array[Vector2i]:
	var o: Dictionary = objects[idx]
	return footprint(def_of(str(o["def"])), o["tile"], int(o["rot"]))


## True when the `rot` back side of every footprint tile is a plain wall (object stands with its back to a wall).
func back_to_wall(fp: Array, rot: int) -> bool:
	var b: Vector2i = -FRONT[rot]
	var n := 0
	for t in fp:
		if (t + b) in fp:
			continue
		if not is_wall_edge(t, t + b):
			return false
		n += 1
	return n > 0


## Number of the four sides that touch a plain wall (a corner spot has 2).
func wall_sides(fp: Array) -> int:
	var sides := 0
	for d in DIRS4:
		for t in fp:
			if (t + d) not in fp and is_wall_edge(t, t + d):
				sides += 1
				break
	return sides


# ------------------------------------------------------------------ reachability
func flood(from: Vector2i, rect: Rect2i) -> Dictionary:
	var seen := {from: true}
	var stack: Array[Vector2i] = [from]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS4:
			var n := c + d
			if seen.has(n) or not rect.has_point(n) or occ.has(n) or blocked_edge(c, n):
				continue
			seen[n] = true
			stack.append(n)
	return seen


## Can a folk use slot tile `s` of the object whose footprint is `fp`? (free + reachable, or a seat / inside slot whose
## surroundings are reachable).
func slot_usable(s: Vector2i, fp: Array, reach: Dictionary, depth: int = 0) -> bool:
	if s in fp:
		for d in DIRS4:
			var n: Vector2i = s + d
			if n not in fp and reach.has(n) and not blocked_edge(s, n):
				return true
		return false
	if reach.has(s):
		return true
	var oi: int = occ.get(s, -1)
	if oi != -1 and depth == 0:
		var od := def_of(str(objects[oi]["def"]))
		if "seat" in (od.get("tags", []) as Array):
			return slot_usable(s, fp_of(oi), reach, 1) or _touches_reach(fp_of(oi), reach)
	return false


func _touches_reach(fp: Array, reach: Dictionary) -> bool:
	for t in fp:
		for d in DIRS4:
			var n: Vector2i = t + d
			if n not in fp and reach.has(n) and not blocked_edge(t, n):
				return true
	return false


## Every must-reach tile reachable and every functional object keeps at least one usable slot.
func valid(rect: Rect2i = bounds) -> bool:
	var reach := flood(entry, rect)
	for t in must:
		if not reach.has(t):
			return false
	for i in objects.size():
		var d := def_of(str(objects[i]["def"]))
		var slots := slot_tiles(d, objects[i]["tile"], int(objects[i]["rot"]))
		if slots.is_empty() or is_floor_layer(d):
			continue
		var fp := fp_of(i)
		var ok := false
		for s in slots:
			if rect.has_point(s) and not blocked_between(s, fp) and slot_usable(s, fp, reach):
				ok = true
				break
		if not ok:
			return false
	return true


## A wall between a slot tile and the object (the slot would be on the other side of a wall).
func blocked_between(s: Vector2i, fp: Array) -> bool:
	if s in fp:
		return false
	var best := 99
	var bt := s
	for t in fp:
		var dist := absi(t.x - s.x) + absi(t.y - s.y)
		if dist < best:
			best = dist
			bt = t
	if best == 1:
		return blocked_edge(bt, s)
	return false


func count_def(def_id: String) -> int:
	var n := 0
	for o in objects:
		if str(o["def"]) == def_id:
			n += 1
	return n


func defs_in_rect(r: Rect2i) -> Array:
	var out: Array = []
	for i in objects.size():
		if r.has_point(objects[i]["tile"]):
			out.append(i)
	return out