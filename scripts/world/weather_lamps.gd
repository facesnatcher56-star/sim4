extends "res://scripts/world/weather_precip.gd"
## WeatherView layer: warm lights at lamps / fireplaces after dark.


# ------------------------------------------------------------------ lamps
func _refresh_lamps() -> void:
	var w = WorldIface.world()
	if w == null:
		return
	var seen: Dictionary = {}
	var count: int = 0
	var objs: Array = w.all_objects()
	if "regions" in w and w.regions.has_regions() and not w.regions.home().is_empty():
		var hr: Rect2i = w.regions.home()["rect"]      # big map: the player's own lot gets the light budget first
		objs = objs.filter(func(o): return hr.has_point(o.tile)) + objs.filter(func(o): return not hr.has_point(o.tile))
	for o in objs:
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
