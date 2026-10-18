class_name WeatherView
extends Node3D
## Renders the sky / sun / moon / weather for a LotView (added as its child by LotView._ready; see attach()):
##  * day-night cycle: sun direction + colour, moon + cool ambient at night, sky colour, twilight, overcast dimming
##  * fog (depth fog on the orthographic camera), rain / snow GPUParticles3D that follow the camera, lightning flashes
##  * seasonal ground tint (grass overlay), snow cover + wet look, bare / leafy / blossom trees scenery ring
##  * warm point lights at lamps / fireplaces when it is dark
## Everything is driven from Weather / Seasons / Clock every frame (smoothed), so it follows time warp and forced weather.
## Headless: only the cheap parameter maths run (no particles, lights or scenery) so tests cannot crash.

signal thunder(strength: float)

const TREE_COUNT := 46
const LIGHT_DEFS := {"lamp": {"y": 1.5, "color": Color(1.0, 0.82, 0.55), "range": 5.5, "energy": 1.6},
	"pendant_light": {"y": 2.2, "color": Color(1.0, 0.85, 0.6), "range": 5.0, "energy": 1.5},
	"fireplace": {"y": 0.7, "color": Color(1.0, 0.55, 0.25), "range": 5.5, "energy": 1.8, "state": "lit"},
	"nightstand": {"y": 1.0, "color": Color(1.0, 0.82, 0.55), "range": 3.5, "energy": 0.8}}
const MAX_LIGHTS := 18

var lot: Node3D = null
var sun: DirectionalLight3D = null
var env: Environment = null
var moon: DirectionalLight3D = null
var rain: GPUParticles3D = null
var snow: GPUParticles3D = null
var grass_mi: MeshInstance3D = null
var snow_mi: MeshInstance3D = null
var scenery: Node3D = null
var headless: bool = false
## Smoothed parameters (read by tests / screenshots).
var p: Dictionary = {"light": 1.0, "cloud": 0.0, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wet": 0.0, "snowcover": 0.0, "daylight": 1.0}

var _grass_mat: StandardMaterial3D = null
var _snow_mat: StandardMaterial3D = null
var _leaf_mat: StandardMaterial3D = null
var _pine_mat: StandardMaterial3D = null
var _trees: Array = []          # {root, canopy, pine, snow_cap}
var _flash: float = 0.0
var _flash_timer: float = 6.0
var _lamp_lights: Dictionary = {}   # object id -> OmniLight3D
var _lamp_timer: float = 0.0
var _sky_flash_col: Color = Color.WHITE
var _floors_dirty: bool = true
var time_scale_real: float = 1.0
var fixed_hour: float = -1.0        # >= 0 pins the sun to this hour (screenshots)

static func ensure_on(lv: Node3D) -> WeatherView:
	var existing = lv.get_node_or_null("WeatherView")
	if existing != null:
		return existing
	var wv := WeatherView.new()
	wv.name = "WeatherView"
	lv.add_child(wv)
	wv.attach(lv)
	return wv

func attach(lv: Node3D) -> void:
	lot = lv
	headless = DisplayServer.get_name() == "headless"
	sun = lv.get("_sun")
	env = lv.get("_env")
	if sun == null or env == null:
		return
	if not headless:
		_build_visuals()
	var ev = SimEnv.events()
	if ev != null:
		ev.game_event.connect(_on_game_event)
		ev.object_placed.connect(func(_i): _lamp_timer = 0.0)
		ev.object_removed.connect(func(_i): _lamp_timer = 0.0)
		ev.object_state_changed.connect(func(_i, _k): _lamp_timer = minf(_lamp_timer, 0.2))
	var w = WorldIface.world()
	if w != null and w.has_signal("floors_changed"):
		w.floors_changed.connect(func(): _floors_dirty = true)
		w.world_reset.connect(func(): _floors_dirty = true)
	_apply(1.0, true)

# ------------------------------------------------------------------ construction
func _build_visuals() -> void:
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(145.0), 0.0)
	moon.light_color = Color(0.55, 0.66, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	lot.add_child(moon)
	_grass_mat = _overlay_mat()
	_snow_mat = _overlay_mat()
	grass_mi = MeshInstance3D.new()
	grass_mi.name = "SeasonGrass"
	grass_mi.material_override = _grass_mat
	grass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass_mi)
	snow_mi = MeshInstance3D.new()
	snow_mi.name = "SnowCover"
	snow_mi.material_override = _snow_mat
	snow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(snow_mi)
	rain = _make_rain()
	rain.visible = false
	add_child(rain)
	snow = _make_snow()
	snow.visible = false
	add_child(snow)
	scenery = Node3D.new()
	scenery.name = "Scenery"
	add_child(scenery)
	_build_trees()

