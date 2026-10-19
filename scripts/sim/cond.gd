class_name Cond
extends RefCounted
## Condition evaluator. A condition list is AND'd; each dictionary may carry several keys (also AND'd).
## ctx keys: "folk" (Folk), "object" (WorldObject or null), "target" (Folk or null).

static var _warned: Dictionary = {}

static func check(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if not check_one(c, ctx):
			return false
	return true

static func check_one(c: Variant, ctx: Dictionary) -> bool:
	if c is Array:
		return check(c, ctx)
	if not (c is Dictionary):
		return false
	var d: Dictionary = c
	var folk = ctx.get("folk", null)
	var obj = ctx.get("object", null)
	var target = ctx.get("target", null)
	for key in d:
		var v: Variant = d[key]
		match str(key):
			"stat_below":
				if folk == null or not (folk.get_stat_value(str(v[0])) < float(v[1])):
					return false
			"stat_above":
				if folk == null or not (folk.get_stat_value(str(v[0])) > float(v[1])):
					return false
			"has_trait":
				if folk == null or not folk.has_trait(str(v)):
					return false
			"lacks_trait":
				if folk == null or folk.has_trait(str(v)):
					return false
			"has_buff":
				if folk == null or not folk.has_buff(str(v)):
					return false
			"lacks_buff":
				if folk == null or folk.has_buff(str(v)):
					return false
			"mood_is":
				if folk == null:
					return false
				var mood_now: String
				if ctx.has("#mood"):                   # opt-in per-evaluation cache (Autonomy.gather): Mood.compute is expensive
					if ctx["#mood"] == null:
						ctx["#mood"] = str(folk.get_mood().get("mood", ""))
					mood_now = ctx["#mood"]
				else:
					mood_now = str(folk.get_mood().get("mood", ""))
				if mood_now != str(v):
					return false
			"skill_at_least":
				if folk == null or folk.skill_level(str(v[0])) < int(v[1]):
					return false
			"object_state_eq":
				if obj == null:
					return false
				var cur: Variant = WorldIface.state_get(obj, str(v[0]), null)
				if cur == null:
					cur = false if typeof(v[1]) == TYPE_BOOL else 0
				if not _loose_eq(cur, v[1]):
					return false
			"object_state_above":
				if obj == null or not (float(WorldIface.state_get(obj, str(v[0]), 0.0)) > float(v[1])):
					return false
			"object_state_below":
				if obj == null or not (float(WorldIface.state_get(obj, str(v[0]), 0.0)) < float(v[1])):
					return false
			"time_between":
				if not _time_between(float(v[0]), float(v[1])):
					return false
			"pair_flag_absent":
				if folk == null or target == null or RelationshipBits.has_flag(int(folk.id), int(target.id), str(v)):
					return false
			"circadian":
				if folk == null or not Circadian.in_phase(folk, str(v)):
					return false
			"coins_at_least":
				if folk == null or WorldIface.get_coins(int(folk.household_id)) < int(v):
					return false
			"relationship_above":
				if folk == null or target == null:
					return false
				if not (folk.get_rel(int(target.id), str(v[0])) > float(v[1])):
					return false
			"has_job":
				if folk == null or (folk.has_job() != bool(v)):
					return false
			"age_stage_is":                    # a stage id or a list of them (SysCond has the same key for systems-level checks)
				if folk == null:
					return false
				if v is Array:
					if not (v as Array).has(str(folk.age_stage)):
						return false
				elif str(folk.age_stage) != str(v):
					return false
			"posture_is":
				if folk == null or str(folk.posture) != str(v):
					return false
			"posture_not":
				if folk == null or str(folk.posture) == str(v):
					return false
			"not":
				if check_one(v, ctx):
					return false
			"any":
				var ok := false
				for sub in v:
					if check_one(sub, ctx):
						ok = true
						break
				if not ok:
					return false
			_:
				if not _warned.has(str(key)):          # once per key: a warning per evaluation costs ~2 ms each in autonomy's hot path
					_warned[str(key)] = true
					push_warning("Cond: unknown condition key '%s'" % str(key))
				return false
	return true

## Does this condition look at the target folk / the object? (If not, it can be decided from the actor alone.)
static func uses_target(c: Variant) -> bool:
	return _mentions(c, ["relationship_above", "pair_flag_absent"])

static func uses_object(c: Variant) -> bool:
	return _mentions(c, ["object_state_eq", "object_state_above", "object_state_below"])

static func _mentions(c: Variant, keys: Array) -> bool:
	if c is Array:
		for x in c:
			if _mentions(x, keys):
				return true
		return false
	if not (c is Dictionary):
		return false
	for key in c:
		var k := str(key)
		if keys.has(k):
			return true
		if k == "not" and _mentions(c[key], keys):
			return true
		if k == "any":
			for sub in c[key]:
				if _mentions(sub, keys):
					return true
	return false

static func _loose_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return bool(a) == bool(b)
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	return a == b

static func _time_between(h1: float, h2: float) -> bool:
	var h: float = SimEnv.hour_f()
	if h1 <= h2:
		return h >= h1 and h < h2
	return h >= h1 or h < h2
