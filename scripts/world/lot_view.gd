class_name LotView
extends "res://scripts/world/lot_shells.gd"
## 3D view of the lot (see lot_state.gd for the layer chain): rig, floors, objects, folk, main loop.
## Display only: all state lives in the World autoload; kept in sync via World/Events signals.

static var instance: LotView = null


# ------------------------------------------------------------------ lifecycle

func _ready() -> void:
	instance = self
	add_to_group("lot_view")
	_init_chunk_materials()
	_build_rig()
	_build_fx()
	_connect_signals()
	LevelView.ensure_on(self)      # upper floors / basements of multi-floor buildings (scripts/world/level_view.gd)
	level_view.view_changed.connect(return_to_cutaway)     # changing floor or building: back to the readable Cutaway view
	LookOverlay.ensure_on(self)    # vignette + grain of the current look (scripts/world/look_overlay.gd)
	WeatherView.ensure_on(self)    # sky / sun / weather particles / seasons (scripts/world/weather_view.gd)
	ClutterView.ensure_on(self)    # floor clutter that grows with a room's mess (scripts/world/clutter_view.gd; view only)
	OrderMarker.ensure_on(self)    # task 58b: where the player's character is going (scripts/world/order_marker.gd; view only)
	WearView.ensure_on(self)       # district wear dressing near the camera: litter, graffiti, weeds, cracks (scripts/world/wear_view.gd; view only)
	ObjectStateView.ensure_on(self)    # objects show their state: soil, grime, sparks, burners, screens (scripts/world/object_state_view.gd; view only)
	FireView.ensure_on(self)       # flames / smoke / scorch marks (scripts/world/fire_view.gd)
	PlotView.ensure_on(self)       # scaffolding, building sites and finished buildings on the reserved plots of the east side (scripts/world/plot_view.gd; view only)
	VehicleView.ensure_on(self)    # cars, buses, taxis, emergency vehicles, bikes on the roads near the camera (scripts/world/vehicle_view.gd; view only)
	DisasterView.ensure_on(self)   # siren / tornado / flood / quake shake / blizzard / blackout visuals (scripts/world/disaster_view.gd)
	HelpWantedView.ensure_on(self)  # "Help wanted" cards in the windows of businesses that are hiring (scripts/world/help_wanted_view.gd; view only)
	rebuild_all()
	frame_home()


func _exit_tree() -> void:
	if instance == self:
		instance = null
		CameraFocus.release("cam")


func _connect_signals() -> void:
	World.world_reset.connect(rebuild_all)
	World.world_reset.connect(func(): call_deferred("frame_home"))   # new / loaded / travelled-to lot: show all of it
	World.walls_changed.connect(func(): _walls_dirty = true)
	World.floors_changed.connect(func(): _floors_dirty = true)
	WearLayer.bus.changed.connect(func(_lot): _refresh_wall_wear(); _refresh_poor_objects())      # task 41a: wealth / district wear changed
	Looks.bus.changed.connect(func(_id): rebuild_all())     # a new visual style (Settings / --look): rebuild floors, walls and shells with its tints
	var ev := get_node_or_null("/root/Events")
	if ev:
		ev.object_placed.connect(_on_object_placed)
		ev.object_removed.connect(_on_object_removed)
		ev.object_state_changed.connect(_on_object_state)
		ev.folk_added.connect(_on_folk_added)
		ev.folk_removed.connect(_on_folk_removed)
		ev.game_event.connect(_on_collapse_event)
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
	_sel_arrow = _make_sel_arrow()
	_hover_label = _make_hover_label()
	_preview_root = Node3D.new()
	_fx_root.add_child(_preview_root)