func _overlay_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.albedo_color = Color(1, 1, 1, 0)
	return m

func _make_rain() -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.name = "Rain"
	ps.amount = 3200
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
	mat.albedo_color = Color(0.78, 0.88, 1.0, 0.5)
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

func _build_trees() -> void:
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.roughness = 0.9
	_pine_mat = StandardMaterial3D.new()
	_pine_mat.roughness = 0.9
	_pine_mat.albedo_color = Color(0.16, 0.36, 0.22)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.25, 0.16)
	trunk_mat.roughness = 1.0
	var snow_cap_mat := StandardMaterial3D.new()
	snow_cap_mat.albedo_color = Color(0.96, 0.98, 1.0)
	snow_cap_mat.roughness = 1.0
	var cx: float = 16.0
	var cy: float = 12.0
	var w = WorldIface.world()
	var ww: float = float(w.width) if w != null else 32.0
	var wh: float = float(w.height) if w != null else 24.0
	cx = ww * 0.5
	cy = wh * 0.5
	var r := RandomNumberGenerator.new()
	r.seed = 424242
	var n: int = 0
	var guard: int = 0
	while n < TREE_COUNT and guard < 2000:
		guard += 1
		var x: float = r.randf_range(-22.0, ww + 22.0)
		var z: float = r.randf_range(-20.0, wh + 20.0)
		# keep a clear margin around the lot so trees never hide the house from the iso camera
		var dx: float = maxf(maxf(-x, x - ww), 0.0)
		var dz: float = maxf(maxf(-z, z - wh), 0.0)
		if maxf(dx, dz) < 5.5:
			continue
		var pine: bool = r.randf() < 0.28
		var root := Node3D.new()
		root.position = Vector3(x, 0.0, z)
		var sc: float = r.randf_range(0.85, 1.35)
		root.scale = Vector3(sc, sc, sc)
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.11
		tm.bottom_radius = 0.17
		tm.height = 1.1
		trunk.mesh = tm
		trunk.material_override = trunk_mat
		trunk.position.y = 0.55
		root.add_child(trunk)
		var canopy := Node3D.new()
		canopy.position.y = 1.0
		root.add_child(canopy)
		var cap: MeshInstance3D = null
		if pine:
			for i in 3:
				var cm := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 1.0 - float(i) * 0.27
				cone.height = 1.1
				cm.mesh = cone
				cm.material_override = _pine_mat
				cm.position.y = 0.45 + float(i) * 0.6
				canopy.add_child(cm)
			cap = MeshInstance3D.new()
			var capm := CylinderMesh.new()
			capm.top_radius = 0.0
			capm.bottom_radius = 0.55
			capm.height = 0.6
			cap.mesh = capm
			cap.material_override = snow_cap_mat
			cap.position.y = 1.95
			canopy.add_child(cap)
		else:
			for i2 in 3:
				var sm := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 0.85 - 0.15 * float(i2)
				sp.height = sp.radius * 2.0
				sm.mesh = sp
				sm.material_override = _leaf_mat
				sm.position = Vector3(r.randf_range(-0.35, 0.35) if i2 > 0 else 0.0, 0.8 + 0.4 * float(i2), r.randf_range(-0.3, 0.3) if i2 > 0 else 0.0)
				canopy.add_child(sm)
		scenery.add_child(root)
		_trees.append({"root": root, "canopy": canopy, "pine": pine, "cap": cap, "blossom": (not pine) and r.randf() < 0.45})
		n += 1

# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if lot == null or sun == null or env == null:
		return
	_apply(delta, false)

func _season_col(key: String, pos: float, default: Color) -> Color:
	var arr: Array = Seasons.cfg().get("seasons", [])
	if arr.size() < 4:
		return default
	var q: float = fposmod(pos - 0.5, 4.0)
	var i0: int = int(floor(q)) % 4
	var f: float = q - floor(q)
	f = f * f * (3.0 - 2.0 * f)
	var a := Color(str((arr[i0] as Dictionary).get(key, default.to_html())))
	var b := Color(str((arr[(i0 + 1) % 4] as Dictionary).get(key, default.to_html())))
	return a.lerp(b, f)

func _season_num(key: String, pos: float, default: float) -> float:
	var arr: Array = Seasons.cfg().get("seasons", [])
	if arr.size() < 4:
		return default
	var q: float = fposmod(pos - 0.5, 4.0)
	var i0: int = int(floor(q)) % 4
	var f: float = q - floor(q)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float((arr[i0] as Dictionary).get(key, default)), float((arr[(i0 + 1) % 4] as Dictionary).get(key, default)), f)

func _smooth(cur: float, target: float, delta: float, rate: float) -> float:
	return lerpf(cur, target, clampf(1.0 - exp(-delta * rate), 0.0, 1.0))

func _apply(delta: float, snap: bool) -> void:
	var clk = SimEnv.clock()
	var hour: float = fixed_hour if fixed_hour >= 0.0 else (float(clk.hour_f()) if clk != null else 12.0)
	var rate: float = 100.0 if snap else 1.6
	var wid: String = Weather.current()
	var kind: String = Weather.precip_kind(wid)
	var inten: float = Weather.precip_intensity(wid)
	p["light"] = _smooth(float(p["light"]), Weather.light_factor(wid), delta, rate)
	p["cloud"] = _smooth(float(p["cloud"]), Weather.cloud_cover(wid), delta, rate)
	p["fog"] = _smooth(float(p["fog"]), Weather.fog_amount(wid), delta, rate * 0.7)
	p["rain"] = _smooth(float(p["rain"]), inten if kind == "rain" else 0.0, delta, rate * 1.5)
	p["snow"] = _smooth(float(p["snow"]), inten if kind == "snow" else 0.0, delta, rate * 1.5)
	p["wet"] = _smooth(float(p["wet"]), Weather.wetness(), delta, rate * 0.5)
	p["snowcover"] = _smooth(float(p["snowcover"]), Weather.snow_cover(), delta, rate * 0.5)
	var dl: float = Weather.daylight(hour)
	p["daylight"] = dl
	var pos: float = Seasons.year_pos(-1, hour)
	_update_sun(hour, dl, pos)
	_update_sky(dl, wid)
	_update_lightning(delta, wid)
	if not headless:
		_update_particles(delta)
		_update_ground(pos)
		_update_trees(pos)
		_lamp_timer -= delta
		if _lamp_timer <= 0.0:
			_lamp_timer = 1.0
			_refresh_lamps()
		_update_lamp_energy(dl)

