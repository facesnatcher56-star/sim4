extends RefCounted
## Task 22 review fix: bladder on board. Cabins have bathrooms and every public deck has toilets; with autonomy on, nobody on a cruise sinks below
## -50 bladder (the owner's report saw -79 on the first morning and -95 on day 5). Full length (3 days) in the slow runs, 17 hours in the fast tier.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func run() -> Array:
	fails = []
	var folk: Array = K.new_game("small", 9000, true, 21)
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 3, "cabin_class": "ocean", "seed": 21})
	var w = WorldIface.world()
	var toilets := {}
	for o in w.objects.values():
		if str(o.def_id) == "toilet" and NeighborhoodLots.lot_at(o.tile) == "trip_0":
			toilets[int(o.level)] = true
	K.run(5)
	var minutes: int = TestFixture.pick(4300, 1000)
	var lowest: float = 100.0
	var who: String = ""
	var n: int = 0
	while n < minutes:
		K.run(10)
		n += 10
		for f in folk:
			var b: float = f.get_stat_value("bladder")
			if b < lowest:
				lowest = b
				who = "%s at minute %d (level %d)" % [f.name, n, int(f.level)]
	var t: Dictionary = Vacation.trip(int(res["trip"]))
	for e in w.objects.values():
		if str(e.def_id) == "toilet" and NeighborhoodLots.lot_at(e.tile) == str(t.get("lot", "trip_0")):
			toilets[int(e.level)] = true
	print("  [cruise] lowest bladder over %d minutes aboard: %.0f (%s); decks with toilets: %s" % [minutes, lowest, who, str(toilets.keys())])
	if lowest < -50.0:
		fails.append("somebody's bladder fell to %.0f (%s)" % [lowest, who])
	if toilets.size() < 4:
		fails.append("toilets on at least four decks (%s)" % str(toilets.keys()))
	K.teardown()
	return fails
