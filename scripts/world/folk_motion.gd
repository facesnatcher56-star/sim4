extends "res://scripts/world/folk_look.gd"
## FolkView layer: path following, facing, social partner alignment.


const MAX_SLICE := 24     # a tile jump longer than this (fast forward, fast travel, loading) is not animated: the folk is simply there


func _update_waypoints(f) -> void:
	if f.tile == _last_tile:
		return
	var d: Vector2i = f.tile - _last_tile
	var far: int = maxi(absi(d.x), absi(d.y))
	if _last_tile.x < -900:
		position = World.tile_to_pos(f.tile)
		_waypoints.clear()
	elif far <= 1:
		_waypoints.append(World.tile_to_pos(f.tile))
	else:
		var seg: Array = _route_slice(f, _last_tile, f.tile)
		if seg.is_empty() and far <= 8:
			seg = World.find_path(_last_tile, f.tile)          # short hop off any known route
		if seg.is_empty() or seg.size() > MAX_SLICE:
			position = World.tile_to_pos(f.tile)               # teleport (fast travel, fast forward, unreachable, loaded game)
			_waypoints.clear()
		else:
			for t in seg:
				_waypoints.append(World.tile_to_pos(t))
	_last_tile = f.tile


## The walker's own route (computed once by Interaction.start) between two tiles it passed: the view follows sidewalks and
## crosswalks exactly as routed, it never plans a path of its own for a long walk.
func _route_slice(f, a: Vector2i, b: Vector2i) -> Array:
	if f.current == null or f.current.path.is_empty():
		return []
	var p: Array = f.current.path
	var i: int = p.find(b)
	var j: int = p.find(a)
	if i < 0 or i <= j or (j < 0 and maxi(absi(p[0].x - a.x), absi(p[0].y - a.y)) > 1):
		return []
	return p.slice(j + 1, i + 1)


func _is_running(f) -> bool:
	return f.current != null and str(f.current.state) == "running"


func _partner_view(id: int) -> Node3D:
	var par := get_parent()
	if par != null:
		var n := par.get_node_or_null("folk_%d" % id)
		if n is Node3D:
			return n
	return null


func _partner_pos(id: int) -> Vector3:
	var pv := _partner_view(id)
	if pv != null:
		return pv.position
	var pf = World.get_folk(id)
	return World.tile_to_pos(pf.tile) if pf != null else position


## Finds who we are interacting with socially (as the actor, or as the target of somebody's running interaction).
func _find_partner(f) -> void:
	_partner_id = -1
	_partner_role = ""
	_partner_inter = null
	if _is_running(f) and str(f.current.target_kind) == "folk" and int(f.current.target_id) >= 0:
		_partner_id = int(f.current.target_id)
		_partner_role = "actor"
		_partner_inter = f.current
		return
	for o in World.all_folk():
		if o.id == f.id or o.current == null:
			continue
		if str(o.current.state) == "running" and str(o.current.target_kind) == "folk" and int(o.current.target_id) == f.id:
			_partner_id = o.id
			_partner_role = "target"
			_partner_inter = o.current
			return