func _update_sun(hour: float, dl: float, pos: float) -> void:
	var sr: float = Seasons.sunrise(pos)
	var ss: float = Seasons.sunset(pos)
	var t: float = clampf((hour - sr) / maxf(ss - sr, 1.0), 0.0, 1.0)
	var peak: float = lerpf(34.0, 66.0, clampf((Seasons.daylight_hours(pos) - 8.5) / 7.0, 0.0, 1.0))   # low winter sun, high summer sun
	var elev: float = lerpf(7.0, peak, sin(PI * t))
	var yaw: float = lerpf(-105.0, 35.0, t)
	sun.rotation = Vector3(deg_to_rad(-elev), deg_to_rad(yaw), 0.0)
	var warm := Color(1.0, 0.6, 0.36)
	var white := Color(1.0, 0.97, 0.9)
	sun.light_color = warm.lerp(white, clampf(sin(PI * t) * 1.6, 0.0, 1.0)).lerp(_weather_tint(), 0.6)
	var base: float = 0.98 * float(p["light"])
	sun.light_energy = base * dl + _flash * 0.9
	sun.shadow_enabled = dl > 0.12 and float(p["light"]) > 0.35
	sun.shadow_opacity = clampf(float(p["light"]) * 1.2 - 0.1, 0.25, 1.0)
	if moon != null:
		moon.light_energy = (1.0 - dl) * 0.55 * (1.0 - float(p["cloud"]) * 0.55) + _flash * 0.4
	# ambient: cool and readable at night, bright and neutral by day, a touch richer when overcast (diffuse)
	var amb_day := Color(0.78, 0.8, 0.86)
	var amb_night := Color(0.2, 0.25, 0.46)
	env.ambient_light_color = amb_night.lerp(amb_day, dl)
	var dim: float = lerpf(1.0, 0.72, clampf(1.0 - float(p["light"]), 0.0, 1.0) * 1.2)
	env.ambient_light_energy = lerpf(0.62, 0.62, dl) * dim + _flash * 0.45
	env.tonemap_exposure = lerpf(1.1, 1.0, dl)
	# overcast / stormy / foggy days look washed out and grey
	env.adjustment_enabled = true
	env.adjustment_saturation = lerpf(1.0, 0.62, clampf(float(p["cloud"]) * 0.8 + float(p["fog"]) * 0.3, 0.0, 1.0))
	env.adjustment_contrast = lerpf(1.0, 0.94, float(p["fog"]))

## Colour cast of the current weather on the sunlight (heatwave warm, cold snap blue, white = none).
func _weather_tint() -> Color:
	var t: String = str(Weather.def().get("tint", ""))
	return Color(t) if t != "" else Color(1, 1, 1)

func _update_sky(dl: float, wid: String) -> void:
	var day_sky: Color = Weather.sky_color(wid)
	var night_sky := Color(0.035, 0.045, 0.11)
	var tw := Color(0.92, 0.55, 0.42)
	var sky: Color = night_sky.lerp(day_sky, dl)
	var twilight: float = 4.0 * dl * (1.0 - dl)
	sky = sky.lerp(tw.lerp(day_sky, 0.35), twilight * 0.55 * (1.0 - float(p["cloud"]) * 0.5))
	if float(p["snowcover"]) > 0.1:
		sky = sky.lerp(Color(0.8, 0.84, 0.9) * (0.25 + 0.75 * dl), float(p["snowcover"]) * 0.25)
	sky = sky.lerp(Color(0.85, 0.9, 1), _flash * 0.4)
	env.background_color = sky
	var fog: float = float(p["fog"])
	if fog > 0.03:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = (Color(0.72, 0.75, 0.78) * (0.25 + 0.75 * dl)).lerp(sky, 0.3)
		env.fog_depth_begin = lerpf(85.0, 52.0, fog)
		env.fog_depth_end = lerpf(160.0, 78.0, fog)
		env.fog_depth_curve = 1.0
		env.fog_density = clampf(fog * 1.05, 0.0, 1.0)
		env.fog_sun_scatter = 0.0
	else:
		env.fog_enabled = false

func _update_lightning(delta: float, wid: String) -> void:
	_flash = maxf(_flash - delta * 3.2, 0.0)
	if wid == "thunderstorm":
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(5.0, 14.0)
			strike()

