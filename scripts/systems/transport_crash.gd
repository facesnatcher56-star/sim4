class_name TransportCrash
extends RefCounted
## Crashes, wear and breakdowns of trips by car or bike (task 12.2). The chance per trip is data (data/transport.json crash): night, rush hour, bad weather,
## a tired driver, bad roads, a worn car and traffic lights that are out all raise it. A crash is minor (a dent), serious (hurt, real repairs) or a wreck;
## the car policy of BankInsurance pays a share of repairs, a wreck is towed (free when insured). Notifications are plain words; serious ones are in the chronicle.

static func cfg() -> Dictionary:
	return Transport.sect("crash")

static func wear(c: Dictionary) -> float:
	var q: float = TransportTraffic.mean_quality()
	var w: float = Transport.num("cars", "wear_per_trip", 0.0006)
	if float(c["cond"]) < 0.6:
		w += Transport.num("cars", "wear_old", 0.0004)
	return w * (1.0 + (1.0 - q))

## The chance that this trip ends in a crash (before the dice).
static func chance(f, p: Dictionary) -> float:
	var c: Dictionary = cfg()
	var mode: String = str(p["mode"])
	var base: float = float(c.get("per_trip", 0.0036)) if mode == "car" else float(c.get("bike_per_trip", 0.002))
	var h: float = SysUtil.hour_f()
	var zone: String = TransportTraffic.zone_of_tile(f.tile)
	if h >= 21.0 or h < 5.5:
		base *= float(c.get("night", 1.6))
	if TransportTraffic.density(h, zone) >= 0.8:
		base *= float(c.get("rush", 1.35))
	base *= float((c.get("weather", {}) as Dictionary).get(Weather.current(), 1.0))
	if f.get_stat_value("energy") < float(c.get("tired_energy", -40)):
		base *= float(c.get("tired", 1.8))
	base *= 1.0 + (1.0 - TransportTraffic.quality(zone)) * float(Transport.num("roads", "crash_mult", 1.0))
	if TransportTraffic.lights_out(zone):
		base *= 1.3
	if mode == "car":
		var car: Dictionary = Transport.car(int(p.get("car", -1)))
		if not car.is_empty():
			base *= 1.0 + (1.0 - float(car["cond"]))
	return base

## "" (no crash) | minor | serious | wreck | bike.
static func roll(f, p: Dictionary) -> String:
	var mode: String = str(p["mode"])
	if mode != "car" and mode != "bike":
		return ""
	if not CityState.chance(chance(f, p)):
		return ""
	if mode == "bike":
		return "bike"
	var out: Dictionary = cfg().get("outcomes", {"minor": 1.0})
	var total: float = 0.0
	for k in out:
		total += float(out[k])
	var r: float = CityState.rng.randf() * total
	for k2 in out:
		r -= float(out[k2])
		if r <= 0.0:
			return str(k2)
	return "minor"

static func _range(a: Array) -> float:
	return CityState.rng.randf_range(float(a[0]), float(a[1]))

## The aftermath, at the minute the trip would have ended.
static func apply(f, p: Dictionary) -> void:
	var kind: String = str(p["crash"])
	var c: Dictionary = cfg()
	var text: Dictionary = Transport.sect("text")
	var hid: int = int(f.household_id)
	Transport.count("crashes")
	Transport.count("crash_" + kind)
	if kind == "bike":
		SysUtil.notify(str(text.get("bike_crash", "")).replace("{name}", str(f.name)), "warn")
		if CityState.chance(float(c.get("bike_injure", 0.4))):
			Health.injure(f, 1, "a fall from the bike")
		return
	var spec: Dictionary = c.get(kind, {})
	var car: Dictionary = Transport.car(int(p.get("car", -1)))
	var sev: int = int(spec.get("severity", 1))
	if not car.is_empty():
		car["cond"] = maxf(float(car["cond"]) - _range(spec.get("cond", [0.1, 0.2])), 0.0)
		if kind == "wreck":
			car["wreck"] = true
			car["cond"] = 0.0
			TransportParking.leave(car)
			var insured: bool = BankInsurance.has(hid, "car")
			if not insured:
				Economy.record(hid, -int(round(float(c.get("tow_fee", 60)) * Transport.price_mult())), "tow")
	var hurt: bool = CityState.chance(float(spec.get("injure", 0.0)))
	SysUtil.notify(str(text.get("crash_" + kind, "")).replace("{name}", str(f.name)), "bad" if kind != "minor" else "warn")
	if hurt:
		Health.injure(f, sev, "a car crash")
	if kind == "wreck" and CityState.chance(float(spec.get("death", 0.0))):
		Aging.kill(int(f.id), "accident_traffic")
	if kind != "minor":
		ChronicleHook.note("car_crash", "%s crashed a car." % str(f.name), [int(f.id)], "home:%d" % hid, 2 if kind == "serious" else 3, true)
	SysUtil.game_event("car_crash", {"folk_id": int(f.id), "kind": kind, "household_id": hid})
