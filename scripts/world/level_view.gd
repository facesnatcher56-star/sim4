class_name LevelView
extends Node3D
## 3D side of multi-floor buildings (child of LotView, see ensure_on). Level 0 is drawn by LotView exactly as before; this node draws
## the OTHER levels of the ACTIVE building: floor slabs, walls (merged meshes), objects of the viewed level, stairs / lifts, the roof.
##
## Active building = the one the selected Folk is in, else the one under the camera, else (in build mode) the home lot's.
## Viewed level = the selected Folk's level while `follow` is on (the camera follows the floor), else whatever the player stepped to
## with the floor buttons / Page Up / Page Down. Levels ABOVE the viewed one are not drawn (so you look into it); the viewed level uses
## the wall mode (cut-away = walls on the camera side are low); levels below it are drawn as shells with their stairs. Viewing a
## basement hides the ground inside the building. Folk of the building on another floor are hidden (they show as dots in FloorSelector).

signal view_changed

const CHECK_EVERY := 0.15

var lot = null                         # the LotView
var building: int = -1
var viewed: int = 0
var follow: bool = true                # camera follows the selected Folk's floor
var level_nodes: Dictionary = {}       # level -> {root, floor, walls, glass, objs: {id: Node3D}, sig: String, obj_sig: int}
var _roof: MeshInstance3D = null
var _roof_sig: String = ""
var _clock: float = 0.0
var _objs_gen: int = 0
var _floor_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _hidden_rect: Rect2i = Rect2i()
var _folk_clock: float = 0.0
var _hidden_objs: Dictionary = {}
var _blockers_gen: int = -1
var _blockers: Node3D = null


static func ensure_on(p_lot) -> LevelView:
	var existing = p_lot.get("level_view")
	if existing is LevelView:
		return existing
	var lv := LevelView.new()
	lv.name = "LevelView"
	lv.lot = p_lot
	p_lot.add_child(lv)
	p_lot.set("level_view", lv)
	return lv


func _ready() -> void:
	_floor_mat = LevelMesher.material()
	_glass_mat = LevelMesher.material(true)
	World.world_reset.connect(_on_reset)
	var ev := get_node_or_null("/root/Events")
	if ev:
		ev.object_placed.connect(func(_id): _objs_gen += 1)
		ev.object_removed.connect(func(_id): _objs_gen += 1)
		ev.object_state_changed.connect(func(_id, _k): _objs_gen += 1)


func _on_reset() -> void:
	building = -1
	viewed = 0
	for lv in level_nodes.values():
		(lv["root"] as Node3D).queue_free()
	level_nodes.clear()
	_set_roof(null)
	_apply_ground_hiding(Rect2i())
	view_changed.emit()


# ------------------------------------------------------------------ public API (HUD, build panel, tests)

func active() -> bool:
	return building >= 0


func range_of_building() -> Vector2i:
	var b: Dictionary = World.levels.building(building)
	return Vector2i(0, 0) if b.is_empty() else Vector2i(int(b["min"]), int(b["max"]))


func set_viewed(level: int, keep_follow: bool = false) -> void:
	if building < 0:
		return
	var r := range_of_building()
	level = clampi(level, r.x, r.y)
	if level == viewed:
		return
	viewed = level
	if not keep_follow:
		follow = false
	view_changed.emit()


func step(d: int) -> void:
	set_viewed(viewed + d)


func set_follow(on: bool) -> void:
	follow = on
	if on:
		_follow_folk()
	view_changed.emit()


## Selected-folk id or -1.
func _selected_folk():
	if lot != null and str(lot.get("selected_kind")) == "folk":
		return World.get_folk(int(lot.get("selected_id")))
	return null


## {level: [folk ids]} of the active building (for the floor selector's dots).
func folk_by_level() -> Dictionary:
	var out: Dictionary = {}
	if building < 0:
		return out
	var rc: Rect2i = World.levels.building(building)["rect"]
	for f in World.all_folk():
		if f.has_meta("away") or not rc.has_point(f.tile):
			continue
		if not out.has(f.level):
			out[f.level] = []
		(out[f.level] as Array).append(f.id)
	return out


