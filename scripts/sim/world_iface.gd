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

static func has_world() -> bool:
	return world() != null

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

static func objects_near(tile: Vector2i, r: int = 64) -> Array:
	var w = world()
	if w != null and w.has_method("objects_in_radius"):
		return w.objects_in_radius(tile, r)
	return []

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
	for i in slot_count(obj):
		if w.reserve(obj.id, i, folk_id):
			return i
	return -1

static func release(obj_id: int, slot_idx: int, folk_id: int) -> void:
	var w = world()
	if w != null and w.has_method("release") and slot_idx >= 0:
		w.release(obj_id, slot_idx, folk_id)

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

## Number of steps from a to b, 0 if same tile, -1 when unreachable.
static func path_length(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	var w = world()
	if w != null and w.has_method("find_path"):
		var p: Array = w.find_path(from, to)
		if p.is_empty():
			return -1
		return p.size()
	return absi(from.x - to.x) + absi(from.y - to.y)

static func find_path(from: Vector2i, to: Vector2i) -> Array:
	var w = world()
	if w != null and w.has_method("find_path"):
		return w.find_path(from, to)
	return []

# ---- object state (supports obj.state values or obj.stats Stat objects) ----
static func state_get(obj, key: String, default: Variant = null) -> Variant:
	if obj == null:
		return default
	if obj.state is Dictionary and (obj.state as Dictionary).has(key):
		var v: Variant = (obj.state as Dictionary)[key]
		if v is Dictionary and (v as Dictionary).has("value"):
			return (v as Dictionary)["value"]
		return v
	if "stats" in obj and obj.stats is Dictionary and (obj.stats as Dictionary).has(key):
		var s: Variant = (obj.stats as Dictionary)[key]
		if s is Stat:
			return (s as Stat).value
	return default

static func state_set(obj, key: String, value: Variant) -> void:
	if obj == null:
		return
	if "stats" in obj and obj.stats is Dictionary and (obj.stats as Dictionary).has(key) and (obj.stats as Dictionary)[key] is Stat:
		((obj.stats as Dictionary)[key] as Stat).set_value(float(value))
	else:
		var cur: Variant = (obj.state as Dictionary).get(key, null)
		if cur is Dictionary and (cur as Dictionary).has("value"):
			(cur as Dictionary)["value"] = value
		else:
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
