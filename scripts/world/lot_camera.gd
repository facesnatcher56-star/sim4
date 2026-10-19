extends "res://scripts/world/lot_state.gd"
## LotView layer: Camera rig: orbit/zoom/pan, focus, wall-mode cycling.


# ------------------------------------------------------------------ camera

func _snap_camera() -> void:
	_yaw = _yaw_target
	_zoom = _zoom_target
	_apply_camera()


func _apply_camera() -> void:
	_pivot.position = _target
	CameraFocus.look_at("cam", _target.x, _target.z)       # where we look is simulated in full (Tiers anchor; moves only after 6 tiles)
	var dist := maxf(CAM_DIST, _zoom * 1.1 + 5.0)      # zoomed far out (whole-map view) the camera must stay in front of the ground it sees
	var off := Vector3(0, sin(PITCH), cos(PITCH)) * dist
	off = off.rotated(Vector3.UP, _yaw)
	_cam.position = off
	_cam.look_at(_pivot.global_position, Vector3.UP)
	_cam.size = _zoom
	_cam.far = dist + 200.0
	if _sun != null:
		_sun.directional_shadow_max_distance = maxf(90.0, dist + _zoom * 0.7)


func rotate_camera(step: int) -> void:
	_yaw_step = posmod(_yaw_step + step, 4)
	_yaw_target += step * PI * 0.5
	camera_rotated.emit(_yaw_step)
	_cut_dirty = true


func _zoom_max() -> float:
	return ZOOM_MAX_BIG if World.regions.has_regions() else ZOOM_MAX


func set_zoom(z: float) -> void:
	_zoom_target = clampf(z, ZOOM_MIN, _zoom_max())


func focus_tile(t: Vector2i) -> void:
	_follow_id = -1
	_target = Vector3(t.x + 0.5, 0, t.y + 0.5)


func focus_on(kind: String, id: int) -> void:
	if kind == "folk" and _folk_views.has(id):
		_target = _folk_views[id].position
		_begin_follow(kind, id)
	elif kind == "object":
		_follow_id = -1
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


## Big map: selecting a folk makes the camera glide after them until the player pans by hand.
func _begin_follow(kind: String, id: int) -> void:
	_follow_id = id if (kind == "folk" and World.regions.has_regions()) else -1


## Per frame: smooth follow of the selected folk (instant with "Reduce motion"), always inside the map.
func _update_follow(delta: float) -> void:
	if _follow_id < 0:
		return
	var fv = _folk_views.get(_follow_id, null)
	if fv == null or not is_instance_valid(fv):
		_follow_id = -1
		return
	var goal := Vector3(fv.position.x, _target.y, fv.position.z)      # y belongs to LevelView (the viewed floor)
	if GameSettings.reduce_motion():
		_target = goal
	else:
		_target = _target.lerp(goal, clampf(1.0 - exp(-delta * FOLLOW_RATE), 0.0, 1.0))
	_target.x = clampf(_target.x, 0.0, float(World.width))
	_target.z = clampf(_target.z, 0.0, float(World.height))


func _pan(right_amt: float, fwd_amt: float) -> void:
	_follow_id = -1
	var d := _cam_dir()
	var fwd := -d
	var right := Vector3(-fwd.z, 0, fwd.x)   # screen right on the ground
	_target += right * right_amt + fwd * fwd_amt
	_target.x = clampf(_target.x, 0.0, float(World.width))
	_target.z = clampf(_target.z, 0.0, float(World.height))


## Hook for later layers (lot_chunks builds the framed chunks at once, no pop-in).
func _on_framed() -> void:
	pass


## Centre the camera on the built-up part of the lot (walls + objects) and zoom so all of it is on screen.
func frame_home() -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for e in World.walls:
		lo = lo.min(Vector2(e.x, e.y))
		hi = hi.max(Vector2(e.x + (1 if e.z == 0 else 0), e.y + (1 if e.z == 1 else 0)))
	for o in World.all_objects():
		for t in o.footprint():
			lo = lo.min(Vector2(t))
			hi = hi.max(Vector2(t) + Vector2.ONE)
	if World.regions.has_regions():          # big map: the player's own lot
		var home := World.regions.home()
		if not home.is_empty():
			var hr: Rect2i = home["rect"]
			lo = Vector2(hr.position)
			hi = Vector2(hr.end)
	if lo.x > hi.x:       # empty lot: whole lot
		lo = Vector2.ZERO
		hi = Vector2(World.width, World.height)
	var c := (lo + hi) * 0.5
	_follow_id = -1
	_target = Vector3(c.x, 0, c.y)
	_yaw = _yaw_target
	_apply_camera()
	var b := _cam.global_transform.basis
	var aspect := 1.78
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size.y > 0.0:
		aspect = vp.get_visible_rect().size.x / vp.get_visible_rect().size.y
	var mx := Vector2.ZERO
	for x in [lo.x, hi.x]:
		for z in [lo.y, hi.y]:
			for y in [0.0, WALL_H]:
				var d := Vector3(x, y, z) - _target
				mx = mx.max(Vector2(absf(d.dot(b.x)), absf(d.dot(b.y))))
	var need := maxf(mx.y * 2.0, mx.x * 2.0 / aspect) * 1.12
	_zoom_target = clampf(need, ZOOM_MIN, _zoom_max())
	_zoom = _zoom_target
	_apply_camera()
	_on_framed()
