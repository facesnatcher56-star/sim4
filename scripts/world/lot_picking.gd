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
	var t := (_plane_y - o.y) / dir.y
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
		var wh := 2.0 * _wall_scale(e)        # a cut-down wall carries its window / door down with it
		if e.z == 0:
			return AABB(Vector3(e.x + 0.05, LPos.elev(o.level), e.y - 0.12), Vector3(0.9, wh, 0.24))
		return AABB(Vector3(e.x - 0.12, LPos.elev(o.level), e.y + 0.05), Vector3(0.24, wh, 0.9))
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for t in o.footprint():
		lo = lo.min(Vector2(t))
		hi = hi.max(Vector2(t) + Vector2.ONE)
	return AABB(Vector3(lo.x, LPos.elev(o.level), lo.y), Vector3(hi.x - lo.x, h, hi.y - lo.y))


const CEILING_BOX := 0.5             # live play: a ceiling light answers only where the ray meets the fitting itself (this wide, 0.4 tall), not the empty air column under it

const HEAD_H := 1.8                  # things whose box the ray enters above this lose to folk and furniture on the floor under the mouse
const FOOTPRINT_BONUS := 1.2         # an object standing on the floor point under the mouse beats a taller one in front of it
const CEILING_PENALTY := 100.0       # ceiling lights only answer when nothing else is under the mouse


## The small box of the fitting itself, hanging from the top of an object's tall box. In an empty house the lights are the only objects, so a full-height box would win every hover over bare floor.
func _ceiling_box(o) -> AABB:
	var full := _object_aabb(o)
	var c := full.get_center()
	return AABB(Vector3(c.x - CEILING_BOX * 0.5, full.end.y - 0.4, c.z - CEILING_BOX * 0.5), Vector3(CEILING_BOX, 0.4, CEILING_BOX))


## Current height scale (1 = full wall, CUT_RATIO = cut down) of the wall edge an object hangs on.
func _wall_scale(e: Vector3i) -> float:
	var w = _wall_by_edge.get(e, null)
	if w != null:
		return clampf(float(w["scale"]), CUT_RATIO, 1.0)
	return 1.0 if wall_mode == WallMode.UP else CUT_RATIO


## Can the player act on this object in live play? Windows, doors, rugs and pillars are scenery: no hover, no label.
func is_usable_object(o) -> bool:
	if o.is_wall_mounted():
		return false
	return not (o.def.get("interactions", []) as Array).is_empty() or o.def.has("portal") or o.has_tag("grave") or o.is_broken()


func _building_tools() -> bool:
	return build_mode or tool != "select"


## Which objects the mouse may land on: everything in Build/Buy, only usable things (and no wall-hung ones) in live play.
func _pickable(o) -> bool:
	return _building_tools() or is_usable_object(o)


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
			var t := ro.distance_to(hit) - 2.0   # folk beat the furniture they stand next to
			if t < best_t:
				best_t = t
				kind = "folk"
				id = fid
	var gp = ground_point(mp)       # only objects near where the ray meets the ground can be hit (hundreds of objects on the big map)
	var gt := Vector2i(-1, -1) if gp == null else Vector2i(floori(gp.x), floori(gp.z))
	for o in World.all_objects():
		if gp != null and (absf(o.tile.x + 0.5 - gp.x) > 9.0 or absf(o.tile.y + 0.5 - gp.z) > 9.0):
			continue
		var node = _obj_nodes.get(o.id, null)
		if node != null and not node.visible:
			continue          # behind a standing building shell
		if level_view != null and not level_view.object_shown(o):
			continue          # on a floor that is not the one being looked at
		if not _pickable(o):
			continue
		var ceiling_live: bool = o.has_tag("ceiling") and not _building_tools()
		var bb := _ceiling_box(o) if ceiling_live else _object_aabb(o)
		var hit = bb.intersects_ray(ro, rd)
		if hit != null:
			var t := ro.distance_to(hit)
			var on_spot: bool = gp != null and (o.footprint() as Array).has(gt)
			if o.is_floor_layer():
				t += 2.0
			if on_spot:
				t -= FOOTPRINT_BONUS
			elif (hit as Vector3).y > LPos.elev(o.level) + HEAD_H:
				t += 2.0                      # a light or a shelf top high above the room is not what the player points at
			if ceiling_live:
				t += CEILING_PENALTY
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
	var slot := "sel" if ring == _sel_ring else "hover"
	box.visible = false
	ring.visible = false
	var outlined: Node3D = null
	if kind == "folk" and _folk_views.has(id):
		ring.visible = true
		ring.position = Vector3(_folk_views[id].position.x, 0.04, _folk_views[id].position.z)
		ring.scale = Vector3(1.0, 0.25, 1.0) * (1.0 if ring == _sel_ring else 0.85)
	elif kind == "object":
		var o = World.get_object(id)
		if o:
			outlined = _object_node(o)
			if outlined == null:      # wall-hung / undrawn visuals: a thin slab on the floor under the object, never a box around it
				var bb := _object_aabb(o)
				box.visible = true
				box.position = Vector3(bb.get_center().x, bb.position.y + 0.03, bb.get_center().z)
				box.scale = Vector3(bb.size.x, 0.05, bb.size.z)
	_set_outline(slot, outlined)


