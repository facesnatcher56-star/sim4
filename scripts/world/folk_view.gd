class_name FolkView
extends Node3D
## Visual for one Folk. Follows the logical `folk.tile` smoothly (walking along World paths), poses itself from the
## reserved object slot / folk.posture / World.folk_pose, and plays Blender clips (assets/models/folk_<stage>.glb)
## chosen through data/animation_map.json. Falls back to folk.glb, then to a capsule-person placeholder.
##
## Public surface kept stable for LotView: setup(folk_id), head_position(), show_name, pose (idle|walk|sit|lie|use|eat),
## signal pose_changed. New: clip (current Blender clip name), variant (body variant), show_mood.

signal pose_changed(folk_id: int, pose: String)

const BASE_SPEED := 2.4
const SPEED_MULT := [0.0, 1.0, 1.8, 3.0]
const MAP_PATH := "res://data/animation_map.json"
const STAGES := ["baby", "toddler", "child", "teen", "adult", "elder"]
const FADE := 0.25
const DEFAULT_MAP := {
	"variant_files": {"fallback": "res://assets/models/folk.glb"},
	"variant_scale": {"adult": 1.0, "teen": 0.92, "child": 0.68, "elder": 0.96, "toddler": 0.5, "baby": 0.3},
	"oneshot": ["Faint", "Fall"],
	"locomotion": {"walk_clip": "Walk", "run_clip": "Run", "run_above_speed": 3.6, "walk_nominal_speed": 2.2,
		"run_nominal_speed": 4.2, "min_scale": 0.5, "max_scale": 2.4},
	"posture": {"stand": "Use_Stand", "sit": "Sit_Idle", "lie": "Sleep"},
	"idle": {"default": "Idle", "sit": "Sit_Idle", "lie": "Sleep", "mood": {}},
	"interactions": {}, "tags": {}, "tag_order": [], "fallbacks": {"*": "Idle"}, "variants": {},
	"mood_icon": {"min_intensity": 2, "colors": {}}, "social": {"stand_distance": 0.7},
}

static var _map: Dictionary = {}
static var _map_loaded: bool = false

var folk_id: int = -1
var pose: String = "idle"
var clip: String = ""                 # clip currently requested (after variant/fallback resolution)
var variant: String = "adult"
var facing_yaw: float = 0.0           # radians, model -Z forward
var show_name: bool = false:
	set(v):
		show_name = v
		if _name_label:
			_name_label.visible = v
var show_mood: bool = true

var _waypoints: Array[Vector3] = []
var _last_tile: Vector2i = Vector2i(-999, -999)
var _target: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_pose: String = "idle"
var _elev: float = 0.0
var _anim: AnimationPlayer = null
var _rig: Node3D = null              # placeholder rig or glb root
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _is_placeholder: bool = true
var _name_label: Label3D = null
var _mood_icon: MeshInstance3D = null
var _mood_mat: StandardMaterial3D = null
var _mood_key: String = ""
var _phase: float = 0.0
var _res_cache: Variant = null
var _res_tick: int = 0
var _moving: bool = false
var _speed_now: float = 0.0           # metres/second actually travelled this frame
var _look_sig: int = 0
var _stage_now: String = ""
var _check_tick: int = 0
var _body_scale: float = 1.0          # variant scale * appearance height (drives sit lift)
# interaction tracking
var _cur_ref: Variant = null
var _inter_t0: float = 0.0
var _hold_clip: String = ""
var _hold_until: float = 0.0
var _partner_id: int = -1
var _partner_role: String = ""        # "actor" | "target" | ""
var _partner_inter: Variant = null
var _social_dir: Vector2 = Vector2.ZERO
var _last_dir: Vector2 = Vector2(0, 1)


# ------------------------------------------------------------------ data

static func anim_map() -> Dictionary:
	if _map_loaded:
		return _map
	_map_loaded = true
	_map = DEFAULT_MAP.duplicate(true)
	if FileAccess.file_exists(MAP_PATH):
		var txt := FileAccess.get_file_as_string(MAP_PATH)
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			for k in (parsed as Dictionary):
				_map[k] = parsed[k]
	return _map


