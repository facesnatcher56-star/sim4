class_name LotView
extends Node3D
## 3D view of the lot: floors, walls (with cut-away), objects, folk, camera rig, picking, build tools.
## Display only: all state lives in the World autoload. Everything is generated from World data and
## kept in sync via World/Events signals. Missing models fall back to coloured boxes.
##
## Controls: WASD / middle-drag pan, wheel zoom, Q/E rotate (4 steps), Z cycle wall mode,
##           R rotate build ghost, Esc / right-click cancel tool, Ctrl+Z undo build.

signal tile_hovered(tile: Vector2i)
signal tile_clicked(tile: Vector2i, button: int)
signal context_requested(kind: String, id: int, tile: Vector2i)   # right-click on something
signal tool_changed(tool: String, arg: String)
signal camera_rotated(step: int)
signal hover_changed(kind: String, id: int)

enum WallMode { UP, CUTAWAY, DOWN }

const WALL_H := 2.6
const WALL_T := 0.16
const CUT_RATIO := 0.16
const CAM_DIST := 60.0
const PITCH := deg_to_rad(35.0)
const ZOOM_MIN := 4.0
const ZOOM_MAX := 34.0

static var instance: LotView = null

var wall_mode: int = WallMode.CUTAWAY
var show_labels: bool = false
var show_names: bool = false:
	set(v):
		show_names = v
		for fv in _folk_views.values():
			fv.show_name = v

var tool: String = "select"          # select | place | wall | floor | sell
var tool_arg: String = ""
var build_rot: int = 0
var selected_kind: String = "none"
var selected_id: int = -1
var hover_kind: String = "none"
var hover_id: int = -1
var hover_tile: Vector2i = Vector2i(-1, -1)

var _pivot: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _floor_root: Node3D
var _wall_root: Node3D
var _obj_root: Node3D
var _folk_root: Node3D
var _fx_root: Node3D
var _floor_mi: MeshInstance3D
var _ground_mi: MeshInstance3D

var _yaw_step: int = 0
var _yaw: float = PI * 0.25
var _yaw_target: float = PI * 0.25
var _zoom: float = 14.0
var _zoom_target: float = 14.0
var _target: Vector3 = Vector3(16, 0, 12)
var _dragging_mmb: bool = false

var _obj_nodes: Dictionary = {}      # object id -> Node3D
var _folk_views: Dictionary = {}     # folk id -> FolkView
var _walls: Array = []               # {node, e, kind, pos, axis, h}
var _doors: Array = []               # {leaf, pos, open}
var _hl_box: MeshInstance3D
var _hl_ring: MeshInstance3D
var _sel_box: MeshInstance3D
var _sel_ring: MeshInstance3D
var _tile_hl: MeshInstance3D
var _ghost: Node3D = null
var _ghost_ok: bool = false
var _ghost_tinted: bool = false
var _ghost_origin: Vector2i = Vector2i.ZERO
var _ghost_rot: int = 0
var _drag_start: Vector3 = Vector3.ZERO
var _dragging_tool: bool = false
var _preview_root: Node3D
var _walls_dirty: bool = false
var _floors_dirty: bool = false
var _cut_dirty: bool = true
var _last_cam_sig: String = ""
var _model_cache: Dictionary = {}


# ------------------------------------------------------------------ lifecycle

func _ready() -> void:
	instance = self
	add_to_group("lot_view")
	_build_rig()
	_build_fx()
	_connect_signals()
	WeatherView.ensure_on(self)    # sky / sun / weather particles / seasons (scripts/world/weather_view.gd)
	rebuild_all()
	var c := Vector2(World.width, World.height) * 0.5
	_target = Vector3(c.x, 0, c.y)
	_snap_camera()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _connect_signals() -> void:
	World.world_reset.connect(rebuild_all)
	World.walls_changed.connect(func(): _walls_dirty = true)
	World.floors_changed.connect(func(): _floors_dirty = true)
	var ev := get_node_or_null("/root/Events")
	if ev:
		ev.object_placed.connect(_on_object_placed)
		ev.object_removed.connect(_on_object_removed)
		ev.object_state_changed.connect(_on_object_state)
		ev.folk_added.connect(_on_folk_added)
		ev.folk_removed.connect(_on_folk_removed)
		ev.selection_changed.connect(_on_selection_changed)
	var clk := get_node_or_null("/root/Clock")
	if clk:
		clk.minute_passed.connect(func(_m): _update_daylight())


