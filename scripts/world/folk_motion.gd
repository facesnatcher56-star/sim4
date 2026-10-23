extends "res://scripts/world/folk_look.gd"
## FolkView layer: path following, facing, social partner alignment.


const MAX_WP_PER_FRAME := 64     # task 56: waypoints the drawn walk may pass in one frame (the time skip on a slow frame)
const MAX_SLICE := 24     # a tile jump longer than this x the game speed (fast travel, loading) is not animated: the folk is simply there


## Task 56: the longest route slice still walked at this game speed (a faster game moves the sim further between frames).
func _max_slice() -> int:
	return int(float(MAX_SLICE) * maxf(_speed_mult(), 1.0))


## Point of a (tile, level): tile centre, y = the floor (or the stair step) of that level.
func _wp(t: Vector2i, lv: int) -> Vector3:
	var p: Vector3 = World.tile_to_pos(t)
	p.y = World.walk_y(t, lv)
	return p


## The folk's own multi-floor route (Interaction.path3, computed once) between two positions it passed, as 3D waypoints.
func _route_slice3(f, a: Vector3i, b: Vector3i) -> Array:
	if f.current == null or f.current.path3.is_empty():
		return []
	var p: Array = f.current.path3
	var i: int = p.find(b)
	var j: int = p.find(a)
	if i < 0 or i <= j or (j < 0 and maxi(absi(p[0].x - a.x), absi(p[0].y - a.y)) > 1):
		return []
	var out: Array = []
	for q in p.slice(j + 1, i + 1):
		out.append(_wp(Vector2i(q.x, q.y), q.z))
	return out


var _lead_id := 0          # task 58: the walk whose route the view was handed at once (instance id), 0 = none
var _lead_fed := 0         # route tiles of it already handed to the walk
var _lead_pace := 0.0      # the sim's walking pace on it (tiles per real second)


## Task 58: a walk is drawn from the frame it starts. The view takes the walk's own route (Interaction.path) and keeps one tile ahead of
## where the sim walker is, counting the part of a game minute already gone (Clock._accum), so it never waits for f.tile to change.
## Returns true while it leads (the tile-jump replay of _update_waypoints is then skipped). Multi-floor routes and rides keep the old way.
func _lead_walk(f) -> bool:
	var ir = f.current
	if ir == null or str(ir.state) != "walking" or ir.path.is_empty() or not ir.path3.is_empty() or ir.travel_total <= 0.0 or ir.params.has("ride_minutes"):
		if _lead_id != 0:
			_lead_id = 0
			_last_tile = f.tile          # the route was already handed over: nothing to replay
			_last_level = f.level
		return false
	var p: Array = ir.path
	if ir.get_instance_id() != _lead_id:
		_lead_id = ir.get_instance_id()
		_waypoints.clear()
		_lead_fed = 0
		var here := Vector2(position.x, position.z)
		for i in mini(3, p.size() - 1):          # a new route starts at the sim tile, which the view may already be past: don't walk back
			var a: Vector3 = World.tile_to_pos(p[i])
			var b: Vector3 = World.tile_to_pos(p[i + 1])
			if here.distance_to(Vector2(b.x, b.z)) < Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)):
				_lead_fed = i + 1
	var clk := get_node_or_null("/root/Clock")
	var frac_min: float = float(clk.get("_accum")) if clk != null and int(clk.get("speed")) > 0 else 0.0
	var lead_in: float = float(ir.params.get("lead_in", 0.0))          # the part of a minute gone before the click (SimDirector.start_now)
	var done: float = maxf(ir.travel_total - ir.travel_left + minf(frac_min, ir.travel_left) - lead_in, 0.0)
	var walk_min: float = maxf(ir.travel_total - lead_in, 0.001)
	var want: int = clampi(int(done / walk_min * float(p.size())) + 1, 1, p.size())          # one tile ahead of the sim walker
	while _lead_fed < want:
		_waypoints.append(_wp(p[_lead_fed], f.level))
		_lead_fed += 1
	_lead_pace = float(p.size()) / walk_min * (float(clk.call("real_rate")) if clk != null else 1.0)
	_level_y = World.walk_y(f.tile, f.level)
	_last_tile = f.tile
	_last_level = f.level
	return true


