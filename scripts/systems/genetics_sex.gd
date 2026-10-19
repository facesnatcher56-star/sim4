class_name GeneticsSex
extends RefCounted
## The sex-specific part of the look (task 18): facial hair only on males, body shape and frame weights, and a height band per sex
## (data/genetics.json "sex": {female|male: {height: [min, max], body_type: [w..], frame: [w..]}}). Everything else (hair, skin, face,
## clothes) is open to both. `fit` only applies hard limits, so it is safe to call again after any reroll.

static func cfg(sex: String) -> Dictionary:
	return (Genetics.cfg().get("sex", {}) as Dictionary).get(sex, {})

## Weights for a look channel ("body_type" | "frame"): the sex table when present, else `fallback`.
static func weights(sex: String, key: String, fallback: Array) -> Array:
	var w = cfg(sex).get(key, null)
	return w if w is Array and not (w as Array).is_empty() else fallback

static func height_range(sex: String, lo: float, hi: float) -> Array:
	var h = cfg(sex).get("height", null)
	if h is Array and (h as Array).size() == 2:
		return [maxf(lo, float(h[0])), minf(hi, float(h[1]))]
	return [lo, hi]

## Hard limits of a look for `sex` (a missing sex changes nothing). Females get no facial hair.
static func fit(ap: Dictionary, sex: String, _g: RandomNumberGenerator = null) -> void:
	if sex == Sexes.FEMALE:
		ap["facial_hair"] = 0
	var h = cfg(sex).get("height", null)
	if h is Array and (h as Array).size() == 2 and ap.has("height"):
		ap["height"] = clampf(float(ap["height"]), float(h[0]), float(h[1]))


## The usual hair styles of a sex (data/genetics.json sex.<s>.hair_pool). Any style stays selectable; this is only where a NEW look starts in the creator.
static func hair_pool(sex: String) -> Array:
	var p = cfg(sex).get("hair_pool", null)
	return p if p is Array else []


static func in_hair_pool(sex: String, style: int) -> bool:
	for h in hair_pool(sex):
		if int(h) == style:
			return true
	return false


static func _argmax(w: Array, default: int) -> int:
	var best: int = default
	var bv: float = -1.0
	for i in w.size():
		if float(w[i]) > bv:
			bv = float(w[i])
			best = i
	return best


## The creator's starting look for a sex: the most usual body type and frame (shoulder and hip width), a height and build inside the sex's bands and a hair style from its usual
## pool (kept when the current one is already in it). Deterministic from `key` (the name). Creator only: the sim's looks (random_look / fit) are unchanged.
static func creator_fit(ap: Dictionary, sex: String, key: String = "") -> void:
	if not Sexes.valid(sex):
		return
	fit(ap, sex)
	var cr: Dictionary = cfg(sex).get("creator", {})
	ap["body_type"] = int(cr["body_type"]) if cr.has("body_type") else _argmax(weights(sex, "body_type", [0.3, 0.4, 0.3]), 1)      # women: slimmer shoulders, softer frame; men: broad shoulders, angular frame
	ap["frame"] = int(cr["frame"]) if cr.has("frame") else _argmax(weights(sex, "frame", [0.4, 0.3, 0.3]), 0)
	var b = cfg(sex).get("build", null)
	if b is Array and (b as Array).size() == 2:
		ap["build"] = clampf(float(ap.get("build", 1.0)), float(b[0]), float(b[1]))
	var pool: Array = hair_pool(sex)
	if not pool.is_empty() and not in_hair_pool(sex, int(ap.get("hair_style", 0))):
		ap["hair_style"] = int(pool[absi(hash(key + sex)) % pool.size()])
	_fit_outfit(ap, sex, key)


## The usual clothes of a sex (sex.<s>.outfit_pool {top: [...], bottom: [...]}); empty = no preference. Every top and bottom stays selectable.
static func outfit_pool(sex: String, part: String) -> Array:
	var p = cfg(sex).get("outfit_pool", {})
	var a = (p as Dictionary).get(part, []) if p is Dictionary else []
	return a if a is Array else []


static func in_outfit_pool(sex: String, part: String, v: int) -> bool:
	for x in outfit_pool(sex, part):
		if int(x) == v:
			return true
	return false


## A new creator look starts in the sex's usual clothes (a man is not dressed in a dress or an apron); a top or bottom already in the pool is kept.
static func _fit_outfit(ap: Dictionary, sex: String, key: String) -> void:
	var tops: Array = outfit_pool(sex, "top")
	if not tops.is_empty() and not in_outfit_pool(sex, "top", int(ap.get("top", 0))):
		ap["top"] = int(tops[absi(hash(key + sex + "top")) % tops.size()])
	var bottoms: Array = outfit_pool(sex, "bottom")
	if not bottoms.is_empty() and not in_outfit_pool(sex, "bottom", int(ap.get("bottom", 0))):
		ap["bottom"] = int(bottoms[absi(hash(key + sex + "bottom")) % bottoms.size()])