## A lightning flash (double pulse). Emits `thunder` after a short delay so audio can hook in later.
func strike(strength: float = 1.0) -> void:
	_flash = clampf(strength, 0.0, 1.0)
	if not is_inside_tree():
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
	var rp: float = float(p["rain"])
	var sp: float = float(p["snow"])
	_set_precip(rain, rp > 0.03)
	rain.amount_ratio = clampf(rp, 0.05, 1.0)
	(rain.process_material as ParticleProcessMaterial).direction = Vector3(0.1 + wind * 0.35, -1.0, 0.04)
	_set_precip(snow, sp > 0.03)
	snow.amount_ratio = clampf(sp / 0.6, 0.05, 1.0)
	(snow.process_material as ParticleProcessMaterial).gravity = Vector3(0.2 + wind * 1.4, -0.2, 0.1)
	# rain streaks dimmer at night
	var rm: StandardMaterial3D = (rain.draw_pass_1 as QuadMesh).material
	rm.albedo_color = Color(0.78, 0.88, 1.0, lerpf(0.28, 0.5, float(p["daylight"])))

func _set_precip(ps: GPUParticles3D, on: bool) -> void:
	if on and not ps.visible:
		ps.visible = true
		ps.emitting = true
		ps.restart()           # runs the preprocess again so the sky is already full of flakes / drops
	elif not on and ps.visible:
		ps.visible = false
		ps.emitting = false