## While leading a walk the view heads for the last route tile it was given, not for the sim tile behind it.
func _lead_target(f) -> void:
	if _lead_id != 0 and _lead_fed > 0 and f.current != null and not f.current.path.is_empty():
		var t: Vector3 = World.tile_to_pos(f.current.path[_lead_fed - 1])
		_target = Vector3(t.x, 0.0, t.z)


func _update_waypoints(f) -> void:
	_level_y = World.walk_y(f.tile, f.level)
	if f.tile == _last_tile and f.level == _last_level:
		return
	var d: Vector2i = f.tile - _last_tile
	var far: int = maxi(absi(d.x), absi(d.y))
	if _last_tile.x < -900:
		position = _wp(f.tile, f.level)
		_ybase = position.y
		_waypoints.clear()
	elif f.level != _last_level or (far > 1 and f.current != null and not f.current.path3.is_empty()):
		var seg3: Array = _route_slice3(f, Vector3i(_last_tile.x, _last_tile.y, _last_level), Vector3i(f.tile.x, f.tile.y, f.level))
		if seg3.is_empty() or seg3.size() > _max_slice():
			position = _wp(f.tile, f.level)                  # teleport between floors (loaded game, fast forward)
			_ybase = position.y
			_waypoints.clear()
		else:
			for w in seg3:
				_waypoints.append(w)
	elif far <= 1:
		_waypoints.append(_wp(f.tile, f.level))
	else:
		var seg: Array = _route_slice(f, _last_tile, f.tile)
		if seg.is_empty() and far <= 8:
			seg = World.find_path(_last_tile, f.tile)          # short hop off any known route
		if seg.is_empty() or seg.size() > _max_slice():
			position = _wp(f.tile, f.level)                    # teleport (fast travel, fast forward, unreachable, loaded game)
			_ybase = position.y
			_waypoints.clear()
		else:
			for t in seg:
				_waypoints.append(_wp(t, f.level))
	_last_tile = f.tile
	_last_level = f.level


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
			if sp != "stand" and FolkClipRules.stands_at_slot(f):
				sp = "stand"                                              # a chore on a bed or toilet: stand beside it
			var seat = _seat_at_slot(o, si, f)
			if sp == "stand" and seat != null:
				_target_pose = "sit"                                      # the chair at the desk, computer or table: use it sitting, facing the object
				var sp2: Vector2 = seat.slot_use_pos(0)
				_target = Vector3(sp2.x, 0, sp2.y)
				_elev = seat.slot_elev(0)
				face_vec = o.center2d() - sp2
			elif sp == "stand":
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
			var reach := _social_len if _social_len > 0.0 else dist
			_target = Vector3(pp.x + d.x * reach, 0, pp.z + d.y * reach)
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
	if _res_tick % 6 == 0:
		_update_separation(f)
	if _spaced_pose():
		_target.x += _sep_off.x
		_target.z += _sep_off.y
	if face_vec.length() > 0.01:
		_target_yaw = atan2(-face_vec.x, -face_vec.y)


## The seat object standing on the use tile of a slot flagged sit_if_seat (desk, computer, table, bar), or null.
func _seat_at_slot(o, si: int, f) -> Variant:
	if not o.slot_flag(si, "sit_if_seat"):
		return null
	var s = World.object_at(o.slot_tile(si), int(f.level))
	if s != null and s != o and s.has_tag("seat") and s.slot_count() > 0 and s.slot_pose(0) == "sit":
		return s
	return null


func _pick_social_dir(partner_pos: Vector3) -> Vector2:
	## Side of the partner we stand on: prefer the side we walked in from, else any open neighbouring tile.
	var pt: Vector2i = World.pos_to_tile(partner_pos)
	if _social_dir != Vector2.ZERO and pt == _social_pt:
		return _social_dir                    # (the side is kept while the partner stays on its tile)
	_social_pt = pt
	var came := Vector2i(-1 if _last_dir.x > 0.5 else (1 if _last_dir.x < -0.5 else 0), -1 if _last_dir.y > 0.5 else (1 if _last_dir.y < -0.5 else 0))
	var cands: Array[Vector2i] = []
	if came != Vector2i.ZERO and (came.x == 0 or came.y == 0):
		cands.append(came)
	for c in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not cands.has(c):
			cands.append(c)
	var pick := Vector2i(1, 0)
	var fallback := Vector2i.ZERO
	var any_open := false
	for c in cands:
		var nt: Vector2i = pt + c
		if World.is_walkable(nt) and World.edge_open(pt, nt):
			any_open = true
			if fallback == Vector2i.ZERO:
				fallback = c
			if not _spot_taken(partner_pos, Vector2(c)):
				pick = c
				fallback = Vector2i.ZERO
				break
	if fallback != Vector2i.ZERO:
		pick = fallback
	_social_len = 0.0
	if not any_open:                      # boxed in (a sofa between a wall and a table): stand on the nearest open tile instead
		var n: Vector2i = World.open_neighbor(pt, _last_level, World.pos_to_tile(position))
		if n != pt:
			var v := Vector2(n - pt)
			_social_dir = v.normalized()
			_social_len = v.length()
			return _social_dir
	_social_dir = Vector2(pick)
	return _social_dir


