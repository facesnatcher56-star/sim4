class_name GeneticsLook
extends RefCounted
## The expanded part of the appearance contract (body shape, face, hair, accessories, clothing) and the perceptual
## "how different do two folk look" measure used for the no-clones rule. Data: data/genetics.json.
##
## New appearance keys (all ints unless noted; every index is a toggleable mesh of the folk model, see FolkRigStyle):
##   body_type 0..2 slim/average/broad   frame 0..2 neutral/soft/angular   face 0..15 (eyes = face % 4, nose = face / 4)
##   mouth 0..3  brows 0..3  ears 0..2   facial_hair 0..3 none/moustache/goatee/beard   mark 0..2 none/freckles/mole
##   glasses 0..2  hat 0..2 none/cap/beanie  scarf 0..1  bag 0..2 none/backpack/satchel
##   top 0..6 tee/hoodie/sweater/shirt/dress/apron/uniform   bottom 0..2 trousers/shorts/skirt   shoes 0..3 shoes/boots/barefoot/sneakers
##   accent "#rrggbb" (cap, scarf, bag, apron, collar...)   shoe_color "#rrggbb"   hair_style 0..15

const INT_KEYS := ["hair_style", "body_type", "frame", "face", "mouth", "brows", "ears", "facial_hair", "mark", "glasses", "hat",
	"scarf", "bag", "top", "bottom", "shoes"]
const NEUTRAL := {"hair_style": 0, "body_type": 1, "frame": 0, "face": 0, "mouth": 0, "brows": 0, "ears": 0, "facial_hair": 0,
	"mark": 0, "glasses": 0, "hat": 0, "scarf": 0, "bag": 0, "top": 0, "bottom": 0, "shoes": 0, "accent": "#d9d9d9", "shoe_color": "#241c1a"}
const DEFAULT_COUNTS := {"hair_style": 16, "body_type": 3, "frame": 3, "face": 16, "mouth": 4, "brows": 4, "ears": 3, "facial_hair": 4,
	"mark": 3, "glasses": 3, "hat": 3, "scarf": 2, "bag": 3, "top": 7, "bottom": 3, "shoes": 4}


static func counts() -> Dictionary:
	var c: Dictionary = DEFAULT_COUNTS.duplicate()
	c.merge(Genetics.cfg().get("counts", {}), true)
	return c