## Test hook: force a reload of the map next time.
static func reload_map() -> void:
	_map_loaded = false


static func stage_of(f) -> String:
	if f == null:
		return "adult"
	var s := str(f.age_stage)
	return s if s in STAGES else "adult"


static func variant_path(stage: String) -> String:
	var files: Dictionary = anim_map().get("variant_files", {})
	var p := str(files.get(stage, ""))
	if p != "" and ResourceLoader.exists(p):
		return p
	p = str(files.get("fallback", "res://assets/models/folk.glb"))
	if ResourceLoader.exists(p):
		return p
	return ""


## Loop modes + trailing duplicate-frame trim for the clips of an imported AnimationPlayer (idempotent, shared resources).
static func prepare_player(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	var oneshot: Array = anim_map().get("oneshot", [])
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n)
		if a.has_meta("folk_prepared"):
			continue
		a.set_meta("folk_prepared", true)
		if str(n) in oneshot:
			a.loop_mode = Animation.LOOP_NONE
		else:
			a.loop_mode = Animation.LOOP_LINEAR
			a.length = maxf(a.length - 1.0 / 24.0, 1.0 / 24.0)


static func color_of(hex: Variant, default: Color) -> Color:
	var s := str(hex)
	if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
		return Color.html(s)
	return default


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
	_build_mood_icon()


func head_position() -> Vector3:
	var h := 1.9 * clampf(_body_scale, 0.3, 1.2) + 0.1
	return global_position + Vector3(0, h if pose != "lie" else 0.9 * clampf(_body_scale + 0.2, 0.4, 1.2), 0)


# ------------------------------------------------------------------ visuals

func _build_visual() -> void:
	if _rig != null:
		_rig.queue_free()
		_rig = null
		_anim = null
	_legs.clear()
	_arms.clear()
	var f = World.get_folk(folk_id)
	_stage_now = stage_of(f)
	variant = _stage_now
	var path := variant_path(variant)
	if path != "":
		var ps = load(path)
		if ps is PackedScene:
			_rig = ps.instantiate()
			add_child(_rig)
			_anim = _find_anim(_rig)
			prepare_player(_anim)
			_is_placeholder = false
			_apply_appearance(f)
			clip = ""
			_play_clip("Idle")
			return
	_build_placeholder()
	_apply_appearance(f)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func _appearance_of(f) -> Dictionary:
	if f != null and "appearance" in f and f.appearance is Dictionary:
		return f.appearance
	return {}


## Tint materials (skin/hair/eyes/shirt/pants), choose the hair style, apply height & build.
func _apply_appearance(f) -> void:
	var ap := _appearance_of(f)
	_look_sig = hash(ap) + 31 * hash(_stage_now)
	var skin := color_of(ap.get("skin", null), Color(0.90, 0.70, 0.56))
	var hair := color_of(ap.get("hair_color", null), Color(0.25, 0.15, 0.10))
	var eyes := color_of(ap.get("eye_color", null), Color(0.20, 0.30, 0.45))
	var shirt_d := Color.from_hsv(fposmod(float(folk_id) * 0.173, 1.0), 0.55, 0.85)
	var shirt := color_of(ap.get("shirt", null), shirt_d)
	var pants := color_of(ap.get("pants", null), Color(0.25, 0.28, 0.40))
	var height := clampf(float(ap.get("height", 1.0)), 0.8, 1.2)
	var build := clampf(float(ap.get("build", 1.0)), 0.8, 1.2)
	var style := clampi(int(ap.get("hair_style", folk_id % 6)), 0, 5)
	var tints := {"skin": skin, "hair": hair, "eyes": eyes, "shirt": shirt, "pants": pants}
	var vs: Dictionary = anim_map().get("variant_scale", {})
	_body_scale = float(vs.get(_stage_now, 1.0)) * height
	if _rig == null:
		return
	if _is_placeholder:
		_tint_placeholder(tints)
		return
	_rig.scale = Vector3(build * height, height, build * height)
	_tint_model(_rig, tints)
	for i in 6:
		var hn := _rig.find_child("hair_%d" % i, true, false)
		if hn is Node3D:
			(hn as Node3D).visible = (i == style)