## Somebody else (not our partner) already stands where we would stand next to the partner.
func _spot_taken(partner_pos: Vector3, dir: Vector2) -> bool:
	var par := get_parent()
	if par == null:
		return false
	var dist := float((anim_map().get("social", {}) as Dictionary).get("stand_distance", 0.7))
	var spot := Vector2(partner_pos.x, partner_pos.z) + dir * dist
	for n in par.get_children():
		if n == self or not (n is Node3D) or not ("folk_id" in n) or not n.visible or int(n.folk_id) == _partner_id:
			continue
		if Vector2(n.position.x, n.position.z).distance_to(spot) < 0.75:
			return true
	return false


func _use_pose(f) -> String:
	if f.current != null:
		var id := str(f.current.def_id)
		if id.contains("eat") or id.contains("meal") or id.contains("snack"):
			return "eat"
	return "use"


## Walking pace by intent, not by how far behind the sim walker the view is: a walk catches up with a brisk Walk (capped), only an urgent
## move runs. Data: animation_map locomotion.
## Task 56: times the real clock rate, so at speed 2, 3 and the skip the same walk is simply faster (running stays a matter of intent).
func _walk_speed() -> float:
	var loco: Dictionary = anim_map().get("locomotion", {})
	var m: float = maxf(_speed_mult(), 1.0)
	if _lead_id != 0 and not _urgent:
		return maxf(float(loco.get("walk_base_speed", BASE_SPEED)) * m, _lead_pace * 1.05)          # task 58: the sim's own pace (never behind it)
	if _urgent:
		return float(loco.get("run_speed", 4.6)) * m
	var behind: float = float(_waypoints.size()) / m          # the catch-up looks at how far behind in time, not in waypoints
	var s := float(loco.get("walk_base_speed", BASE_SPEED)) * (1.0 + float(loco.get("walk_catchup_per_waypoint", 0.4)) * behind)
	return minf(s, float(loco.get("walk_max_speed", 3.5))) * m


## A backlog the capped pace cannot clear (fast forward, long routes): the view hops ahead along the route instead of running.
func _trim_backlog() -> void:
	var keep := int(float((anim_map().get("locomotion", {}) as Dictionary).get("max_backlog", 4)) * maxf(_speed_mult(), 1.0) * 2.0)          # task 56: scaled with the speed, a real break only
	if _waypoints.size() <= keep:
		return
	var drop := _waypoints.size() - keep
	while drop > 1 and _blocked_wp(_waypoints[drop - 1]):          # hop only onto a walkable route tile
		drop -= 1
	var hop: Vector3 = _waypoints[drop - 1]
	if _blocked_wp(hop):
		return
	position.x = hop.x
	position.z = hop.z
	_ybase = hop.y
	_waypoints = _waypoints.slice(drop)


## A waypoint on a blocked tile that is not the folk's own tile (a route that starts in the shower the folk just left, a stale first step):
## never walked to, the folk would cross the shower, a dresser or a chair. Stairs and lift cabins are walkable portal tiles.
func _blocked_wp(w: Vector3) -> bool:
	var t: Vector2i = World.pos_to_tile(w)
	if t == World.pos_to_tile(position) or World.is_walkable(t, _last_level):
		return false
	var o = World.object_at(t, _last_level)
	return o == null or not o.def.has("portal")


