extends RefCounted
## Homework and school spread their XP over several subjects, steered by traits, instead of feeding only logic and writing.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(21)
	var plain := K.make_folk(w, "Plain", [], 1, Vector2i(12, 12), "child")
	var out := K.make_folk(w, "Outdoor", ["outdoorsy"], 1, Vector2i(14, 12), "child")
	var sp: Dictionary = SkillInterest.pool_shares(plain, "school")
	var total: float = 0.0
	for s in sp:
		total += float(sp[s])
	K.expect(f, sp.size() >= 4 and absf(total - 1.0) < 0.001, "study is spread over %d subjects" % sp.size())
	K.expect(f, float(sp.get("logic", 1.0)) <= 0.3, "logic gets no more than a third (%.2f)" % float(sp.get("logic", 1.0)))
	var so: Dictionary = SkillInterest.pool_shares(out, "school")
	K.expect(f, float(so["fitness"]) > float(sp["fitness"]), "an outdoorsy child leans to fitness (%.2f vs %.2f)" % [float(so["fitness"]), float(sp["fitness"])])
	plain.skills["logic"] = {"xp": 0.0, "level": 9}
	K.expect(f, float(SkillInterest.pool_shares(plain, "school")["logic"]) < float(sp["logic"]), "a mastered subject gets less")
	# a school day teaches several subjects, and homework does too
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(16, 12), "child")
	for _d in 10:
		SkillInterest.school_day(kid)
	var learned: int = 0
	for s2 in sp:
		if float((kid.skills.get(s2, {}) as Dictionary).get("xp", 0.0)) > 5.0:
			learned += 1
	K.expect(f, learned >= 4, "ten school days teach %d subjects" % learned)
	var def: Dictionary = SimEnv.data().interaction_def("do_homework")
	K.expect(f, def.has("skill_xp_pool") and not def.has("skill_xp_per_min"), "homework uses the study pool")
	K.teardown()
	return f