func _update_ground(pos: float) -> void:
	if _floors_dirty:
		_rebuild_overlays()
	var tint: Color = _season_col("grass_tint", pos, Color("#9be36a"))
	var alpha: float = _season_num("grass_alpha", pos, 0.2)
	var wet: float = float(p["wet"])
	var snowc: float = float(p["snowcover"])
	# wet ground darkens and turns bluish; snow covers everything
	var g: Color = tint.lerp(Color(0.12, 0.16, 0.2), wet * 0.5)
	var ga: float = clampf(alpha + wet * 0.25, 0.0, 1.0)
	g = g.lerp(Color(0.95, 0.97, 1.0), snowc)
	ga = lerpf(ga, 0.96, snowc)
	_grass_mat.albedo_color = Color(g.r, g.g, g.b, ga)
	var sc := Color(0.95, 0.97, 1.0, clampf(snowc * 0.95, 0.0, 0.95))
	if snow_mi != null:
		snow_mi.visible = snowc > 0.02
	_snow_mat.albedo_color = sc
	var ground = lot.get("_ground_mi")
	if ground != null and ground is MeshInstance3D and (ground as MeshInstance3D).material_override is StandardMaterial3D:
		var gc: Color = _season_col("ground", pos, Color("#6fb050"))
		gc = gc.lerp(Color(0.1, 0.14, 0.12), wet * 0.3)
		gc = gc.lerp(Color(0.92, 0.95, 0.98), snowc)
		((ground as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = gc

func _rebuild_overlays() -> void:
	_floors_dirty = false
	var w = WorldIface.world()
	if w == null or grass_mi == null:
		return
	var st_g := SurfaceTool.new()
	var st_s := SurfaceTool.new()
	st_g.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var snow_types := ["grass", "dirt", "stone", "concrete"]
	var ng: int = 0
	var ns: int = 0
	for y in int(w.height):
		for x in int(w.width):
			var ft: String = w.get_floor(Vector2i(x, y))
			var is_grass: bool = ft == "grass"
			var is_snow: bool = snow_types.has(ft)
			if not is_snow:
				continue
			var a := Vector3(x, 0.0, y)
			var b := Vector3(x + 1, 0.0, y)
			var c := Vector3(x + 1, 0.0, y + 1)
			var d := Vector3(x, 0.0, y + 1)
			if is_grass:
				for v in [a, b, c, a, c, d]:
					st_g.set_normal(Vector3.UP)
					st_g.add_vertex((v as Vector3) + Vector3(0, 0.006, 0))
				ng += 1
			for v2 in [a, b, c, a, c, d]:
				st_s.set_normal(Vector3.UP)
				st_s.add_vertex((v2 as Vector3) + Vector3(0, 0.009, 0))
			ns += 1
	grass_mi.mesh = st_g.commit() if ng > 0 else null
	snow_mi.mesh = st_s.commit() if ns > 0 else null

func _update_trees(pos: float) -> void:
	var leaf: Color = _season_col("leaf", pos, Color("#3f9a3a"))
	var leaf_amt: float = _season_num("leaf_alpha", pos, 1.0)
	var snowc: float = float(p["snowcover"])
	var spring_f: float = clampf(1.0 - absf(pos - 0.5) * 3.0, 0.0, 1.0)     # blossoms peak mid spring
	var bl := Color(str(Seasons.info("spring").get("blossom", "#f6b8d0")))
	_leaf_mat.albedo_color = leaf.lerp(Color(0.95, 0.97, 1.0), snowc * 0.4)
	_pine_mat.albedo_color = Color(0.16, 0.36, 0.22).lerp(Color(0.85, 0.9, 0.95), snowc * 0.55)
	for t in _trees:
		var canopy: Node3D = t["canopy"]
		if bool(t["pine"]):
			canopy.visible = true
			var cap = t["cap"]
			if cap != null:
				(cap as Node3D).visible = snowc > 0.1
		else:
			var s: float = clampf(leaf_amt, 0.0, 1.0)
			canopy.visible = s > 0.06
			canopy.scale = Vector3.ONE * lerpf(0.55, 1.0, s)
	# blossoms: tint a share of deciduous canopies pink in spring
	for t2 in _trees:
		if bool(t2["blossom"]) and spring_f > 0.01:
			for c2 in (t2["canopy"] as Node3D).get_children():
				if c2 is MeshInstance3D:
					(c2 as MeshInstance3D).material_override = _blossom_mat(bl.lerp(leaf, 1.0 - spring_f))
		elif not bool(t2["pine"]) and bool(t2["blossom"]):
			for c3 in (t2["canopy"] as Node3D).get_children():
				if c3 is MeshInstance3D and (c3 as MeshInstance3D).material_override != _leaf_mat:
					(c3 as MeshInstance3D).material_override = _leaf_mat

var _blossom: StandardMaterial3D = null
func _blossom_mat(c: Color) -> StandardMaterial3D:
	if _blossom == null:
		_blossom = StandardMaterial3D.new()
		_blossom.roughness = 0.9
	_blossom.albedo_color = c
	return _blossom

# ------------------------------------------------------------------ lamps
func _refresh_lamps() -> void:
	var w = WorldIface.world()
	if w == null:
		return
	var seen: Dictionary = {}
	var count: int = 0
	for o in w.all_objects():
		var ld: Dictionary = LIGHT_DEFS.get(str(o.def_id), {})
		if ld.is_empty() or count >= MAX_LIGHTS:
			continue
		count += 1
		seen[int(o.id)] = true
		var light: OmniLight3D = _lamp_lights.get(int(o.id), null)
		if light == null:
			light = OmniLight3D.new()
			light.shadow_enabled = false
			light.omni_range = float(ld["range"])
			light.light_color = ld["color"]
			light.omni_attenuation = 1.4
			var c: Vector2 = o.center2d()
			light.position = Vector3(c.x, float(ld["y"]), c.y)
			add_child(light)
			_lamp_lights[int(o.id)] = light
		var key: String = str(ld.get("state", "on"))
		var on: bool = bool(o.state.get(key, true)) and not bool(o.state.get("broken", false))
		light.set_meta("on", on)
		light.set_meta("base", float(ld["energy"]))
	for id in _lamp_lights.keys():
		if not seen.has(id):
			(_lamp_lights[id] as Node).queue_free()
			_lamp_lights.erase(id)

func _update_lamp_energy(dl: float) -> void:
	var dark: float = clampf(1.0 - dl * 1.15 + float(p["cloud"]) * 0.25 * dl, 0.0, 1.0)
	var t: float = Time.get_ticks_msec() * 0.001
	for id in _lamp_lights:
		var l: OmniLight3D = _lamp_lights[id]
		var on: bool = bool(l.get_meta("on", true))
		var e: float = float(l.get_meta("base", 1.0)) * dark if on else 0.0
		if l.light_color.r > 0.95 and l.light_color.g < 0.6:
			e *= 0.9 + 0.1 * sin(t * 9.0 + float(id))      # fireplace flicker
		l.light_energy = e
		l.visible = e > 0.02
