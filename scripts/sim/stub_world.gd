class_name StubWorld
extends RefCounted
## Minimal World replacement so the sim runs standalone (tests). Mirrors the World API in ARCHITECTURE.md.
## Install with `WorldIface.stub = StubWorld.new()`.

class StubObject:
	extends RefCounted
	var id: int = -1
	var def_id: String = ""
	var tile: Vector2i = Vector2i.ZERO
	var rot: int = 0
	var state: Dictionary = {}
	var slots_reserved: Dictionary = {}

var folk: Dictionary = {}      # id -> Folk
var objects: Dictionary = {}   # id -> StubObject
var _next_obj: int = 1
var width: int = 32
var height: int = 32

func add_object(def_id: String, tile: Vector2i, rot: int = 0) -> StubObject:
	var o := StubObject.new()
	o.id = _next_obj
	_next_obj += 1
	o.def_id = def_id
	o.tile = tile
	o.rot = rot
	var def: Dictionary = SimEnv.data().object_def(def_id)
	var st: Dictionary = def.get("state", {})
	for k in st:
		var spec: Variant = st[k]
		if spec is Dictionary and (spec as Dictionary).has("start"):
			o.state[k] = (spec as Dictionary)["start"]
		else:
			o.state[k] = 0
	objects[o.id] = o
	return o

func place_object(def_id: String, tile: Vector2i, rot: int = 0) -> int:
	return add_object(def_id, tile, rot).id

func get_object(id: int):
	return objects.get(id, null)

func remove_object(id: int) -> bool:
	return objects.erase(id)

func objects_in_radius(tile: Vector2i, r: int) -> Array:
	var out: Array = []
	for o in objects.values():
		if Vector2(o.tile - tile).length() <= float(r):
			out.append(o)
	return out

func add_folk(f, tile: Vector2i = Vector2i.ZERO) -> void:
	f.tile = tile
	folk[f.id] = f

func get_folk(id: int):
	return folk.get(id, null)

func all_folk() -> Array:
	return folk.values()

func reserve(object_id: int, slot_idx: int, folk_id: int) -> bool:
	var o = objects.get(object_id, null)
	if o == null:
		return false
	if o.slots_reserved.has(slot_idx) and o.slots_reserved[slot_idx] != folk_id:
		return false
	o.slots_reserved[slot_idx] = folk_id
	return true

func release(object_id: int, slot_idx: int, folk_id: int) -> void:
	var o = objects.get(object_id, null)
	if o != null and o.slots_reserved.get(slot_idx, -1) == folk_id:
		o.slots_reserved.erase(slot_idx)

## Open-field path: straight L-shaped route (no obstacles).
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cur := from
	while cur != to:
		if cur.x != to.x:
			cur.x += signi(to.x - cur.x)
		else:
			cur.y += signi(to.y - cur.y)
		out.append(cur)
	return out

func is_walkable(_tile: Vector2i) -> bool:
	return true
