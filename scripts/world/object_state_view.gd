class_name ObjectStateView
extends Node
## Task 33.3 (view only): objects show their state. LotView calls `refresh` from `_refresh_object_visual` (object placed or `object_state_changed`, never per frame); this node adds
## what the state signal cannot say: which objects somebody is using right now (stove burners, fridge door, TV flicker), found by a 3 Hz look at the folk (a pure read of
## `Folk.current`), and the LOD switch (particles / lights only near the camera, 2 Hz). Nothing here writes sim state or touches an rng.

const SCAN_SEC := 0.35
const LOD_SEC := 0.5

static var _use: Dictionary = {}          # object id -> Array of interaction tags, for objects with a RUNNING interaction on them
static var _near_cache: Dictionary = {}   # object id -> bool, last near/far decision

var lot = null
var _scan_t := 0.0
var _lod_t := 0.0


static func ensure_on(parent: Node) -> ObjectStateView:
	var n := parent.get_node_or_null("ObjectStateView") as ObjectStateView
	if n == null:
		n = ObjectStateView.new()
		n.name = "ObjectStateView"
		n.lot = parent
		parent.add_child(n)
		reset()
		World.world_reset.connect(reset)
	return n


## Tags of what somebody is doing to the object (null when nobody is).
static func use_tags_of(object_id: int) -> Variant:
	return _use.get(object_id, null)


static func reset() -> void:
	_use.clear()
	_near_cache.clear()


## The look for one object right now (pure read of its state): used by LotView and by the tests.
static func look_of(o) -> Dictionary:
	if not ObjectVisualRules.has_rules(str(o.def_id)):
		return {}
	var st: Dictionary = o.state
	var pov := WearLayer.poverty_at(o.tile)               # task 41a: the lot's wealth score and a stable per-object pick pick the poor variants (view only)
	if pov > 0.0:
		st = o.state.duplicate()
		st["_poverty"] = pov
		st["_pick"] = WearRules.pick_of(int(o.id))
	return ObjectVisualRules.resolve(str(o.def_id), st, o.def.get("state", {}), use_tags_of(int(o.id)), float(o.def.get("height", 1.0)))


## Called by LotView for an object node after it was built or its state changed.
static func refresh(lot_view, o, node: Node3D) -> void:
	if not ObjectVisualRules.has_rules(str(o.def_id)) and not node.has_meta("ovsig"):
		return
	ObjectVisualNodes.apply(node, look_of(o))
	if bool(node.get_meta("has_near", false)):
		var near := _is_near(lot_view, node)
		_near_cache[int(o.id)] = near
		ObjectVisualNodes.set_near(node, near)


static func _is_near(lot_view, node: Node3D) -> bool:
	if lot_view == null or not ("_target" in lot_view):
		return true
	var t: Vector3 = lot_view._target
	var d := Vector2(node.position.x - t.x, node.position.z - t.z).length()
	if "_zoom" in lot_view and float(lot_view._zoom) > 70.0:
		return false          # zoomed out over the whole map: no particles, no lights
	return d <= ObjectVisualRules.near_tiles()


func _process(delta: float) -> void:
	if lot == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_SEC
		_scan_use()
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = LOD_SEC
		_update_lod()


func _scan_use() -> void:
	var now: Dictionary = {}
	for f in World.all_folk():
		var cur = f.current
		if cur == null or str(cur.state) != "running" or str(cur.target_kind) != "object":
			continue
		var tags: Array = cur.def.get("tags", []) if cur.def is Dictionary else []
		var merged: Array = now.get(int(cur.target_id), [])
		for t in tags:
			if not merged.has(str(t)):
				merged.append(str(t))
		now[int(cur.target_id)] = merged
	if now.hash() == _use.hash() and now.size() == _use.size():
		return
	var changed: Array = []
	for id in now:
		if not _use.has(id) or _use[id] != now[id]:
			changed.append(id)
	for id in _use:
		if not now.has(id):
			changed.append(id)
	_use = now
	for id in changed:
		var o = World.get_object(int(id))
		if o != null and ObjectVisualRules.has_rules(str(o.def_id)):
			lot._refresh_object_visual(o)


func _update_lod() -> void:
	for id in lot._obj_nodes:
		var node: Node3D = lot._obj_nodes[id]
		if not is_instance_valid(node) or not bool(node.get_meta("has_near", false)):
			continue
		var near := _is_near(lot, node)
		if _near_cache.get(id, null) != near:
			_near_cache[id] = near
			ObjectVisualNodes.set_near(node, near)
