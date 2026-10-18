class_name WorldRegions
extends RefCounted
## Regions of the one continuous map (lots, parks, roads), the 16x16 chunk grid and "who may build where".
## Back-references the World autoload as `world` (`World.regions`).
##
## Region = {id, rect: Rect2i, kind: home|venue|townie_home|park|road, venue_type, owner: player|npc|public,
##           template, entry: Vector2i (street-side gate tile INSIDE the lot, next to the sidewalk), door: Vector2i (inner
##           template door, optional), label, lot (neighbourhood lot id, optional), axis/lines (road markings, optional)}.
## LEGACY MODE: with no regions defined (the classic single lot, all current tests) everything is buildable and the
## whole map is one room partition. Defining the first region switches to region mode.
##
## Chunks are an INDEX only (chunk_of, chunk -> object ids, dirty floor chunks for the renderer), never storage.

const CHUNK := 16
const NONE := -1
const BUILD_ERROR := "You can only build on your own lot."
const LOT_KINDS := ["home", "venue", "townie_home"]     # kinds that get their own room partition

var world: WorldGrid
var regions: Dictionary = {}              # id -> region dictionary
var home_id: int = NONE
var enforce: bool = true                  # false while a loader (MapBuilder / LotLoader) places content in any lot

var _tile: PackedInt32Array = PackedInt32Array()   # per-tile region id (NONE outside every region)
var _next_id: int = 1
var _chunk_objs: Dictionary = {}          # Vector2i chunk -> {object id: true}
var _obj_chunk: Dictionary = {}           # object id -> Vector2i chunk it is indexed in
var _dirty: Dictionary = {}               # Vector2i chunk -> true (floors changed)
var _all_dirty: bool = true


func _init(w: WorldGrid) -> void:
	world = w


## Called by World.reset(): forget every region and chunk, size the lookup for the new grid.
func reset() -> void:
	regions.clear()
	home_id = NONE
	enforce = true
	_next_id = 1
	_tile.resize(world.width * world.height)
	_tile.fill(NONE)
	_chunk_objs.clear()
	_obj_chunk.clear()
	_dirty.clear()
	_all_dirty = true


# ------------------------------------------------------------------ regions

func has_regions() -> bool:
	return not regions.is_empty()


## Add a region; returns its id. Later regions overwrite earlier ones where they overlap (lookup only).
func add_region(d: Dictionary) -> int:
	var r: Dictionary = d.duplicate(true)
	var id: int = int(r.get("id", _next_id))
	_next_id = maxi(_next_id, id + 1)
	r["id"] = id
	var rc: Rect2i = r.get("rect", Rect2i())
	r["rect"] = rc
	r["kind"] = str(r.get("kind", "road"))
	for k in ["venue_type", "template", "label", "lot"]:
		r[k] = str(r.get(k, ""))
	r["owner"] = str(r.get("owner", "public"))
	r["entry"] = r.get("entry", Vector2i(-1, -1))
	regions[id] = r
	var clip := rc.intersection(Rect2i(0, 0, world.width, world.height))
	for y in range(clip.position.y, clip.end.y):
		var base := y * world.width
		for x in range(clip.position.x, clip.end.x):
			_tile[base + x] = id
	if str(r["kind"]) == "home" and str(r["owner"]) == "player":
		home_id = id
	world.rooms.invalidate_all()
	return id


func region(id: int) -> Dictionary:
	return regions.get(id, {})


## Region id covering the tile, NONE (-1) for open ground / out of bounds.
func region_at(tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0 or tile.x >= world.width or tile.y >= world.height:
		return NONE
	return _tile[tile.y * world.width + tile.x]


func region_of(tile: Vector2i) -> Dictionary:
	return regions.get(region_at(tile), {})


func kind_at(tile: Vector2i) -> String:
	return str(region_of(tile).get("kind", ""))


func by_lot(lot_id: String) -> Dictionary:
	for r in regions.values():
		if str(r["lot"]) == lot_id:
			return r
	return {}


func of_kind(kind: String) -> Array:
	var out: Array = []
	for r in regions.values():
		if str(r["kind"]) == kind:
			out.append(r)
	return out


func home() -> Dictionary:
	return regions.get(home_id, {})


## True for kinds that are a closed lot (own rooms); roads, parks and open ground are "the street".
func is_lot(id: int) -> bool:
	return id != NONE and str(regions[id]["kind"]) in LOT_KINDS


# ------------------------------------------------------------------ build rules

## Legacy mode (no regions) or enforce == false: everything. Otherwise only the player's home lot.
func can_build(tile: Vector2i) -> bool:
	if not enforce or regions.is_empty():
		return true
	return home_id != NONE and region_at(tile) == home_id


func can_build_all(tiles: Array) -> bool:
	if not enforce or regions.is_empty():
		return true
	for t in tiles:
		if not can_build(t):
			return false
	return true


## A wall edge is buildable when either tile next to it is (so lot-border fences work).
func can_build_edge(e: Vector3i) -> bool:
	if not enforce or regions.is_empty():
		return true
	var a := Vector2i(e.x, e.y)
	var b := Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y)
	return can_build(a) or can_build(b)


