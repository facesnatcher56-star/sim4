extends RefCounted
## Town growth: townie couples have babies (adults only, spaced out), new singles, couples and families move in, nothing romantic skips RomanceRules.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_births(f)
	_arrivals(f)
	return f

func _births(f: Array) -> void:
	K.setup(311)
	Story.generate_townies(12)
	var adults: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult")
	var a: Dictionary = adults[0]
	var b: Dictionary = adults[1]
	RelationshipService.add_both(int(a["id"]), int(b["id"]), "friendship", 60.0)
	RelationshipBits.set_flag(int(a["id"]), int(b["id"]), "partner", true, false)
	Story.cfg()["growth"]["baby_chance"] = 1.0
	a["sex"] = "female"
	b["sex"] = "male"
	Fertility.state(int(a["id"]))["infertile"] = false
	Fertility.state(int(b["id"]))["infertile"] = false
	a["age_days"] = 90.0
	b["age_days"] = 90.0
	var before: int = Story.townies.size()
	StoryGrowth._births()
	K.expect(f, a.has("preg"), "a partnered adult couple conceives")
	K.set_time(SysUtil.day() + Pregnancy.length_days() + 1, 8)
	PregnancyTownie.on_day()
	K.expect(f, Story.townies.size() >= before + 1, "and has a baby (%d -> %d)" % [before, Story.townies.size()])
	before = Story.townies.size()
	StoryGrowth._births()
	K.expect(f, Story.townies.size() == before and not a.has("preg"), "babies are spaced out by baby_gap_days")
	# an elder couple has none
	Story.townies[int(a["id"])]["age_days"] = 200.0
	Story.townies[int(a["id"])]["last_baby_day"] = -99
	Story.townies[int(b["id"])]["last_baby_day"] = -99
	StoryGrowth._births()
	K.expect(f, Story.townies.size() == before and not a.has("preg"), "an elder is not a parent")
	K.teardown()

func _arrivals(f: Array) -> void:
	K.setup(312)
	Story.generate_townies(12)
	var g: Dictionary = Story.cfg()["growth"]
	g["arrive_chance"] = 1.0
	var kinds: Dictionary = {}
	for i in 12:
		for t in Story.alive_townies().duplicate():
			if Story.alive_townies().size() > 6:
				Story.townies.erase(int(t["id"]))
		var n0: int = Story.townies.size()
		StoryGrowth._arrivals()
		kinds[Story.townies.size() - n0] = true
	K.expect(f, kinds.has(1) and (kinds.has(2) or kinds.has(3)), "singles, couples and families arrive (sizes %s)" % str(kinds.keys()))
	for t2 in Story.alive_townies():
		K.expect(f, Story.stage_of(t2) != "baby" or int(t2.get("kids", 0)) == 0, "no stray babies")
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
		if (p["flags"] as Dictionary).get("partner", false):
			K.expect(f, RomanceRules.allowed(int(p["lo"]), int(p["hi"])), "every arrived couple passes RomanceRules")
	K.teardown()
