extends RefCounted
## 19i: a married man and woman, adults, at home, left alone for 20 game days: the day-by-day story (StoryMilestones: the planned try and the
## quiet evenings) gets them a pregnancy in most seeds. Before this the odds were under 1 percent a day and real runs had no babies at all.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var got := 0
	var seeds := [11, 22, 33, 44, 55, 66, 77, 88, 99, 110]
	for s in seeds:
		if _twenty_days(int(s)):
			got += 1
	print("  couple pregnancy in 20 days: %d of %d seeds" % [got, seeds.size()])
	K.expect(f, got >= 7, "a married adult couple at home has a pregnancy within 20 days in most seeds (%d of %d)" % [got, seeds.size()])
	return f

func _twenty_days(seed_value: int) -> bool:
	var w := K.setup(seed_value, true)
	var a := K.make_folk(w, "Una Hale", [], 1)
	var b := K.make_folk(w, "Vik Hale", [], 1, Vector2i(14, 12))
	a.sex = "female"
	b.sex = "male"
	Aging.set_age_days(a, 100.0)
	Aging.set_age_days(b, 101.0)
	K.mgr.new_game([1])
	HouseholdSetup._bond(a.id, b.id)
	RelationshipBits.set_flag(a.id, b.id, "partner", true, false)
	FamilyMarriage.marry(a.id, b.id, "", true)
	var pregnant := false
	for d in range(2, 22):
		K.set_time(d, 6)
		StoryMilestones.on_day(d)
		if Aging.pregnancies.has(a.id) or K.count_events("baby_born") > 0:
			pregnant = true
			break
	K.teardown()
	return pregnant
