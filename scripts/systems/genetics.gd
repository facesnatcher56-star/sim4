class_name Genetics
extends RefCounted
## Appearance + inheritance. Data: data/genetics.json.
##
## ===== APPEARANCE CONTRACT (the ANIMATION / folk_view agent renders exactly these keys) =====
## Folk.appearance : Dictionary
##   skin        : "#rrggbb"  skin tone (sRGB hex)
##   hair_style  : int 0..5   index into the hair styles of the folk model (6 styles)
##   hair_color  : "#rrggbb"
##   eye_color   : "#rrggbb"
##   shirt       : "#rrggbb"  top/torso colour (also the HUD portrait colour, see ui_color())
##   pants       : "#rrggbb"  legs colour
##   height      : float 0.9..1.1   multiplier on the ADULT body height (view scales babies/children on top of it)
##   build       : float 0.9..1.1   body width multiplier (1.0 = default)
##   color       : "#rrggbb"  convenience alias of `shirt` (UIU.folk_color already understands this key)
## Missing/empty appearance means "not generated yet": call Genetics.ensure(folk) (SystemsManager does it for everyone;
## Folk.create already assigns a random one).
##
## Inheritance: Genetics.inherit(parent_a, parent_b, rng) -> {appearance, traits}. Parents may be Folk objects or plain
## dictionaries {traits, appearance} (townies / people who left the lot).
##   * skin: linear-RGB blend of both parents at a random weight, plus small clamped per-channel mutation
##   * hair / eye colour: dominance rules (a parent's palette colour wins with probability proportional to its
##     dominance), occasional linear blend, rare palette mutation
##   * traits: each parent trait passes on with `trait_chance` (35%), plus `random_extra_traits` random trait(s) that
##     neither parent has, capped to the trait slots of `cap_stage`
##   * height / build: parent average + gaussian noise, clamped

const KEYS := ["skin", "hair_style", "hair_color", "eye_color", "shirt", "pants", "height", "build"]

## Independent rng so appearance never perturbs the gameplay rng (SysUtil.rng) and tests stay deterministic.
static var rng: RandomNumberGenerator = _make_rng()

static func _make_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

static func cfg() -> Dictionary:
	return SimEnv.data().get_table("genetics")

static func _r(r) -> RandomNumberGenerator:
	return r if r != null else rng

# ------------------------------------------------------------------ colour helpers
static func hex_to_linear(hex: String) -> Color:
	return Color.html(hex).srgb_to_linear()

static func linear_to_hex(c: Color) -> String:
	var s: Color = Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), 1.0).linear_to_srgb()
	return "#" + s.to_html(false)

## Blend two hex colours in linear RGB space (w = weight of b).
static func blend_hex(a: String, b: String, w: float) -> String:
	var la: Color = hex_to_linear(a)
	var lb: Color = hex_to_linear(b)
	return linear_to_hex(Color(lerpf(la.r, lb.r, w), lerpf(la.g, lb.g, w), lerpf(la.b, lb.b, w)))

static func _pick_hex(arr: Array, g: RandomNumberGenerator) -> String:
	if arr.is_empty():
		return "#808080"
	var v = arr[g.randi_range(0, arr.size() - 1)]
	return str(v["hex"]) if v is Dictionary else str(v)

# ------------------------------------------------------------------ random appearance
static func random_appearance(r: RandomNumberGenerator = null) -> Dictionary:
	var g: RandomNumberGenerator = _r(r)
	var c: Dictionary = cfg()
	var tones: Array = c.get("skin_tones", ["#d9a47f"])
	var t1: String = str(tones[g.randi_range(0, tones.size() - 1)])
	var t2: String = str(tones[g.randi_range(0, tones.size() - 1)])
	var hmin: float = float(c.get("height", {}).get("min", 0.9))
	var hmax: float = float(c.get("height", {}).get("max", 1.1))
	var bmin: float = float(c.get("build", {}).get("min", 0.9))
	var bmax: float = float(c.get("build", {}).get("max", 1.1))
	var shirt: String = _pick_hex(c.get("shirt_colors", []), g)
	return {
		"skin": blend_hex(t1, t2, g.randf()),
		"hair_style": g.randi_range(0, int(c.get("hair_styles", 6)) - 1),
		"hair_color": _pick_hex(c.get("hair_colors", []), g),
		"eye_color": _pick_hex(c.get("eye_colors", []), g),
		"shirt": shirt,
		"pants": _pick_hex(c.get("pants_colors", []), g),
		"height": snappedf(g.randf_range(hmin, hmax), 0.001),
		"build": snappedf(g.randf_range(bmin, bmax), 0.001),
		"color": shirt,
	}

