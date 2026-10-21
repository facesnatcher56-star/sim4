class_name Looks
extends RefCounted
## Visual looks (task 41, view only: no sim state, no rng). data/looks.json holds named looks; the current one is a static switch.
## Static API, no autoload. `reference` is today's look and changes nothing; `grounded` is muted, dark-night and dirty.
## Who reads it: lot_chunks / level_mesher (floor colours + wear), lot_models / lot_shells (tint_tree on glb materials),
## WeatherView (env knobs, lamps, wet overlay, window glow), LookOverlay (vignette, grain), UITheme (ui colours).
## Initial look: `--look=<id>` (user args after `--`) or env SIM_LOOK, else the Settings "Visual style" value, else data default.
## Listen with Looks.bus.changed(id); LotView rebuilds its meshes on a change.

class Bus extends RefCounted:
	signal changed(id: String)

static var bus := Bus.new()
static var _data: Dictionary = {}
static var _id: String = ""
static var _cli_pending: String = ""
static var _inited := false
static var _mat_cache: Dictionary = {}       # "<material id>|<look>|<variant>" -> tinted material
static var _glass: Dictionary = {}           # key -> {mat, lit}

const PATH := "res://data/looks.json"
const SURFACES := ["floor_wood", "floor_tile", "floor_carpet", "ground", "grass", "road", "sidewalk", "sand", "water", "wall", "roof", "trim", "awning", "accent", "glass", "wood", "leaf", "sky"]
const ENV_KEYS := ["night_sky", "twilight", "twilight_mix", "sun_warm", "sun_white", "sun_base", "shadow_mult", "moon_color", "moon_energy", "amb_day", "amb_night",
	"amb_energy_day", "amb_energy_night", "exposure_night", "exposure_day", "saturation", "contrast", "brightness", "fog_tint", "fog_floor", "lamp_color",
	"lamp_energy", "lamp_range", "window_glow", "window_color", "wet_dark", "wet_color", "vignette", "grain"]
const UI_KEYS := ["bg", "panel", "panel_hi", "accent", "text", "muted", "radius"]
const WEAR_KEYS := ["floor_dirt", "stain_chance", "stain_color", "corner_dark"]
const DEFAULT_SHADER_CLASSES := []          # looks.json wear.shader_classes: surface classes drawn with WearShader (task 41a), e.g. wall and wood


static func data() -> Dictionary:
	if _data.is_empty():
		var fa := FileAccess.open(PATH, FileAccess.READ)
		if fa != null:
			var j := JSON.new()
			if j.parse(fa.get_as_text()) == OK and j.data is Dictionary:
				_data = j.data
	return _data


static func ids() -> Array:
	return (data().get("order", []) as Array).duplicate()


static func look(id: String) -> Dictionary:
	return (data().get("looks", {}) as Dictionary).get(id, {})


static func label(id: String) -> String:
	return str(look(id).get("label", id))


static func _ensure() -> void:
	if _inited:
		return
	_inited = true
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			want = a.substr(7)
	if want == "":
		want = OS.get_environment("SIM_LOOK")
	_cli_pending = want if not look(want).is_empty() else ""
	_id = _cli_pending if _cli_pending != "" else str(data().get("default", "reference"))


static func current_id() -> String:
	_ensure()
	return _id


static func cur() -> Dictionary:
	return look(current_id())


static func is_reference() -> bool:
	return current_id() == "reference"


## Switch the look (no setting is written). Notifies listeners only on a change.
static func set_look(id: String) -> void:
	_ensure()
	if look(id).is_empty() or id == _id:
		return
	_id = id
	_mat_cache.clear()
	_glass.clear()
	bus.changed.emit(id)


## Called by SettingsApply for the "visual_style" setting; the command line choice wins the first time (startup apply_all).
static func from_setting(id: String) -> void:
	_ensure()
	if _cli_pending != "":
		_cli_pending = ""
		return
	set_look(id)


# ------------------------------------------------------------------ colours

