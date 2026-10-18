extends "res://scripts/world/lot_walls.gd"
## LotView layer: Mouse picking, hover + selection markers, screen anchors.


# ------------------------------------------------------------------ selection

func _on_selection_changed(kind: String, id: int) -> void:
	selected_kind = kind
	selected_id = id
	_begin_follow(kind, id)


func _set_selected(kind: String, id: int) -> void:
	selected_kind = kind
	selected_id = id
	var ev := get_node_or_null("/root/Events")
	if ev:
		ev.selection_changed.emit(kind, id)


func select(kind: String, id: int) -> void:
	_set_selected(kind, id)


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
	var gp = ground_point(mp)       # only objects near where the ray meets the ground can be hit (hundreds of objects on the big map)
	for o in World.all_objects():
		if gp != null and (absf(o.tile.x + 0.5 - gp.x) > 9.0 or absf(o.tile.y + 0.5 - gp.z) > 9.0):
			continue
		var node = _obj_nodes.get(o.id, null)
		if node != null and not node.visible:
			continue          # behind a standing building shell
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
		ring.position = Vector3(_folk_views[id].position.x, 0.04, _folk_views[id].position.z)
		ring.scale = Vector3(1.0, 0.25, 1.0) * (1.0 if ring == _sel_ring else 0.85)
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
	_sel_arrow.visible = selected_kind == "folk" and _folk_views.has(selected_id) and _folk_views[selected_id].visible
	if _sel_arrow.visible:
		var hp: Vector3 = _folk_views[selected_id].head_position()
		_sel_arrow.position = hp + Vector3(0, 0.45 + sin(Time.get_ticks_msec() * 0.005) * 0.06, 0)
	_update_hover_label()
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


# ------------------------------------------------------------------ x-ray (folk hidden behind walls / tall furniture)

## Throttled: marks each folk occluded or not so FolkView can draw its silhouette through the blocker.
func _update_xray(delta: float) -> void:
	_xray_t -= delta
	if _xray_t > 0.0:
		return
	_xray_t = 0.12
	var toward := _cam.global_transform.basis.z      # unit vector from the scene toward the camera
	var blockers: Array = []
	for w in _walls:
		if float(w["scale"]) > 0.5 and w["kind"] != "fence":
			var p: Vector3 = w["pos"]
			var half := Vector3(0.58, WALL_H * 0.5, WALL_T) if w["axis"] == 0 else Vector3(WALL_T, WALL_H * 0.5, 0.58)
			blockers.append(AABB(p + Vector3(0, WALL_H * 0.5, 0) - half, half * 2.0))
	for o in World.all_objects():
		if o.is_wall_mounted() or o.is_floor_layer() or float(o.def.get("height", 1.0)) < 1.3:
			continue
		blockers.append(_object_aabb(o))
	for fv in _folk_views.values():
		var occluded := false
		if fv.visible:
			var spots := [fv.head_position() - Vector3(0, 0.25, 0), fv.global_position + Vector3(0, 0.6, 0)]
			for hp in spots:
				for bb in blockers:
					if (bb as AABB).grow(0.05).has_point(hp):
						continue
					var hit = (bb as AABB).intersects_ray(hp, toward)
					if hit != null and (hit - hp).dot(toward) > 0.05:
						occluded = true
						break
				if occluded:
					break
		fv.set_xray(occluded)


func _update_hover_label() -> void:
	_hover_label.visible = false
	if hover_kind == "folk" and _folk_views.has(hover_id) and _folk_views[hover_id].visible:
		var f = World.get_folk(hover_id)
		if f != null and not show_names:
			_hover_label.text = str(f.name)
			_hover_label.position = _folk_views[hover_id].head_position() + Vector3(0, 0.55, 0)
			_hover_label.visible = true
	elif hover_kind == "object":
		var o = World.get_object(hover_id)
		if o != null:
			var bb := _object_aabb(o)
			_hover_label.text = str(o.def.get("label", o.def_id))
			_hover_label.position = bb.get_center() + Vector3(0, bb.size.y * 0.5 + 0.3, 0)
			_hover_label.visible = true