func _make_hl_box(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mi.mesh = bm
	var bmat := _glow_mat(c)
	bmat.render_priority = -2      # under the hover / name labels
	mi.material_override = bmat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	return mi


func _make_hl_ring(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()      # a flat ring on the ground: reads clearly on any floor colour
	tm.inner_radius = 0.44
	tm.outer_radius = 0.56
	tm.rings = 24
	tm.ring_segments = 4
	mi.mesh = tm
	var m := _glow_mat(Color(c.r, c.g, c.b, 0.95))
	m.render_priority = 2
	mi.material_override = m
	mi.scale = Vector3(1, 0.25, 1)
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	var disc := MeshInstance3D.new()    # faint fill inside the ring
	var cm := CylinderMesh.new()
	cm.top_radius = 0.46
	cm.bottom_radius = 0.46
	cm.height = 0.01
	disc.mesh = cm
	disc.material_override = _glow_mat(Color(c.r, c.g, c.b, 0.3))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(disc)
	return mi


## Name of whatever the mouse is over (objects only get a label on hover, never permanently).
func _make_hover_label() -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0016
	l.font_size = 36
	l.outline_size = 12
	l.outline_modulate = Color(0.05, 0.07, 0.12, 0.95)
	l.no_depth_test = true
	l.render_priority = 10
	l.visible = false
	_fx_root.add_child(l)
	return l


## Cone floating above the selected folk (drawn through walls so the player can always find them).
func _make_sel_arrow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.0
	cm.height = 0.34
	cm.radial_segments = 4
	mi.mesh = cm
	var m := _glow_mat(Color(0.3, 0.9, 1.0, 1.0))
	m.no_depth_test = true
	m.render_priority = 5
	mi.material_override = m
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	return mi


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
	_rebuild_chunks_all()
	_build_walls()
	if _grid_mi != null:
		_grid_mi.queue_free()      # lot size may have changed
		_grid_mi = null
		_set_grid_visible(tool != "select")
	for n in _obj_nodes.values():
		n.queue_free()
	_obj_nodes.clear()
	for o in World.all_objects():
		_add_object_node(o)
	_sync_folk()
	_rebuild_shells()
	for sh in _shells.values():
		_set_interior_visible(sh["rect"], false)
	_walls_dirty = false
	_floors_dirty = false


func _add_object_node(o) -> void:
	if o.level != 0:
		return        # upper floors and basements are drawn by LevelView (only the floor being looked at)
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
	var props: Node3D = LevelProps.make(o)          # stairs / lifts / pillars: procedural parts instead of a plain box
	if props != null:
		node.rotation.y = 0.0
		node.add_child(props)
	else:
		node.add_child(make_def_visual(o.def_id, o.id))
	node.visible = not _shell_hides(o.tile)
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
	ObjectStateView.refresh(self, o, node)      # task 33.3: state -> look (data/object_visuals.json)


## Task 41a: re-resolve the look of objects whose lot's wealth score changed (poor variants appear / go).
func _refresh_poor_objects() -> void:
	for id in _obj_nodes.keys():
		var o = World.get_object(int(id))
		if o != null and ObjectVisualRules.has_rules(str(o.def_id)):
			_refresh_object_visual(o)


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


var _collapsing: Dictionary = {}       # folk ids about to die (Aging.kill emits folk_collapsing first)

func _on_collapse_event(ev_name: String, payload: Dictionary) -> void:
	if ev_name == "folk_collapsing":
		_collapsing[int(payload.get("folk_id", -1))] = true

func _on_folk_removed(id: int) -> void:
	if _folk_views.has(id):
		var fv = _folk_views[id]
		_folk_views.erase(id)
		if _collapsing.has(id) and not GameSettings.reduce_motion():
			var tw: Tween = fv.create_tween()       # a short, quiet collapse: sink and shrink, no gore
			tw.tween_property(fv, "scale", Vector3(1.0, 0.05, 1.0), 0.9)
			tw.tween_callback(fv.queue_free)
		else:
			fv.queue_free()
	_collapsing.erase(id)
	if selected_id == id and selected_kind == "folk":
		_set_selected("none", -1)


func get_folk_view(id: int) -> FolkView:
	return _folk_views.get(id, null)


# ------------------------------------------------------------------ process

func _process(delta: float) -> void:
	# keyboard pan
	if get_viewport().gui_get_focus_owner() == null:
		var dx := int(Input.is_action_pressed("sim_pan_right")) - int(Input.is_action_pressed("sim_pan_left"))
		var dz := int(Input.is_action_pressed("sim_pan_up")) - int(Input.is_action_pressed("sim_pan_down"))
		if dx != 0 or dz != 0:
			var sp := _zoom * 0.9 * delta * GameSettings.pan_speed()
			_pan(dx * sp, dz * sp)
	_update_follow(delta)
	_yaw = lerp_angle(_yaw, _yaw_target, clampf(delta * 10.0, 0.0, 1.0))
	if absf(angle_difference(_yaw, _yaw_target)) < 0.0005:
		_yaw = _yaw_target
	_zoom = lerpf(_zoom, _zoom_target, clampf(delta * 12.0, 0.0, 1.0))
	_apply_camera()
	_update_chunks()
	if _walls_dirty:
		_build_walls()
	_sync_wall_chunks()
	_update_walls(delta)
	_update_doors(delta)
	_update_hover()
	_update_highlights()
	_update_xray(delta)
	_update_ghost()
	_update_shells(delta)
	_enforce_ground_hidden()


## Basement view: hide the ground (floor chunks, walls, objects) of the chunks the building stands in. Empty rect = show again.
func set_ground_hidden_rect(rc: Rect2i) -> void:
	_ground_hidden = rc
	_cut_ground_plane(rc)
	if rc.size == Vector2i.ZERO:
		for c in _chunks:
			(_chunks[c]["root"] as Node3D).visible = _vis.has(c) or _vis.is_empty()
		for c in _wall_nodes:
			(_wall_nodes[c]["root"] as Node3D).visible = true
		for oid in _obj_nodes:
			var o = World.get_object(oid)
			if o != null and o.level == 0:
				(_obj_nodes[oid] as Node3D).visible = not _shell_hides(o.tile)


## The big grass plane under everything would cover a basement: while one is shown it becomes four strips around the building.
func _cut_ground_plane(rc: Rect2i) -> void:
	if _ground_mi == null:
		return
	var ring := get_node_or_null("GroundRing")
	if ring != null:
		ring.queue_free()
	_ground_mi.visible = rc.size == Vector2i.ZERO
	if rc.size == Vector2i.ZERO:
		return
	var root := Node3D.new()
	root.name = "GroundRing"
	add_child(root)
	var big := 400.0
	var strips := [Rect2(-big, -big, big + rc.position.x, 2.0 * big), Rect2(rc.end.x, -big, big, 2.0 * big),
		Rect2(rc.position.x, -big, rc.size.x, big + rc.position.y), Rect2(rc.position.x, rc.end.y, rc.size.x, big)]
	for r in strips:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = (r as Rect2).size
		mi.mesh = pm
		mi.position = Vector3(r.position.x + r.size.x * 0.5, -0.03, r.position.y + r.size.y * 0.5)
		mi.material_override = _ground_mi.material_override
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# the pit: soil floor and sides so the basement sits in the ground instead of floating over the sky
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.36, 0.27, 0.19)
	soil.cull_mode = BaseMaterial3D.CULL_DISABLED
	var depth := 3.3
	var cx := rc.position.x + rc.size.x * 0.5
	var cz := rc.position.y + rc.size.y * 0.5
	for b in [[Vector3(rc.size.x, 0.1, rc.size.y), Vector3(cx, -depth, cz)],
			[Vector3(rc.size.x, depth, 0.05), Vector3(cx, -depth * 0.5, rc.position.y)], [Vector3(rc.size.x, depth, 0.05), Vector3(cx, -depth * 0.5, rc.end.y)],
			[Vector3(0.05, depth, rc.size.y), Vector3(rc.position.x, -depth * 0.5, cz)], [Vector3(0.05, depth, rc.size.y), Vector3(rc.end.x, -depth * 0.5, cz)]]:
		var bm := BoxMesh.new()
		bm.size = b[0]
		var bi := MeshInstance3D.new()
		bi.mesh = bm
		bi.position = b[1]
		bi.material_override = soil
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bi)


func _enforce_ground_hidden() -> void:
	if _ground_hidden.size == Vector2i.ZERO:
		return
	for c in _chunks:
		if World.regions.chunk_rect(c).intersects(_ground_hidden):
			(_chunks[c]["root"] as Node3D).visible = false
	for c in _wall_nodes:
		if World.regions.chunk_rect(c).intersects(_ground_hidden):
			(_wall_nodes[c]["root"] as Node3D).visible = false
	for oid in _obj_nodes:
		var o = World.get_object(oid)
		if o != null and o.level == 0 and _ground_hidden.has_point(o.tile):
			(_obj_nodes[oid] as Node3D).visible = false


## Screen position (viewport pixels) to anchor pie menus / balloons. (-1,-1) when unknown.
static func screen_pos_of(kind: String, id: int) -> Vector2:
	if instance == null:
		return Vector2(-1, -1)
	return instance.screen_pos(kind, id)
