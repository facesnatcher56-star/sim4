extends RefCounted
## Task 12.1 long run (slow tier): measured outage rates per zone-year against data/city.json, the effect of weather and of a starved budget.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

const YEARS := 60

func _measure(years: int) -> Dictionary:
	Utilities.reset()
	UtilityEvents.dice_on = true
	var hours: int = years * 28 * 24
	for i in hours:
		SimEnv.clock().total_minutes += 60
		Utilities.on_minute()
		UtilityEvents.roll_hour()
	return Utilities.stats.duplicate()

func run() -> Array:
	var f: Array = []
	C.setup()
	UtilityEvents.dice_on = true
	var zones: int = CityState.zone_ids().size()
	Weather.force("sunny")
	var st: Dictionary = _measure(YEARS)
	var causes: Dictionary = Utilities.cfg().get("causes", {})
	for util in causes:
		for cid in causes[util]:
			var spec: Dictionary = causes[util][cid]
			var maint: float = CityBudget.maintenance_mult("utilities") if bool(spec.get("maintenance", false)) else 1.0
			var want: float = float(spec["rate"]) * maint * float(zones) * float(YEARS)
			var got: float = float(st.get("cause_" + str(cid), 0))
			# an outage blocks its own util for a while, so slightly fewer than the raw rate (hours/672 per year)
			K.expect(f, absf(got - want * 0.97) < 3.5 * sqrt(want) + 0.05 * want, "%s: %.0f outages in %d years x %d zones, expected about %.0f" % [cid, got, YEARS, zones, want])
	K.expect(f, int(st.get("boil_notices", 0)) > 0, "boil notices happen (%s)" % str(st.get("boil_notices", 0)))
	# storms: a thunderstorm year has far more power cuts
	Weather.force("thunderstorm")
	var storm: Dictionary = _measure(2)
	K.expect(f, int(storm.get("cause_storm", 0)) > int(st.get("cause_storm", 1)) / YEARS * 2 * 3, "thunderstorms multiply storm damage (%s)" % str(storm.get("cause_storm", 0)))
	Weather.force("sunny")
	# a starved budget lets things break more and fixes them slower
	var base: Dictionary = _measure(10)
	CityBudget.set_funding("utilities", 0.5)
	var poor: Dictionary = _measure(10)
	K.expect(f, int(poor.get("outages", 0)) > int(base.get("outages", 1)) * 1.3, "a starved budget: more outages (%s vs %s)" % [str(poor.get("outages", 0)), str(base.get("outages", 0))])
	K.expect(f, int(poor.get("hours_down", 0)) > int(base.get("hours_down", 1)) * 1.6, "and longer ones (%s h vs %s h)" % [str(poor.get("hours_down", 0)), str(base.get("hours_down", 0))])
	CityBudget.set_funding("utilities", 1.0)
	K.teardown()
	return f