static func _col(v, d: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is String and v != "":
		return Color(v)
	return d


static func _identity(g: Dictionary) -> bool:
	return g.is_empty() or (is_equal_approx(float(g.get("sat", 1.0)), 1.0) and is_equal_approx(float(g.get("val", 1.0)), 1.0)
		and str(g.get("tint", "#ffffff")).to_lower() == "#ffffff" and is_zero_approx(float(g.get("lift", 0.0))))


## Colour of a surface class under the current look (identity for the reference look).
static func grade(surface: String, c: Color) -> Color:
	var g: Dictionary = (cur().get("surfaces", {}) as Dictionary).get(surface, {})
	if _identity(g):
		return c
	var s := clampf(c.s * float(g.get("sat", 1.0)), 0.0, 1.0)
	var v := clampf(c.v * float(g.get("val", 1.0)), 0.0, 1.0)
	var o := Color.from_hsv(c.h, s, v, c.a)
	var t := _col(g.get("tint", "#ffffff"), Color.WHITE)
	var lift := float(g.get("lift", 0.0))
	return Color(clampf(o.r * t.r + lift, 0.0, 1.0), clampf(o.g * t.g + lift, 0.0, 1.0), clampf(o.b * t.b + lift, 0.0, 1.0), c.a)


static func floor_class(ft: String) -> String:
	return str((data().get("floor_class", {}) as Dictionary).get(ft, ""))


static func _hash01(x: int, y: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Floor colour: palette replaces the base, then the class grade, then deterministic wear (grime, stains). Reference: returns `base`.
static func floor_color(ft: String, base: Color, t: Vector2i) -> Color:
	if is_reference():
		return base
	var l := cur()
	var c := base
	var pal: Dictionary = l.get("palette", {})
	if pal.has(ft):
		c = Color(str(pal[ft]))
	var cls := floor_class(ft)
	if cls != "":
		c = grade(cls, c)
	if ft in ["grass", "lawn", "water", "asphalt", "crosswalk"]:
		return c
	var w: Dictionary = l.get("wear", {})
	var dirt := float(w.get("floor_dirt", 0.0))
	if dirt > 0.0:
		c = c.darkened(dirt * _hash01(t.x, t.y, 11))
	var sc := float(w.get("stain_chance", 0.0))
	if sc > 0.0 and _hash01(t.x, t.y, 12) < sc:
		c = c.lerp(Color(str(w.get("stain_color", "#3a2f25"))), 0.35 + 0.3 * _hash01(t.x, t.y, 13))
	return c


# ------------------------------------------------------------------ env / ui

static func ef(key: String, d: float = 0.0) -> float:
	return float((cur().get("env", {}) as Dictionary).get(key, d))


static func ec(key: String, d: Color = Color.WHITE) -> Color:
	return _col((cur().get("env", {}) as Dictionary).get(key, null), d)


static func ui_col(key: String, d: Color) -> Color:
	return _col((cur().get("ui", {}) as Dictionary).get(key, null), d)


static func ui_radius(d: int) -> int:
	return int((cur().get("ui", {}) as Dictionary).get("radius", d))


# ------------------------------------------------------------------ glb materials

static func _class_of_material(mname: String) -> String:
	var m: Dictionary = data().get("material_class", {})
	if m.has(mname):
		return str(m[mname])
	for k in m:
		if (k as String).ends_with("*") and mname.begins_with((k as String).trim_suffix("*")):
			return str(m[k])
	return ""


## Tints the materials of an instantiated glb (walls, doors, windows, shells) by material name; shared copies are cached.
## `variant` separates window glow per building (some windows lit, some dark). Reference look: does nothing.
static func tint_tree(n: Node, variant: String = "") -> void:
	if is_reference() or n == null:
		return
	_tint_node(n, variant)


static func _tint_node(n: Node, variant: String) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var cls := _class_of_material(src.resource_name)
			if cls == "":
				continue
			var key := "%d|%s|%s" % [src.get_instance_id(), _id, variant if cls == "glass" else ""]
			var m: Material = _mat_cache.get(key)
			if m == null:
				var wear_cfg: Dictionary = cur().get("wear", {})
				if cls in (wear_cfg.get("shader_classes", DEFAULT_SHADER_CLASSES) as Array) and src.albedo_color.a >= 0.99:
					m = WearShader.material(grade(cls, src.albedo_color), src.roughness, float(wear_cfg.get("wall_base", 0.1)), _id)
				else:
					var sm := src.duplicate() as BaseMaterial3D
					sm.albedo_color = grade(cls, src.albedo_color)
					if cls == "glass":
						sm.emission_enabled = true
						sm.emission = ec("window_color", Color(1.0, 0.78, 0.45))
						sm.emission_energy_multiplier = 0.0
						_glass[key] = {"mat": sm, "lit": 0.35 + 0.65 * _hash01(variant.hash() & 0xFFFF, 7, 5) if variant != "" else 1.0}
					m = sm
				_mat_cache[key] = m
			mi.set_surface_override_material(s, m)
	for c in n.get_children():
		_tint_node(c, variant)


## WeatherView: 0 by day .. 1 in the dark; windows with a glow share light up.
static func set_night_glow(dark: float) -> void:
	var e := ef("window_glow", 0.0)
	for k in _glass:
		var g: Dictionary = _glass[k]
		(g["mat"] as BaseMaterial3D).emission_energy_multiplier = e * dark * float(g["lit"])