func _tint_model(n: Node, tints: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(s)
				if m == null:
					continue
				var key := str(m.resource_name)
				if tints.has(key) and m is BaseMaterial3D:
					var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					d.albedo_color = tints[key]
					mi.set_surface_override_material(s, d)
	for c in n.get_children():
		_tint_model(c, tints)


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


var _ph_parts: Dictionary = {}


func _tint_placeholder(t: Dictionary) -> void:
	for k in _ph_parts:
		for mi in _ph_parts[k]:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).material_override = _mat(t[k])


func _ph_add(k: String, mi: MeshInstance3D) -> void:
	if not _ph_parts.has(k):
		_ph_parts[k] = []
	_ph_parts[k].append(mi)


func _build_placeholder() -> void:
	_is_placeholder = true
	_ph_parts.clear()
	_rig = Node3D.new()
	add_child(_rig)
	var c0 := Color(0.5, 0.5, 0.5)
	var torso := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.2
	cm.height = 0.75
	torso.mesh = cm
	torso.position = Vector3(0, 1.08, 0)
	_rig.add_child(torso)
	_ph_add("shirt", torso)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	head.mesh = sm
	head.position = Vector3(0, 1.62, 0)
	_rig.add_child(head)
	_ph_add("skin", head)
	_ph_add("skin", _box(_rig, Vector3(0.08, 0.06, 0.12), Vector3(0, 1.62, -0.15), c0))   # nose = facing marker
	for sx in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.1 * sx, 0.72, 0)
		_rig.add_child(pivot)
		_ph_add("pants", _box(pivot, Vector3(0.14, 0.72, 0.14), Vector3(0, -0.36, 0), c0))
		_legs.append(pivot)
	for sx in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.27 * sx, 1.3, 0)
		_rig.add_child(pivot)
		_ph_add("shirt", _box(pivot, Vector3(0.1, 0.55, 0.1), Vector3(0, -0.27, 0), c0))
		_arms.append(pivot)


# ------------------------------------------------------------------ mood icon

func _build_mood_icon() -> void:
	_mood_icon = MeshInstance3D.new()
	var sm := SphereMesh.new()      # 4 segments / 2 rings = an octahedron "diamond"
	sm.radial_segments = 4
	sm.rings = 2
	sm.radius = 0.07
	sm.height = 0.18
	_mood_icon.mesh = sm
	_mood_mat = StandardMaterial3D.new()
	_mood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mood_mat.albedo_color = Color.WHITE
	_mood_icon.material_override = _mood_mat
	_mood_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mood_icon.visible = false
	add_child(_mood_icon)


func _update_mood_icon(f, delta: float) -> void:
	if _mood_icon == null:
		return
	var mi: Dictionary = anim_map().get("mood_icon", {})
	var minv := int(mi.get("min_intensity", 2))
	var mood := str(f.mood_name) if "mood_name" in f else "neutral"
	var inten := int(f.mood_intensity) if "mood_intensity" in f else 0
	var on := show_mood and mood != "neutral" and inten >= minv
	_mood_icon.visible = on
	if not on:
		return
	if mood != _mood_key:
		_mood_key = mood
		var cols: Dictionary = mi.get("colors", {})
		_mood_mat.albedo_color = color_of(cols.get(mood, "#ffffff"), Color.WHITE)
	_phase += delta
	_mood_icon.position = Vector3(0, head_position().y - global_position.y + 0.28 + sin(_phase * 3.0) * 0.03, 0)
	_mood_icon.rotation.y += delta * 1.8
	_mood_icon.scale = Vector3.ONE * (0.8 + 0.15 * inten)


# ------------------------------------------------------------------ logic

