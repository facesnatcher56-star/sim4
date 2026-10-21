extends "res://scripts/world/weather_precip.gd"
## WeatherView layer: warm lights at lamps / fireplaces after dark.


# ------------------------------------------------------------------ lamps
## Real lights for the nearest MAX_LIGHTS fixtures to the camera only (the big map has hundreds of lamps and screens): the rest cost nothing.
## Fixture rows (colour temperature, range, energy, which state key switches it) live in data/looks.json "lights".
func _refresh_lamps() -> void:
	var w = WorldIface.world()
	if w == null:
		return
	var defs: Dictionary = LightMood.light_defs()
	var focus := Vector2.ZERO
	var tg = lot.get("_target")
	if tg is Vector3:
		focus = Vector2((tg as Vector3).x, (tg as Vector3).z)
	var cands: Array = []
	for o in w.all_objects():
		if defs.has(str(o.def_id)):
			cands.append([(o.center2d() as Vector2).distance_squared_to(focus), o])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var seen: Dictionary = {}
	for i in mini(cands.size(), MAX_LIGHTS):
		var o = cands[i][1]
		var ld: Dictionary = defs[str(o.def_id)]
		seen[int(o.id)] = true
		var light: OmniLight3D = _lamp_lights.get(int(o.id), null)
		if light == null:
			light = OmniLight3D.new()
			light.shadow_enabled = false
			light.omni_range = float(ld["range"]) * Looks.ef("lamp_range", 1.0)
			light.light_color = (ld["color"] as Color) * Looks.ec("lamp_color", Color.WHITE) if str(ld.get("temp", "warm")) == "warm" else (ld["color"] as Color)
			light.omni_attenuation = 1.4
			var c: Vector2 = o.center2d()
			light.position = Vector3(c.x, float(ld["y"]), c.y)
			light.set_meta("flicker", float(ld.get("flicker", 0.0)))
			add_child(light)
			_lamp_lights[int(o.id)] = light
		var key: String = str(ld.get("state", "on"))
		var on: bool = (key == "" or bool(o.state.get(key, true))) and not bool(o.state.get("broken", false))
		light.set_meta("on", on)
		light.set_meta("base", float(ld["energy"]) * Looks.ef("lamp_energy", 1.0))
	for id in _lamp_lights.keys():
		if not seen.has(id):
			(_lamp_lights[id] as Node).queue_free()
			_lamp_lights.erase(id)


func _drop_lamps() -> void:
	for id in _lamp_lights:
		(_lamp_lights[id] as Node).queue_free()
	_lamp_lights.clear()
	_lamp_timer = 0.0


func _update_lamp_energy(dl: float) -> void:
	var dark: float = clampf(1.0 - dl * 1.15 + float(p["cloud"]) * 0.25 * dl, 0.0, 1.0)
	Looks.set_night_glow(dark, _hour)
	var t: float = Time.get_ticks_msec() * 0.001
	for id in _lamp_lights:
		var l: OmniLight3D = _lamp_lights[id]
		var on: bool = bool(l.get_meta("on", true))
		var e: float = float(l.get_meta("base", 1.0)) * dark if on else 0.0
		var fl: float = float(l.get_meta("flicker", 0.0))
		if fl > 0.0:
			e *= 1.0 - fl * (0.5 + 0.5 * sin(t * 9.0 + float(id) * 1.7) * sin(t * 3.1 + float(id)))      # fireplace / screen flicker
		l.light_energy = e
		l.visible = e > 0.02
	_update_fill(dark)


## A faint neutral fill light over the selected folk in the dark, so they stay readable whatever the look's night is (Night brightness setting).
func _update_fill(dark: float) -> void:
	if _fill == null:
		_fill = OmniLight3D.new()
		_fill.name = "FolkFill"
		_fill.shadow_enabled = false
		_fill.omni_range = 4.5
		_fill.omni_attenuation = 1.2
		add_child(_fill)
	_fill.light_color = Looks.ec("fill_color", Color(0.79, 0.82, 1.0))
	var e: float = LightMood.fill_energy(dark, _nb())
	var sel_ok: bool = lot.get("selected_kind") == "folk" and lot.get("_folk_views") is Dictionary and (lot.get("_folk_views") as Dictionary).has(lot.get("selected_id"))
	if sel_ok:
		var fv = (lot.get("_folk_views") as Dictionary)[lot.get("selected_id")]
		_fill.position = (fv.head_position() as Vector3) + Vector3(0, 1.2, 0)
	_fill.light_energy = e if sel_ok else 0.0
	_fill.visible = _fill.light_energy > 0.02


func _nb() -> float:
	return GameSettings.get_float("night_brightness") / 100.0
