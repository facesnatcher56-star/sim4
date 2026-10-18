class_name SysUtil
extends RefCounted
## Small shared helpers for the systems layer (time, rng, notifications, world access).

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

static func now() -> int:
	return SimEnv.now_min()

static func day() -> int:
	return int(SimEnv.clock().day())

## 0..6, day 1 = weekday 0. Weekend is days 5 and 6.
static func weekday(d: int = -1) -> int:
	var dd: int = day() if d < 0 else d
	return posmod(dd - 1, 7)

static func hour_f() -> float:
	return SimEnv.hour_f()

static func table(tname: String) -> Dictionary:
	return SimEnv.data().get_table(tname)

static func notify(text: String, kind: String = "info") -> void:
	SimEnv.emit("notification", text, kind)

static func game_event(ev_name: String, payload: Dictionary = {}) -> void:
	SimEnv.emit("game_event", ev_name, payload)

static func folk(id: int):
	return WorldIface.get_folk(id)

static func folk_name(id: int) -> String:
	var f = WorldIface.get_folk(id)
	if f != null:
		return str(f.name)
	return Story.name_of(id)

static func chance(p: float) -> bool:
	return rng.randf() < p

static func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]

## Weighted pick: items = Array, weights = Array[float].
static func pick_weighted(items: Array, weights: Array):
	var total: float = 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if items.is_empty() or total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	for i in items.size():
		roll -= maxf(float(weights[i]), 0.0)
		if roll <= 0.0:
			return items[i]
	return items[items.size() - 1]

static func is_resident(f) -> bool:
	return f != null and int(f.household_id) > 0 and not bool(f.has_meta("visitor"))

static func residents() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if is_resident(f):
			out.append(f)
	return out

static func is_away(f) -> bool:
	return f != null and bool(f.has_meta("away"))

## Remove a folk from the world (real World or stub).
static func world_remove_folk(id: int) -> void:
	var w = WorldIface.world()
	if w == null:
		return
	if w.has_method("remove_folk"):
		w.remove_folk(id)
	elif "folk" in w and w.folk is Dictionary:
		(w.folk as Dictionary).erase(id)
		SimEnv.emit("folk_removed", id)

static func world_add_folk(f, tile: Vector2i) -> void:
	var w = WorldIface.world()
	if w == null:
		return
	if w.has_method("add_folk"):
		w.add_folk(f, tile)

static func all_world_objects() -> Array:
	var w = WorldIface.world()
	if w == null:
		return []
	if w.has_method("all_objects"):
		return w.all_objects()
	if "objects" in w and w.objects is Dictionary:
		return (w.objects as Dictionary).values()
	return []

static func clone_dict(d: Dictionary) -> Dictionary:
	return d.duplicate(true)

## JSON round trip turns int keys into strings; convert a dictionary's keys back to int.
static func int_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[int(str(k))] = d[k]
	return out

static func str_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[str(k)] = d[k]
	return out

static func pair_key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]
