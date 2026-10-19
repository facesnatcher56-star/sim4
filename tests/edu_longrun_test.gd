extends RefCounted
## Task 14 education rates over years of game time (SLOW tier): the statistical townie studies, the yearly school events, the report cards,
## the weekly job board and the staff turnover stay in believable ranges and nothing grows without a cap.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(1414)
	K.make_folk(w, "Ann")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid, 25.6)
	WorldIface.coins[1] = 100000
	Story.generate_townies(12)
	K.set_time(1, 6)
	Careers.on_day(1)
	LifeTick.new_game()
	var adults: int = Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult").size()
	var years: int = TestFixture.pick(8, 4)
	var days: int = years * 28
	var open_sum := 0
	var open_n := 0
	var closed_days := 0
	var unstaffed_days := 0
	for d in range(2, days + 2):
		K.set_time(d, 8)
		Careers.school[int(kid.id)]["grade"] = 75.0           # keep the child enrolled and average
		LifeTick.on_day(d)
		if d % 7 == 1:
			for cid in Careers.career_ids():
				open_sum += EduJobs.openings(str(cid))
				open_n += 1
		for pid in Places.all():
			if PlaceStaff.closed_today(pid):
				closed_days += 1
			if not PlaceStaff.staffed(pid):
				unstaffed_days += 1
	# townies: graduates per adult townie over the years, capped at two degrees each
	var grads := 0
	var most := 0
	for tid in EduState.recs:
		var n: int = EduState.degrees(int(tid)).size()
		if int(tid) >= 1000:
			grads += n
			most = maxi(most, n)
	var per_adult_year: float = float(grads) / float(maxi(adults, 1)) / float(years)
	K.expect(f, adults >= 5, "enough adult townies to measure (%d)" % adults)
	K.expect(f, per_adult_year > 0.08 and per_adult_year < 0.7, "degrees per adult townie per game year are believable (%.2f)" % per_adult_year)
	K.expect(f, most <= 3, "nobody collects degrees without end (%d)" % most)
	# school events: exactly one run of each event every year
	var yr: int = Seasons.year_at(days + 1)
	for id in LifeDefs.section("events"):
		K.expect(f, int(EduState.fired.get(str(id), -1)) >= yr - 1, "%s keeps running every year" % id)
	K.expect(f, (EduState.rec(int(kid.id))["reports"] as Array).size() >= 2, "report cards keep coming (%d kept)" % (EduState.rec(int(kid.id))["reports"] as Array).size())
	K.expect(f, (EduState.rec(int(kid.id))["reports"] as Array).size() <= 8, "and only the last eight are kept")
	# the job board: average openings per career per week close to the middle of 0..3 (a little under: floor of a uniform roll)
	var avg_open: float = float(open_sum) / float(maxi(open_n, 1))
	K.expect(f, avg_open > 0.8 and avg_open < 2.2, "average openings per career per week (%.2f)" % avg_open)
	# places: staffed nearly always, closed for a day only now and then
	var place_days: int = Places.all().size() * days
	K.expect(f, float(unstaffed_days) / float(place_days) < 0.02, "places are almost always staffed (%d of %d place-days)" % [unstaffed_days, place_days])
	var closed_share: float = float(closed_days) / float(place_days)
	K.expect(f, closed_share > 0.0005 and closed_share < 0.03, "places close for a day now and then (%.4f of place-days)" % closed_share)
	for pid in PlaceStaff.rosters:
		K.expect(f, (PlaceStaff.rosters[pid] as Array).size() <= 6, "%s roster stays small" % pid)
	print("edu_longrun: %d years, %d adult townies, %.2f degrees per adult-year, %.2f openings per career-week, closed %.4f, unstaffed %.4f" % [years, adults, per_adult_year, avg_open, closed_share, float(unstaffed_days) / float(place_days)])
	K.teardown()
	return f