func _build_rig() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.62, 0.78, 0.92)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.75, 0.78, 0.85)
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	_sun.light_energy = 1.1
	add_child(_sun)
	_floor_root = _new_root("Floors")
	_wall_root = _new_root("Walls")
	_obj_root = _new_root("Objects")
	_folk_root = _new_root("Folk")
	_fx_root = _new_root("Fx")
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = _zoom
	_cam.near = 0.5
	_cam.far = 200.0
	_cam.current = true
	_pivot.add_child(_cam)
	_update_daylight()


func _new_root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


func _build_fx() -> void:
	_hl_box = _make_hl_box(Color(1.0, 0.9, 0.3, 0.28))
	_hl_ring = _make_hl_ring(Color(1.0, 0.9, 0.3, 0.6))
	_sel_box = _make_hl_box(Color(0.3, 0.9, 1.0, 0.28))
	_sel_ring = _make_hl_ring(Color(0.3, 0.9, 1.0, 0.7))
	_tile_hl = _make_hl_box(Color(1, 1, 1, 0.25))
	_preview_root = Node3D.new()
	_fx_root.add_child(_preview_root)


func _make_hl_box(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mi.mesh = bm
	mi.material_override = _glow_mat(c)
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	return mi


func _make_hl_ring(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 0.03
	mi.mesh = cm
	mi.material_override = _glow_mat(c)
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	return mi


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


func _mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _update_daylight() -> void:
	var clk := get_node_or_null("/root/Clock")
	var h := 12.0
	if clk and clk.has_method("hour_f"):
		h = clk.hour_f()
	# 0 at night .. 1 at noon
	var day := clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0)
	_sun.light_energy = lerpf(0.12, 1.15, day)
	_sun.light_color = Color(1.0, 0.82, 0.62).lerp(Color(1, 0.98, 0.94), day)
	_env.ambient_light_energy = lerpf(0.28, 0.72, day)
	_env.background_color = Color(0.06, 0.08, 0.16).lerp(Color(0.62, 0.78, 0.92), day)


# ------------------------------------------------------------------ rebuild

func rebuild_all() -> void:
	if _floor_root == null:
		return
	_build_floors()
	_build_walls()
	for n in _obj_nodes.values():
		n.queue_free()
	_obj_nodes.clear()
	for o in World.all_objects():
		_add_object_node(o)
	_sync_folk()
	_walls_dirty = false
	_floors_dirty = false


func _build_floors() -> void:
	if _floor_mi:
		_floor_mi.queue_free()
	if _ground_mi:
		_ground_mi.queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in World.height:
		for x in World.width:
			var t := Vector2i(x, y)
			var ft: String = World.get_floor(t)
			var col := Color(str((World.FLOOR_DEFS.get(ft, {}) as Dictionary).get("color", "#6aa84f")))
			if (x + y) % 2 == 1:
				col = col.darkened(0.035)
			var m: float = World.mess.get(t, 0.0)
			if m > 0.0:
				col = col.lerp(Color(0.35, 0.28, 0.2), clampf(m / 10.0, 0.0, 0.6))
			st.set_color(col)
			st.set_normal(Vector3.UP)
			var a := Vector3(x, 0, y)
			var b := Vector3(x + 1, 0, y)
			var c := Vector3(x + 1, 0, y + 1)
			var d := Vector3(x, 0, y + 1)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	_floor_mi = MeshInstance3D.new()
	_floor_mi.mesh = st.commit()
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.roughness = 0.95
	_floor_mi.material_override = fm
	_floor_root.add_child(_floor_mi)
	_ground_mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	_ground_mi.mesh = pm
	_ground_mi.position = Vector3(World.width * 0.5, -0.03, World.height * 0.5)
	_ground_mi.material_override = _mat(Color(0.36, 0.5, 0.3))
	_floor_root.add_child(_ground_mi)
	_floors_dirty = false


func _load_model(path: String) -> PackedScene:
	if _model_cache.has(path):
		return _model_cache[path]
	var ps: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		var r = load(path)
		if r is PackedScene:
			ps = r
	_model_cache[path] = ps
	return ps


func _box_mesh_instance(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	return mi


func _build_walls() -> void:
	for w in _walls:
		w["node"].queue_free()
	_walls.clear()
	_doors.clear()
	for e in World.walls:
		var kind: String = World.walls[e]
		var horizontal: bool = e.z == 0
		var node := Node3D.new()
		node.position = Vector3(e.x + 0.5, 0, e.y) if horizontal else Vector3(e.x, 0, e.y + 0.5)
		if not horizontal:
			node.rotation.y = PI * 0.5
		var visual := _make_wall_visual(kind)
		node.add_child(visual["root"])
		_wall_root.add_child(node)
		if visual.has("leaf") and visual["leaf"] != null:
			_doors.append({"leaf": visual["leaf"], "pos": node.position, "open": 0.0})
		var init_scale := 1.0 if (wall_mode == WallMode.UP or kind == "fence") else CUT_RATIO
		node.scale.y = init_scale
		_walls.append({"node": node, "e": e, "kind": kind, "pos": node.position, "axis": 0 if horizontal else 1,
			"scale": init_scale})
	_walls_dirty = false
	_cut_dirty = true


func _make_wall_visual(kind: String) -> Dictionary:
	var root := Node3D.new()
	var leaf: Node3D = null
	var wall_col := Color(0.9, 0.87, 0.8)
	var def_id := kind
	if kind == "fence":
		root.add_child(_box_mesh_instance(Vector3(1.0, 0.9, 0.06), Vector3(0, 0.45, 0), Color(0.55, 0.38, 0.22)))
		root.set_meta("fence", true)
		return {"root": root, "leaf": null}
	var model_path := "res://assets/models/%s.glb" % ("wall" if kind == "wall" else def_id)
	var ps := _load_model(model_path)
	if ps:
		var inst := ps.instantiate()
		root.add_child(inst)
		if kind == "door":
			leaf = inst.get_node_or_null("leaf")
		return {"root": root, "leaf": leaf}
	# fallbacks
	match kind:
		"wall":
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, 0), wall_col))
		"window":
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, 0.9, WALL_T), Vector3(0, 0.45, 0), wall_col))
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, WALL_H - 1.9, WALL_T), Vector3(0, 1.9 + (WALL_H - 1.9) * 0.5, 0), wall_col))
			var glass := _box_mesh_instance(Vector3(1.0, 1.0, 0.03), Vector3(0, 1.4, 0), Color(0.6, 0.8, 0.95, 0.5))
			(glass.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			root.add_child(glass)
		"door":
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, WALL_H - 2.0, WALL_T), Vector3(0, 2.0 + (WALL_H - 2.0) * 0.5, 0), wall_col))
			root.add_child(_box_mesh_instance(Vector3(0.08, 2.0, WALL_T), Vector3(-0.46, 1.0, 0), Color(0.55, 0.4, 0.25)))
			root.add_child(_box_mesh_instance(Vector3(0.08, 2.0, WALL_T), Vector3(0.46, 1.0, 0), Color(0.55, 0.4, 0.25)))
			leaf = Node3D.new()
			leaf.position = Vector3(-0.42, 0, 0)
			leaf.add_child(_box_mesh_instance(Vector3(0.84, 1.95, 0.05), Vector3(0.42, 0.975, 0), Color(0.62, 0.45, 0.28)))
			root.add_child(leaf)
	return {"root": root, "leaf": leaf}


