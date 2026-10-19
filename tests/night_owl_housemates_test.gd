extends RefCounted
## A night owl up at 03:00 must not keep the rest of the household up: non-night-owls are asleep on at least 85% of nights.

const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	var days: int = 4 if TestFixture.fast else 9
	var w := Kit.setup(77)
	Kit.set_time(1, 8)
	var objs := Kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	w.add_object("toilet", Vector2i(16, 14))
	var owl := Folk.create("Mika Owl", ["night_owl"])
	var u := Folk.create("Ulla Day", ["social"])
	var s := Folk.create("Sorrel Day", ["creative"])
	var folks: Array = [owl, u, s]
	for p in folks:
		p.age_stage = "adult"
		p.household_id = 1
		w.add_folk(p, Vector2i(12 + folks.find(p), 12))
		Aging.register(p)
	RelationshipService.add_both(u.id, s.id, "friendship", 60.0)
	RelationshipService.add_both(u.id, owl.id, "friendship", 60.0)
	RelationshipService.add_both(s.id, owl.id, "friendship", 60.0)
	var dir = Kit.director()
	var asleep: Dictionary = {}
	var doing: Dictionary = {}
	var nights := 0
	for minute in days * 1440:
		SimEnv.clock().advance_minutes(1)
		if minute % 1440 == 1439:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10
		if SimEnv.now_min() % 1440 == 60:            # the owl is lonely and bored at 01:00 every night
			(owl.needs["social"] as Stat).set_value(-80.0)
			(owl.needs["fun"] as Stat).set_value(-80.0)
		if SimEnv.now_min() % 1440 == 22 * 60 + 30:         # well rested after a lazy day: not tired yet at bedtime
			for rested in [u, s]:
				(rested.needs["energy"] as Stat).set_value(95.0)
		dir.tick_minute(1)
		if SimEnv.now_min() % 1440 == 180 and minute > 1440:
			nights += 1
			for p2 in [u, s]:
				var cur: String = "-" if p2.current == null else str(p2.current.def_id)
				if cur in ["sleep_bed", "nap_bed", "nap_sofa"]:
					asleep[p2.id] = int(asleep.get(p2.id, 0)) + 1
				else:
					doing[cur] = int(doing.get(cur, 0)) + 1
	print("  owl housemates: %d nights, asleep %s, awake doing %s" % [nights, str(asleep), str(doing)])
	for p3 in [u, s]:
		var share: float = float(asleep.get(p3.id, 0)) / float(maxi(nights, 1))
		Kit.expect(f, share >= 0.85, "%s is asleep at 03:00 on at least 85%% of nights even with a night owl up (%.2f)" % [p3.name, share])
	Kit.teardown()
	return f
