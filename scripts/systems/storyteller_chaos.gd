class_name StorytellerChaos
extends RefCounted
## The hidden chaos level of every key (household "h<id>", townie lot "l<n>", district "d<zone>", "town") and the HEAT that makes related events likelier nearby.
## The level is a noisy random walk around the personality's mean with occasional sudden jumps, so quiet and busy spells have irregular lengths and there is
## no schedule to learn. District kinds shift the mean (downtown is livelier than the suburbs). Level 1.0 = a normal spell.
## Heat: events add `per_event` to heat[zone][tag] (capped); it halves every `half_life_days`; a card weighs (1 + weight_gain x heat) for each of its tags.

static func hcfg() -> Dictionary:
	return Storyteller.cfg().get("heat", {})

static func level_of(key: String) -> float:
	return float(Storyteller.entries.get(key, {}).get("level", 1.0))

## One day of the walk for `key`. Uses the storyteller's own stream (callers iterate keys in sorted order).
static func step(key: String) -> void:
	var e: Dictionary = StorytellerBudget.entry(key)
	var w: Dictionary = Storyteller.param("walk", {})
	var mean: float = float(w.get("mean", 1.0)) * kind_chaos(key)
	var lv: float = float(e["level"])
	lv += (mean - lv) * float(w.get("revert", 0.1)) + Storyteller.rng.randfn(0.0, float(w.get("noise", 0.2)))
	if Storyteller.rng.randf() < float(w.get("jump_chance", 0.04)):
		var up: bool = Storyteller.rng.randf() < 0.55
		lv += float(w.get("jump_size", 0.8)) * Storyteller.rng.randf_range(0.5, 1.0) * (1.0 if up else -1.0)
	e["level"] = clampf(lv, 0.05, 4.0)

## District character: the chaos multiplier of the kind (downtown, suburb ...) for district keys and for the households in it.
static func kind_chaos(key: String) -> float:
	var zone: String = StorytellerBudget.zone_of_key(key)
	if zone == "":
		return 1.0
	return float(StorytellerDistrict.kind_def(zone).get("chaos", 1.0))

# ------------------------------------------------------------------ heat (contagion)
static func heat_of(zone: String, tag: String) -> float:
	return float((Storyteller.heat.get(zone, {}) as Dictionary).get(tag, 0.0))

static func add_heat(zone: String, tag: String, amount: float = -999.0) -> void:
	if zone == "" or tag == "":
		return
	var h: Dictionary = hcfg()
	var a: float = float(h.get("per_event", 1.0)) if amount == -999.0 else amount
	var z: Dictionary = Storyteller.heat.get(zone, {})
	z[tag] = clampf(float(z.get(tag, 0.0)) + a, 0.0, float(h.get("cap", 4.0)))
	Storyteller.heat[zone] = z

static func decay_heat() -> void:
	var f: float = pow(0.5, 1.0 / maxf(float(hcfg().get("half_life_days", 4.0)), 0.5))
	for z in Storyteller.heat.keys():
		var d: Dictionary = Storyteller.heat[z]
		for t in d.keys():
			d[t] = float(d[t]) * f
			if float(d[t]) < 0.05:
				d.erase(t)
		if d.is_empty():
			Storyteller.heat.erase(z)

## Weight multiplier for a card's tags in a zone.
static func heat_mult(zone: String, tags: Array) -> float:
	var m: float = 1.0
	var g: float = float(hcfg().get("weight_gain", 0.5))
	for t in tags:
		m += g * heat_of(zone, str(t))
	return m