# ------------------------------------------------------------------ objects

func _yaw_for_rot(rot: int) -> float:
	var f := WorldObject.rotate_vec(Vector2(0, 1), rot)
	return atan2(-f.x, -f.y)


## Visual (model or fallback) for a definition, origin at footprint centre, unrotated (front = model -Z).
func make_def_visual(def_id: String) -> Node3D:
	var d: Dictionary = World.get_def(def_id)
	var root := Node3D.new()
	var ps := _load_model(str(d.get("model", "")))
	if ps:
		root.add_child(ps.instantiate())
		if show_labels:
			root.add_child(_label(str(d.get("label", def_id)), float(d.get("height", 1.0)) + 0.3))
		return root
	var sz: Array = d.get("size", [1, 1])
	var h: float = float(d.get("height", 1.0))
	var col := Color(str(d.get("color", "#aaaaaa")))
	var w := float(sz[0]) * 0.92
	var dp := float(sz[1]) * 0.92
	root.add_child(_box_mesh_instance(Vector3(w, h, dp), Vector3(0, h * 0.5, 0), col))
	# front marker (model front = -Z)
	root.add_child(_box_mesh_instance(Vector3(w * 0.5, h * 0.25, 0.04), Vector3(0, h * 0.7, -dp * 0.5 - 0.01), col.darkened(0.45)))
	root.add_child(_label(str(d.get("label", def_id)), h + 0.25))
	return root


