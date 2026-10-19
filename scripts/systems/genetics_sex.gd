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
