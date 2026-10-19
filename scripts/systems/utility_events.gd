class_name UtilityEvents
extends RefCounted
## The dice of the utility networks (task 12.1): once per game hour, for every zone, every cause of data/city.json utilities.causes rolls at
## rate / (year_days x 24) x weather multiplier x maintenance (the budget: starved crews, ageing equipment). Boil water notices come from
## contamination (x flood). Counts: zones x causes (about 10 rolls an hour), nothing per person.

## Tests switch the dice off so a scripted outage is the only one (CityState.reset turns them back on).
static var dice_on: bool = true

static func roll_hour() -> void:
	if not dice_on:
		return
	var u: Dictionary = Utilities.cfg()
	var per_hour: float = 1.0 / (float(u.get("year_days", 28)) * 24.0)
	var wid: String = Weather.current()
	var causes: Dictionary = u.get("causes", {})
	for zone in CityState.zone_ids():
		for util in Utilities.UTILS:
			if Utilities.is_down(util, str(zone)):
				continue
			var specs: Dictionary = causes.get(util, {})
			for cid in specs:
				var spec: Dictionary = specs[cid]
				var p: float = float(spec.get("rate", 0.0)) * per_hour * _weather_mult(spec, wid) * _maint(spec)
				if CityState.chance(p):
					start(util, str(zone), str(cid))
					break
		_contamination(str(zone), per_hour, u)

static func _weather_mult(spec: Dictionary, wid: String) -> float:
	return float((spec.get("weather", {}) as Dictionary).get(wid, 1.0))

static func _maint(spec: Dictionary) -> float:
	return CityBudget.maintenance_mult("utilities") if bool(spec.get("maintenance", false)) else 1.0

static func _contamination(zone: String, per_hour: float, u: Dictionary) -> void:
	if Utilities.boil_active(zone):
		return
	var b: Dictionary = u.get("boil", {})
	var p: float = float(b.get("contamination_rate", 0.0)) * per_hour * (float(b.get("flood_mult", 1.0)) if DisasterState.running("flood") else 1.0)
	if CityState.chance(p):
		Utilities.start_boil(zone)

## Start a cause now (the dice and the tests both come through here). Repair time follows the budget.
static func start(util: String, zone: String, cause: String, opts: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = ((Utilities.cfg().get("causes", {}) as Dictionary).get(util, {}) as Dictionary).get(cause, {})
	var hrs: Array = spec.get("hours", [2, 6])
	var hours: float = float(CityState.rng.randi_range(int(hrs[0]) * 4, int(hrs[1]) * 4)) / 4.0
	hours /= CityBudget.repair_speed("utilities")
	if opts.has("hours"):
		hours = float(opts["hours"])
	return Utilities.begin(util, zone, hours, cause, opts)
