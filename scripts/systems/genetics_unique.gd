class_name GeneticsUnique
extends RefCounted
## The no-clones rule: every living Folk (household, townies, visitors, crowd, staff, babies) must differ from every other by
## at least `distinct.threshold` (default 3.0) weighted perceptual channels (hair style, hair colour band, skin band, top +
## top colour, accessories, body shape, bottom, height band, face; weights in data/genetics.json "distinct").
## New folk reroll their free channels (clothes, accessories, hair style, body shape ...) until they are distinct from
## everyone in `registry()` (capped tries, deterministic with a seeded rng). Saved folk are never changed.


static func _dcfg() -> Dictionary:
	return Genetics.cfg().get("distinct", {})


static func threshold() -> float:
	return float(_dcfg().get("threshold", 3.0))


## Appearance dictionaries of everyone currently in the world: folk on the loaded lot + living townies (visitors, staff,
## residents elsewhere).
static func registry() -> Array:
	var out: Array = []
	var seen := {}
	for f in WorldIface.all_folk():
		if f.appearance is Dictionary and not (f.appearance as Dictionary).is_empty():
			out.append(f.appearance)
			seen[int(f.id)] = true
	for id in Story.townies:
		var t: Dictionary = Story.townies[id]
		if bool(t.get("alive", true)) and not seen.has(int(id)) and Genetics.is_valid(t.get("appearance", {})):
			out.append(t["appearance"])
	return out


static func _channels_of(others: Array) -> Array:
	var chs: Array = []
	for o in others:
		chs.append(GeneticsLook.channels(o))
	return chs


## Smallest distance from `ap` to any of the pre-computed channel arrays (1e9 when there are none).
static func min_distance(ap: Dictionary, other_ch: Array) -> float:
	var c: Array = GeneticsLook.channels(ap)
	var w: Array = GeneticsLook.weights()
	var best := 1.0e9
	for oc in other_ch:
		best = minf(best, GeneticsLook.distance_ch(c, oc, w))
	return best


static func is_distinct(ap: Dictionary, others: Array) -> bool:
	return min_distance(ap, _channels_of(others)) >= threshold()


static func tries() -> int:
	return int(_dcfg().get("tries", 60))


## A fresh random appearance distinct from `others`; the best of `tries` candidates when none passes.
static func unique_random(others: Array, g: RandomNumberGenerator) -> Dictionary:
	var chs: Array = _channels_of(others)
	var best: Dictionary = {}
	var bd := -1.0
	for _t in tries():
		var cand: Dictionary = Genetics.random_appearance(g)
		var d: float = min_distance(cand, chs)
		if d >= threshold():
			return cand
		if d > bd:
			bd = d
			best = cand
	return best


## Keep what makes a family look related (skin, hair / eye colour, face, height, build) and reroll the rest until the look is
## distinct from `others`. The first candidate is the input itself.
static func make_distinct(ap: Dictionary, others: Array, g: RandomNumberGenerator) -> Dictionary:
	var chs: Array = _channels_of(others)
	var best: Dictionary = ap
	var bd: float = min_distance(ap, chs)
	if bd >= threshold():
		return ap
	var n: Dictionary = GeneticsLook.counts()
	for t in tries():
		var cand: Dictionary = ap.duplicate(true)
		GeneticsLook.random_outfit(cand, g)
		if t >= 8:
			cand["hair_style"] = g.randi_range(0, int(n["hair_style"]) - 1)
		if t >= 16:
			cand["body_type"] = g.randi_range(0, 2)
			cand["frame"] = g.randi_range(0, 2)
		if t >= 28:
			cand["facial_hair"] = g.randi_range(0, 3) if g.randf() < 0.3 else 0
			cand["mark"] = g.randi_range(0, 2)
		if int(cand["hat"]) > 0 and Genetics.HAT_BLOCK.has(int(cand["hair_style"])):
			cand["hat"] = 0
		var d: float = min_distance(cand, chs)
		if d >= threshold():
			return cand
		if d > bd:
			bd = d
			best = cand
	return best


# ------------------------------------------------------------------ palette check (visible from the iso camera)
## True when the colours that dominate the silhouette (hair, top, bottoms, hat/accent when worn) all differ from every floor /
## ground colour by `palette.min_distance` (sRGB euclidean). Skin is fixed by the tone palette and not checked.
static func palette_ok(ap: Dictionary) -> bool:
	return palette_report(ap).is_empty()


## Names of the appearance colours that blend with a floor colour (empty = fine).
static func palette_report(ap: Dictionary) -> Array:
	var pc: Dictionary = Genetics.cfg().get("palette", {})
	var mind: float = float(pc.get("min_distance", 0.18))
	var hmind: float = float(pc.get("hair_min_distance", 0.1))
	var a: Dictionary = Genetics.normalize(ap)
	var keys: Array = ["hair_color", "shirt", "pants"]
	if int(a["hat"]) > 0 or int(a["top"]) in [5, 6, 3] or int(a["scarf"]) > 0:
		keys.append("accent")
	var bad: Array = []
	for k in keys:
		if not colour_ok(str(a[k]), hmind if k == "hair_color" else mind):
			bad.append(k)
	return bad


## True when `hex` is at least `min_d` (sRGB euclidean) away from every floor / ground colour.
static func colour_ok(hex: String, min_d: float) -> bool:
	var c := Color.html(hex)
	for fl in Genetics.cfg().get("palette", {}).get("floors", []):
		var f := Color.html(str(fl))
		if sqrt((c.r - f.r) * (c.r - f.r) + (c.g - f.g) * (c.g - f.g) + (c.b - f.b) * (c.b - f.b)) < min_d:
			return false
	return true


## registry() without the entries equal to `ap` (the subject itself when it is already registered).
static func registry_without(ap: Dictionary) -> Array:
	return registry().filter(func(o): return o != ap)
