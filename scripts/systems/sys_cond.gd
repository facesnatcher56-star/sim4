class_name SysCond
extends RefCounted
## Cond extension: everything sim-core's Cond understands, plus systems-level keys:
##   friends_at_least n | bit_count [bit, n] | career_is id | career_level_at_least n
##   age_stage_is stage (or [stages]) | skill_below [skill, n] | in_school b | pregnant b
## `not` / `any` recurse through THIS evaluator so extension keys work inside them.

static func check(conds: Array, folk) -> bool:
	for c in conds:
		if not check_one(c, folk):
			return false
	return true

static func check_one(c: Variant, folk) -> bool:
	if c is Array:
		return check(c, folk)
	if not (c is Dictionary):
		return false
	var d: Dictionary = c
	for key in d:
		var v: Variant = d[key]
		match str(key):
			"friends_at_least":
				if folk == null or RelationshipBits.count_bit(int(folk.id), "friend", true) < int(v):
					return false
			"bit_count":
				if folk == null or RelationshipBits.count_bit(int(folk.id), str(v[0]), false) < int(v[1]):
					return false
			"career_is":
				if folk == null or Careers.career_of(int(folk.id)) != str(v):
					return false
			"career_level_at_least":
				if folk == null or Careers.level_of(int(folk.id)) < int(v):
					return false
			"age_stage_is":
				if folk == null:
					return false
				if v is Array:
					if not (v as Array).has(str(folk.age_stage)):
						return false
				elif str(folk.age_stage) != str(v):
					return false
			"skill_below":
				if folk == null or folk.skill_level(str(v[0])) >= int(v[1]):
					return false
			"in_school":
				if folk == null or (Careers.school.has(int(folk.id)) != bool(v)):
					return false
			"pregnant":
				if folk == null or (folk.has_buff("pregnant") != bool(v)):
					return false
			"not":
				if check_one(v, folk):
					return false
			"any":
				var ok: bool = false
				for sub in v:
					if check_one(sub, folk):
						ok = true
						break
				if not ok:
					return false
			_:
				if not Cond.check_one({key: v}, {"folk": folk, "object": null, "target": null}):
					return false
	return true
