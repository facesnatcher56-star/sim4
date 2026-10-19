extends RefCounted
## Task 12.2 long run (slow tier): crash rates per car trip and per car-year, the outcome mix, the effect of rain, night and bad roads, and tows per street-year.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

const TRIPS := 150000

func _crashes(ada: Folk, p: Dictionary, n: int) -> Dictionary:
	var out: Dictionary = {"all": 0, "minor": 0, "serious": 0, "wreck": 0}
	for i in n:
		var k: String = TransportCrash.roll(ada, p)
		if k != "":
			out["all"] = int(out["all"]) + 1
			out[k] = int(out[k]) + 1
	return out

func run() -> Array:
	var f: Array = []
	var w := C.setup()
	var h: Dictionary = C.home(w)
	var ada: Folk = h["ada"]
	K.set_time(3, 13)
	WorldIface.coins[1] = 9000
	Weather.force("sunny")
	for z in CityState.zone_ids():
		TransportTraffic.set_quality(str(z), 0.85)
	var car: Dictionary = Transport.car(int(TransportCars.buy(1, "hatch")["car"]))
	var p := {"mode": "car", "car": int(car["id"])}
	var base: Dictionary = _crashes(ada, p, TRIPS)
	var want: float = TransportCrash.chance(ada, p) * float(TRIPS)
	K.expect(f, absf(float(base["all"]) - want) < 4.0 * sqrt(want), "crashes per car trip: %d in %d trips, expected %.0f" % [int(base["all"]), TRIPS, want])
	var per_year: float = float(base["all"]) / float(TRIPS) * 56.0
	K.expect(f, per_year > 0.15 and per_year < 0.4, "about one crash in four car-years at two trips a day (%.2f per car-year)" % per_year)
	var tot: float = float(base["all"])
	K.expect(f, absf(float(base["minor"]) / tot - 0.7) < 0.06 and absf(float(base["serious"]) / tot - 0.25) < 0.06 and float(base["wreck"]) / tot < 0.09, "outcome mix 70 / 25 / 5 percent (%s)" % str(base))
	Weather.force("rain")
	var rain: Dictionary = _crashes(ada, p, TRIPS)
	K.expect(f, float(rain["all"]) > float(base["all"]) * 1.5, "rain makes crashes more likely (%d vs %d)" % [int(rain["all"]), int(base["all"])])
	Weather.force("sunny")
	K.set_time(3, 2)
	var night: Dictionary = _crashes(ada, p, TRIPS)
	K.expect(f, float(night["all"]) > float(base["all"]) * 1.35, "so does the night (%d vs %d)" % [int(night["all"]), int(base["all"])])
	K.set_time(3, 13)
	for z2 in CityState.zone_ids():
		TransportTraffic.set_quality(str(z2), 0.15)
	var bad: Dictionary = _crashes(ada, p, TRIPS)
	K.expect(f, float(bad["all"]) > float(base["all"]) * 1.4, "and bad roads (%d vs %d)" % [int(bad["all"]), int(base["all"])])
	# tows: a car left on a venue street overnight, every night for a long time
	Transport.cars.clear()
	WorldIface.coins[1] = 9000
	var c2: Dictionary = Transport.car(int(TransportCars.buy(1, "banger")["car"]))
	var tows: int = 0
	var nights: int = 4000
	for i in nights:
		c2["towed"] = false
		c2["at"] = "cafe"
		c2["spot"] = "street"
		TransportParking.on_day(10 + i)
		if bool(c2["towed"]):
			tows += 1
	var want_t: float = 0.4 * float(nights)
	K.expect(f, absf(float(tows) - want_t) < 4.0 * sqrt(want_t * 0.6), "street tows at a venue: %d in %d nights, expected %.0f" % [tows, nights, want_t])
	var home_tows: int = 0
	for i2 in 500:
		c2["towed"] = false
		c2["at"] = "home"
		c2["spot"] = "drive"
		TransportParking.on_day(10 + i2)
		if bool(c2["towed"]):
			home_tows += 1
	K.expect(f, home_tows == 0, "a car on its own drive is never towed")
	K.teardown()
	return f