## Fix types after a JSON round trip (ints become floats) and fill missing keys.
static func normalize(ap: Dictionary) -> Dictionary:
	if ap.is_empty():
		return {}
	var out: Dictionary = ap.duplicate(true)
	out["hair_style"] = int(out.get("hair_style", 0))
	out["height"] = float(out.get("height", 1.0))
	out["build"] = float(out.get("build", 1.0))
	for k in ["skin", "hair_color", "eye_color", "shirt", "pants"]:
		out[k] = str(out.get(k, "#808080"))
	out["color"] = str(out.get("color", out["shirt"]))
	return out

static func is_valid(ap) -> bool:
	if not (ap is Dictionary):
		return false
	for k in KEYS:
		if not (ap as Dictionary).has(k):
			return false
	return true

## Give a folk (or townie dict) an appearance if it has none. Returns the appearance.
static func ensure(f) -> Dictionary:
	if f is Dictionary:
		if not is_valid(f.get("appearance", {})):
			f["appearance"] = random_appearance()
		return f["appearance"]
	if not is_valid(f.appearance):
		f.appearance = random_appearance()
	return f.appearance

static func ensure_all() -> void:
	for f in WorldIface.all_folk():
		ensure(f)

# ------------------------------------------------------------------ UI colour
## HUD / portrait colour of a folk (derived from the shirt, so UIU.folk_colors is no longer needed).
static func ui_color(f) -> Color:
	var ap = null
	if f is Dictionary:
		ap = f.get("appearance", null)
	elif f != null and "appearance" in f:
		ap = f.appearance
	if ap is Dictionary and (ap as Dictionary).has("shirt"):
		return Color.html(str(ap["shirt"]))
	var nm: String = ""
	if f is Dictionary:
		nm = str(f.get("name", "x"))
	elif f != null and "name" in f:
		nm = str(f.name)
	return Color.from_hsv(float(absi(hash(nm)) % 360) / 360.0, 0.5, 0.85)

# ------------------------------------------------------------------ inheritance
static func _ap_of(p) -> Dictionary:
	var ap = null
	if p is Dictionary:
		ap = p.get("appearance", {})
	elif p != null:
		ap = p.appearance
	return ap if is_valid(ap) else {}

static func _traits_of(p) -> Array:
	if p is Dictionary:
		return (p.get("traits", []) as Array).duplicate()
	if p != null:
		return (p.traits as Array).duplicate()
	return []

static func _nearest_dom(palette: Array, hex: String) -> float:
	var best: float = 1.0
	var bd: float = 1.0e9
	var l: Color = hex_to_linear(hex)
	for e in palette:
		var le: Color = hex_to_linear(str(e["hex"]))
		var d: float = (l.r - le.r) * (l.r - le.r) + (l.g - le.g) * (l.g - le.g) + (l.b - le.b) * (l.b - le.b)
		if d < bd:
			bd = d
			best = float(e.get("dominance", 1.0))
	return best

static func _inherit_dominant(key_palette: String, ha: String, hb: String, mix_chance: float, g: RandomNumberGenerator) -> String:
	var c: Dictionary = cfg()
	var pal: Array = c.get(key_palette, [])
	var inh: Dictionary = c.get("inherit", {})
	if g.randf() < float(inh.get("palette_mutation_chance", 0.03)):
		return _pick_hex(pal, g)
	if g.randf() < mix_chance:
		return blend_hex(ha, hb, g.randf())
	var da: float = _nearest_dom(pal, ha)
	var db: float = _nearest_dom(pal, hb)
	return ha if g.randf() * (da + db) < da else hb

