extends RefCounted
## Task 37 (data): the bus service fits a small town. One route until the town grows; the real timetable is data: 30 minutes at the rush hours, hourly by day, nothing after
## 20:30, a few buses on Sundays; the loop is short enough that about one bus is out at a time; the stop prints "Next bus 14:30"; TransportTrip uses the REAL wait, so a 50 minute
## wait is not chosen for a short trip (walking wins).

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")


func run() -> Array:
	var f: Array = []
	var w := C.setup()
	var h: Dictionary = C.home(w)
	var ada: Folk = h["ada"]
	K.set_time(3, 8)
	WorldIface.coins[1] = 6000
	var all: Array = TransportBus.all_routes()
	K.expect(f, TransportBus.routes().size() == 1 and all.size() >= 2, "one route runs in a town that has not grown (%d of %d)" % [TransportBus.routes().size(), all.size()])
	var loop: Dictionary = TransportBus.route("loop")
	var stops: Array = loop["stops"]
	for need in ["market", "hospital", "school", "office", "apartments", "works"]:
		K.expect(f, stops.has(need), "the loop serves %s" % need)
	K.expect(f, str(stops[0]) == "works" and str(stops[stops.size() - 1]) == "hospital", "a circuit through town: in at the works, out past the hospital (%s ... %s)" % [stops[0], stops[stops.size() - 1]])
	# weekday timetable: gaps by band
	var runs: Array = TransportBus.runs_day(loop, 2)
	var worst_peak: float = 0.0
	var worst_day: float = 0.0
	for k in range(1, runs.size()):
		var at: float = float(runs[k]) / 60.0
		var gap: float = float(int(runs[k]) - int(runs[k - 1]))
		var before: float = float(runs[k - 1]) / 60.0
		var peak: bool = (before >= 6.5 and at <= 9.0) or (before >= 16.0 and at <= 18.0)
		if peak:
			worst_peak = maxf(worst_peak, gap)
		elif before >= 9.0 and at <= 16.0:
			worst_day = maxf(worst_day, gap)
	K.expect(f, worst_peak > 0.0 and worst_peak <= 30.0, "rush hour headway is 30 minutes or better (%.0f)" % worst_peak)
	K.expect(f, worst_day >= 60.0 - 0.01 and worst_day <= 60.0 + 0.01, "daytime headway is 60 minutes (%.0f)" % worst_day)
	K.expect(f, int(runs[runs.size() - 1]) <= 20 * 60 + 30 and int(runs[0]) >= 4 * 60, "no bus after about 20:00 (last run %s)" % TransportBus.clock_text(int(runs[runs.size() - 1])))
	K.expect(f, TransportBus.runs_day(loop, 6).size() <= 6 and TransportBus.runs_day(loop, 5).size() < runs.size(), "reduced service on Saturday and Sunday")
	# how many buses are out at once
	var run_min: float = TransportBus.run_minutes(loop)
	var most: int = 0
	for t in range(0, 1440, 5):
		var out: int = 0
		for d in runs:
			if t >= int(d) and float(t) <= float(d) + run_min:
				out += 1
		most = maxi(most, out)
	print("  [bus] the run takes %.0f min, most buses out at once on a weekday: %d" % [run_min, most])
	K.expect(f, run_min >= 30.0 and run_min <= 150.0 and most <= 4, "a run of %.0f minutes puts at most 4 buses on the road at once (%d)" % [run_min, most])
	# growth: the second route needs finished projects
	K.expect(f, str((TransportBus.route("east")).get("requires_built", 0)) != "0", "the second route waits for town growth")
	CityPlan.built["residential"] = 1
	K.expect(f, TransportBus.routes().size() == 2, "after a finished project the second route runs")
	CityPlan.built.clear()
	# the stop and the Town window say when the next bus comes
	K.set_time(3, 10, 5)
	var txt: String = TransportBus.next_text("market")
	K.expect(f, txt.begins_with("Next bus ") and txt.length() == 14, "the stop shows 'Next bus HH:MM' (%s)" % txt)
	K.set_time(3, 21)
	K.expect(f, TransportBus.next_text("market").begins_with("No more buses today"), "after the last bus it says so (%s)" % TransportBus.next_text("market"))
	K.set_time(3, 9, 45)
	K.expect(f, not TransportBus.calls_today("loop", "market").is_empty() and TransportBus.calls_today("loop", "office").size() == runs.size(), "the whole day's calls at a stop are listed")
	# the minutes on the sign are what the bus in the street takes: the timetable is built from the real lane route lengths
	var leg_tiles: float = VehicleRoads.leg_length("works", "apartments")
	K.expect(f, leg_tiles > 0.0 and absf(TransportBus.offset_at(loop, 1) - (leg_tiles / float(TransportBus.cfg().get("tiles_per_min", 6.0)) + float(Transport.sect("modes")["bus"].get("dwell", 0.5)))) < 0.01, "the ride time between two stops follows the lane route (%.0f tiles)" % leg_tiles)
	# the real wait decides the mode: find a minute with a long wait at the market, ask for a trip of about ten minutes on foot
	var idx: int = stops.find("market")
	var long_t: int = -1
	var short_t: int = -1
	for m in range(5 * 60, 20 * 60):
		var t2: int = 2 * 1440 + m
		var wt: float = TransportBus.wait_at(loop, idx, t2)
		if long_t < 0 and wt >= 50.0 and wt < 60.0:
			long_t = t2
		if short_t < 0 and wt <= 2.0:
			short_t = t2
	K.expect(f, long_t > 0 and short_t > 0, "there are minutes with a 50 minute wait and with almost none")
	var dest := Vector2i(60, 12)
	var opts := {"n": 32, "from_lot": "market", "to_lot": "school", "modes": ["bus", "taxi"]}
	opts["modes"] = ["bus"]
	SimEnv.clock().total_minutes = long_t
	var p_long: Dictionary = TransportTrip.plan(ada, dest, opts)
	K.expect(f, str(p_long["mode"]) == "walk", "a 50 minute wait is not taken for a short trip: they walk (%s, %.0f min)" % [p_long["mode"], float(p_long["minutes"])])
	SimEnv.clock().total_minutes = short_t
	var p_short: Dictionary = TransportTrip.plan(ada, dest, {"n": 90, "from_lot": "market", "to_lot": "school", "modes": ["bus"]})
	K.expect(f, str(p_short["mode"]) == "bus" and float(p_short["minutes"]) < 90.0 * Interaction.WALK_MIN_PER_TILE, "with no wait a long trip goes by bus (%s, %.0f min)" % [p_short["mode"], float(p_short["minutes"])])
	return f
