extends RefCounted
## Two in-game years fast-forwarded headless with the whole systems stack, a few folk and the director: no errors, no NaNs.

const W = preload("res://tests/weather_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w: StubWorld = W.setup(8675309)
	var a: Folk = K.make_folk(w, "Ann", [], 1, Vector2i(12, 12))
	var b: Folk = K.make_folk(w, "Bo", [], 1, Vector2i(14, 12))
	W.outdoors(b, true)
	w.add_object("garden_plot", Vector2i(18, 12))
	w.add_object("tv", Vector2i(20, 12))
	w.add_object("fridge", Vector2i(22, 12))
	WorldIface.coins[1] = 100000
	var dir = K.director()
	SimEnv.clock().total_minutes = W.at(1, 7)
	var kinds: Dictionary = {}
	var seasons_seen: Dictionary = {}
	var bad: int = 0
	var holidays: int = 0
	var changes_before: int = K.count_events("weather_changed")
	var total_days: int = 2 * 4 * 7
	for day in total_days:
		if not Holidays.today().is_empty():
			holidays += 1
		for chunk in 24:
			for m in 60:
				SimEnv.clock().advance_minutes(1)
				if (day < 3 and m % 5 == 0) or m == 30:
					dir.tick_minute(1)       # the director is slow; sample it sparsely after the first days
			var t: float = Weather.temperature()
			if is_nan(t) or is_inf(t) or t < -30.0 or t > 55.0:
				bad += 1
			kinds[Weather.current()] = true
			seasons_seen[Seasons.current()] = true
		for fk in [a, b]:
			for n in fk.needs:
				var v: float = (fk.needs[n] as Stat).value
				if is_nan(v) or is_inf(v):
					bad += 1
	W.expect(f, bad == 0, "%d NaN / out-of-range values during the run" % bad)
	W.expect(f, Seasons.year() == 3 and Seasons.current() == "spring", "two years elapsed: year %d %s" % [Seasons.year(), Seasons.current()])
	W.expect(f, seasons_seen.size() == 4, "all four seasons visited")
	W.expect(f, kinds.size() >= 6, "variety of weather over two years: %s" % str(kinds.keys()))
	W.expect(f, holidays == 15, "15 holiday days in two years, saw %d" % holidays)
	W.expect(f, K.count_events("weather_changed") - changes_before > 100, "weather changed regularly")
	W.expect(f, K.count_events("season_changed") >= 7, "season_changed events: %d" % K.count_events("season_changed"))
	W.expect(f, Economy.bills.size() >= 8, "bills were issued during the run")
	var worst: float = 0.0
	for bl in Economy.bills:
		worst = maxf(worst, float(bl["amount"]))
	W.expect(f, worst > 0.0 and worst < 100000.0, "bill amounts sane")
	W.teardown()
	return f