func _label(text: String, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.006
	l.position = Vector3(0, y, 0)
	l.no_depth_test = true
	l.name = "Label"
	return l


func _add_object_node(o) -> void:
	if _obj_nodes.has(o.id):
		_obj_nodes[o.id].queue_free()
		_obj_nodes.erase(o.id)
	if o.is_wall_mounted():
		_walls_dirty = true   # door/window visuals come from the wall edge
		return
	var node := Node3D.new()
	node.name = "obj_%d" % o.id
	var c: Vector2 = o.center2d()
	node.position = Vector3(c.x, 0, c.y)
	node.rotation.y = _yaw_for_rot(o.rot)
	if o.is_floor_layer():
		node.position.y = 0.005
	node.add_child(make_def_visual(o.def_id))
	_obj_root.add_child(node)
	_obj_nodes[o.id] = node
	_refresh_object_visual(o)


func _refresh_object_visual(o) -> void:
	var node: Node3D = _obj_nodes.get(o.id, null)
	if node == null:
		return
	var broken: bool = o.is_broken()
	var flag := node.get_node_or_null("BrokenFlag")
	if broken and flag == null:
		var l := _label("!", float(o.def.get("height", 1.0)) + 0.5)
		l.name = "BrokenFlag"
		l.modulate = Color(1, 0.2, 0.2)
		l.font_size = 64
		node.add_child(l)
	elif not broken and flag != null:
		flag.queue_free()
	# fallback boxes: dim when "off"
	var vis: Node = node.get_child(0) if node.get_child_count() > 0 else null
	if vis and vis.get_child_count() > 0 and vis.get_child(0) is MeshInstance3D:
		var mi: MeshInstance3D = vis.get_child(0)
		if mi.material_override is StandardMaterial3D:
			var base := Color(str(o.def.get("color", "#aaaaaa")))
			var on: bool = bool(o.state.get("on", true))
			(mi.material_override as StandardMaterial3D).albedo_color = base if on else base.darkened(0.2)
			if o.def.has("decor_scale_state"):
				(mi.material_override as StandardMaterial3D).albedo_color = base.lerp(Color(0.5, 0.4, 0.2), 1.0 - o.ratio(str(o.def["decor_scale_state"])))


func _on_object_placed(id: int) -> void:
	var o = World.get_object(id)
	if o:
		_add_object_node(o)


func _on_object_removed(id: int) -> void:
	if _obj_nodes.has(id):
		_obj_nodes[id].queue_free()
		_obj_nodes.erase(id)
	_walls_dirty = true   # may have been a door/window (cheap to rebuild)
	if selected_id == id and selected_kind == "object":
		_set_selected("none", -1)


func _on_object_state(id: int, _key: String) -> void:
	if id < 0:
		_floors_dirty = true   # mess puddles tint the floor
		return
	var o = World.get_object(id)
	if o:
		_refresh_object_visual(o)


# ------------------------------------------------------------------ folk

func _sync_folk() -> void:
	for id in _folk_views.keys():
		if World.get_folk(id) == null:
			_folk_views[id].queue_free()
			_folk_views.erase(id)
	for f in World.all_folk():
		if not _folk_views.has(f.id):
			_on_folk_added(f.id)


func _on_folk_added(id: int) -> void:
	if _folk_views.has(id) or World.get_folk(id) == null:
		return
	var fv := FolkView.new()
	fv.name = "folk_%d" % id
	_folk_root.add_child(fv)
	fv.setup(id)
	fv.show_name = show_names
	_folk_views[id] = fv


func _on_folk_removed(id: int) -> void:
	if _folk_views.has(id):
		_folk_views[id].queue_free()
		_folk_views.erase(id)
	if selected_id == id and selected_kind == "folk":
		_set_selected("none", -1)


func get_folk_view(id: int) -> FolkView:
	return _folk_views.get(id, null)


# ------------------------------------------------------------------ selection

func _on_selection_changed(kind: String, id: int) -> void:
	selected_kind = kind
	selected_id = id


func _set_selected(kind: String, id: int) -> void:
	selected_kind = kind
	selected_id = id
	var ev := get_node_or_null("/root/Events")
	if ev:
		ev.selection_changed.emit(kind, id)


func select(kind: String, id: int) -> void:
	_set_selected(kind, id)


# ------------------------------------------------------------------ camera

func _snap_camera() -> void:
	_yaw = _yaw_target
	_zoom = _zoom_target
	_apply_camera()


func _apply_camera() -> void:
	_pivot.position = _target
	var off := Vector3(0, sin(PITCH), cos(PITCH)) * CAM_DIST
	off = off.rotated(Vector3.UP, _yaw)
	_cam.position = off
	_cam.look_at(_pivot.global_position, Vector3.UP)
	_cam.size = _zoom


func rotate_camera(step: int) -> void:
	_yaw_step = posmod(_yaw_step + step, 4)
	_yaw_target += step * PI * 0.5
	camera_rotated.emit(_yaw_step)
	_cut_dirty = true


func set_zoom(z: float) -> void:
	_zoom_target = clampf(z, ZOOM_MIN, ZOOM_MAX)


func focus_tile(t: Vector2i) -> void:
	_target = Vector3(t.x + 0.5, 0, t.y + 0.5)


func focus_on(kind: String, id: int) -> void:
	if kind == "folk" and _folk_views.has(id):
		_target = _folk_views[id].position
	elif kind == "object":
		var o = World.get_object(id)
		if o:
			var c: Vector2 = o.center2d()
			_target = Vector3(c.x, 0, c.y)


func cycle_wall_mode() -> int:
	wall_mode = (wall_mode + 1) % 3
	_cut_dirty = true
	return wall_mode


func set_wall_mode(m: int) -> void:
	wall_mode = clampi(m, 0, 2)
	_cut_dirty = true


## Horizontal unit vector from the focus point toward the camera.
func _cam_dir() -> Vector3:
	return Vector3(0, 0, 1).rotated(Vector3.UP, _yaw)


func _pan(right_amt: float, fwd_amt: float) -> void:
	var d := _cam_dir()
	var fwd := -d
	var right := Vector3(-fwd.z, 0, fwd.x)   # screen right on the ground
	_target += right * right_amt + fwd * fwd_amt
	_target.x = clampf(_target.x, 0.0, float(World.width))
	_target.z = clampf(_target.z, 0.0, float(World.height))


# ------------------------------------------------------------------ process

func _process(delta: float) -> void:
	# keyboard pan
	if get_viewport().gui_get_focus_owner() == null:
		var dx := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
		var dz := int(Input.is_key_pressed(KEY_W)) - int(Input.is_key_pressed(KEY_S))
		if dx != 0 or dz != 0:
			var sp := _zoom * 0.9 * delta
			_pan(dx * sp, dz * sp)
	_yaw = lerp_angle(_yaw, _yaw_target, clampf(delta * 10.0, 0.0, 1.0))
	if absf(angle_difference(_yaw, _yaw_target)) < 0.0005:
		_yaw = _yaw_target
	_zoom = lerpf(_zoom, _zoom_target, clampf(delta * 12.0, 0.0, 1.0))
	_apply_camera()
	if _floors_dirty:
		_build_floors()
	if _walls_dirty:
		_build_walls()
	_update_walls(delta)
	_update_doors(delta)
	_update_hover()
	_update_highlights()
	_update_ghost()


func _update_walls(delta: float) -> void:
	var d := _cam_dir()
	for w in _walls:
		var target := 1.0
		if w["kind"] == "fence":
			target = 1.0
		elif wall_mode == WallMode.DOWN:
			target = CUT_RATIO
		elif wall_mode == WallMode.CUTAWAY:
			var p: Vector3 = w["pos"]
			var comp: float
			var rel: float
			if w["axis"] == 0:     # along X, faces +-Z
				comp = d.z
				rel = (p.z - _target.z) * signf(d.z)
			else:                  # along Z, faces +-X
				comp = d.x
				rel = (p.x - _target.x) * signf(d.x)
			if absf(comp) > 0.25 and rel > -0.5:
				target = CUT_RATIO
		var cur: float = w["scale"]
		if not is_equal_approx(cur, target):
			cur = move_toward(cur, target, delta * 4.0)
			w["scale"] = cur
			(w["node"] as Node3D).scale.y = maxf(cur, 0.01)


func _update_doors(delta: float) -> void:
	if _doors.is_empty():
		return
	for dd in _doors:
		var leaf: Node3D = dd["leaf"]
		if not is_instance_valid(leaf):
			continue
		var gp: Vector3 = dd["pos"]
		var near := false
		for fv in _folk_views.values():
			if fv.position.distance_to(gp) < 1.3:
				near = true
				break
		dd["open"] = move_toward(dd["open"], 1.0 if near else 0.0, delta * 4.0)
		leaf.rotation.y = -dd["open"] * deg_to_rad(95)


# ------------------------------------------------------------------ picking

func ground_point(mp: Vector2) -> Variant:
	var o := _cam.project_ray_origin(mp)
	var dir := _cam.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return null
	var t := -o.y / dir.y
	if t < 0:
		return null
	return o + dir * t


func tile_at_screen(mp: Vector2) -> Vector2i:
	var g = ground_point(mp)
	if g == null:
		return Vector2i(-1, -1)
	return Vector2i(floori(g.x), floori(g.z))


func _object_aabb(o) -> AABB:
	var h: float = float(o.def.get("height", 1.0))
	if o.is_wall_mounted():
		var e: Vector3i = World.mount_edge(o.tile, o.rot)
		if e.z == 0:
			return AABB(Vector3(e.x + 0.05, 0, e.y - 0.12), Vector3(0.9, 2.0, 0.24))
		return AABB(Vector3(e.x - 0.12, 0, e.y + 0.05), Vector3(0.24, 2.0, 0.9))
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for t in o.footprint():
		lo = lo.min(Vector2(t))
		hi = hi.max(Vector2(t) + Vector2.ONE)
	return AABB(Vector3(lo.x, 0, lo.y), Vector3(hi.x - lo.x, h, hi.y - lo.y))


func pick(mp: Vector2) -> Dictionary:
	var ro := _cam.project_ray_origin(mp)
	var rd := _cam.project_ray_normal(mp)
	var best_t := INF
	var kind := "none"
	var id := -1
	for fid in _folk_views:
		var fv: FolkView = _folk_views[fid]
		if not fv.visible:
			continue
		var box := AABB(fv.position + Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.8, 0.6))
		if fv.pose == "lie":
			box = AABB(fv.position + Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
		var hit = box.intersects_ray(ro, rd)
		if hit != null:
			var t := ro.distance_to(hit) - 0.3   # prefer folk when overlapping furniture
			if t < best_t:
				best_t = t
				kind = "folk"
				id = fid
	for o in World.all_objects():
		var bb := _object_aabb(o)
		var hit = bb.intersects_ray(ro, rd)
		if hit != null:
			var t := ro.distance_to(hit)
			if o.is_floor_layer():
				t += 2.0
			if t < best_t:
				best_t = t
				kind = "object"
				id = o.id
	return {"kind": kind, "id": id, "tile": tile_at_screen(mp)}


func _mouse_over_gui() -> bool:
	var vp := get_viewport()
	if vp.has_method("gui_get_hovered_control"):
		return vp.gui_get_hovered_control() != null
	return false


func _update_hover() -> void:
	if _mouse_over_gui():
		_set_hover("none", -1, Vector2i(-1, -1))
		return
	var mp := get_viewport().get_mouse_position()
	if tool == "select" or tool == "sell":
		var p := pick(mp)
		_set_hover(p["kind"], p["id"], p["tile"])
	else:
		_set_hover("none", -1, tile_at_screen(mp))


func _set_hover(kind: String, id: int, tile: Vector2i) -> void:
	if tile != hover_tile:
		hover_tile = tile
		tile_hovered.emit(tile)
	if kind != hover_kind or id != hover_id:
		hover_kind = kind
		hover_id = id
		hover_changed.emit(kind, id)


func _place_highlight(box: MeshInstance3D, ring: MeshInstance3D, kind: String, id: int) -> void:
	box.visible = false
	ring.visible = false
	if kind == "folk" and _folk_views.has(id):
		ring.visible = true
		ring.position = Vector3(_folk_views[id].position.x, 0.03, _folk_views[id].position.z)
		ring.scale = Vector3(1.0, 1.0, 1.0)
	elif kind == "object":
		var o = World.get_object(id)
		if o:
			var bb := _object_aabb(o)
			box.visible = true
			box.position = bb.get_center()
			box.scale = bb.size + Vector3(0.06, 0.06, 0.06)


func _update_highlights() -> void:
	var hk := hover_kind
	var hid := hover_id
	if hk == selected_kind and hid == selected_id:
		hk = "none"
	_place_highlight(_hl_box, _hl_ring, hk, hid)
	_place_highlight(_sel_box, _sel_ring, selected_kind, selected_id)
	_tile_hl.visible = false
	if tool != "select" and tool != "sell" and World.in_bounds(hover_tile) and tool != "place" and not _dragging_tool:
		_tile_hl.visible = true
		_tile_hl.position = Vector3(hover_tile.x + 0.5, 0.02, hover_tile.y + 0.5)
		_tile_hl.scale = Vector3(1, 0.04, 1)


func screen_pos(kind: String, id: int) -> Vector2:
	var p := Vector3.ZERO
	if kind == "folk" and _folk_views.has(id):
		p = _folk_views[id].head_position() + Vector3(0, 0.3, 0)
	elif kind == "object":
		var o = World.get_object(id)
		if o == null:
			return Vector2(-1, -1)
		var bb := _object_aabb(o)
		p = bb.get_center() + Vector3(0, bb.size.y * 0.5 + 0.2, 0)
	else:
		return Vector2(-1, -1)
	if _cam.is_position_behind(p):
		return Vector2(-1, -1)
	return _cam.unproject_position(p)


## Screen position (viewport pixels) to anchor pie menus / balloons. (-1,-1) when unknown.
static func screen_pos_of(kind: String, id: int) -> Vector2:
	if instance == null:
		return Vector2(-1, -1)
	return instance.screen_pos(kind, id)


# ------------------------------------------------------------------ build tools

func set_tool(t: String, arg: String = "") -> void:
	tool = t
	tool_arg = arg
	_dragging_tool = false
	_clear_preview()
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if t == "place":
		_ghost = make_def_visual(arg)
		_ghost_tinted = false
		_apply_ghost_tint(_ghost, Color(0.3, 1.0, 0.3, 0.45))
		_fx_root.add_child(_ghost)
	tool_changed.emit(tool, tool_arg)


func _apply_ghost_tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		n.material_override = _glow_mat(c)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is Label3D:
		n.visible = false
	for ch in n.get_children():
		_apply_ghost_tint(ch, c)


func _clear_preview() -> void:
	for ch in _preview_root.get_children():
		ch.queue_free()


func _update_ghost() -> void:
	if _ghost == null or tool != "place":
		return
	var mp := get_viewport().get_mouse_position()
	var g = ground_point(mp)
	if g == null or _mouse_over_gui():
		_ghost.visible = false
		return
	_ghost.visible = true
	var d: Dictionary = World.get_def(tool_arg)
	var tile := Vector2i(floori(g.x), floori(g.z))
	var rot := build_rot
	if str(d.get("mount", "")) == "wall":
		var fx: float = g.x - tile.x
		var fz: float = g.z - tile.y
		var m := minf(minf(fx, 1.0 - fx), minf(fz, 1.0 - fz))
		if m == fz:
			rot = 0
		elif m == 1.0 - fx:
			rot = 1
		elif m == 1.0 - fz:
			rot = 2
		else:
			rot = 3
		var e := World.mount_edge(tile, rot)
		_ghost.position = Vector3(e.x + 0.5, 0, e.y) if e.z == 0 else Vector3(e.x, 0, e.y + 0.5)
		_ghost.rotation.y = 0.0 if e.z == 0 else PI * 0.5
	else:
		var s: Array = d.get("size", [1, 1])
		var off := WorldObject.rotate_vec(Vector2((int(s[0]) - 1) * 0.5, (int(s[1]) - 1) * 0.5), rot)
		_ghost.position = Vector3(tile.x + 0.5 + off.x, 0.0, tile.y + 0.5 + off.y)
		_ghost.rotation.y = _yaw_for_rot(rot)
	_ghost_origin = tile
	_ghost_rot = rot
	var ok := World.can_place(tool_arg, tile, rot)
	if ok != _ghost_ok or not _ghost_tinted:
		_ghost_ok = ok
		_ghost_tinted = true
		_apply_ghost_tint(_ghost, Color(0.3, 1.0, 0.3, 0.45) if ok else Color(1.0, 0.25, 0.25, 0.45))


func _notify(text: String, kind: String = "warn") -> void:
	var ev := get_node_or_null("/root/Events")
	if ev:
		ev.emit_signal("notification", text, kind)


func _vertex_at(g: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi(g.x), 0, World.width), clampi(roundi(g.z), 0, World.height))


