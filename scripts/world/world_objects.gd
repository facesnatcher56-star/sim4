class_name WorldObjects
extends RefCounted
## Object placement, removal, queries and state.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

var world: WorldGrid


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ objects

func can_place(def_id: String, tile: Vector2i, rot: int = 0) -> bool:
	world.last_error = ""
	var d := world.get_def(def_id)
	if d.is_empty():
		world.last_error = "unknown object"
		return false
	rot = posmod(rot, 4)
	if str(d.get("mount", "")) == "wall":
		if not world.in_bounds(tile):
			world.last_error = "out of bounds"
			return false
		if not world.regions.can_build(tile):
			return world.regions.deny()
		var e := world.mount_edge(tile, rot)
		if world.walls.get(e, "") != "wall":
			world.last_error = "needs a wall"
			return false
		if world.mounts.has(e):
			world.last_error = "edge taken"
			return false
		return true
	var fp := world.WorldObjectScript.footprint_of(d, tile, rot)
	var floor_layer := str(d.get("layer", "")) == "floor"
	for t in fp:
		if not world.in_bounds(t):
			world.last_error = "out of bounds"
			return false
		if floor_layer:
			if world._occ_floor.has(t):
				world.last_error = "occupied"
				return false
		elif world._occ.has(t):
			world.last_error = "occupied"
			return false
	if not world.regions.can_build_all(fp):
		return world.regions.deny()
	# no wall may cut through the footprint
	for t in fp:
		for dd in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nb: Vector2i = t + dd
			if nb in fp and not world.edge_open(t, nb):
				world.last_error = "wall in the way"
				return false
	return true

func place_object(def_id: String, tile: Vector2i, rot: int = 0) -> int:
	if not can_place(def_id, tile, rot):
		return -1
	return _create_object(def_id, tile, posmod(rot, 4), -1)

func _create_object(def_id: String, tile: Vector2i, rot: int, force_id: int) -> int:
	var d := world.get_def(def_id)
	var o = world.WorldObjectScript.new()
	o.id = force_id if force_id >= 0 else world._next_id
	world._next_id = maxi(world._next_id, o.id + 1)
	o.def_id = def_id
	o.def = d
	o.tile = tile
	o.rot = rot
	o.init_state_from_def()
	world.objects[o.id] = o
	if o.is_wall_mounted():
		var e := world.mount_edge(tile, rot)
		world.mounts[e] = o.id
		var wt := str(d.get("wall_type", "door"))
		world.walls[e] = wt
		world.nav.touch_edge(e)
	else:
		for t in o.footprint():
			if o.is_floor_layer():
				world._occ_floor[t] = o.id
			else:
				world._occ[t] = o.id
				if o.blocks():
					world.nav.touch_tile(t)
					world._blocked[t] = true
	world.regions.index_object(o)
	world.rooms.mark_dirty(tile)
	world._emit("object_placed", o.id)
	return o.id

func remove_object(object_id: int) -> bool:
	if not world.objects.has(object_id):
		return false
	var o = world.objects[object_id]
	if o.is_wall_mounted():
		var e: Vector3i = world.mount_edge(o.tile, o.rot)
		world.mounts.erase(e)
		if world.walls.has(e):
			world.walls[e] = "wall"
		world.nav.touch_edge(e)
	else:
		for t in o.footprint():
			if o.is_floor_layer():
				if world._occ_floor.get(t, -1) == object_id:
					world._occ_floor.erase(t)
			else:
				if world._occ.get(t, -1) == object_id:
					world._occ.erase(t)
				world._blocked.erase(t)
				world.nav.touch_tile(t)
	world.objects.erase(object_id)
	world.regions.unindex_object(object_id)
	world.rooms.mark_dirty(o.tile)
	world._emit("object_removed", object_id)
	return true

func get_object(object_id: int):
	return world.objects.get(object_id, null)

func all_objects() -> Array:
	return world.objects.values()

func object_at(t: Vector2i):
	var id: int = world._occ.get(t, -1)
	if id == -1:
		id = world._occ_floor.get(t, -1)
	return world.objects.get(id, null)

func objects_with_tag(tag: String) -> Array:
	var out: Array = []
	for o in world.objects.values():
		if o.has_tag(tag):
			out.append(o)
	return out

func objects_of_def(def_id: String) -> Array:
	var out: Array = []
	for o in world.objects.values():
		if o.def_id == def_id:
			out.append(o)
	return out

func objects_in_radius(tile: Vector2i, r: float) -> Array:
	var scored: Array = []
	for o in world.objects.values():
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

## Objects of the lot the tile stands in, nearest first, within `r` tiles. Streets, parks and open ground use STREET_REACH
## instead: only street / park things (bench, fountain, lamp post: objects outside every lot) within that many tiles - a folk
## on the road never wanders into a lot by itself (that is an explicit player errand, see NeighborhoodTravel).
const STREET_REACH := 12.0

func objects_in_lot_of(tile: Vector2i, r: float) -> Array:
	var rg: WorldRegions = world.regions
	var rid := rg.region_at(tile)
	if rid == WorldRegions.NONE or not rg.is_lot(rid):
		return _street_objects_near(tile, minf(r, STREET_REACH))
	var rc: Rect2i = rg.regions[rid]["rect"]
	var scored: Array = []
	for c in rg.chunks_in_rect(rc):
		for oid in rg.chunk_objects(c):
			var o = world.objects.get(oid, null)
			if o == null or not rc.has_point(o.tile):
				continue
			var best := INF
			if o.is_wall_mounted():
				best = Vector2(o.tile).distance_to(Vector2(tile))
			else:
				for t in o.footprint():
					best = minf(best, Vector2(t).distance_to(Vector2(tile)))
			if best <= r:
				scored.append([best, o])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1].id < b[1].id))
	var out: Array = []
	for s in scored:
		out.append(s[1])
	return out

func set_object_state(object_id: int, key: String, value: Variant) -> void:
	var o = world.objects.get(object_id, null)
	if o == null:
		return
	var sd: Dictionary = (o.def.get("state", {}) as Dictionary).get(key, {})
	if sd.has("max") and (value is float or value is int):
		value = clampf(float(value), float(sd.get("min", 0.0)), float(sd["max"]))
	if o.state.get(key) == value:
		return
	o.state[key] = value
	world.rooms.mark_dirty(o.tile)   # decor/mess depend on state
	world._emit("object_state_changed", object_id, key)

func add_object_state(object_id: int, key: String, delta: float) -> void:
	var o = world.objects.get(object_id, null)
	if o == null:
		return
	set_object_state(object_id, key, float(o.state.get(key, 0.0)) + delta)

func _street_objects_near(tile: Vector2i, r: float) -> Array:
	var rg: WorldRegions = world.regions
	var ri := int(ceil(r))
	var scored: Array = []
	for c in rg.chunks_in_rect(Rect2i(tile - Vector2i(ri, ri), Vector2i(2 * ri + 1, 2 * ri + 1))):
		for oid in rg.chunk_objects(c):
			var o = world.objects.get(oid, null)
			if o == null or o.is_wall_mounted() or o.is_floor_layer():
				continue
			var orid := rg.region_at(o.tile)
			if orid != WorldRegions.NONE and rg.is_lot(orid):
				continue
			var d := Vector2(o.tile).distance_to(Vector2(tile))
			if d <= r:
				scored.append([d, o])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1].id < b[1].id))
	var out: Array = []
	for s in scored:
		out.append(s[1])
	return out
