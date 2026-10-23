class_name WorldIface
extends RefCounted
## Adapter between the sim and the World. Uses `stub` when set (tests), else the World autoload if it
## exists, else harmless defaults. All sim code goes through here, never through World directly.

static var stub = null
## Household coin balances used when no economy system provides them.
static var coins: Dictionary = {}

static func world():
	if stub != null:
		return stub
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var root: Window = (ml as SceneTree).root
		if root != null:
			return root.get_node_or_null("World")
	return null

static func all_folk() -> Array:
	var w = world()
	if w != null and w.has_method("all_folk"):
		return w.all_folk()
	return []

static func get_folk(id: int):
	var w = world()
	if w != null and w.has_method("get_folk"):
		return w.get_folk(id)
	return null

static func get_object(id: int):
	var w = world()
	if w != null and w.has_method("get_object"):
		return w.get_object(id)
	return null

## Objects a folk standing on `tile` may use. On the big map (regions defined) that is the objects of its own lot only.
## `level` (default LPos.ALL = every floor of the lot): only the objects of that floor.
static func objects_near(tile: Vector2i, r: int = 64, level: int = LPos.ALL) -> Array:
	var w = world()
	if w != null and w.has_method("objects_in_lot_of") and w.regions.has_regions():
		return w.objects_in_lot_of(tile, r, level)
	if w != null and w.has_method("objects_in_radius"):
		return w.objects_in_radius(tile, r) if level == LPos.ALL else w.objects_in_radius(tile, r, level)
	return []

## Objects a FOLK may use (what autonomy offers). A lot without floors: objects_near. A venue with floors (office, hospital, school ...): the
## folk's own floor only (they are put on their floor). A single-household home: every floor (the bed is upstairs). A block of flats: the folk's
## own floor and the floor(s) of the flat(s) its household holds, never somebody else's flat (LevelInfo.usable).
static func objects_for(f, r: int = 64) -> Array:
	if not LevelInfo.lot_is_multi(f.tile):
		return objects_near(f.tile, r)
	if not LevelInfo.home_kind(f.tile):
		return objects_near(f.tile, r, int(f.level))
	var units: Array = ApartmentUnits.units_of(NeighborhoodLots.lot_at(f.tile))
	if units.is_empty():
		return objects_near(f.tile, r)
	var levels: Array = [int(f.level)]
	for u in units:
		if int(u["level"]) not in levels and ApartmentUnits.owner_of(u) == int(f.household_id):
			levels.append(int(u["level"]))
	var out: Array = []
	for lv in levels:
		for o in objects_near(f.tile, r, lv):
			if LevelInfo.usable(f, o, units):
				out.append(o)
	return out

## Folk a folk can interact with: everyone on a plain world; on the big map the folk of its own lot (on a street: the other folk on streets within 12 tiles).
static func folk_near(f) -> Array:
	var w = world()
	if w == null or not ("regions" in w) or not w.regions.has_regions():
		return all_folk()
	var rid: int = w.regions.region_at(f.tile)
	var in_lot: bool = rid != -1 and w.regions.is_lot(rid)
	var out: Array = []
	for o in all_folk():
		var orid: int = w.regions.region_at(o.tile)
		if in_lot:
			if orid == rid:
				out.append(o)
		elif not (orid != -1 and w.regions.is_lot(orid)) and absi(o.tile.x - f.tile.x) + absi(o.tile.y - f.tile.y) <= 12:
			out.append(o)          # street folk only meet other street folk (nobody is called into a lot from outside)
	return out

static func slot_count(obj) -> int:
	var def: Dictionary = SimEnv.data().object_def(str(obj.def_id))
	var slots: Variant = def.get("slots", [])
	if slots is Array and (slots as Array).size() > 0:
		return (slots as Array).size()
	return 1

## Is some slot of the object available to this folk?
static func has_free_slot(obj, folk_id: int) -> bool:
	var n := slot_count(obj)
	var res: Variant = obj.slots_reserved if "slots_reserved" in obj else {}
	for i in n:
		if res is Dictionary:
			var rd: Dictionary = res
			if not rd.has(i) or rd[i] == null or int(rd[i]) == folk_id or int(rd[i]) < 0:
				return true
		elif res is Array:
			var ra: Array = res
			if i >= ra.size() or ra[i] == null or int(ra[i]) < 0 or int(ra[i]) == folk_id:
				return true
		else:
			return true
	return false

## Reserve the first available slot. Returns the slot index or -1.
static func reserve_any(obj, folk_id: int) -> int:
	var w = world()
	if w == null or not w.has_method("reserve"):
		return 0
	if obj.has_method("slot_count") and int(obj.slot_count()) == 0:
		return 0          # a door or a ceiling lamp has no spot to hold: anyone may use it (has_free_slot counts it as one free slot)
	for i in slot_count(obj):
		if w.reserve(obj.id, i, folk_id):
			return i
	return -1

static func release(obj_id: int, slot_idx: int, folk_id: int) -> void:
	var w = world()
	if w != null and w.has_method("release") and slot_idx >= 0:
		w.release(obj_id, slot_idx, folk_id)

## Somebody else is in (or heading for) the shower or bath of the bathroom this object is in.
static func bathroom_locked(obj, folk_id: int) -> bool:
	var w = world()
	return w != null and w.has_method("bathroom_locked") and bool(w.call("bathroom_locked", obj, folk_id))

## The folk is in the middle of something private (shower, bath: objects.json `private`): nobody chats to them.
static func private_use(f) -> bool:
	if f == null or f.current == null or str(f.current.state) != "running" or f.current.obj == null:
		return false
	return bool(SimEnv.data().object_def(str(f.current.obj.def_id)).get("private", false))