func _resolve_target(f) -> void:
	var tile_pos: Vector3 = World.tile_to_pos(f.tile)
	_target = tile_pos
	_elev = 0.0
	_target_pose = "idle"
	var face_vec := Vector2.ZERO
	var running := _is_running(f)
	_res_tick += 1
	if _res_tick % 8 == 1:
		_res_cache = World.reservation_of(folk_id)
		_find_partner(f)
	var handled := false
	if _res_cache is Array and running:
		var o = World.get_object(_res_cache[0])
		var si: int = _res_cache[1]
		if o != null and o.slots_reserved.get(si, -1) == folk_id and f.tile == o.slot_tile(si):
			var sp: String = o.slot_pose(si)
			if sp == "stand":
				_target_pose = _use_pose(f)
				var c: Vector2 = o.center2d()
				face_vec = c - Vector2(tile_pos.x, tile_pos.z)
				_target = tile_pos
			else:
				_target_pose = sp
				var up: Vector2 = o.slot_use_pos(si)
				_target = Vector3(up.x, 0, up.y)
				_elev = o.slot_elev(si)
				face_vec = o.front_dir()
			handled = true
	if not handled and _partner_role != "" and _waypoints.is_empty():
		# face-to-face: the actor steps up to the target, the target turns to the actor
		var pp := _partner_pos(_partner_id)
		if _partner_role == "actor":
			var dist := float((anim_map().get("social", {}) as Dictionary).get("stand_distance", 0.7))
			var d := _pick_social_dir(pp)
			_target = Vector3(pp.x + d.x * dist, 0, pp.z + d.y * dist)
			face_vec = Vector2(pp.x - _target.x, pp.z - _target.z)
		else:
			face_vec = Vector2(pp.x - position.x, pp.z - position.z)
		_target_pose = "use"
		handled = true
	if not handled:
		var ov: Variant = World.folk_pose.get(folk_id, null)
		if ov is Dictionary and str(ov["pose"]) != "":
			_target_pose = str(ov["pose"])
			var fc: Vector2i = ov.get("face", Vector2i.ZERO)
			if fc != Vector2i.ZERO:
				face_vec = Vector2(fc - f.tile)
		elif str(f.posture) == "sit" or str(f.posture) == "lie":
			_target_pose = str(f.posture)
		elif running:
			_target_pose = _use_pose(f)
	if face_vec.length() > 0.01:
		_target_yaw = atan2(-face_vec.x, -face_vec.y)


func _pick_social_dir(partner_pos: Vector3) -> Vector2:
	## Side of the partner we stand on: prefer the side we walked in from, else any open neighbouring tile.
	if _social_dir != Vector2.ZERO:
		return _social_dir
	var pt: Vector2i = World.pos_to_tile(partner_pos)
	var came := Vector2i(-1 if _last_dir.x > 0.5 else (1 if _last_dir.x < -0.5 else 0), -1 if _last_dir.y > 0.5 else (1 if _last_dir.y < -0.5 else 0))
	var cands: Array[Vector2i] = []
	if came != Vector2i.ZERO and (came.x == 0 or came.y == 0):
		cands.append(came)
	for c in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not cands.has(c):
			cands.append(c)
	var pick := Vector2i(1, 0)
	for c in cands:
		var nt: Vector2i = pt + c
		if World.is_walkable(nt) and World.edge_open(pt, nt):
			pick = c
			break
	_social_dir = Vector2(pick)
	return _social_dir


func _use_pose(f) -> String:
	if f.current != null:
		var id := str(f.current.def_id)
		if id.contains("eat") or id.contains("meal") or id.contains("snack"):
			return "eat"
	return "use"


func _move(delta: float) -> void:
	var mult := _speed_mult()
	_speed_now = 0.0
	if mult <= 0.0:
		_moving = false
		return
	var speed := BASE_SPEED * mult * (1.0 + 0.4 * float(_waypoints.size())) * Weather.walk_speed_mult_at(Vector2i(int(floor(position.x)), int(floor(position.z))))
	var goal: Vector3 = _waypoints[0] if not _waypoints.is_empty() else _target
	var to := goal - position
	to.y = 0
	var dist := to.length()
	var step := speed * delta
	_moving = dist > 0.03
	if dist <= step:
		position.x = goal.x
		position.z = goal.z
		_speed_now = dist / maxf(delta, 0.0001)
		if not _waypoints.is_empty():
			_waypoints.remove_at(0)
	else:
		var dir := to / dist
		position += dir * step
		_speed_now = speed
		_last_dir = Vector2(dir.x, dir.z)
		if _waypoints.size() > 0 or _target_pose in ["idle", "walk"]:
			_target_yaw = atan2(-dir.x, -dir.z)
	# smooth turning (faster while locomoting)
	var rate := 14.0 if _moving else 9.0
	facing_yaw = lerp_angle(facing_yaw, _target_yaw, clampf(delta * rate, 0.0, 1.0))
