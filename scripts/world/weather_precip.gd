extends "res://scripts/world/weather_scenery.gd"
## WeatherView layer: rain / snow particles and lightning.


func _make_rain() -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.name = "Rain"
	ps.amount = 2200
	ps.lifetime = 0.8
	ps.preprocess = 1.0
	ps.local_coords = false
	ps.emitting = false
	ps.visibility_aabb = AABB(Vector3(-45, -4, -45), Vector3(90, 30, 90))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(34, 0.5, 34)
	pm.direction = Vector3(0.12, -1.0, 0.04)
	pm.spread = 1.5
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3.ZERO
	ps.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.7, 0.8, 0.95, 0.3)
	mat.no_depth_test = false
	qm.material = mat
	ps.draw_pass_1 = qm
	return ps


func _make_snow() -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.name = "Snow"
	ps.amount = 5000
	ps.lifetime = 9.0
	ps.preprocess = 9.0
	ps.local_coords = false
	ps.emitting = false
	ps.visibility_aabb = AABB(Vector3(-45, -4, -45), Vector3(90, 30, 90))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(34, 0.5, 34)
	pm.direction = Vector3(0.1, -1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.3
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.3, -0.2, 0.1)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	ps.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.15, 0.15)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1, 1, 1, 0.9)
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	mat.albedo_texture = gt
	qm.material = mat
	ps.draw_pass_1 = qm
	return ps


func _update_lightning(delta: float, wid: String) -> void:
	_flash = maxf(_flash - delta * 3.2, 0.0)
	if wid == "thunderstorm":
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(5.0, 14.0)
			strike()


## A lightning flash (double pulse). Emits `thunder` after a short delay so audio can hook in later.
func strike(strength: float = 1.0) -> void:
	var flash_ok: bool = GameSettings.flashing_allowed()
	_flash = clampf(strength, 0.0, 1.0) if flash_ok else 0.0
	if not is_inside_tree():
		return
	if not flash_ok:
		var quiet := create_tween()
		quiet.tween_interval(0.9)
		quiet.tween_callback(func(): thunder.emit(strength))
		return
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func(): _flash = maxf(_flash, 0.7 * strength))
	tw.tween_interval(0.9)
	tw.tween_callback(func(): thunder.emit(strength))


func _on_game_event(ev_name: String, _payload: Dictionary) -> void:
	if ev_name == "lightning" and is_inside_tree():
		strike(1.0)
		_flash_timer = maxf(_flash_timer, 4.0)


func _update_particles(_delta: float) -> void:
	var target = lot.get("_target")
	var zoom: float = float(lot.get("_zoom"))
	var ctr: Vector3 = target if target is Vector3 else Vector3(16, 0, 12)
	var half: float = clampf(zoom * 1.5 + 8.0, 26.0, 52.0)
	var wind: float = Weather.wind()
	for ps in [rain, snow]:
		if ps == null:
			continue
		var pm: ParticleProcessMaterial = ps.process_material
		pm.emission_box_extents = Vector3(half, 0.5, half)
	rain.position = Vector3(ctr.x, 17.0, ctr.z)
	snow.position = Vector3(ctr.x, 12.0, ctr.z)
	var q: float = [0.0, 0.5, 1.0][clampi(GameSettings.effects_quality(), 0, 2)]
	var rp: float = float(p["rain"]) * q
	var sp: float = float(p["snow"]) * q
	_set_precip(rain, rp > 0.03)
	rain.amount_ratio = clampf(rp, 0.05, 1.0)
	(rain.process_material as ParticleProcessMaterial).direction = Vector3(0.1 + wind * 0.35, -1.0, 0.04)
	_set_precip(snow, sp > 0.03)
	snow.amount_ratio = clampf(sp / 0.6, 0.05, 1.0)
	(snow.process_material as ParticleProcessMaterial).gravity = Vector3(0.2 + wind * 1.4, -0.2, 0.1)
	# rain streaks dimmer at night
	var rm: StandardMaterial3D = (rain.draw_pass_1 as QuadMesh).material
	rm.albedo_color = Color(0.78, 0.88, 1.0, lerpf(0.16, 0.3, float(p["daylight"])))


func _set_precip(ps: GPUParticles3D, on: bool) -> void:
	if on and not ps.visible:
		ps.visible = true
		ps.emitting = true
		ps.restart()           # runs the preprocess again so the sky is already full of flakes / drops
	elif not on and ps.visible:
		ps.visible = false
		ps.emitting = false
