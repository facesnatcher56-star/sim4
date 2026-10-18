class_name WorldObject
extends RefCounted
## A placed object in the lot. Pure data (no rendering).
## state: Dictionary key -> float|bool (the single source of truth for object state).
## slots_reserved: Dictionary slot_idx(int) -> folk_id(int).

var id: int = -1
var def_id: String = ""
var tile: Vector2i = Vector2i.ZERO
var rot: int = 0
var level: int = 0         # 0 = ground, negative = basement, no upper limit (multi-floor: see WorldLevels)
var span: int = 0          # extra levels ABOVE `level` the object also stands on (elevator shaft)
var state: Dictionary = {}
var slots_reserved: Dictionary = {}
var def: Dictionary = {}   # shared reference to the definition dictionary


static func rotate_offset(o: Vector2i, r: int) -> Vector2i:
	match posmod(r, 4):
		1: return Vector2i(-o.y, o.x)
		2: return Vector2i(-o.x, -o.y)
		3: return Vector2i(o.y, -o.x)
	return o


static func rotate_vec(o: Vector2, r: int) -> Vector2:
	match posmod(r, 4):
		1: return Vector2(-o.y, o.x)
		2: return Vector2(-o.x, -o.y)
		3: return Vector2(o.y, -o.x)
	return o


func label() -> String:
	return str(def.get("label", def_id))


func tags() -> Array:
	return def.get("tags", [])


func has_tag(t: String) -> bool:
	return t in tags()


func size() -> Vector2i:
	var s: Array = def.get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


func blocks() -> bool:
	return bool(def.get("blocks", true)) and not is_wall_mounted()


func is_wall_mounted() -> bool:
	return str(def.get("mount", "")) == "wall"


func is_floor_layer() -> bool:
	return str(def.get("layer", "")) == "floor"


func footprint() -> Array[Vector2i]:
	return footprint_of(def, tile, rot)


static func footprint_of(d: Dictionary, t: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s: Array = d.get("size", [1, 1])
	for i in int(s[0]):
		for j in int(s[1]):
			out.append(t + rotate_offset(Vector2i(i, j), r))
	return out


func slot_count() -> int:
	return (def.get("slots", []) as Array).size()


## Approach tile of a slot (where the folk stands before using it).
func slot_tile(idx: int) -> Vector2i:
	var slots: Array = def.get("slots", [])
	if idx < 0 or idx >= slots.size():
		return tile
	var o: Array = slots[idx].get("offset", [0, 0])
	return tile + rotate_offset(Vector2i(int(o[0]), int(o[1])), rot)


func slot_pose(idx: int) -> String:
	var slots: Array = def.get("slots", [])
	if idx < 0 or idx >= slots.size():
		return "stand"
	return str(slots[idx].get("pose", "stand"))


## Body position in tile units (x,z of the grid, not 3D) while using the slot.
func slot_use_pos(idx: int) -> Vector2:
	var slots: Array = def.get("slots", [])
	if idx < 0 or idx >= slots.size():
		return Vector2(tile) + Vector2(0.5, 0.5)
	var s: Dictionary = slots[idx]
	var base: Vector2
	if s.has("use"):
		var u: Array = s["use"]
		var ru := rotate_vec(Vector2(float(u[0]) - 0.5, float(u[1]) - 0.5), rot)
		base = Vector2(tile) + Vector2(0.5, 0.5) + ru
	else:
		base = Vector2(slot_tile(idx)) + Vector2(0.5, 0.5)
	return base


## Elevation (metres) of the body base while using the slot (e.g. mattress top for lying).
func slot_elev(idx: int) -> float:
	var slots: Array = def.get("slots", [])
	if idx < 0 or idx >= slots.size():
		return 0.0
	return float(slots[idx].get("y", 0.0))


## Centre of the footprint in grid units (x, z), e.g. tile (3,4) 1x1 -> (3.5, 4.5).
func center2d() -> Vector2:
	if is_wall_mounted():
		return Vector2(tile) + Vector2(0.5, 0.5)
	var s := size()
	return Vector2(tile) + Vector2(0.5, 0.5) + rotate_vec(Vector2((s.x - 1) * 0.5, (s.y - 1) * 0.5), rot)


## Unit vector (x, z) of the object's front (slot offset [0,1] side).
func front_dir() -> Vector2:
	return rotate_vec(Vector2(0, 1), rot)


func free_slot() -> int:
	for i in slot_count():
		if not slots_reserved.has(i):
			return i
	return -1


func get_val(key: String, default: Variant = 0.0) -> Variant:
	return state.get(key, default)


## 0..1 ratio of a numeric state key according to the definition.
func ratio(key: String) -> float:
	var sd: Dictionary = (def.get("state", {}) as Dictionary).get(key, {})
	if not sd.has("max"):
		return 1.0 if bool(state.get(key, false)) else 0.0
	var mn := float(sd.get("min", 0.0))
	var mx := float(sd.get("max", 1.0))
	if mx <= mn:
		return 0.0
	return clampf((float(state.get(key, mn)) - mn) / (mx - mn), 0.0, 1.0)


func is_broken() -> bool:
	return bool(state.get("broken", false))


## Environment contribution: [decor, mess]
func env_contribution() -> Vector2:
	var decor := float(def.get("decor", 0.0))
	var scale_key := str(def.get("decor_scale_state", ""))
	if scale_key != "":
		decor *= ratio(scale_key)
	var mess := 0.0
	for k in ["dirtiness", "fullness"]:
		if state.has(k):
			mess += ratio(k) * 2.0
	if is_broken():
		mess += 2.0
		decor *= 0.5
	return Vector2(decor, mess)


func init_state_from_def() -> void:
	state = {}
	var sd: Dictionary = def.get("state", {})
	for k in sd:
		var e: Dictionary = sd[k]
		if e.has("min") or e.has("max"):
			state[k] = float(e.get("start", e.get("min", 0.0)))
		else:
			state[k] = e.get("start", false)


func to_dict() -> Dictionary:
	var d := {
		"id": id, "def_id": def_id, "tile": [tile.x, tile.y], "rot": rot,
		"state": state.duplicate(true),
	}
	if level != 0:
		d["level"] = level
	if span != 0:
		d["span"] = span
	return d


## Position as (x, y, level).
func lpos() -> Vector3i:
	return Vector3i(tile.x, tile.y, level)
