class_name FolkView
extends Node3D
## Visual for one Folk. Follows the logical `folk.tile` smoothly (walking along World paths),
## and poses itself from the reserved object slot / folk.posture / World.folk_pose.
## Uses assets/models/folk.glb (AnimationPlayer clips Idle/Walk/Sit/Sleep/Use/Eat) when present,
## otherwise a capsule-person placeholder driven by simple transforms.

signal pose_changed(folk_id: int, pose: String)

const BASE_SPEED := 2.4
const SPEED_MULT := [0.0, 1.0, 1.8, 3.0]
const CLIPS := {"idle": "Idle", "walk": "Walk", "sit": "Sit", "lie": "Sleep", "use": "Use", "eat": "Eat"}

var folk_id: int = -1
var pose: String = "idle"
var facing_yaw: float = 0.0   # radians, model -Z forward
var show_name: bool = false:
	set(v):
		show_name = v
		if _name_label:
			_name_label.visible = v

var _waypoints: Array[Vector3] = []
var _last_tile: Vector2i = Vector2i(-999, -999)
var _target: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_pose: String = "idle"
var _elev: float = 0.0
var _anim: AnimationPlayer = null
var _rig: Node3D = null            # placeholder rig or glb root
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _is_placeholder: bool = true
var _name_label: Label3D = null
var _phase: float = 0.0
var _res_cache: Variant = null
var _res_tick: int = 0
var _moving: bool = false


func setup(p_folk_id: int) -> void:
	folk_id = p_folk_id
	_build_visual()
	var f = World.get_folk(folk_id)
	if f != null:
		_last_tile = f.tile
		position = World.tile_to_pos(f.tile)
		_target = position
	_name_label = Label3D.new()
	_name_label.text = str(f.name) if f != null else ""
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0, 2.0, 0)
	_name_label.pixel_size = 0.006
	_name_label.no_depth_test = true
	_name_label.visible = show_name
	add_child(_name_label)


func head_position() -> Vector3:
	return global_position + Vector3(0, 1.9 if pose != "lie" else 0.9, 0)


# ------------------------------------------------------------------ visuals

func _build_visual() -> void:
	var path := "res://assets/models/folk.glb"
	var f = World.get_folk(folk_id)
	if f != null and str(f.age_stage) in ["child", "toddler", "baby"] and ResourceLoader.exists("res://assets/models/folk_child.glb"):
		path = "res://assets/models/folk_child.glb"
	if ResourceLoader.exists(path):
		var ps = load(path)
		if ps is PackedScene:
			_rig = ps.instantiate()
			add_child(_rig)
			_anim = _find_anim(_rig)
			_is_placeholder = false
			_tint_model(_rig)
			_play_clip("idle")
			return
	_build_placeholder()


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func _tint_model(_n: Node) -> void:
	pass   # models ship with their own materials


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_placeholder() -> void:
	_is_placeholder = true
	_rig = Node3D.new()
	add_child(_rig)
	var hue := fposmod(float(folk_id) * 0.173, 1.0)
	var shirt := Color.from_hsv(hue, 0.55, 0.85)
	var skin := Color(0.93, 0.76, 0.62)
	var pants := Color(0.25, 0.28, 0.4)
	# torso
	var torso := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.2
	cm.height = 0.75
	torso.mesh = cm
	torso.material_override = _mat(shirt)
	torso.position = Vector3(0, 1.08, 0)
	_rig.add_child(torso)
	# head
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	head.mesh = sm
	head.material_override = _mat(skin)
	head.position = Vector3(0, 1.62, 0)
	_rig.add_child(head)
	_box(_rig, Vector3(0.08, 0.06, 0.12), Vector3(0, 1.62, -0.15), skin.darkened(0.15))   # nose = facing marker
	# legs (pivot at hip)
	for sx in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.1 * sx, 0.72, 0)
		_rig.add_child(pivot)
		_box(pivot, Vector3(0.14, 0.72, 0.14), Vector3(0, -0.36, 0), pants)
		_legs.append(pivot)
	# arms (pivot at shoulder)
	for sx in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.27 * sx, 1.3, 0)
		_rig.add_child(pivot)
		_box(pivot, Vector3(0.1, 0.55, 0.1), Vector3(0, -0.27, 0), shirt.darkened(0.1))
		_arms.append(pivot)


# ------------------------------------------------------------------ logic

func _process(delta: float) -> void:
	if folk_id < 0:
		return
	var f = World.get_folk(folk_id)
	if f == null:
		return
	_update_waypoints(f)
	_resolve_target(f)
	_move(delta)
	_apply_pose(delta)


