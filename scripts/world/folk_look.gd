extends "res://scripts/world/folk_data.gd"
## FolkView layer: model / placeholder building, appearance tints, mood icon, x-ray silhouette, clip playback.


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
	_name_label.fixed_size = true          # constant on-screen size at every zoom level
	_name_label.pixel_size = 0.0016
	_name_label.font_size = 40
	_name_label.outline_size = 14
	_name_label.outline_modulate = Color(0.05, 0.07, 0.12, 0.95)
	_name_label.no_depth_test = true
	_name_label.render_priority = 4
	_name_label.visible = show_name
	add_child(_name_label)
	_build_mood_icon()


static var _xray_mat: ShaderMaterial = null
var _xray_on: bool = false


## Silhouette drawn on top of whatever hides the folk (wall, wardrobe, ...).
func set_xray(on: bool) -> void:
	if on == _xray_on or _rig == null:
		return
	_xray_on = on
	if _xray_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;
void fragment() { ALBEDO = vec3(0.35, 0.85, 1.0); ALPHA = 0.5; }"
		_xray_mat = ShaderMaterial.new()
		_xray_mat.shader = sh
		_xray_mat.render_priority = 3
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _xray_mat if on else null


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
	_props.clear()                         # the hand props hung on the old skeleton went with it
	_prop_sig = 0
	FolkFx.reset(self)
	_xray_on = false
	var f = World.get_folk(folk_id)
	_styled = false
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
	push_error("FolkView: no folk model could be loaded for stage %s" % variant)
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


## Show / hide / tint the model parts for the appearance (FolkRigStyle); a changed look rebuilds the model (unused parts are freed).
var _styled: bool = false

## 1 while she is in the third trimester of a pregnancy (a rounder body), else 0.
func bump_of(f) -> int:
	return 1 if f != null and f.has_method("has_buff") and f.has_buff("pregnant_t3") else 0

func _apply_appearance(f) -> void:
	if _styled and not _is_placeholder:
		_build_visual()
		return
	var ap := _appearance_of(f)
	_look_sig = hash(ap) + 31 * hash(_stage_now) + 977 * bump_of(f)
	var skin := color_of(ap.get("skin", null), Color(0.90, 0.70, 0.56))
	var hair := color_of(ap.get("hair_color", null), Color(0.25, 0.15, 0.10))
	var eyes := color_of(ap.get("eye_color", null), Color(0.20, 0.30, 0.45))
	var shirt_d := Color.from_hsv(fposmod(float(folk_id) * 0.173, 1.0), 0.55, 0.85)
	var shirt := color_of(ap.get("shirt", null), shirt_d)
	var pants := color_of(ap.get("pants", null), Color(0.25, 0.28, 0.40))
	var height := clampf(float(ap.get("height", 1.0)), 0.8, 1.2)
	var build := clampf(float(ap.get("build", 1.0)), 0.8, 1.2)
	var tints := {"skin": skin, "hair": hair, "eyes": eyes, "shirt": shirt, "pants": pants}
	var vs: Dictionary = anim_map().get("variant_scale", {})
	_body_scale = float(vs.get(_stage_now, 1.0)) * height
	if _rig == null:
		return
	if _is_placeholder:
		_tint_placeholder(tints)
		return
	var wide: float = 1.0 + 0.14 * float(bump_of(f))              # a visible bump in the third trimester
	_rig.scale = Vector3(build * height * wide, height, build * height * wide)
	FolkRigStyle.apply(_rig, ap, _stage_now, shirt_d)
	_styled = true


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


## How many times faster than speed 1 the game runs right now (task 56: the real clock rate, the time skip included).
func _speed_mult() -> float:
	var clk := get_node_or_null("/root/Clock")
	if clk != null:
		return float(clk.call("real_rate")) if clk.has_method("real_rate") else SPEED_MULT[clampi(int(clk.get("speed")), 0, 3)]
	return 1.0


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
		var top: float = maxf(float(loco.get("max_scale", 2.4)), minf(float(loco.get("max_scale", 2.4)) * mult, float(loco.get("max_scale_fast", 5.0))))
		return clampf(s, float(loco.get("min_scale", 0.5)), top)          # the legs keep up with a fast game, up to a rate that still reads as walking
	return minf(mult, float(loco.get("use_max_scale", 6.0)))


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
	_phase += delta * 9.0 * minf(m, 5.0) * (1.0 + 0.25 * float(_waypoints.size()) / maxf(m, 1.0))
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