func _constrain_line(a: Vector2i, b: Vector2i) -> Vector2i:
	var d := b - a
	if absi(d.x) >= absi(d.y):
		return Vector2i(b.x, a.y)
	return Vector2i(a.x, b.y)


func _tool_press(mp: Vector2) -> void:
	var g = ground_point(mp)
	if g == null:
		return
	match tool:
		"place":
			var id := World.buy_place(tool_arg, _ghost_origin, _ghost_rot)
			if id < 0:
				_notify(World.last_error if World.last_error != "" else "Can't place here")
		"wall", "floor":
			_dragging_tool = true
			_drag_start = g
		"sell":
			var p := pick(mp)
			if p["kind"] == "object":
				World.sell_object(p["id"])
			elif p["kind"] == "none" and World.in_bounds(p["tile"]):
				World.sell_object_at(p["tile"])


func _tool_motion(mp: Vector2) -> void:
	if not _dragging_tool:
		return
	var g = ground_point(mp)
	if g == null:
		return
	_clear_preview()
	if tool == "wall":
		var a := _vertex_at(_drag_start)
		var b := _constrain_line(a, _vertex_at(g))
		var col := Color(0.4, 0.8, 1.0, 0.6) if tool_arg != "none" else Color(1.0, 0.3, 0.3, 0.6)
		for e in World._line_edges(a, b):
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.0, 0.4, 0.2) if e.z == 0 else Vector3(0.2, 0.4, 1.0)
			mi.mesh = bm
			mi.material_override = _glow_mat(col)
			mi.position = Vector3(e.x + 0.5, 0.2, e.y) if e.z == 0 else Vector3(e.x, 0.2, e.y + 0.5)
			_preview_root.add_child(mi)
	elif tool == "floor":
		var a := Vector2i(floori(_drag_start.x), floori(_drag_start.z))
		var b := Vector2i(floori(g.x), floori(g.z))
		var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(hi.x - lo.x + 1, 0.05, hi.y - lo.y + 1)
		mi.mesh = bm
		mi.material_override = _glow_mat(Color(1, 1, 1, 0.35))
		mi.position = Vector3(lo.x + bm.size.x * 0.5, 0.03, lo.y + bm.size.z * 0.5)
		_preview_root.add_child(mi)