func _update_waypoints(f) -> void:
	if f.tile == _last_tile:
		return
	var d: Vector2i = f.tile - _last_tile
	if _last_tile.x < -900:
		position = World.tile_to_pos(f.tile)
		_waypoints.clear()
	elif maxi(absi(d.x), absi(d.y)) <= 1:
		_waypoints.append(World.tile_to_pos(f.tile))
	else:
		var p: Array = World.find_path(_last_tile, f.tile)
		if p.is_empty():
			position = World.tile_to_pos(f.tile)   # teleport (unreachable / loaded game)
			_waypoints.clear()
		else:
			for t in p:
				_waypoints.append(World.tile_to_pos(t))
	_last_tile = f.tile


func _resolve_target(f) -> void:
	var tile_pos: Vector3 = World.tile_to_pos(f.tile)
	_target = tile_pos
	_elev = 0.0
	_target_pose = "idle"
	var face_vec := Vector2.ZERO
	var running: bool = f.current != null and str(f.current.state) == "running"
	_res_tick += 1
	if _res_tick % 8 == 1:
		_res_cache = World.reservation_of(folk_id)
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


func _use_pose(f) -> String:
	if f.current != null:
		var id := str(f.current.def_id)
		if id.contains("eat") or id.contains("meal") or id.contains("snack"):
			return "eat"
	return "use"


func _speed_mult() -> float:
	var clk := get_node_or_null("/root/Clock")
	if clk != null:
		return SPEED_MULT[clampi(int(clk.get("speed")), 0, 3)]
	return 1.0


func _move(delta: float) -> void:
	var mult := _speed_mult()
	if mult <= 0.0:
		_moving = false
		return
	var speed := BASE_SPEED * mult * (1.0 + 0.4 * float(_waypoints.size()))
	var goal: Vector3 = _waypoints[0] if not _waypoints.is_empty() else _target
	var to := goal - position
	to.y = 0
	var dist := to.length()
	var step := speed * delta
	_moving = dist > 0.03
	if dist <= step:
		position.x = goal.x
		position.z = goal.z
		if not _waypoints.is_empty():
			_waypoints.remove_at(0)
	else:
		var dir := to / dist
		position += dir * step
		if _waypoints.size() > 0 or _target_pose in ["idle", "walk"]:
			_target_yaw = atan2(-dir.x, -dir.z)
	# walking pose while moving between tiles
	facing_yaw = lerp_angle(facing_yaw, _target_yaw, clampf(delta * 12.0, 0.0, 1.0))


func _apply_pose(delta: float) -> void:
	var want := _target_pose
	if _moving or not _waypoints.is_empty():
		want = "walk"
	if want != pose:
		pose = want
		_play_clip(pose)
		pose_changed.emit(folk_id, pose)
	rotation.y = facing_yaw
	if _anim != null:
		_anim.speed_scale = _speed_mult() if _speed_mult() > 0.0 else 0.0
		position.y = _elev if pose in ["sit", "lie"] else 0.0
		return
	if _rig == null:
		return
	var m := _speed_mult()
	_phase += delta * 9.0 * m * (1.0 + 0.25 * float(_waypoints.size()))
	var ls := sin(_phase)
	# reset
	_rig.rotation = Vector3.ZERO
	_rig.position = Vector3.ZERO
	for l in _legs:
		l.rotation = Vector3.ZERO
	for a in _arms:
		a.rotation = Vector3.ZERO
	position.y = 0.0
	match pose:
		"walk":
			_legs[0].rotation.x = ls * 0.6
			_legs[1].rotation.x = -ls * 0.6
			_arms[0].rotation.x = -ls * 0.5
			_arms[1].rotation.x = ls * 0.5
			_rig.position.y = absf(cos(_phase)) * 0.04
		"sit":
			_rig.position.y = -0.2
			position.y = _elev
			for l in _legs:
				l.rotation.x = PI * 0.5
		"lie":
			_rig.rotation.x = PI * 0.5
			_rig.position = Vector3(0, 0.22, 0)
			position.y = _elev
			# head toward +Z (model back); rig pivot at feet -> shift so body centre sits on the surface
			_rig.position.z = -0.85
		"use":
			_arms[0].rotation.x = -1.0 + sin(_phase * 0.4) * 0.15
			_arms[1].rotation.x = -1.0 - sin(_phase * 0.4) * 0.15
		"eat":
			_arms[0].rotation.x = -1.3 + sin(_phase * 0.5) * 0.35
			_arms[1].rotation.x = -0.4
		_:
			_rig.position.y = sin(_phase * 0.2) * 0.01


func _play_clip(p: String) -> void:
	if _anim == null:
		return
	var clip: String = CLIPS.get(p, "Idle")
	if _anim.has_animation(clip):
		_anim.play(clip, 0.2)
	elif _anim.has_animation(clip.to_lower()):
		_anim.play(clip.to_lower(), 0.2)
