class_name WorldRooms
extends RefCounted
## Room detection (flood fill between walls) with decor / cleanliness scores, built LAZILY per partition.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.
##
## Partitions: in LEGACY mode (no regions) the whole grid is one partition; once regions exist every closed lot
## (home / venue / townie_home) is its own partition, flood-filled only inside its rect on the first query after a change.
## Everything else (roads, parks, open ground) is ONE shared outdoor "street" room (id STREET) that is never flood-filled.
## A wall edit / object change only drops the partition it touched (mark_dirty); `dirty = true` drops everything.
## A room that touches the partition border (or a fence) is outdoor.

const STREET := 0                  # room id of the street (region mode only)
const PART_STRIDE := 100000        # room id = partition key * stride + index (legacy: just the index)
const DX := [1, -1, 0, 0]                  # neighbour step and the wall edge in between (edge key = tile + E, see WorldGrid)
const DY := [0, 0, 1, -1]
const EX := [1, 0, 0, 0]
const EY := [0, 0, 1, 0]
const EZ := [1, 1, 0, 0]

var world: WorldGrid
## Legacy flag kept for existing callers: `rooms.dirty = true` invalidates everything.
var dirty: bool:
	get:
		return _parts.is_empty()
	set(v):
		if v:
			_parts.clear()
var _parts: Dictionary = {}               # key -> {rooms:Array, room_of:Dictionary}


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ invalidation

func invalidate_all() -> void:
	_parts.clear()


## A change happened at this tile (wall edge next to it, object, mess, floor): drop its partition.
func mark_dirty(tile: Vector2i) -> void:
	if _parts.is_empty():
		return
	_parts.erase(_key(tile))


func mark_dirty_edge(e: Vector3i) -> void:
	mark_dirty(Vector2i(e.x, e.y))
	mark_dirty(Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y))


func mark_dirty_rect(lo: Vector2i, hi: Vector2i) -> void:
	if _parts.is_empty():
		return
	if not world.regions.has_regions():
		_parts.clear()
		return
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			_parts.erase(_key(Vector2i(x, y)))


# ------------------------------------------------------------------ partitions

## Partition key of a tile: 0 in legacy mode, region id inside a closed lot, -1 for the street.
func _key(tile: Vector2i) -> int:
	if not world.regions.has_regions():
		return 0
	var rid := world.regions.region_at(tile)
	return rid if world.regions.is_lot(rid) else -1


func _rect_of(key: int) -> Rect2i:
	if key == 0 and not world.regions.has_regions():
		return Rect2i(0, 0, world.width, world.height)
	return (world.regions.region(key)["rect"] as Rect2i).intersection(Rect2i(0, 0, world.width, world.height))


func _part(key: int) -> Dictionary:
	if not _parts.has(key):
		_parts[key] = _build_part(key)
	return _parts[key]


func _build_part(key: int) -> Dictionary:
	var rc := _rect_of(key)
	var base: int = 0 if key == 0 else key * PART_STRIDE
	var rooms: Array = []
	var room_of: Dictionary = {}
	var walls: Dictionary = world.walls
	var x1 := rc.end.x
	var y1 := rc.end.y
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var start := Vector2i(x, y)
			if room_of.has(start):
				continue
			var idx := rooms.size()
			var tiles: Array[Vector2i] = []
			var outdoor := false
			var stack: Array[Vector2i] = [start]
			room_of[start] = idx
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				tiles.append(c)
				for k in 4:
					var nx: int = c.x + DX[k]
					var ny: int = c.y + DY[k]
					if nx < rc.position.x or ny < rc.position.y or nx >= x1 or ny >= y1:
						outdoor = true       # touches the lot / map border
						continue
					var wt: String = walls.get(Vector3i(c.x + EX[k], c.y + EY[k], EZ[k]), "")
					if wt != "":
						if wt == "fence":
							outdoor = true   # fenced-only areas are still outdoors
						continue             # any wall type incl. door separates rooms
					var nb := Vector2i(nx, ny)
					if room_of.has(nb):
						continue
					room_of[nb] = idx
					stack.append(nb)
			rooms.append({"id": base + idx, "tiles": tiles, "outdoor": outdoor})
	_score(rooms, room_of, rc)
	return {"rooms": rooms, "room_of": room_of}


