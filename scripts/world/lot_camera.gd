extends "res://scripts/world/lot_state.gd"
## LotView layer: Camera rig: orbit/zoom/pan, focus, wall-mode cycling.


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
	if lo.x > hi.x:       # empty lot: whole lot
		lo = Vector2.ZERO
		hi = Vector2(World.width, World.height)
	var c := (lo + hi) * 0.5
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
	_zoom_target = clampf(need, ZOOM_MIN, ZOOM_MAX)
	_zoom = _zoom_target
	_apply_camera()
