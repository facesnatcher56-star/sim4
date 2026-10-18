extends RefCounted
## Weather model: Markov chain validity per season, determinism, temperature bounds / curve, forecast accuracy.

const W = preload("res://tests/weather_kit.gd")

func run() -> Array:
	var f: Array = []
	_markov(f)
	_determinism(f)
	_temperature(f)
	_forecast(f)
	_daylight(f)
	return f

func _markov(f: Array) -> void:
	W.setup(31)
	var steps: int = 2 * 4 * 7 * 6 * 3    # 3 years of 4-hour steps (7-day seasons)
	var seen: Dictionary = {}
	var prev: String = ""
	for k in steps:
		var id: String = Weather.weather_at_step(k)
		var season: String = Weather._season_of_step(k)
		seen[id] = true
		W.expect(f, Weather.valid_in_season(id, season), "step %d: %s must not occur in %s" % [k, id, season])
		if prev != "" and Weather.valid_in_season(prev, season):
			var probs: Dictionary = Weather.transition_probs(prev, season)
			W.expect(f, float(probs.get(id, 0.0)) > 0.0, "step %d: transition %s -> %s has zero probability in %s" % [k, prev, id, season])
		prev = id
	for s in Seasons.IDS:
		for p in Weather.season_weights(s):
			var probs2: Dictionary = Weather.transition_probs(str(p), s)
			var sum: float = 0.0
			for q in probs2:
				sum += float(probs2[q])
			W.expect(f, absf(sum - 1.0) < 0.0001, "probabilities for %s in %s sum to %f" % [p, s, sum])
	W.expect(f, seen.size() >= 7, "three years should show most weather types, saw %d" % seen.size())
	for id2 in ["sunny", "cloudy", "rain"]:
		W.expect(f, seen.has(id2), "%s should occur" % id2)
	# type restrictions
	for k2 in steps:
		var id3: String = Weather.weather_at_step(k2)
		var season2: String = Weather._season_of_step(k2)
		if id3 == "snow":
			W.expect(f, season2 == "winter", "snow outside winter")
		if id3 == "heatwave":
			W.expect(f, season2 == "summer", "heatwave outside summer")
	W.teardown()

func _determinism(f: Array) -> void:
	W.setup(5)
	var a: Array = []
	for k in 200:
		a.append(Weather.weather_at_step(k))
	Weather.reset(5)
	var b: Array = []
	for k in range(199, -1, -1):     # query in a different order
		b.append(Weather.weather_at_step(k))
	b.reverse()
	W.expect(f, a == b, "same seed must give the same chain regardless of query order")
	Weather.reset(6)
	var c: Array = []
	for k in 200:
		c.append(Weather.weather_at_step(k))
	W.expect(f, a != c, "different seeds should differ")
	W.teardown()

func _temperature(f: Array) -> void:
	W.setup(99)
	var lo: float = 999.0
	var hi: float = -999.0
	var by_season: Dictionary = {"spring": [], "summer": [], "autumn": [], "winter": []}
	var noon: float = 0.0
	var night: float = 0.0
	var days: int = 0
	for day in range(1, 2 * 28 + 1):
		for h in 24:
			var t: float = Weather.temperature(W.at(day, h))
			W.expect(f, not is_nan(t) and not is_inf(t), "temperature NaN/inf on day %d h%d" % [day, h])
			lo = minf(lo, t)
			hi = maxf(hi, t)
			(by_season[Seasons.season_at_day(day)] as Array).append(t)
		noon += Weather.temperature(W.at(day, 15))
		night += Weather.temperature(W.at(day, 3))
		days += 1
	W.expect(f, lo >= -25.0 and hi <= 50.0, "temperature range %f .. %f outside sane bounds" % [lo, hi])
	W.expect(f, lo < 5.0 and hi > 22.0, "two years should span cold and warm (%f .. %f)" % [lo, hi])
	var means: Dictionary = {}
	for s in by_season:
		var sum: float = 0.0
		for v in by_season[s]:
			sum += float(v)
		means[s] = sum / float((by_season[s] as Array).size())
	W.expect(f, means["summer"] > means["spring"] and means["spring"] > means["winter"], "season means: %s" % str(means))
	W.expect(f, means["winter"] < 3.0 and means["summer"] > 18.0, "winter should be cold and summer warm: %s" % str(means))
	W.expect(f, noon / days > night / days + 3.0, "afternoons must be warmer than pre-dawn on average")
	# no jumps larger than a few degrees between consecutive minutes-of-hour (smooth blending)
	var worst: float = 0.0
	for m in range(0, 60 * 24 * 10, 10):
		worst = maxf(worst, absf(Weather.temperature(m + 10) - Weather.temperature(m)))
	W.expect(f, worst < 2.5, "temperature changes %f deg in 10 minutes (should blend smoothly)" % worst)
	# forced weather shifts the curve
	var base: float = Weather.temperature(W.at(10, 12))
	Weather.force("heatwave")
	var hot: float = Weather.temperature(W.at(10, 12))
	Weather.force("cold_snap")
	var cold: float = Weather.temperature(W.at(10, 12))
	W.expect(f, hot > cold + 10.0, "heatwave vs cold snap offset (%f vs %f, base %f)" % [hot, cold, base])
	W.teardown()

func _forecast(f: Array) -> void:
	W.setup(1234)
	SimEnv.clock().total_minutes = W.at(3, 10)
	var fc: Array = Weather.forecast(2)
	W.expect(f, fc.size() == 2, "forecast(2) returns two days")
	W.expect(f, int(fc[0]["day"]) == 4 and int(fc[1]["day"]) == 5, "forecast starts tomorrow")
	for d in fc:
		W.expect(f, (d["steps"] as Array).size() == 6, "6 four-hour steps per day")
		W.expect(f, float(d["hi"]) >= float(d["lo"]), "hi >= lo")
		W.expect(f, str(d["label"]) != "", "forecast has a label")
	# the forecast is exact: step weathers match reality when the day arrives
	var predicted: Array = (fc[0]["steps"] as Array).duplicate()
	var actual: Array = []
	for step in 6:
		SimEnv.clock().total_minutes = W.at(4, step * 4, 5)
		actual.append(Weather.current())
	W.expect(f, predicted == actual, "forecast %s != actual %s" % [str(predicted), str(actual)])
	W.expect(f, Weather.forecast_text(2).split("\n").size() == 2, "forecast text has one line per day")
	W.teardown()

func _daylight(f: Array) -> void:
	W.setup()
	SimEnv.clock().total_minutes = W.at(11, 12)
	W.expect(f, Weather.daylight(12.0) > 0.95 and Weather.daylight(0.0) < 0.05, "noon bright, midnight dark")
	W.expect(f, Weather.daylight(Seasons.sunrise()) > 0.1 and Weather.daylight(Seasons.sunrise()) < 0.9, "sunrise is twilight")
	SimEnv.clock().total_minutes = W.at(11, 2)
	W.expect(f, Weather.is_dark(), "2am is dark")
	W.teardown()
