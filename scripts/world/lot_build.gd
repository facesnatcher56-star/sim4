extends "res://scripts/world/lot_picking.gd"
## LotView layer: Build tools (place ghost, walls, floors, sell) and input handling.


# ------------------------------------------------------------------ build tools

func set_tool(t: String, arg: String = "") -> void:
	tool = t
	tool_arg = arg
	_dragging_tool = false
	_clear_preview()
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_set_grid_visible(t != "select")
	if t == "place":
		_ghost = make_def_visual(arg)
		_ghost_tinted = false
		_add_ghost_footprint(_ghost, arg)
		_apply_ghost_tint(_ghost, Color(0.1, 0.95, 0.3, 0.6))
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
	var lvl := build_level()
	var gy := LPos.elev(lvl)
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
		_ghost.position = Vector3(e.x + 0.5, gy, e.y) if e.z == 0 else Vector3(e.x, gy, e.y + 0.5)
		_ghost.rotation.y = 0.0 if e.z == 0 else PI * 0.5
	else:
		var s: Array = d.get("size", [1, 1])
		var off := WorldObject.rotate_vec(Vector2((int(s[0]) - 1) * 0.5, (int(s[1]) - 1) * 0.5), rot)
		_ghost.position = Vector3(tile.x + 0.5 + off.x, gy, tile.y + 0.5 + off.y)
		_ghost.rotation.y = _yaw_for_rot(rot)
	_ghost_origin = tile
	_ghost_rot = rot
	var ok := World.can_place(tool_arg, tile, rot, lvl)
	if ok != _ghost_ok or not _ghost_tinted:
		_ghost_ok = ok
		_ghost_tinted = true
		_apply_ghost_tint(_ghost, Color(0.1, 0.95, 0.3, 0.6) if ok else Color(1.0, 0.2, 0.2, 0.55))


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
			var id := World.buy_place(tool_arg, _ghost_origin, _ghost_rot, -1, build_level())
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
				var so = World.object_at(p["tile"], build_level())
				if so != null:
					World.sell_object(so.id)


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
			mi.position = Vector3(e.x + 0.5, 0.2 + _plane_y, e.y) if e.z == 0 else Vector3(e.x, 0.2 + _plane_y, e.y + 0.5)
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
		mi.position = Vector3(lo.x + bm.size.x * 0.5, 0.03 + _plane_y, lo.y + bm.size.z * 0.5)
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
			var n := World.set_wall_line(a, b, tool_arg if tool_arg != "" else "wall", -1, build_level())
			if n == 0 and World.last_error != "":
				_notify(World.last_error)
	elif tool == "floor":
		var a := Vector2i(floori(_drag_start.x), floori(_drag_start.z))
		var b := Vector2i(floori(g.x), floori(g.z))
		var n := World.paint_floor_rect(a, b, tool_arg, -1, build_level())
		if n == 0 and World.last_error != "":
			_notify(World.last_error)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("sim_rotate_left"):
			rotate_camera(-1)
		elif event.is_action_pressed("sim_rotate_right"):
			rotate_camera(1)
		elif event.is_action_pressed("sim_undo"):
			World.undo_last()
		elif event.is_action_pressed("sim_build_rotate"):
			build_rot = posmod(build_rot + 1, 4)
		elif event.keycode == KEY_ESCAPE and tool != "select":
			set_tool("select")
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.is_action("sim_zoom_in"):
			set_zoom(_zoom_target * (1.0 / 0.9 if GameSettings.invert_zoom() else 0.9))
		elif mb.pressed and mb.is_action("sim_zoom_out"):
			set_zoom(_zoom_target * (0.9 if GameSettings.invert_zoom() else 1.1))
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


# ------------------------------------------------------------------ build-mode feedback

## Flat tile-sized quad under the ghost so the footprint (and its valid / invalid colour) is obvious.
func _add_ghost_footprint(ghost: Node3D, def_id: String) -> void:
	var d: Dictionary = World.get_def(def_id)
	if str(d.get("mount", "")) == "wall":
		return
	var sz: Array = d.get("size", [1, 1])
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(float(sz[0]), 0.04, float(sz[1]))
	mi.mesh = bm
	mi.position.y = 0.02
	mi.name = "Foot"
	ghost.add_child(mi)


func _set_grid_visible(on: bool) -> void:
	if on and _grid_mi == null:
		_grid_mi = _make_grid()
		_fx_root.add_child(_grid_mi)
	if _grid_mi != null:
		_grid_mi.visible = on


## Thin tile lines over the whole lot, shown while any build tool is active.
func _make_grid() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var area := Rect2i(0, 0, World.width, World.height)
	if World.regions.has_regions() and not World.regions.home().is_empty():
		area = World.regions.home()["rect"]       # big map: only the player's own lot is buildable
	for x in range(area.position.x, area.end.x + 1):
		st.add_vertex(Vector3(x, 0.025, area.position.y))
		st.add_vertex(Vector3(x, 0.025, area.end.y))
	for z in range(area.position.y, area.end.y + 1):
		st.add_vertex(Vector3(area.position.x, 0.025, z))
		st.add_vertex(Vector3(area.end.x, 0.025, z))
	var mi := MeshInstance3D.new()
	mi.name = "BuildGrid"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
