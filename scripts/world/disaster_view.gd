class_name DisasterView
extends Node3D
## Cheap disaster visuals for a LotView (task 06), added next to WeatherView by LotView._ready (one line). Almost everything is
## STATE driven (DisasterState: siren, tornado funnel, flood water, blackout, blizzard whiteout, wildfire haze), so it follows time
## warp, saving and loading; a few one-shots come from game events ("disaster" quake / hail / meteor). Screen effects are
## ColorRects on a CanvasLayer under the HUD; world effects are a funnel mesh, a water plane and a hail particle burst.
## Headless: only the parameter maths run (`p`), nothing is built.

const FUNNEL_SECONDS := 22.0

var lot: Node3D = null
var headless: bool = false
## Smoothed parameters (tests read these): siren, dark, white, haze, flood, flash.
var p: Dictionary = {"siren": 0.0, "dark": 0.0, "white": 0.0, "haze": 0.0, "flood": 0.0, "flash": 0.0, "funnel": 0.0}
var shake_left: float = 0.0
var shake_power: float = 1.0
var hail_left: float = 0.0
var _layer: CanvasLayer = null
var _rects: Dictionary = {}
var _funnel: MeshInstance3D = null
var _water: MeshInstance3D = null
var _hail: GPUParticles3D = null
var _meteor: MeshInstance3D = null
var _meteor_t: float = -1.0
var _meteor_target: Vector3 = Vector3.ZERO
var _funnel_t: float = 0.0
var _time: float = 0.0


static func ensure_on(lv: Node3D) -> DisasterView:
	var existing = lv.get_node_or_null("DisasterView")
	if existing != null:
		return existing
	var dv := DisasterView.new()
	dv.name = "DisasterView"
	lv.add_child(dv)
	dv.attach(lv)
	return dv


func attach(lv: Node3D) -> void:
	lot = lv
	headless = DisplayServer.get_name() == "headless"
	var ev = SimEnv.events()
	if ev != null and not ev.game_event.is_connected(_on_game_event):
		ev.game_event.connect(_on_game_event)
	if not headless:
		_build()


func _exit_tree() -> void:
	var ev = SimEnv.events()
	if ev != null and ev.game_event.is_connected(_on_game_event):
		ev.game_event.disconnect(_on_game_event)


# ------------------------------------------------------------------ build
func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 1
	add_child(_layer)
	for id in ["dark", "white", "haze", "siren", "flash"]:
		var r := ColorRect.new()
		r.name = id
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.color = Color(0, 0, 0, 0)
		_layer.add_child(r)
		_rects[id] = r
	(_rects["dark"] as ColorRect).color = Color(0.02, 0.03, 0.08, 0.0)
	(_rects["white"] as ColorRect).color = Color(0.92, 0.95, 1.0, 0.0)
	(_rects["haze"] as ColorRect).color = Color(0.85, 0.5, 0.2, 0.0)
	(_rects["siren"] as ColorRect).color = Color(0.9, 0.1, 0.08, 0.0)
	(_rects["flash"] as ColorRect).color = Color(1.0, 0.95, 0.85, 0.0)
	var fm := CylinderMesh.new()
	fm.top_radius = 2.4
	fm.bottom_radius = 0.35
	fm.height = 10.0
	fm.radial_segments = 14
	fm.rings = 6
	_funnel = MeshInstance3D.new()
	_funnel.mesh = fm
	_funnel.material_override = _unshaded(Color(0.32, 0.32, 0.36, 0.6))
	_funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_funnel.visible = false
	add_child(_funnel)
	var pm := PlaneMesh.new()
	pm.size = Vector2(220, 220)
	_water = MeshInstance3D.new()
	_water.mesh = pm
	_water.material_override = _unshaded(Color(0.25, 0.45, 0.7, 0.42))
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.visible = false
	add_child(_water)
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	_meteor = MeshInstance3D.new()
	_meteor.mesh = sm
	_meteor.material_override = _unshaded(Color(1.0, 0.6, 0.2, 1.0))
	_meteor.visible = false
	add_child(_meteor)
	_hail = _make_hail()
	add_child(_hail)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