func _score(rooms: Array, room_of: Dictionary, rc: Rect2i) -> void:
	var decor_of: Dictionary = {}              # floor type -> decor (looked up once per type)
	var floors := world.floors
	var w := world.width
	var no_mess: bool = world.mess.is_empty()
	for r in rooms:
		r["decor"] = 0.0
		r["objects"] = []
		var fl := 0.0
		var ms := 0.0
		for t in r["tiles"]:
			var ft: String = floors[t.y * w + t.x]
			if not decor_of.has(ft):
				decor_of[ft] = float((world.FLOOR_DEFS.get(ft, {}) as Dictionary).get("decor", 0.0))
			fl += decor_of[ft]
			if not no_mess:
				ms += float(world.mess.get(t, 0.0))
		r["mess"] = ms
		r["floor_decor"] = fl / maxf(1.0, float(r["tiles"].size()))
	for o in _objects_in(rc):
		var idx: int = room_of.get(o.tile, -1)
		if idx == -1:
			continue
		var c: Vector2 = o.env_contribution()
		var r: Dictionary = rooms[idx]
		r["decor"] += c.x
		r["mess"] += c.y
		r["objects"].append(o.id)
	for r in rooms:
		r["score"] = float(r["decor"]) + float(r["floor_decor"]) * 3.0 - float(r["mess"])
		r["cleanliness"] = 1.0 / (1.0 + float(r["mess"]) / 4.0)


## Objects anchored inside the rect (via the chunk index in region mode; everything in legacy mode).
func _objects_in(rc: Rect2i) -> Array:
	var out: Array = []
	if not world.regions.has_regions():
		return world.objects.values()
	for c in world.regions.chunks_in_rect(rc):
		for id in world.regions.chunk_objects(c):
			var o = world.objects.get(id, null)
			if o != null and rc.has_point(o.tile):
				out.append(o)
	return out


# ------------------------------------------------------------------ queries

## The room dictionary at a tile: a partition room, the street, or {} (out of bounds).
func _room_at(tile: Vector2i) -> Dictionary:
	if not world.in_bounds(tile):
		return {}
	var key := _key(tile)
	if key == -1:
		return _street(tile)
	var p := _part(key)
	var idx: int = (p["room_of"] as Dictionary).get(tile, -1)
	return {} if idx == -1 else (p["rooms"] as Array)[idx]


## The street is one shared room; its numbers are per-tile (floor decor, mess on the tile).
func _street(tile: Vector2i) -> Dictionary:
	var fd := float((world.FLOOR_DEFS.get(world.get_floor(tile), {}) as Dictionary).get("decor", 0.0))
	var m := float(world.mess.get(tile, 0.0))
	return {"id": STREET, "tiles": [], "outdoor": true, "decor": 0.0, "mess": m, "floor_decor": fd, "objects": [],
		"score": fd * 3.0 - m, "cleanliness": 1.0 / (1.0 + m / 4.0)}


func room_id(tile: Vector2i) -> int:
	return int(_room_at(tile).get("id", -1))


## Tiles of the room (empty for the street: it is "everything else").
func room_tiles(tile: Vector2i) -> Array[Vector2i]:
	var r := _room_at(tile)
	if r.is_empty():
		return []
	var out: Array[Vector2i] = []
	out.assign(r["tiles"])
	return out


func is_outdoor(tile: Vector2i) -> bool:
	var r := _room_at(tile)
	return not r.is_empty() and bool(r["outdoor"])


## Number of rooms (region mode: +1 for the street). Builds every lot's rooms.
func room_count() -> int:
	if not world.regions.has_regions():
		return (_part(0)["rooms"] as Array).size()
	var n := 1
	for id in world.regions.regions:
		if world.regions.is_lot(id):
			n += (_part(id)["rooms"] as Array).size()
	return n


func room_info(tile: Vector2i) -> Dictionary:
	var r := _room_at(tile)
	if r.is_empty():
		return {}
	return {"id": r["id"], "size": r["tiles"].size(), "outdoor": r["outdoor"], "decor": r["decor"],
		"mess": r["mess"], "floor_decor": r["floor_decor"], "score": r["score"],
		"cleanliness": r["cleanliness"], "objects": (r["objects"] as Array).duplicate()}


## Environment score of the room containing `tile`: sum(decor) + floor bonus - mess. ~ -10..+20.
func room_score(tile: Vector2i) -> float:
	var r := _room_at(tile)
	return 0.0 if r.is_empty() else float(r["score"])


## 0..1 (1 = spotless)
func room_cleanliness(tile: Vector2i) -> float:
	var r := _room_at(tile)
	return 1.0 if r.is_empty() else float(r["cleanliness"])