## Drops the waypoints in front of the folk that lie on blocked tiles (the last one is the goal and stays: a slot tile is the object's own tile).
func _skip_blocked_waypoints() -> void:
	while _waypoints.size() > 1 and _blocked_wp(_waypoints[0]):
		_waypoints.remove_at(0)


## The view is far from where it has to be and has no route (it was left behind by the sim walker, got up from a seat, or its chat partner walked on):
## follow a real path to it, never a straight line across tables and chairs. No route: it simply appears there.
func _route_far_goal() -> void:
	if _last_level != 0 or Vector2(_target.x - position.x, _target.z - position.z).length() < 1.6:
		return
	var goal_t: Vector2i = World.pos_to_tile(_target)
	var from: Vector2i = World.open_neighbor(World.pos_to_tile(position), 0, goal_t)
	var to: Vector2i = World.open_neighbor(goal_t, 0, from)
	var seg: Array = World.find_path(from, to)
	if seg.is_empty() or seg.size() > _max_slice():
		position.x = _target.x
		position.z = _target.z
		return
	for t in seg:
		_waypoints.append(_wp(t, 0))


func _move(delta: float) -> void:
	var mult := _speed_mult()
	_speed_now = 0.0
	if mult <= 0.0:
		_moving = false
		if not _waypoints.is_empty():          # task 58: paused, an order still shows at once: they turn to where they are going
			var to0: Vector3 = _waypoints[0] - position
			if Vector2(to0.x, to0.z).length() > 0.05:
				_target_yaw = atan2(-to0.x, -to0.z)
				facing_yaw = _target_yaw
		return
	_trim_backlog()
	_skip_blocked_waypoints()
	var speed := _walk_speed() * Weather.walk_speed_mult_at(Vector2i(int(floor(position.x)), int(floor(position.z))), _last_level)
	if _waypoints.is_empty():
		_route_far_goal()
	if _avoid != Vector2.ZERO and not _waypoints.is_empty():
		var ahead := Vector2(_waypoints[0].x - position.x, _waypoints[0].z - position.z)
		if ahead.dot(_avoid) < 0.0:
			speed *= 0.5                                  # somebody is just ahead of us on the way: queue behind them
	# Task 56: the step left over after reaching a waypoint carries on to the next ones in the same frame (capped), so the drawn walk keeps
	# the sim's pace at any game speed and frame rate; height follows each waypoint passed.
	var budget: float = speed * delta
	var moved: float = 0.0
	var passed: int = 0
	var dist := 0.0
	while true:
		var goal: Vector3 = _waypoints[0] if not _waypoints.is_empty() else _target
		if _waypoints.is_empty():
			goal += Vector3(_avoid.x, 0.0, _avoid.y)          # arriving beside somebody: stop where there is room
		var gy: float = goal.y if not _waypoints.is_empty() else _level_y
		var to := goal - position
		to.y = 0
		dist = to.length()
		if dist <= budget:
			position.x = goal.x
			position.z = goal.z
			budget -= dist
			moved += dist
			if _waypoints.is_empty():
				_ybase = move_toward(_ybase, gy, (maxf(speed, 1.0) + 2.5) * delta)
				break
			if budget > 0.0 and passed < MAX_WP_PER_FRAME:
				_ybase = gy                                   # passed through this waypoint: on its floor / step
			else:
				_ybase = move_toward(_ybase, gy, (maxf(speed, 1.0) + 2.5) * delta)
			if absf(gy - _ybase) > 0.06:
				break                                     # still climbing to it (a stair step, a lift ride)
			_waypoints.remove_at(0)
			passed += 1
			if budget <= 0.0 or passed >= MAX_WP_PER_FRAME:
				break
			continue
		var dir := to / dist
		position += dir * budget
		moved += budget
		_ybase = move_toward(_ybase, gy, (maxf(speed, 1.0) + 2.5) * delta)          # climbing: the height follows the route (a lift ride is vertical)
		_last_dir = Vector2(dir.x, dir.z)
		if _waypoints.size() > 0 or _target_pose in ["idle", "walk"]:
			_target_yaw = atan2(-dir.x, -dir.z)
		break
	_moving = moved > 0.0 or dist > 0.03
	_speed_now = moved / maxf(delta, 0.0001)
	# smooth turning (faster while locomoting)
	var rate := 14.0 if _moving else 9.0
	facing_yaw = lerp_angle(facing_yaw, _target_yaw, clampf(delta * rate, 0.0, 1.0))