func _process(delta: float) -> void:
	if folk_id < 0:
		return
	var f = World.get_folk(folk_id)
	if f == null:
		return
	_check_tick += 1
	if _check_tick % 20 == 0:
		if stage_of(f) != _stage_now:
			_build_visual()
		elif hash(_appearance_of(f)) + 31 * hash(_stage_now) != _look_sig:
			_apply_appearance(f)
	_update_waypoints(f)
	_resolve_target(f)
	_move(delta)
	_apply_pose(f, delta)
	_update_mood_icon(f, delta)


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


func _speed_mult() -> float:
	var clk := get_node_or_null("/root/Clock")
	if clk != null:
		return SPEED_MULT[clampi(int(clk.get("speed")), 0, 3)]
	return 1.0


func _move(delta: float) -> void:
	var mult := _speed_mult()
	_speed_now = 0.0
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


# ------------------------------------------------------------------ clip selection

func _pose_key() -> String:
	# key used by interactions[...] dictionaries
	match _target_pose:
		"sit":
			return "sit"
		"lie":
			return "lie"
	return "stand"


func _pick_from(entry: Variant, key: String) -> String:
	if entry is String:
		return entry
	if entry is Dictionary:
		var d: Dictionary = entry
		if d.has(key):
			return str(d[key])
		if d.has("default"):
			return str(d["default"])
	return ""


func _social_clip(entry: Dictionary, role: String) -> String:
	var arr: Array = entry.get(role, [])
	if arr.is_empty():
		return ""
	var seg := maxf(float(entry.get("seg", 4.0)), 0.5)
	var t := (Time.get_ticks_msec() / 1000.0 - _inter_t0) / seg + float(folk_id % 3) * 0.0
	return str(arr[int(t) % arr.size()])


func _interaction_entry(f) -> Variant:
	var m := anim_map()
	var inter = f.current if _partner_role != "target" else _partner_inter
	if inter == null:
		return null
	var id := str(inter.def_id)
	var ints: Dictionary = m.get("interactions", {})
	if ints.has(id):
		return ints[id]
	var tags: Array = inter.def.get("tags", []) if inter.def is Dictionary else []
	var tmap: Dictionary = m.get("tags", {})
	for t in m.get("tag_order", []):
		if str(t) in tags and tmap.has(str(t)):
			return tmap[str(t)]
	for t in tags:
		if tmap.has(str(t)):
			return tmap[str(t)]
	return null


func _desired_clip(f) -> String:
	var m := anim_map()
	var loco: Dictionary = m.get("locomotion", {})
	var key := _pose_key()
	# 1. locomotion
	if _moving or not _waypoints.is_empty():
		if _speed_now >= float(loco.get("run_above_speed", 3.6)):
			return str(loco.get("run_clip", "Run"))
		return str(loco.get("walk_clip", "Walk"))
	# 2. one-shot "enter" clip held for its duration
	var now := Time.get_ticks_msec() / 1000.0
	if _hold_clip != "" and now < _hold_until:
		return _hold_clip
	# 3. interaction / partner
	var running := _is_running(f)
	if running or _partner_role == "target":
		var entry: Variant = _interaction_entry(f)
		if entry is Dictionary and ((entry as Dictionary).has("actor") or (entry as Dictionary).has("target")):
			var role := "actor"
			if _partner_role == "target":
				role = "target"
			var c := _social_clip(entry, role)
			if c != "":
				return c
		elif entry != null:
			var c2 := _pick_from(entry, key)
			if c2 != "":
				return c2
		if running:
			var post: Dictionary = m.get("posture", {})
			return str(post.get(key, "Use_Stand"))
	# 4. idle by posture / mood
	var idle: Dictionary = m.get("idle", {})
	if _target_pose == "sit":
		return str(idle.get("sit", "Sit_Idle"))
	if _target_pose == "lie":
		return str(idle.get("lie", "Sleep"))
	var mood := str(f.mood_name) if "mood_name" in f else "neutral"
	var moods: Dictionary = idle.get("mood", {})
	if moods.has(mood):
		var md: Dictionary = moods[mood]
		if int(f.mood_intensity) >= int(md.get("min_intensity", 1)):
			return str(md.get("clip", "Idle"))
	return str(idle.get("default", "Idle"))


