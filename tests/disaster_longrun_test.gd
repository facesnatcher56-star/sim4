extends RefCounted
## SLOW: real yearly frequency of every disaster over many game years of the real weather (28-day years) against the targets
## (power outage ~0.5, blizzard ~0.3, tornado ~0.02, flood ~0.02, earthquake ~0.01, wildfire ~0.005, hail ~0.1, meteor ~0.0005).
## Two measurements: the EXPECTED yearly rate (sum of every hourly / daily chance, no dice: exact calibration) and the dice count
## (must sit within 4 sigma of the expectation). Also the forecast-watch volume.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

## [target per year, lowest expected, highest expected]
const TARGETS := {
	"power_outage": [0.5, 0.42, 0.6], "blizzard": [0.3, 0.24, 0.36], "tornado": [0.02, 0.016, 0.025], "flood": [0.02, 0.016, 0.025],
	"earthquake": [0.01, 0.0085, 0.0115], "wildfire": [0.005, 0.004, 0.0065], "hailstorm": [0.1, 0.08, 0.125], "meteor_strike": [0.0005, 0.0004, 0.0006],
}

func run() -> Array:
	var f: Array = []
	var years: int = 40 if TestFixture.fast else 160
	var w := D.setup()
	D.home(w)
	Weather.unforce()
	Weather.reset(2468)
	Incidents.register_handler("disaster_hit", Callable(self, "_noop"))
	for id in IncidentDefs.defs.keys():                 # only the disasters (other incidents have their own long-run tests)
		if not TARGETS.has(id):
			IncidentDefs.defs.erase(id)
	for id in TARGETS:
		IncidentDefs.defs[id]["lot_hit"] = 1.0           # count town events, not lots
	var dummy := IncidentSubject.of_town_lot(0)
	var expect_sum: Dictionary = {}
	var watch: int = 0
	var t0 := Time.get_ticks_msec()
	for day in range(2, years * 28 + 2):
		for hr in 24:
			K.set_time(day, hr)
			for id2 in TARGETS:
				var d: Dictionary = IncidentDefs.defs[id2]
				if str(d["check"]) == "hour":
					expect_sum[id2] = float(expect_sum.get(id2, 0.0)) + IncidentRisk.chance(d, dummy)
			Incidents.on_hour()
			DisasterClock.on_hour(hr)
		K.set_time(day, 0, 5)
		for id3 in TARGETS:
			var d3: Dictionary = IncidentDefs.defs[id3]
			if str(d3["check"]) == "day":
				expect_sum[id3] = float(expect_sum.get(id3, 0.0)) + IncidentRisk.chance(d3, dummy)
		Incidents.on_day()
		var notes0: int = K.notes.size()
		DisasterClock.on_day(day)
		for n in range(notes0, K.notes.size()):
			if str(K.notes[n][1]) == "weather":
				watch += 1
		DisasterState.active.clear()
	var report: Dictionary = {}
	for id4 in TARGETS:
		var t: Array = TARGETS[id4]
		var exp_year: float = float(expect_sum.get(id4, 0.0)) / float(years)
		var got: int = int(Incidents.stat(id4)["triggered"])
		report[id4] = "%.4f exp, %d dice" % [exp_year, got]
		K.expect(f, exp_year >= float(t[1]) and exp_year <= float(t[2]), "%s: expected %.4f per year (target %.4f, band %.4f-%.4f)" % [id4, exp_year, float(t[0]), float(t[1]), float(t[2])])
		var e_total: float = exp_year * float(years)
		K.expect(f, absf(float(got) - e_total) <= 4.0 * sqrt(maxf(e_total, 1.0)) + 1.0, "%s: dice gave %d events in %d years, expected about %.1f" % [id4, got, years, e_total])
	var ms: int = Time.get_ticks_msec() - t0
	print("disaster_longrun: %d years in %d ms; %s; watches/yr %.2f" % [years, ms, str(report), float(watch) / float(years)])
	K.expect(f, float(watch) / float(years) <= 14.0, "forecast watches stay occasional (%.1f per year)" % (float(watch) / float(years)))
	Incidents.clear_handlers()
	K.teardown()
	return f

func _noop(_ctx: Dictionary, _args: Dictionary) -> Dictionary:
	return {}