## Standing about (idle, or waiting as the target of somebody else's chat) is where folk keep their distance.
func _spaced_pose() -> bool:
	return (_target_pose == "idle" and _partner_role == "") or (_partner_role == "target" and _target_pose == "use")


## Idle and crowd folk keep their distance (view only, no sim state): a folk standing about with nothing to do, on a spot another folk is
## also idling at, drifts to at least `keep_apart` metres away (data: animation_map social.keep_apart), never onto a blocked tile or across a wall.
func _update_separation(f) -> void:
	_sep_off = Vector2.ZERO
	if not _spaced_pose() or not _waypoints.is_empty() or World.folk_pose.has(folk_id):
		return
	if _res_cache is Array and _is_running(f):
		return
	var keep := float((anim_map().get("social", {}) as Dictionary).get("keep_apart", 0.5))
	var par := get_parent()
	if par == null:
		return
	var push := Vector2.ZERO
	for n in par.get_children():
		if n == self or not (n is Node3D) or not n.visible or not ("folk_id" in n):
			continue
		if str(n.pose) in ["sit", "lie"]:
			continue
		var nb: Vector3 = n.position if (not n._waypoints.is_empty() or n._moving) else Vector3(n._target.x - n._sep_off.x, 0.0, n._target.z - n._sep_off.y)
		var d := Vector2(_target.x - nb.x, _target.z - nb.z)     # between the spots they idle at, so the spacing is stable (no jitter)
		var len := d.length()
		if len >= keep:
			continue
		if len < 0.02:
			# the same spot: the lower id gives way along a fixed direction so the pair always separates
			d = Vector2.from_angle(float((folk_id * 5 + int(n.folk_id) * 3) % 8) * PI / 4.0) * (1.0 if folk_id > int(n.folk_id) else -1.0)
			len = 0.02
		push += d / len * (keep - len)
	if push == Vector2.ZERO:
		return
	if push.length() > keep:
		push = push.normalized() * keep
	var goal := Vector3(_target.x + push.x, _target.y, _target.z + push.y)
	var t0: Vector2i = World.pos_to_tile(_target)
	var t1: Vector2i = World.pos_to_tile(goal)
	if t1 != t0 and (not World.is_walkable(t1, _last_level) or not World.edge_open(t0, t1, _last_level)):
		return
	_sep_off = push


## Folk never stand inside each other (view only): anybody closer than `personal_space` (animation_map social) to a standing or walking folk is nudged
## away from it, whatever either is doing, except while one sits, lies or uses an object at its slot. Symmetric, so a pair separates in a moment.
func _update_avoid(f) -> void:
	_avoid = Vector2.ZERO
	if pose in ["sit", "lie"] or (_res_cache is Array and _is_running(f) and _target_pose != "idle"):
		return
	var space := float((anim_map().get("social", {}) as Dictionary).get("personal_space", 0.45))
	var par := get_parent()
	if par == null:
		return
	for n in par.get_children():
		if n == self or not (n is Node3D) or not ("folk_id" in n) or not n.visible or str(n.pose) in ["sit", "lie"]:
			continue
		var d := Vector2(position.x - n.position.x, position.z - n.position.z)
		var len := d.length()
		if len >= space:
			continue
		if len < 0.02:
			d = Vector2.from_angle(float((folk_id * 7 + int(n.folk_id) * 3) % 8) * PI / 4.0) * (1.0 if folk_id > int(n.folk_id) else -1.0)
			len = 0.02
		_avoid += d / len * (space - len)


func _apply_avoid(delta: float) -> void:
	if _avoid == Vector2.ZERO:
		return
	var push := _avoid
	if _moving and _last_dir != Vector2.ZERO:
		push -= _last_dir * push.dot(_last_dir)          # walking: only sidestep; the one behind slows down instead (see _move)
	var step := push * minf(delta * 10.0, 1.0)
	var np := Vector3(position.x + step.x, position.y, position.z + step.y)
	var a: Vector2i = World.pos_to_tile(position)
	var b: Vector2i = World.pos_to_tile(np)
	if a != b and (not World.is_walkable(b, _last_level) or not World.edge_open(a, b, _last_level)):
		return
	position.x = np.x
	position.z = np.z