## Is this object drawn / pickable right now? Level 0 things outside the active building always are.
func object_shown(o) -> bool:
	if building < 0:
		return o.level == 0
	var rc: Rect2i = World.levels.building(building)["rect"]
	if not rc.has_point(o.tile):
		return o.level == 0
	if o.level == viewed:
		return true
	return o.span > 0 and viewed >= o.level and viewed <= o.level + o.span


## The drawn node of an object on a viewed upper / lower floor (null when not drawn).
func object_node(id: int):
	for n in level_nodes.values():
		var objs: Dictionary = n["objs"]
		if objs.has(id):
			return objs[id]
	return null


## The shell of a building with this footprint must be open (we are looking inside a floor).
func wants_open(rect: Rect2i) -> bool:
	if building < 0 or viewed == 0:
		return false
	return (World.levels.building(building)["rect"] as Rect2i).intersects(rect)


func plane_y() -> float:
	return LPos.elev(viewed) if building >= 0 else 0.0


# ------------------------------------------------------------------ per frame

func _unhandled_input(event: InputEvent) -> void:
	if building < 0 or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("sim_level_up"):
		step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sim_level_down"):
		step(-1)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if lot == null or not World.levels.any() and building < 0:
		return
	if _blockers_gen != World.levels.gen:
		_blockers_gen = World.levels.gen
		_make_rain_blockers()
	_clock += delta
	if _clock >= CHECK_EVERY:
		_clock = 0.0
		_pick_building()
	if building < 0:
		_move_camera_y(0.0, delta)
		_sync_nodes()
		_clear_folk_hiding()
		_restore_ground_objects()
		return
	if follow:
		_follow_folk()
	_move_camera_y(LPos.elev(viewed), delta)
	_sync_nodes()
	_folk_clock += delta
	if _folk_clock >= 0.1:
		_folk_clock = 0.0
		_update_folk_visibility()


func _clear_folk_hiding() -> void:
	for fv in lot.get("_folk_views").values():
		if is_instance_valid(fv) and fv.has_meta("level_hidden"):
			fv.remove_meta("level_hidden")


func _move_camera_y(goal: float, delta: float) -> void:
	var t: Vector3 = lot.get("_target")
	if absf(t.y - goal) < 0.01:
		t.y = goal
	else:
		t.y = lerpf(t.y, goal, clampf(delta * 6.0, 0.0, 1.0))
	lot.set("_target", t)
	lot.set("_plane_y", plane_y())


func _pick_building() -> void:
	var f = _selected_folk()
	var b := -1
	if f != null and not f.has_meta("away"):
		b = World.levels.building_at(f.tile)
	if b < 0:
		var t: Vector3 = lot.get("_target")
		b = World.levels.building_at(Vector2i(floori(t.x), floori(t.z)))
	if b < 0 and str(lot.get("tool")) != "select" and World.regions.has_regions():
		var home := World.regions.home()
		if not home.is_empty():
			b = World.lbuild.ensure_building((home["rect"] as Rect2i).position + Vector2i(2, 2))
	if b != building:
		building = b
		viewed = 0
		follow = true
		if b >= 0:
			_follow_folk()
		view_changed.emit()


func _follow_folk() -> void:
	var f = _selected_folk()
	if f == null or building < 0 or f.has_meta("away"):
		return
	if World.levels.building_at(f.tile) != building or not World.levels.has_level(building, f.level):
		return
	var lvl: int = f.level
	var fv = lot.get("_folk_views").get(f.id, null)
	if fv != null and is_instance_valid(fv) and fv.visible:
		lvl = clampi(roundi(fv.get("_ybase") / LPos.H), range_of_building().x, range_of_building().y)      # the floor the BODY is on (halfway up the stairs the view switches)
	if lvl != viewed:
		viewed = lvl
		view_changed.emit()


# ------------------------------------------------------------------ nodes

func _sync_nodes() -> void:
	var want: Array = []
	if building >= 0 and viewed != 0:
		if viewed > 0:
			for l in range(1, viewed + 1):
				want.append(l)
		else:
			for l in range(viewed, 0):
				want.append(l)
	for l in level_nodes.keys():
		if not want.has(l):
			(level_nodes[l]["root"] as Node3D).queue_free()
			level_nodes.erase(l)
	var rc: Rect2i = Rect2i()
	if building >= 0:
		rc = World.levels.building(building)["rect"]
	var hide_rc: Rect2i = rc if (building >= 0 and viewed < 0) else Rect2i()
	if hide_rc != _hidden_rect:
		_apply_ground_hiding(hide_rc)
	for l in want:
		_sync_level(l, rc)
	_sync_roof()