func _tool_release(mp: Vector2) -> void:
	if not _dragging_tool:
		return
	_dragging_tool = false
	var g = ground_point(mp)
	_clear_preview()
	if g == null:
		return
	if tool == "wall":
		var a := _vertex_at(_drag_start)
		var b := _constrain_line(a, _vertex_at(g))
		if a != b:
			var n := World.set_wall_line(a, b, tool_arg if tool_arg != "" else "wall")
			if n == 0 and World.last_error != "":
				_notify(World.last_error)
	elif tool == "floor":
		var a := Vector2i(floori(_drag_start.x), floori(_drag_start.z))
		var b := Vector2i(floori(g.x), floori(g.z))
		var n := World.paint_floor_rect(a, b, tool_arg)
		if n == 0 and World.last_error != "":
			_notify(World.last_error)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				rotate_camera(-1)
			KEY_E:
				rotate_camera(1)
			KEY_Z:
				if event.ctrl_pressed:
					World.undo_last()
				else:
					cycle_wall_mode()
			KEY_R:
				build_rot = posmod(build_rot + 1, 4)
			KEY_ESCAPE:
				if tool != "select":
					set_tool("select")
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(_zoom_target * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(_zoom_target * 1.1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_mmb = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_press(mb.position)
			else:
				_tool_release(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_right_press(mb.position)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _dragging_mmb:
			var wpp := _zoom / maxf(1.0, float(get_viewport().get_visible_rect().size.y))
			_pan(-mm.relative.x * wpp, mm.relative.y * wpp / sin(PITCH))
		else:
			_tool_motion(mm.position)


func _on_left_press(mp: Vector2) -> void:
	var p := pick(mp)
	tile_clicked.emit(p["tile"], MOUSE_BUTTON_LEFT)
	if tool == "select":
		_set_selected(p["kind"], p["id"])
	else:
		_tool_press(mp)


func _on_right_press(mp: Vector2) -> void:
	if tool != "select":
		set_tool("select")
		return
	var p := pick(mp)
	tile_clicked.emit(p["tile"], MOUSE_BUTTON_RIGHT)
	if p["kind"] != "none":
		context_requested.emit(p["kind"], p["id"], p["tile"])