static func inherit_skin(sa: String, sb: String, g: RandomNumberGenerator) -> String:
	var inh: Dictionary = cfg().get("inherit", {})
	var w: float = clampf(g.randfn(0.5, float(inh.get("skin_weight_sigma", 0.18))), 0.0, 1.0)
	var la: Color = hex_to_linear(sa)
	var lb: Color = hex_to_linear(sb)
	var sig: float = float(inh.get("color_mutation_sigma", 0.012))
	var mx: float = float(inh.get("color_mutation_max", 0.03))
	var chan: Array = []
	for i in 3:
		var base: float = lerpf(la[i], lb[i], w)
		chan.append(base + clampf(g.randfn(0.0, sig), -mx, mx))
	return linear_to_hex(Color(chan[0], chan[1], chan[2]))

## opts: {chance: trait chance per parent trait, cap: max traits, cap_stage: stage whose slots cap them, extra: random extras}
static func inherit(parent_a, parent_b, r: RandomNumberGenerator = null, opts: Dictionary = {}) -> Dictionary:
	var g: RandomNumberGenerator = _r(r)
	var c: Dictionary = cfg()
	var inh: Dictionary = c.get("inherit", {})
	var aa: Dictionary = _ap_of(parent_a)
	var ab: Dictionary = _ap_of(parent_b)
	if aa.is_empty():
		aa = random_appearance(g)
	if ab.is_empty():
		ab = random_appearance(g)
	var hmin: float = float(c.get("height", {}).get("min", 0.9))
	var hmax: float = float(c.get("height", {}).get("max", 1.1))
	var bmin: float = float(c.get("build", {}).get("min", 0.9))
	var bmax: float = float(c.get("build", {}).get("max", 1.1))
	var ns: float = float(inh.get("body_noise_sigma", 0.02))
	var style: int = int(aa["hair_style"]) if g.randf() < 0.5 else int(ab["hair_style"])
	if g.randf() < float(inh.get("hair_style_random_chance", 0.12)):
		style = g.randi_range(0, int(c.get("hair_styles", 6)) - 1)
	var shirt: String = _pick_hex(c.get("shirt_colors", []), g)
	var ap: Dictionary = {
		"skin": inherit_skin(str(aa["skin"]), str(ab["skin"]), g),
		"hair_style": style,
		"hair_color": _inherit_dominant("hair_colors", str(aa["hair_color"]), str(ab["hair_color"]), float(inh.get("hair_mix_chance", 0.12)), g),
		"eye_color": _inherit_dominant("eye_colors", str(aa["eye_color"]), str(ab["eye_color"]), float(inh.get("eye_mix_chance", 0.08)), g),
		"shirt": shirt,
		"pants": _pick_hex(c.get("pants_colors", []), g),
		"height": snappedf(clampf((float(aa["height"]) + float(ab["height"])) * 0.5 + g.randfn(0.0, ns), hmin, hmax), 0.001),
		"build": snappedf(clampf((float(aa["build"]) + float(ab["build"])) * 0.5 + g.randfn(0.0, ns), bmin, bmax), 0.001),
		"color": shirt,
	}
	return {"appearance": ap, "traits": inherit_traits(parent_a, parent_b, g, opts)}

static func inherit_traits(parent_a, parent_b, r: RandomNumberGenerator = null, opts: Dictionary = {}) -> Array:
	var g: RandomNumberGenerator = _r(r)
	var inh: Dictionary = cfg().get("inherit", {})
	var chance: float = float(opts.get("chance", inh.get("trait_chance", 0.35)))
	var cap: int = int(opts.get("cap", Aging.trait_slots(str(opts.get("cap_stage", inh.get("cap_stage", "adult"))))))
	var from_parents: Array = []
	var pool: Array = []
	for p in [parent_a, parent_b]:
		for t in _traits_of(p):
			if not pool.has(t):
				pool.append(t)
			if g.randf() < chance and not from_parents.has(t):
				from_parents.append(t)
	var out: Array = []
	for t in from_parents:
		if out.size() < cap:
			out.append(t)
	# random extras: traits neither parent has
	var extras: int = int(opts.get("extra", inh.get("random_extra_traits", 1)))
	var cand: Array = []
	for t2 in SimEnv.data().traits():
		if not pool.has(t2):
			cand.append(str(t2))
	for _i in extras:
		if cand.is_empty() or out.size() >= cap:
			break
		var pick: String = str(cand[g.randi_range(0, cand.size() - 1)])
		cand.erase(pick)
		out.append(pick)
	return out