func _level_sig(l: int) -> String:
	var lay := World.levels.layer(l, false)
	var g: int = lay.gen if lay != null else -1
	var cut := 0
	if l == viewed:
		cut = 1 + int(lot.get("wall_mode")) * 10 + int(lot.get("_yaw_step"))
	return "%d|%d|%d" % [g, cut, building]


func _sync_level(l: int, rc: Rect2i) -> void:
	var n: Dictionary = level_nodes.get(l, {})
	if n.is_empty():
		var root := Node3D.new()
		root.name = "level_%d" % l
		add_child(root)
		n = {"root": root, "objs": {}, "sig": "", "obj_sig": -1}
		for k in ["floor", "walls", "glass"]:
			var mi := MeshInstance3D.new()
			mi.name = k
			mi.material_override = _glass_mat if k == "glass" else _floor_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k == "glass" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mi)
			n[k] = mi
		level_nodes[l] = n
	var sig := _level_sig(l)
	if sig != n["sig"]:
		n["sig"] = sig
		(n["floor"] as MeshInstance3D).mesh = LevelMesher.floors(World, l)
		var cut_mode: int = int(lot.get("wall_mode"))
		var yaw_d: Vector3 = lot.call("_cam_dir")
		var low := Callable()
		if l == viewed and cut_mode != 0:
			var wb := _wall_bounds(World.levels.layer(l, false))      # the far outer walls stay up, every other wall of the floor is cut
			low = func(e: Vector3i) -> bool:
				if cut_mode == 2:
					return true
				return not LotView.is_far_wall(e, wb, yaw_d)
		var wm := LevelMesher.walls(World, l, low)
		(n["walls"] as MeshInstance3D).mesh = wm[0]
		(n["glass"] as MeshInstance3D).mesh = wm[1]
	if int(n["obj_sig"]) != _objs_gen:
		n["obj_sig"] = _objs_gen
		_sync_objects(l, n)


## Bounding rectangle of a layer's wall edges as LotView.is_far_wall wants it (position = smallest x / y, end = largest).
func _wall_bounds(lay) -> Rect2i:
	if lay == null or lay.walls.is_empty():
		return Rect2i()
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for e in lay.walls:
		lo = Vector2i(mini(lo.x, e.x), mini(lo.y, e.y))
		hi = Vector2i(maxi(hi.x, e.x), maxi(hi.y, e.y))
	return Rect2i(lo, hi - lo)


func _sync_objects(l: int, n: Dictionary) -> void:
	var objs: Dictionary = n["objs"]
	for node in objs.values():
		(node as Node3D).queue_free()
	objs.clear()
	var root: Node3D = n["root"]
	var rc: Rect2i = World.levels.building(building)["rect"]
	var y := LPos.elev(l)
	var full: bool = l == viewed
	for o in World.all_objects():
		if o.is_wall_mounted() or not rc.has_point(o.tile):
			continue
		var in_span: bool = o.level <= l and l <= o.level + o.span
		if not in_span:
			continue
		var node: Node3D = null
		var props: Node3D = LevelProps.make(o)
		var c: Vector2 = LevelProps.centre(o)
		if props != null:
			node = props
			node.position = Vector3(c.x, y, c.y)
		elif full and o.level == l:
			node = lot.call("make_def_visual", o.def_id)
			node.position = Vector3(c.x, y + (0.005 if o.is_floor_layer() else 0.0), c.y)
			node.rotation.y = lot.call("_yaw_for_rot", o.rot)
		if node != null:
			root.add_child(node)
			objs[o.id] = node
	# stairs / ladders that start one level below: their upper half shows through the opening in this floor
	if l - 1 != 0 or true:
		for o in World.all_objects():
			if o.level == l - 1 and o.def.has("portal") and int(o.def["portal"].get("dz", 1)) > 0 and str(o.def["portal"].get("kind", "")) != "elevator" and rc.has_point(o.tile) and full:
				var p2: Node3D = LevelProps.make(o)
				var c2: Vector2 = LevelProps.centre(o)
				p2.position = Vector3(c2.x, LPos.elev(l - 1), c2.y)
				root.add_child(p2)
				objs[-o.id] = p2


