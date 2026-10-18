class_name WorldObjects
extends RefCounted
## Object placement, removal, queries and state.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

var world: WorldGrid


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ objects

func can_place(def_id: String, tile: Vector2i, rot: int = 0, level: int = 0) -> bool:
	world.last_error = ""
	var d := world.get_def(def_id)
	if d.is_empty():
		world.last_error = "unknown object"
		return false
	rot = posmod(rot, 4)
	var lay: LevelLayer = null
	if level != 0:
		if not world.levels.has_level(world.levels.building_at(tile), level):
			world.last_error = "there is no floor here"
			return false
		lay = world.levels.layer(level)
	if str(d.get("mount", "")) == "wall":
		if not world.in_bounds(tile):
			world.last_error = "out of bounds"
			return false
		if not world.regions.can_build(tile):
			return world.regions.deny()
		var e := world.mount_edge(tile, rot)
		if world.levels.wall_at(e, level) != "wall":
			world.last_error = "needs a wall"
			return false
		if world.levels.mounts_of(level).has(e):
			world.last_error = "edge taken"
			return false
		return true
	var fp := world.WorldObjectScript.footprint_of(d, tile, rot)
	var floor_layer := str(d.get("layer", "")) == "floor"
	var occ: Dictionary = world._occ if lay == null else lay.occ
	var occ_floor: Dictionary = world._occ_floor if lay == null else lay.occ_floor
	for t in fp:
		if not world.in_bounds(t):
			world.last_error = "out of bounds"
			return false
		if lay != null and (not lay.floors.has(t) or lay.holes.has(t)):
			world.last_error = "needs a floor"
			return false
		if floor_layer:
			if occ_floor.has(t):
				world.last_error = "occupied"
				return false
		elif occ.has(t) or (lay != null and lay.blocked.has(t)):
			world.last_error = "occupied"
			return false
	if not world.regions.can_build_all(fp):
		return world.regions.deny()
	# no wall may cut through the footprint
	for t in fp:
		for dd in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nb: Vector2i = t + dd
			if nb in fp and not world.edge_open(t, nb, level):
				world.last_error = "wall in the way"
				return false
	if LevelPortals.is_portal_def(d) and not world.lbuild.portal_fits(d, tile, rot, level):
		return false
	return true

func place_object(def_id: String, tile: Vector2i, rot: int = 0, level: int = 0) -> int:
	if not can_place(def_id, tile, rot, level):
		return -1
	return _create_object(def_id, tile, posmod(rot, 4), -1, level, default_span(world.get_def(def_id), tile, level))

## Elevator shafts run from the placed level up to the highest level of the building.
func default_span(d: Dictionary, tile: Vector2i, level: int) -> int:
	if str((d.get("portal", {}) as Dictionary).get("kind", "")) != "elevator":
		return 0
	return maxi(0, world.levels.range_at(tile).y - level)

func _create_object(def_id: String, tile: Vector2i, rot: int, force_id: int, level: int = 0, span: int = 0) -> int:
	var d := world.get_def(def_id)
	var o = world.WorldObjectScript.new()
	o.id = force_id if force_id >= 0 else world._next_id
	world._next_id = maxi(world._next_id, o.id + 1)
	o.def_id = def_id
	o.def = d
	o.tile = tile
	o.rot = rot
	o.level = level
	o.span = span
	o.init_state_from_def()
	world.objects[o.id] = o
	var lay: LevelLayer = world.levels.layer(level) if level != 0 else null
	if o.is_wall_mounted():
		var e := world.mount_edge(tile, rot)
		var wt := str(d.get("wall_type", "door"))
		if lay == null:
			world.mounts[e] = o.id
			world.walls[e] = wt
			world.nav.touch_edge(e)
		else:
			lay.mounts[e] = o.id
			lay.walls[e] = wt
			lay.touch()
			world.levels.touch()
			world.rooms.mark_dirty_edge(e, level)
	else:
		for t in o.footprint():
			if o.is_floor_layer():
				(world._occ_floor if lay == null else lay.occ_floor)[t] = o.id
			else:
				(world._occ if lay == null else lay.occ)[t] = o.id
				if o.blocks():
					if lay == null:
						world.nav.touch_tile(t)
						world._blocked[t] = true
					else:
						lay.blocked[t] = true
		if lay != null:
			lay.touch()
			world.levels.touch()
	world.portals.on_created(o)
	world.regions.index_object(o)
	world.rooms.mark_dirty(tile, level)
	world._emit("object_placed", o.id)
	return o.id

func remove_object(object_id: int) -> bool:
	if not world.objects.has(object_id):
		return false
	var o = world.objects[object_id]
	var lay: LevelLayer = world.levels.layer(o.level, false) if o.level != 0 else null
	world.portals.on_removed(o)
	if o.is_wall_mounted():
		var e: Vector3i = world.mount_edge(o.tile, o.rot)
		if lay == null:
			world.mounts.erase(e)
			if world.walls.has(e):
				world.walls[e] = "wall"
			world.nav.touch_edge(e)
		elif lay != null:
			lay.mounts.erase(e)
			if lay.walls.has(e):
				lay.walls[e] = "wall"
			lay.touch()
			world.levels.touch()
			world.rooms.mark_dirty_edge(e, o.level)
	else:
		for t in o.footprint():
			if o.is_floor_layer():
				var of: Dictionary = world._occ_floor if lay == null else lay.occ_floor
				if of.get(t, -1) == object_id:
					of.erase(t)
			else:
				var oc: Dictionary = world._occ if lay == null else lay.occ
				if oc.get(t, -1) == object_id:
					oc.erase(t)
				if lay == null:
					world._blocked.erase(t)
					world.nav.touch_tile(t)
				else:
					lay.blocked.erase(t)
		if lay != null:
			lay.touch()
			world.levels.touch()
	world.objects.erase(object_id)
	world.regions.unindex_object(object_id)
	world.rooms.mark_dirty(o.tile, o.level)
	world._emit("object_removed", object_id)
	return true

func get_object(object_id: int):
	return world.objects.get(object_id, null)

func all_objects() -> Array:
	return world.objects.values()

func object_at(t: Vector2i, level: int = 0):
	var occ: Dictionary = world._occ
	var occ_floor: Dictionary = world._occ_floor
	if level != 0:
		var lay := world.levels.layer(level, false)
		if lay == null:
			return null
		occ = lay.occ
		occ_floor = lay.occ_floor
	var id: int = occ.get(t, -1)
	if id == -1:
		id = occ_floor.get(t, -1)
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
	if world.portals.portals.has(object_id):
		world.levels.touch()      # lift out of order / repaired: routes change
	world.rooms.mark_dirty(o.tile, o.level)   # decor/mess depend on state
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