func _make_hail() -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.name = "Hail"
	ps.amount = 900
	ps.lifetime = 0.7
	ps.local_coords = false
	ps.emitting = false
	ps.visibility_aabb = AABB(Vector3(-45, -4, -45), Vector3(90, 30, 90))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 0.5, 24)
	pm.direction = Vector3(0.15, -1.0, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3.ZERO
	ps.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.14)
	qm.material = _unshaded(Color(0.95, 0.97, 1.0, 0.9))
	(qm.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ps.draw_pass_1 = qm
	return ps


# ------------------------------------------------------------------ events (one-shots)
func _on_game_event(ev_name: String, payload: Dictionary) -> void:
	if ev_name != "disaster":
		return
	match str(payload.get("kind", "")):
		"quake":
			if str(payload.get("phase", "")) == "impact":
				shake_left = 2.6
				shake_power = float(payload.get("power", 1))
		"hail":
			if str(payload.get("phase", "")) == "start":
				hail_left = 7.0
		"meteor":
			if str(payload.get("phase", "")) == "start":
				_meteor_t = 0.0
		"tornado":
			if str(payload.get("phase", "")) == "impact":
				_funnel_t = FUNNEL_SECONDS


# ------------------------------------------------------------------ per frame
func _focus() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3.ZERO
	var dir: Vector3 = -cam.global_transform.basis.z
	if absf(dir.y) < 0.01:
		return Vector3(cam.global_position.x, 0, cam.global_position.z)
	return cam.global_position + dir * (-cam.global_position.y / dir.y)


func targets() -> Dictionary:
	var hid: int = Economy.primary_household()
	var now: int = SysUtil.now()
	var t := {"siren": 0.0, "dark": 0.0, "white": 0.0, "haze": 0.0, "flood": 0.0}
	var tor: Dictionary = DisasterState.find("tornado")
	if not tor.is_empty() and str(tor["phase"]) == "siren":
		t["siren"] = 0.5 + 0.5 * sin(_time * 6.0)
	if DisasterState.affects("outage", hid):
		t["dark"] = 0.18 + (0.3 if Weather.is_dark() else 0.0)
	if DisasterState.running("blizzard"):
		t["white"] = 0.3
	if DisasterState.running("wildfire"):
		t["haze"] = 0.2
	if DisasterState.affects("flood", hid):
		t["flood"] = 1.0
	return t


func _process(delta: float) -> void:
	_time += delta
	var t: Dictionary = targets()
	for k in t:
		p[k] = lerpf(float(p[k]), float(t[k]), clampf(1.0 - exp(-delta * 2.5), 0.0, 1.0))
	if _funnel_t > 0.0:
		_funnel_t -= delta
	p["funnel"] = clampf(_funnel_t / FUNNEL_SECONDS, 0.0, 1.0)
	p["flash"] = maxf(float(p["flash"]) - delta * 1.6, 0.0)
	if shake_left > 0.0:
		shake_left -= delta
	if hail_left > 0.0:
		hail_left -= delta
	if headless:
		return
	_apply()


func _apply() -> void:
	(_rects["dark"] as ColorRect).color.a = float(p["dark"])
	(_rects["white"] as ColorRect).color.a = float(p["white"])
	(_rects["haze"] as ColorRect).color.a = float(p["haze"])
	(_rects["siren"] as ColorRect).color.a = float(p["siren"]) * 0.26
	(_rects["flash"] as ColorRect).color.a = float(p["flash"]) * 0.7
	var f: Vector3 = _focus()
	_funnel.visible = float(p["funnel"]) > 0.0
	if _funnel.visible:
		var u: float = 1.0 - float(p["funnel"])
		_funnel.position = f + Vector3(sin(u * 5.0) * 6.0 + (u - 0.5) * 18.0, 4.6, cos(u * 3.0) * 3.0)
		_funnel.rotation.y += 0.25
		_funnel.rotation.z = sin(_time * 3.0) * 0.08
	_water.visible = float(p["flood"]) > 0.02
	if _water.visible:
		_water.position = Vector3(f.x, lerpf(-0.2, 0.2, float(p["flood"])), f.z)
		(_water.material_override as StandardMaterial3D).albedo_color.a = 0.42 * float(p["flood"])
	_hail.visible = hail_left > 0.0
	_hail.emitting = hail_left > 0.0
	if hail_left > 0.0:
		_hail.position = f + Vector3(0, 14, 0)
	_apply_meteor(f)
	if shake_left > 0.0:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			var a: float = 0.12 * shake_power * clampf(shake_left, 0.0, 1.0)
			cam.h_offset = randf_range(-a, a)
			cam.v_offset = randf_range(-a, a)
	elif get_viewport().get_camera_3d() != null:
		var cam2: Camera3D = get_viewport().get_camera_3d()
		cam2.h_offset = 0.0
		cam2.v_offset = 0.0


func _apply_meteor(f: Vector3) -> void:
	if _meteor_t < 0.0:
		_meteor.visible = false
		return
	if _meteor_t == 0.0:
		_meteor_target = f + Vector3(randf_range(-3, 3), 0.3, randf_range(-3, 3))
	_meteor_t += get_process_delta_time()
	var k: float = _meteor_t / 0.8
	_meteor.visible = k < 1.0
	_meteor.position = _meteor_target + Vector3(18, 40, -18) * (1.0 - clampf(k, 0.0, 1.0))
	if k >= 1.0:
		p["flash"] = 1.0
		_meteor_t = -1.0