## Sets World.last_error and returns false (convenience for the build hooks).
func deny() -> bool:
	world.last_error = BUILD_ERROR
	return false


# ------------------------------------------------------------------ chunks (16x16, index only)

func chunk_of(tile: Vector2i) -> Vector2i:
	return Vector2i(tile.x >> 4, tile.y >> 4)


func chunk_count() -> Vector2i:
	return Vector2i((world.width + CHUNK - 1) / CHUNK, (world.height + CHUNK - 1) / CHUNK)


## Tile rectangle of a chunk, clipped to the map.
func chunk_rect(c: Vector2i) -> Rect2i:
	return Rect2i(c.x * CHUNK, c.y * CHUNK, CHUNK, CHUNK).intersection(Rect2i(0, 0, world.width, world.height))


func chunks_in_rect(rc: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cc := chunk_count()
	var lo := chunk_of(rc.position)
	var hi := chunk_of(rc.end - Vector2i.ONE)
	for cy in range(maxi(lo.y, 0), mini(hi.y, cc.y - 1) + 1):
		for cx in range(maxi(lo.x, 0), mini(hi.x, cc.x - 1) + 1):
			out.append(Vector2i(cx, cy))
	return out


func index_object(o) -> void:
	var c := chunk_of(o.tile)
	if not _chunk_objs.has(c):
		_chunk_objs[c] = {}
	(_chunk_objs[c] as Dictionary)[o.id] = true
	_obj_chunk[o.id] = c


func unindex_object(object_id: int) -> void:
	var c: Variant = _obj_chunk.get(object_id, null)
	if c == null:
		return
	_obj_chunk.erase(object_id)
	var d: Dictionary = _chunk_objs.get(c, {})
	d.erase(object_id)
	if d.is_empty():
		_chunk_objs.erase(c)


## Object ids whose anchor tile (o.tile) lies in the chunk.
func chunk_objects(c: Vector2i) -> Array:
	return (_chunk_objs.get(c, {}) as Dictionary).keys()


func chunk_object_count(c: Vector2i) -> int:
	return (_chunk_objs.get(c, {}) as Dictionary).size()


# ------------------------------------------------------------------ dirty floor chunks (for the renderer)

func mark_floor_dirty(t: Vector2i) -> void:
	if not _all_dirty and world.in_bounds(t):
		_dirty[chunk_of(t)] = true


func mark_all_floors_dirty() -> void:
	_all_dirty = true


## Chunks whose floor mesh must be rebuilt; clears the set. All chunks after a reset / load.
func take_dirty_floor_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _all_dirty:
		var cc := chunk_count()
		for cy in cc.y:
			for cx in cc.x:
				out.append(Vector2i(cx, cy))
	else:
		for c in _dirty:
			out.append(c)
	_dirty.clear()
	_all_dirty = false
	return out


# ------------------------------------------------------------------ save

func to_dict() -> Dictionary:
	var out: Array = []
	for r in regions.values():
		var rc: Rect2i = r["rect"]
		var e: Vector2i = r["entry"]
		var d := {"id": r["id"], "rect": [rc.position.x, rc.position.y, rc.size.x, rc.size.y], "kind": r["kind"],
			"venue_type": r["venue_type"], "owner": r["owner"], "template": r["template"], "label": r["label"],
			"lot": r["lot"], "entry": [e.x, e.y]}
		if r.has("door"):
			d["door"] = [(r["door"] as Vector2i).x, (r["door"] as Vector2i).y]
		for k in ["axis", "lines"]:
			if r.has(k):
				d[k] = r[k]
		out.append(d)
	return {"regions": out, "next_id": _next_id}


## Restore after World.reset() (load_dict does this). Rebuilds the per-tile lookup.
func from_dict(d: Dictionary) -> void:
	for rd in d.get("regions", []):
		var a: Array = rd["rect"]
		var e: Array = rd.get("entry", [-1, -1])
		var r: Dictionary = {"id": int(rd["id"]), "rect": Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])), "kind": str(rd["kind"]),
			"venue_type": str(rd.get("venue_type", "")), "owner": str(rd.get("owner", "public")), "template": str(rd.get("template", "")),
			"label": str(rd.get("label", "")), "lot": str(rd.get("lot", "")), "entry": Vector2i(int(e[0]), int(e[1]))}
		if rd.has("door"):
			r["door"] = Vector2i(int(rd["door"][0]), int(rd["door"][1]))
		if rd.has("axis"):
			r["axis"] = str(rd["axis"])
		if rd.has("lines"):
			var lines: Array = []
			for l in rd["lines"]:
				lines.append((l as Array).map(func(v): return int(v)))
			r["lines"] = lines
		add_region(r)
	_next_id = maxi(_next_id, int(d.get("next_id", 1)))