## The drawn node of an object (ground floor: LotView's, upper floors: LevelView's).
func _object_node(o) -> Node3D:
	var n = _obj_nodes.get(o.id, null)
	if n == null and level_view != null:
		n = level_view.object_node(o.id)
	return n if n != null and is_instance_valid(n) and (n as Node3D).visible else null


func _outline_material(slot: String) -> StandardMaterial3D:
	if not _outline_mats.has(slot):
		var m := StandardMaterial3D.new()      # inverted hull: a coloured shell a little bigger than the mesh, front faces culled
		m.albedo_color = Color(0.3, 0.9, 1.0) if slot == "sel" else Color(1.0, 0.86, 0.25)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_FRONT
		m.grow = true
		m.grow_amount = 0.025
		_outline_mats[slot] = m
	return _outline_mats[slot]


func _set_outline(slot: String, node: Node3D) -> void:
	var prev = _outlined.get(slot, null)
	if prev == node:
		return
	if prev != null and is_instance_valid(prev):
		_apply_overlay(prev, null)
	_outlined[slot] = node
	if node != null:
		_apply_overlay(node, _outline_material(slot))


func _apply_overlay(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = m
	for c in n.get_children():
		_apply_overlay(c, m)


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
	_update_see_walls(toward)
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


## Folk whose action must stay readable: the selected folk, and any housemate of theirs who is doing something (not just walking). A wall that stands
## between the camera and one of them is cut down (CUTAWAY mode; see _update_walls) so the silhouette is left to everybody else.
func _focus_folk_views() -> Array:
	var out: Array = []
	if selected_kind != "folk" or not _folk_views.has(selected_id):
		return out
	var sel = World.get_folk(selected_id)
	var hid: int = int(sel.household_id) if sel != null else -1
	for f in World.all_folk():
		var v = _folk_views.get(f.id, null)
		if v == null or not is_instance_valid(v) or not v.visible:
			continue
		if int(f.id) == selected_id or (hid > 0 and int(f.household_id) == hid and f.current != null):
			out.append(v)
	return out


## Throttled with the x-ray pass. The test uses each wall's full height whatever its current scale, so a wall that was just cut stays in the set (no flicker).
func _update_see_walls(toward: Vector3) -> void:
	_see_walls.clear()
	var focus := _focus_folk_views()
	if focus.is_empty() or wall_mode != WallMode.CUTAWAY:
		return
	for w in _walls:
		if w["kind"] == "fence" or w["free"]:
			continue
		var p: Vector3 = w["pos"]
		var half := Vector3(0.58, WALL_H * 0.5, WALL_T) if w["axis"] == 0 else Vector3(WALL_T, WALL_H * 0.5, 0.58)
		var bb := AABB(p + Vector3(0, WALL_H * 0.5, 0) - half, half * 2.0)
		for fv in focus:
			var hit = false
			for hp in [fv.head_position() - Vector3(0, 0.25, 0), fv.global_position + Vector3(0, 0.6, 0)]:
				if bb.grow(0.05).has_point(hp):
					continue
				var h = bb.intersects_ray(hp, toward)
				if h != null and (h - hp).dot(toward) > 0.05:
					hit = true
					break
			if hit:
				_see_walls[w["e"]] = true
				break


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
		if o != null and (_building_tools() or is_usable_object(o)):     # live play names only what folk can use
			var bb := _object_aabb(o)
			_hover_label.text = Graves.hover_text(o) if o.has_tag("grave") and Graves.hover_text(o) != "" else str(o.def.get("label", o.def_id))
			var fire_tip: String = Fire.hover_text(o)         # fire risk / protection lines (FireRules.hover_text)
			if fire_tip != "":
				_hover_label.text += "\n" + fire_tip
			_hover_label.position = bb.get_center() + Vector3(0, bb.size.y * 0.5 + 0.3, 0)
			_hover_label.visible = true
