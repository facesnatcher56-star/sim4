extends RefCounted
## Skill taste in autonomy: mastered skills lose their pull, traits / aspiration / job boost the matching skills, work and meals are untouched.

const K = preload("res://tests/systems_kit.gd")

func _def(iid: String) -> Dictionary:
	return SimEnv.data().interaction_def(iid)

func _first_with(skill: String) -> String:
	var ix: Dictionary = SimEnv.data().interactions()
	var ids: Array = ix.keys()
	ids.sort()
	for id in ids:
		if (ix[id].get("skill_xp_per_min", {}) as Dictionary).has(skill) and not AutonomyVariety.exempt(str(id), ix[id]) and (ix[id].get("tags", []) as Array).size() > 0:
			return str(id)
	return ""

func run() -> Array:
	var f: Array = []
	var w := K.setup(21)
	var plain := K.make_folk(w, "Plain", [])
	var out := K.make_folk(w, "Outdoor", ["outdoorsy"], 1, Vector2i(14, 12))
	var mus := K.make_folk(w, "Musical", ["musical"], 1, Vector2i(16, 12))
	var wr := K.make_folk(w, "Wordy", [], 1, Vector2i(18, 12))
	var writes: String = "write_story"
	var fit: String = _first_with("fitness")
	var gtr: String = _first_with("guitar")
	K.expect(f, fit != "" and gtr != "", "test data has fitness and guitar activities (%s, %s)" % [fit, gtr])
	K.expect(f, is_equal_approx(SkillInterest.mult(plain, writes, _def(writes)), 1.0), "a beginner has no preference")
	plain.skills["writing"] = {"xp": 0.0, "level": 9}
	var m9: float = SkillInterest.mult(plain, writes, _def(writes))
	K.expect(f, m9 < 0.4, "a writing 9 has little appetite for more writing (%.2f)" % m9)
	K.expect(f, SkillInterest.mult(plain, writes, _def(writes)) < SkillInterest.mult(plain, _first_with("painting"), _def(_first_with("painting"))), "a fresh skill beats the mastered one")
	var of: float = SkillInterest.mult(out, fit, _def(fit))
	K.expect(f, of >= 1.4 and of > SkillInterest.mult(out, writes, _def(writes)), "outdoorsy folk lean to fitness (%.2f)" % of)
	var mg: float = SkillInterest.mult(mus, gtr, _def(gtr))
	K.expect(f, mg >= 1.4, "musical folk lean to guitar (%.2f)" % mg)
	Careers.jobs[int(wr.id)] = {"career": "writer", "level": 1}
	K.expect(f, SkillInterest.mult(wr, writes, _def(writes)) >= 1.4, "a writer leans to writing")
	wr.skills["writing"] = {"xp": 0.0, "level": 10}
	K.expect(f, SkillInterest.mult(wr, writes, _def(writes)) < 0.8, "writing 10 is mostly done (%.2f)" % SkillInterest.mult(wr, writes, _def(writes)))
	var wk: String = "work_computer"
	plain.skills["logic"] = {"xp": 0.0, "level": 10}
	K.expect(f, is_equal_approx(SkillInterest.mult(plain, wk, _def(wk)), 1.0), "work is exempt")
	K.expect(f, is_equal_approx(SkillInterest.mult(plain, "cook_meal", _def("cook_meal")), 1.0), "cooking (a meal) is exempt")
	K.teardown()
	return f