func _resolve_clip(c: String) -> String:
	## variant overrides, then fallbacks, then whatever exists.
	var m := anim_map()
	var vmap: Dictionary = (m.get("variants", {}) as Dictionary).get(variant, {})
	if not vmap.is_empty():
		if vmap.has(c):
			c = str(vmap[c])
		elif vmap.has("*"):
			c = str(vmap["*"])
	if _anim == null:
		return c
	var fb: Dictionary = m.get("fallbacks", {})
	var guard := 0
	while not _anim.has_animation(c) and guard < 6:
		guard += 1
		c = str(fb.get(c, fb.get("*", "Idle")))
	return c


func _apply_pose(f, delta: float) -> void:
	var want := _target_pose
	if _moving or not _waypoints.is_empty():
		want = "walk"
	if want != pose:
		pose = want
		pose_changed.emit(folk_id, pose)
	rotation.y = facing_yaw
	# interaction change bookkeeping (enter clips, social timers)
	var cur: Variant = f.current if _is_running(f) else null
	if cur != _cur_ref:
		_cur_ref = cur
		_inter_t0 = Time.get_ticks_msec() / 1000.0
		_hold_clip = ""
		_social_dir = Vector2.ZERO
		if cur != null:
			var entry: Variant = _interaction_entry(f)
			if entry is Dictionary and (entry as Dictionary).has("enter"):
				var ec := _resolve_clip(str(entry["enter"]))
				if _anim != null and _anim.has_animation(ec):
					_hold_clip = str(entry["enter"])
					_hold_until = _inter_t0 + clampf(_anim.get_animation(ec).length, 1.0, 4.0)
	var wanted := _desired_clip(f)
	if _anim != null:
		_play_clip_name(_resolve_clip(wanted))
		_anim.speed_scale = _anim_speed(wanted)
		position.y = _elev + _sit_lift() if pose in ["sit", "lie"] else 0.0
		return
	if _rig == null:
		return
	_placeholder_pose(delta)


func _sit_lift() -> float:
	# Smaller bodies sit lower on the same seat; lift them so the pelvis meets the cushion.
	if pose != "sit":
		return 0.0
	return (1.0 - _body_scale) * 0.45


func _anim_speed(wanted: String) -> float:
	var mult := _speed_mult()
	if mult <= 0.0:
		return 0.0
	var loco: Dictionary = anim_map().get("locomotion", {})
	if _moving or not _waypoints.is_empty():
		var nominal := float(loco.get("run_nominal_speed", 4.2)) if wanted == str(loco.get("run_clip", "Run")) \
			else float(loco.get("walk_nominal_speed", 2.2))
		nominal *= clampf(_body_scale, 0.35, 1.2)
		var s := _speed_now / maxf(nominal, 0.1)
		return clampf(s, float(loco.get("min_scale", 0.5)), float(loco.get("max_scale", 2.4)))
	return minf(mult, 2.0)


func _play_clip_name(c: String) -> void:
	if _anim == null or c == clip:
		return
	if not _anim.has_animation(c):
		return
	clip = c
	_anim.play(c, FADE)


func _play_clip(c: String) -> void:
	_play_clip_name(_resolve_clip(c))


func _placeholder_pose(delta: float) -> void:
	var m := _speed_mult()
	_phase += delta * 9.0 * m * (1.0 + 0.25 * float(_waypoints.size()))
	var ls := sin(_phase)
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
			_rig.position.z = -0.85
		"use":
			_arms[0].rotation.x = -1.0 + sin(_phase * 0.4) * 0.15
			_arms[1].rotation.x = -1.0 - sin(_phase * 0.4) * 0.15
		"eat":
			_arms[0].rotation.x = -1.3 + sin(_phase * 0.5) * 0.35
			_arms[1].rotation.x = -0.4
		_:
			_rig.position.y = sin(_phase * 0.2) * 0.01
