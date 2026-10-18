class_name WeatherView
extends "res://scripts/world/weather_lamps.gd"
## Sky / sun / moon / weather for a LotView (see weather_state.gd for the layer chain): per-frame parameter smoothing, sun, sky.


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


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if lot == null or sun == null or env == null:
		return
	_apply(delta, false)


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
	var base: float = 0.9 * float(p["light"])
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
