extends RefCounted
## Save / load: calendar, seed, chain, snow, bill accumulators, holiday state survive a JSON round trip deterministically.

const W = preload("res://tests/weather_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_roundtrip(f)
	_full_save(f)
	return f

func _signature() -> Array:
	var out: Array = [Weather.current(), snappedf(Weather.temperature(), 0.001), Seasons.current(), Seasons.day_of_season(), Seasons.year(),
		snappedf(Weather.snow_cover(), 0.001), snappedf(Weather.bill_multiplier(), 0.0001)]
	for d in Weather.forecast(3):
		out.append([d["weather"], snappedf(float(d["hi"]), 0.001), snappedf(float(d["lo"]), 0.001), d["steps"]])
	for k in range(0, 40):
		out.append(Weather.temperature(W.at(60 + k, 5, 17)))
		out.append(Weather.weather_at(W.at(60 + k, 5, 17)))
	return out

func _roundtrip(f: Array) -> void:
	var w: StubWorld = W.setup(2468)
	K.make_folk(w, "Ann")
	Economy.next_bill_day = 10000          # bills reset the weather bill period; keep them out of this comparison
	Seasons.set_length(5)
	SimEnv.clock().total_minutes = W.at(2, 6)
	W.run_coarse(TestFixture.pick(13, 5) * 1440 + 400)                         # long enough for snow / bills / holidays state
	var before_sig: Array = _signature()
	var before: Dictionary = Weather.to_dict()
	var json: String = JSON.stringify(before)
	var parsed: Variant = JSON.parse_string(json)
	W.expect(f, parsed is Dictionary, "weather state is JSON-serialisable")
	Weather.reset(1)                                   # wipe
	W.expect(f, Weather.seed_value == 1 and Seasons.length() == 7, "reset wiped the state")
	Weather.from_dict(parsed)
	W.expect(f, Weather.seed_value == 2468, "seed restored")
	W.expect(f, Seasons.length() == 5, "season length setting restored")
	var after: Dictionary = Weather.to_dict()
	var diffs: Array = []
	W.expect(f, K.deep_eq(before, after, "weather", diffs), "to_dict identical after round trip: %s" % str(diffs.slice(0, 4)))
	var after_sig: Array = _signature()
	var d2: Array = []
	W.expect(f, K.deep_eq(before_sig, after_sig, "sig", d2), "behaviour identical after round trip: %s" % str(d2.slice(0, 4)))
	# the future is still the same after continuing the game from the loaded state
	W.run_coarse(TestFixture.pick(3, 1) * 1440)
	var cont_a: Array = _signature()
	Weather.from_dict(JSON.parse_string(json))
	SimEnv.clock().total_minutes = W.at(2, 6) + TestFixture.pick(13, 5) * 1440 + 400
	W.run_coarse(TestFixture.pick(3, 1) * 1440)
	var cont_b: Array = _signature()
	var d3: Array = []
	W.expect(f, K.deep_eq(cont_a, cont_b, "cont", d3), "continuing from a loaded state matches the uninterrupted run: %s" % str(d3.slice(0, 4)))
	# empty dict = old save without weather: sane defaults
	Weather.from_dict({})
	W.expect(f, Weather.seed_value == 1337 and Weather.current() != "" and Seasons.length() == 7, "missing weather block falls back to defaults")
	W.teardown()

func _full_save(f: Array) -> void:
	var w: StubWorld = W.setup(555)
	K.make_folk(w, "Ann")
	Seasons.set_length(6)
	SimEnv.clock().total_minutes = W.at(5, 9)
	W.run_coarse(TestFixture.pick(5, 2) * 1440)
	var snap: Dictionary = SaveLoad.snapshot("t")
	W.expect(f, (snap["systems"] as Dictionary).has("weather"), "SaveLoad snapshot has a weather block")
	var json: String = JSON.stringify(snap)
	var sig_before: Array = _signature()
	Weather.reset(9)
	SaveLoad.restore(JSON.parse_string(json))
	var sig_after: Array = _signature()
	var diffs: Array = []
	W.expect(f, K.deep_eq(sig_before, sig_after, "sig", diffs), "SaveLoad.restore restores the weather: %s" % str(diffs.slice(0, 4)))
	W.expect(f, Seasons.length() == 6, "season length is part of the save")
	W.teardown()