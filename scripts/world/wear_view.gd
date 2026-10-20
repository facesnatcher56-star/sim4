class_name WearView
extends Node3D
## Task 41a (view only): applies the district / wealth wear layer in the game. Every 2 s it looks at the lots that have a wear level (districts that declare one in
## data/district_dressing.json, plus the player's lot when its household is poor) and builds each one's dressing (WearLot: litter, tags, cracks, weed clumps, dead patches,
## door stains, boards) while the camera is near, frees it when far (zoomed-out views build nothing). A change of wear (WearLayer.set_district_wear, a poorer household)
## rebuilds that lot. Pieces are MultiMeshes plus at most ~24 decals per lot: no per-frame work at all.

var lot = null
var _built: Dictionary = {}          # lot id -> {node, wear}
var _t := 0.0
const WARM := ["crack", "stain", "grime", "dead_grass", "dirt_patch", "tag_rat", "tag_koz", "tag_six", "tag_nek", "tag_doa", "tag_vex"]
var _warm := 0                       # procedural decal textures are made one per frame before the first lot is dressed (no hitch)
var skip: Array = []                 # lot ids that get no generated dressing (the look-test shots hand-place theirs)


static func ensure_on(parent: Node) -> WearView:
	var n := parent.get_node_or_null("WearView") as WearView
	if n == null:
		n = WearView.new()
		n.name = "WearView"
		n.lot = parent
		parent.add_child(n)
		World.world_reset.connect(n.clear)
		WearLayer.bus.changed.connect(n._on_changed)
		var ev := parent.get_node_or_null("/root/Events")
		if ev != null:
			ev.coins_changed.connect(n._on_coins)
	return n


func clear() -> void:
	for id in _built:
		var nd: Node = _built[id]["node"]
		if is_instance_valid(nd):
			nd.queue_free()
	_built.clear()
	WearLayer.invalidate("")
	_t = 0.0


func _on_changed(lot_id: String) -> void:
	if lot_id == "":
		for id in _built.keys():
			_free(id)
	else:
		_free(lot_id)
	_t = 0.0


func _free(id: String) -> void:
	if _built.has(id):
		var nd: Node = _built[id]["node"]
		if is_instance_valid(nd):
			nd.queue_free()
		_built.erase(id)


## The player's household got richer / poorer: when its lot's wealth tier moved, the lot is re-dressed (interiors, walls, yard).
func _on_coins(hid: int, _amount: int) -> void:
	if hid != World.current_household_id:
		return
	var old := WearLayer.lot_poverty(Neighborhood.HOME)
	WearLayer.invalidate_quiet(Neighborhood.HOME)
	var now := WearLayer.lot_poverty(Neighborhood.HOME)
	if WearRules.tier_of(old) != WearRules.tier_of(now) or absf(old - now) > 0.15:
		WearLayer.invalidate(Neighborhood.HOME)


func _process(delta: float) -> void:
	if _warm < WARM.size() and _wants_dressing:
		DressingTex.tex(str(WARM[_warm]))
		_warm += 1
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = float(WearRules.cfg().get("refresh_sec", 2.0))
	_sync()


func lots_with_wear() -> Array:
	var ids: Array = []
	for d in WearLayer.districts():
		for l in (d.get("lots", []) as Array):
			if not ids.has(str(l)):
				ids.append(str(l))
	if not ids.has(Neighborhood.HOME):
		ids.append(Neighborhood.HOME)
	return ids


var _wants_dressing := false


func _sync() -> void:
	if lot == null or not World.regions.has_regions():
		return
	var near := float(WearRules.cfg().get("near_tiles", 44))
	var tgt: Vector3 = lot._target if "_target" in lot else Vector3.ZERO
	var far_view: bool = "_zoom" in lot and float(lot._zoom) > 70.0
	var todo: Array = []
	for id in lots_with_wear():
		var wear := WearLayer.lot_wear(id)
		var rc := NeighborhoodLots.rect_of(id)
		if rc.size == Vector2i.ZERO or wear <= 0.0 or id in skip:
			_free(id)
			continue
		var c := Vector2(rc.position) + Vector2(rc.size) * 0.5
		var d := c.distance_to(Vector2(tgt.x, tgt.z)) - maxf(rc.size.x, rc.size.y) * 0.5
		if far_view or d > near * 1.3:
			_free(id)
		elif d <= near and not _built.has(id):
			todo.append([id, wear])
	if todo.is_empty():
		return
	_wants_dressing = true
	if _warm < WARM.size():
		return                                  # textures are still being made (one per frame); build on a later tick
	for e in todo:
		_built[e[0]] = {"node": WearLot.build(self, WearLot.plan(str(e[0]), float(e[1]))), "wear": e[1]}


func built_lots() -> Array:
	return _built.keys()