func _sync_roof() -> void:
	var show_roof: bool = building >= 0 and viewed != 0 and viewed == int(World.levels.building(building)["max"]) and int(lot.get("wall_mode")) == 0 and str(lot.get("tool")) == "select"
	if not show_roof:
		_set_roof(null)
		return
	var b: Dictionary = World.levels.building(building)
	var sig := "%d|%s|%d" % [building, str(b["roof"]), World.levels.gen]
	if _roof != null and sig == _roof_sig:
		return
	_roof_sig = sig
	var mi := MeshInstance3D.new()
	mi.mesh = LevelMesher.roof(World, building, str(b["roof"]))
	mi.material_override = _floor_mat
	_set_roof(mi)


func _set_roof(mi: MeshInstance3D) -> void:
	if _roof != null:
		_roof.queue_free()
	_roof = mi
	if mi != null:
		mi.name = "Roof"
		add_child(mi)
	else:
		_roof_sig = ""


# ------------------------------------------------------------------ folk + ground

func _update_folk_visibility() -> void:
	var rc: Rect2i = World.levels.building(building)["rect"]
	_update_ground_objects(rc)
	var y0 := LPos.elev(viewed) - 0.4
	var y1 := y0 + LPos.H
	for fid in lot.get("_folk_views"):
		var fv = lot.get("_folk_views")[fid]
		var f = World.get_folk(fid)
		if f == null or not is_instance_valid(fv):
			continue
		var hide := false
		if rc.has_point(f.tile):
			hide = f.level != viewed and not (fv.position.y >= y0 and fv.position.y < y1)      # on the viewed floor, or physically on its stairs
		if hide:
			fv.set_meta("level_hidden", true)
		elif fv.has_meta("level_hidden"):
			fv.remove_meta("level_hidden")


## Rain and snow only reach the ROOF: a collision box over every multi-floor building hides particles that fall into it
## (the precipitation materials use COLLISION_HIDE_ON_CONTACT), so nothing falls through the floors you look into.
func _make_rain_blockers() -> void:
	if _blockers != null:
		_blockers.queue_free()
	_blockers = Node3D.new()
	_blockers.name = "RainBlockers"
	add_child(_blockers)
	for b in World.levels.buildings.values():
		var rc: Rect2i = b["rect"]
		var h: float = World.levels.height_of(int(b["id"]))
		var box := GPUParticlesCollisionBox3D.new()
		box.size = Vector3(rc.size.x, h + 1.0, rc.size.y)
		box.position = Vector3(rc.position.x + rc.size.x * 0.5, (h - 1.0) * 0.5, rc.position.y + rc.size.y * 0.5)
		_blockers.add_child(box)


## Ground-floor objects of the building are not drawn (their labels show through floors) while another floor is looked at.
func _update_ground_objects(rc: Rect2i) -> void:
	var nodes: Dictionary = lot.get("_obj_nodes")
	if viewed == 0:
		_restore_ground_objects()
		return
	for oid in nodes:
		var o = World.get_object(oid)
		if o != null and o.level == 0 and rc.has_point(o.tile) and (nodes[oid] as Node3D).visible:
			(nodes[oid] as Node3D).visible = false
			_hidden_objs[oid] = true


func _restore_ground_objects() -> void:
	if _hidden_objs.is_empty():
		return
	var nodes: Dictionary = lot.get("_obj_nodes")
	for oid in _hidden_objs:
		var o = World.get_object(oid)
		if o != null and nodes.has(oid) and is_instance_valid(nodes[oid]):
			(nodes[oid] as Node3D).visible = not lot.call("_shell_hides", o.tile)
	_hidden_objs.clear()


## Basement view: the ground (floor chunks, walls, objects, folk) inside the building is hidden so you can look down into it.
func _apply_ground_hiding(rc: Rect2i) -> void:
	_hidden_rect = rc
	if lot != null:
		lot.call("set_ground_hidden_rect", rc)