## Index 0..n-1 by weights (an array of floats), falling back to uniform.
static func pick_w(weights: Array, g: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var x := g.randf() * total
	for i in weights.size():
		x -= float(weights[i])
		if x < 0.0:
			return i
	return weights.size() - 1


static func _chance(key: String, def: float) -> float:
	return float(Genetics.cfg().get("chance", {}).get(key, def))


static func _hex(arr: Array, g: RandomNumberGenerator, def: String) -> String:
	return Genetics.pick_hex(arr, g) if not arr.is_empty() else def


## Random body / face / hair style / accessories / clothes (everything except the colour traits skin, hair, eyes and height).
static func random_look(g: RandomNumberGenerator, sex: String = "") -> Dictionary:
	var c: Dictionary = Genetics.cfg()
	var n: Dictionary = counts()
	var ap := {}
	ap["hair_style"] = g.randi_range(0, int(n["hair_style"]) - 1)
	ap["body_type"] = pick_w(GeneticsSex.weights(sex, "body_type", [0.3, 0.4, 0.3]), g)
	ap["frame"] = pick_w(GeneticsSex.weights(sex, "frame", [0.4, 0.3, 0.3]), g)
	ap["face"] = g.randi_range(0, int(n["face"]) - 1)
	ap["mouth"] = g.randi_range(0, int(n["mouth"]) - 1)
	ap["brows"] = g.randi_range(0, int(n["brows"]) - 1)
	ap["ears"] = g.randi_range(0, int(n["ears"]) - 1)
	ap["facial_hair"] = (1 + g.randi_range(0, 2)) if g.randf() < _chance("facial_hair", 0.22) else 0
	GeneticsSex.fit(ap, sex, g)
	ap["mark"] = (1 + g.randi_range(0, 1)) if g.randf() < _chance("mark", 0.2) else 0
	random_outfit(ap, g, c)
	return ap


## Clothes + accessories only (used by the uniqueness rerolls and by FolkOutfits).
static func random_outfit(ap: Dictionary, g: RandomNumberGenerator, c: Dictionary = {}) -> void:
	if c.is_empty():
		c = Genetics.cfg()
	var shirt := _hex(c.get("shirt_colors", []), g, "#4f9ec4")
	ap["shirt"] = shirt
	ap["color"] = shirt
	ap["pants"] = _hex(c.get("pants_colors", []), g, "#3a4660")
	ap["accent"] = _hex(c.get("accent_colors", []), g, "#e8e2d0")
	ap["shoe_color"] = _hex(c.get("shoe_colors", []), g, "#241c1a")
	ap["top"] = pick_w(c.get("top_weights", [3, 2, 2, 2, 1.2, 0.5, 0.8]), g)
	ap["bottom"] = 0 if int(ap["top"]) == 4 else pick_w(c.get("bottom_weights", [0.6, 0.2, 0.2]), g)
	ap["shoes"] = pick_w(c.get("shoe_weights", [0.5, 0.2, 0.05, 0.25]), g)
	ap["glasses"] = (1 + g.randi_range(0, 1)) if g.randf() < _chance("glasses", 0.2) else 0
	ap["hat"] = (1 + g.randi_range(0, 1)) if g.randf() < _chance("hat", 0.15) else 0
	ap["scarf"] = 1 if g.randf() < _chance("scarf", 0.1) else 0
	ap["bag"] = (1 + g.randi_range(0, 1)) if g.randf() < _chance("bag", 0.18) else 0
	if int(ap["hat"]) > 0 and Genetics.HAT_BLOCK.has(int(ap.get("hair_style", 0))):
		ap["hat"] = 0


## Fill / fix the new keys of an appearance (old saves lack them): deterministic from the legacy values, never random.
static func upgrade(out: Dictionary) -> void:
	var missing := false
	for k in INT_KEYS:
		if not out.has(k):
			missing = true
	if not out.has("accent") or not out.has("shoe_color"):
		missing = true
	if missing:
		var g := RandomNumberGenerator.new()
		g.seed = ("%s|%s|%s|%s|%s" % [out.get("skin", ""), out.get("hair_color", ""), out.get("shirt", ""), out.get("pants", ""),
			out.get("hair_style", 0)]).hash()
		var look: Dictionary = random_look(g)
		look["hair_style"] = int(out.get("hair_style", look["hair_style"]))
		look["shirt"] = out.get("shirt", look["shirt"])
		look["pants"] = out.get("pants", look["pants"])
		for k in look:
			if not out.has(k):
				out[k] = look[k]
	var n: Dictionary = counts()
	for k in INT_KEYS:
		out[k] = clampi(int(out.get(k, NEUTRAL[k])), 0, int(n[k]) - 1)
	out["accent"] = str(out.get("accent", NEUTRAL["accent"]))
	out["shoe_color"] = str(out.get("shoe_color", NEUTRAL["shoe_color"]))


# ------------------------------------------------------------------ perceptual measure
## Colour band: 0 black, 1 grey, 2 white, else 3 + hue bin * 2 + dark flag.
static func cband(hex: String) -> int:
	var c := Color.html(hex)
	if c.s < 0.18:
		return 0 if c.v < 0.35 else (1 if c.v < 0.72 else 2)
	return 3 + (int(c.h * 12.0) % 12) * 2 + (1 if c.v < 0.62 else 0)


static func hair_band(hex: String) -> int:
	var pal: Array = Genetics.cfg().get("hair_colors", [])
	var l := Genetics.hex_to_linear(hex)
	var best := 0
	var bd := 1.0e9
	for i in pal.size():
		var e := Genetics.hex_to_linear(str(pal[i]["hex"]))
		var d := (l.r - e.r) * (l.r - e.r) + (l.g - e.g) * (l.g - e.g) + (l.b - e.b) * (l.b - e.b)
		if d < bd:
			bd = d
			best = i
	return best


static func skin_band(hex: String) -> int:
	var l := Genetics.hex_to_linear(hex)
	return clampi(int((0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b) * 6.5), 0, 4)


static func height_band(h: float) -> int:
	return 0 if h < 0.967 else (1 if h < 1.033 else 2)


## The perceptual channels of an appearance (all small ints). Order = WEIGHTS order.
static func channels(ap: Dictionary) -> Array:
	var a: Dictionary = ap if ap.has("top") else Genetics.normalize(ap)
	var acc: int = (1 if int(a["hat"]) > 0 and not Genetics.HAT_BLOCK.has(int(a["hair_style"])) else 0) | (2 if int(a["glasses"]) > 0 else 0) \
		| (4 if int(a["scarf"]) > 0 else 0) | (8 if int(a["bag"]) > 0 else 0)
	return [
		int(a["hair_style"]),
		hair_band(str(a["hair_color"])),
		skin_band(str(a["skin"])),
		int(a["top"]) * 64 + cband(str(a["shirt"])),
		acc,
		int(a["body_type"]) * 3 + int(a["frame"]),
		int(a["bottom"]) * 64 + cband(str(a["pants"])),
		height_band(float(a["height"])),
		int(a["face"]) * 16 + int(a["facial_hair"]) * 3 + int(a["mark"]),
	]


static func weights() -> Array:
	return Genetics.cfg().get("distinct", {}).get("weights", [1.0, 1.0, 1.0, 1.0, 1.0, 0.75, 0.5, 0.5, 0.5])


## Weighted number of perceptual channels in which two appearances (given as channels()) differ.
static func distance_ch(ca: Array, cb: Array, w: Array) -> float:
	var d := 0.0
	for i in ca.size():
		if ca[i] != cb[i]:
			d += float(w[i])
	return d


static func distance(a: Dictionary, b: Dictionary) -> float:
	return distance_ch(channels(a), channels(b), weights())


static func signature(ap: Dictionary) -> String:
	return ".".join(PackedStringArray(channels(ap).map(func(x): return str(x))))


# ------------------------------------------------------------------ inheritance of the look
static func _drift(v: int, n: int, g: RandomNumberGenerator, chance: float) -> int:
	if g.randf() < chance:
		return clampi(v + (1 if g.randf() < 0.5 else -1), 0, n - 1)
	return v


## Family-resemblance keys of a child: body shape, face parts, marks and glasses come from a parent, clothes are fresh.
static func inherit_look(aa: Dictionary, ab: Dictionary, g: RandomNumberGenerator) -> Dictionary:
	var n: Dictionary = counts()
	var pa: Dictionary = aa if g.randf() < 0.5 else ab
	var pb: Dictionary = ab if pa == aa else aa
	var out := {}
	out["body_type"] = _drift(int((pa if g.randf() < 0.5 else pb)["body_type"]), 3, g, 0.25)
	out["frame"] = int((pa if g.randf() < 0.5 else pb)["frame"])
	var eyes: int = int(pa["face"]) % 4
	var nose: int = int(pb["face"]) / 4
	if g.randf() < 0.1:
		eyes = g.randi_range(0, 3)
	if g.randf() < 0.1:
		nose = g.randi_range(0, 3)
	out["face"] = nose * 4 + eyes
	for k in ["mouth", "brows", "ears"]:
		out[k] = int((pa if g.randf() < 0.5 else pb)[k]) if g.randf() > 0.1 else g.randi_range(0, int(n[k]) - 1)
	out["facial_hair"] = int((pa if g.randf() < 0.5 else pb)["facial_hair"]) if g.randf() < 0.2 else 0
	out["mark"] = int((pa if g.randf() < 0.5 else pb)["mark"]) if g.randf() < 0.4 else 0
	out["glasses"] = int(pa["glasses"]) if g.randf() < 0.3 else 0
	random_outfit(out, g)
	return out
