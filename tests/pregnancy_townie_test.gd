extends RefCounted
## Task 18: the statistical (townie) conception and pregnancy: mixed-sex adult couples only, fertility by age, a pregnancy record on the
## woman, births on the due day with sexes, twins by data; same-sex couples and elders never.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(701)
	var g: Dictionary = Story.cfg().get("growth", {})
	g["baby_chance"] = 1.0
	g["baby_gap_days"] = 0
	g["max_kids"] = 50
	Story.cfg()["max_population"] = 500
	var days: float = float(Aging.stage_def("adult").get("from_day", 76)) + 6.0
	var ma: Dictionary = Story.add_townie(days, "Mara Quill", [], "", 1, "female")
	var pa: Dictionary = Story.add_townie(days, "Pavel Quill", [], "", 1, "male")
	var fb: Dictionary = Story.add_townie(days, "Rhea Dunn", [], "", 1, "female")
	var fc: Dictionary = Story.add_townie(days, "Cora Dunn", [], "", 1, "female")
	for t in [ma, pa, fb, fc]:
		Fertility.state(int(t["id"]))["infertile"] = false
	RelationshipService.add_both(int(ma["id"]), int(pa["id"]), "romance", 70.0)
	RelationshipBits.set_flag(int(ma["id"]), int(pa["id"]), "partner", true, false)
	RelationshipService.add_both(int(fb["id"]), int(fc["id"]), "romance", 70.0)
	RelationshipBits.set_flag(int(fb["id"]), int(fc["id"]), "partner", true, false)
	K.set_time(5, 8)
	StoryGrowth.on_day()
	K.expect(f, ma.has("preg") and not pa.has("preg"), "the woman of a mixed couple carries")
	K.expect(f, not fb.has("preg") and not fc.has("preg"), "a same-sex couple never conceives")
	var pop: int = Story.alive_townies().size()
	K.set_time(5 + Pregnancy.length_days() + 1, 8)
	g["baby_chance"] = 0.0
	StoryGrowth.on_day()
	K.expect(f, not ma.has("preg") and Story.alive_townies().size() > pop, "the baby arrives on the due day (%d -> %d)" % [pop, Story.alive_townies().size()])
	var baby_ok := true
	for t in Story.alive_townies():
		baby_ok = baby_ok and Sexes.valid(Sexes.of_townie(t))
	K.expect(f, baby_ok, "every newborn has a sex")
	# elders never
	var old: Dictionary = Story.add_townie(float(Aging.stage_def("elder").get("from_day", 172)) + 3.0, "Olga Rye", [], "", 1, "female")
	var oldm: Dictionary = Story.add_townie(days, "Otto Rye", [], "", 1, "male")
	K.expect(f, Conception.couple_fertility(int(old["id"]), int(oldm["id"])) == 0.0, "an elder townie has no fertility")
	K.teardown()
	return f