## A walkable tile beside `t` for meeting someone who sits or lies on it (`t` itself when walkable).
static func meet_tile(t: Vector2i, level: int, toward: Vector2i) -> Vector2i:
	var w = world()
	if w != null and w.has_method("open_neighbor"):
		return w.call("open_neighbor", t, level, toward)
	return t

## Tile a folk steps to when it gets up from `slot_idx` of `obj` (the slot tile itself when that is walkable).
static func exit_tile(obj, slot_idx: int) -> Vector2i:
	var w = world()
	if w != null and w.has_method("exit_tile"):
		return w.call("exit_tile", obj, slot_idx)
	return use_tile(obj, slot_idx)

## Tile a folk stands on to use `slot_idx` of `obj`.
static func use_tile(obj, slot_idx: int) -> Vector2i:
	var w = world()
	if w != null:
		for m in ["slot_tile", "get_slot_tile", "use_tile"]:
			if w.has_method(m):
				var t: Variant = w.call(m, obj, slot_idx)
				if t is Vector2i:
					return t
	var def: Dictionary = SimEnv.data().object_def(str(obj.def_id))
	var slots: Variant = def.get("slots", [])
	if slots is Array and slot_idx >= 0 and slot_idx < (slots as Array).size():
		var s: Variant = (slots as Array)[slot_idx]
		if s is Dictionary and (s as Dictionary).has("offset"):
			var off: Array = (s as Dictionary)["offset"]
			var v := Vector2i(int(off[0]), int(off[1]))
			for _i in (int(obj.rot) % 4 + 4) % 4:
				v = Vector2i(-v.y, v.x)
			return obj.tile + v
	return obj.tile

## Number of steps from a to b, 0 if same tile, -1 when unreachable. Uses the world's cached length (`path_length`: LRU per
## pair, distance fields, no tile list); only a world without one (the test stub) falls back to a path.
static func path_length(from: Vector2i, to: Vector2i, from_level: int = 0, to_level: int = 0) -> int:
	if from == to and from_level == to_level:
		return 0
	if from_level != 0 or to_level != 0:             # multi-floor: cost in tile units, stairs and lifts included
		var w2 = world()
		if w2 != null and w2.has_method("route_length"):
			var c: float = w2.route_length(Vector3i(from.x, from.y, from_level), Vector3i(to.x, to.y, to_level))
			return -1 if c < 0.0 else int(ceil(c))
		return absi(from.x - to.x) + absi(from.y - to.y)
	var w = world()
	if w != null:
		if w.has_method("path_length"):
			return int(w.path_length(from, to))
		if w.has_method("find_path"):
			var p: Array = w.find_path(from, to)
			return -1 if p.is_empty() else p.size()
	return absi(from.x - to.x) + absi(from.y - to.y)

## Multi-floor route (entries Vector3i(x, y, level), start excluded, goal included; [] unreachable or already there).
static func find_route(from: Vector3i, to: Vector3i, stair_mult: float = 1.0) -> Array:
	var w = world()
	if w != null and w.has_method("find_route"):
		return w.find_route(from, to, stair_mult)
	return []

## Cost of an existing route in tile units (stairs / lift rides included).
static func route_cost(route: Array, stair_mult: float = 1.0) -> float:
	var w = world()
	if w != null and "router" in w:
		return w.router.cost_of(route, stair_mult)
	return float(route.size())

## Books the lifts on a route; returns the extra game minutes of waiting.
static func book_route(route: Array, folk_id: int, walk_min_per_step: float) -> float:
	var w = world()
	if w != null and "portals" in w:
		return w.portals.elevators.book_route(route, folk_id, walk_min_per_step)
	return 0.0

## How much harder stairs are for this folk (elder / toddler / injured / exhausted).
static func stair_mult(f) -> float:
	return LevelPortals.stair_mult(f)

## Is there a floor of that level at the tile (a folk can be on it)?
static func level_valid(tile: Vector2i, level: int) -> bool:
	if level == 0:
		return true
	var w = world()
	if w == null or not ("levels" in w):
		return false
	return w.levels.has_level(w.levels.building_at(tile), level)

static func find_path(from: Vector2i, to: Vector2i) -> Array:
	var w = world()
	if w != null and w.has_method("find_path"):
		return w.find_path(from, to)
	return []

# ---- object state: `obj.state` is the single source of truth ----
static func state_get(obj, key: String, default: Variant = null) -> Variant:
	if obj == null:
		return default
	return (obj.state as Dictionary).get(key, default)

## Writes through the real World when it owns the object (clamping, rooms dirty, change event), else straight into `state`.
static func state_set(obj, key: String, value: Variant) -> void:
	if obj == null:
		return
	var w = world()
	if w != null and w.has_method("set_object_state") and w.has_method("get_object") and w.get_object(int(obj.id)) == obj:
		w.set_object_state(int(obj.id), key, value)
		return
	(obj.state as Dictionary)[key] = value
	SimEnv.emit("object_state_changed", int(obj.id), key)

static func state_add(obj, key: String, delta: float) -> void:
	var def: Dictionary = SimEnv.data().object_def(str(obj.def_id))
	var spec: Variant = (def.get("state", {}) as Dictionary).get(key, {})
	var lo := 0.0
	var hi := 1.0e9
	if spec is Dictionary:
		lo = float((spec as Dictionary).get("min", 0.0))
		hi = float((spec as Dictionary).get("max", 1.0e9))
	var cur: float = float(state_get(obj, key, 0.0))
	state_set(obj, key, clampf(cur + delta, lo, hi))

# ---- household coins ----
static func get_coins(household_id: int) -> int:
	return int(coins.get(household_id, 0))

static func add_coins(household_id: int, amount: int) -> void:
	coins[household_id] = get_coins(household_id) + amount
	SimEnv.emit("coins_changed", household_id, int(coins[household_id]))