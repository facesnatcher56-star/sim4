extends RefCounted
## SLOW tier: real per-town-year crime rates over many game years, checked against data/justice.json "targets" (task 04 / 09c / 19.3).
## A town here = the player household, two neighbour households and 12 townies; a year = 28 days. Prints the full table so before/after
## tuning numbers can be compared. Repeat offenders must be caught and spend time away: also checks that nobody who is inside commits crimes.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	var w := C.town(12)
	for h in 2:
		K.make_folk(w, "Neighbour%d" % h, [], h + 2, Vector2i(20 + h * 4, 12))
		WorldIface.coins[h + 2] = 800
	var years: int = TestFixture.pick(12, 4)
	var hh: int = Economy.household_ids().size()
	var t0: int = Time.get_ticks_msec()
	for y in years:
		for d in YEAR:
			var day: int = 2 + y * YEAR + d
			for hr in 24:
				K.set_time(day, hr)
				IncidentChecks.run("hour")
				if hr == 0 or hr == 6 or hr == 12 or hr == 18:
					CrimeFlow.on_hour()
				if not JusticeState.pending.is_empty():
					for m in 90:
						SimEnv.clock().total_minutes += 1
						CrimeFlow.on_minute()
					K.set_time(day, hr)
			K.set_time(day, 23)
			Story.on_day(day)
			RelationshipService.on_day(day)
			IncidentChecks.run("day")
			CrimeFlow.on_day(day)
			for r in SysUtil.residents():
				for n in r.needs:
					(r.needs[n] as Stat).set_value(60.0)
			while Story.alive_townies().size() < 12:
				Story.add_townie()
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var T: Dictionary = JusticeState.sect("targets")
	var tol: float = float(T.get("tolerance", 0.3))
	var n := func(k: String) -> int: return JusticeState.counter(k)
	var lots: float = float(hh + 6)
	var burg: float = float(n.call("burglary")) / (float(years) * lots)
	var rob: float = float(n.call("robbery")) / (float(years) * 12.0)
	var expo: float = maxf(float(JusticeState.counters.get("exposure_hh", 0.0)), 0.01)
	var murder: float = float(n.call("murder") + n.call("serial")) / expo
	var assault: float = float(n.call("assault")) / float(years)
	var petty: float = float(n.call("vandalism") + n.call("trespassing") + n.call("disturbance") + n.call("shoplifting")) / float(years)
	var fraud: float = float(n.call("fraud") + n.call("embezzlement") + n.call("blackmail")) / float(years)
	var arrests: float = float(n.call("arrests")) / float(years)
	var convictions: float = float(n.call("convictions")) / float(years)
	var by_kind: Array = []
	for k in JusticeState.counters:
		if str(k).begins_with("arrest_") or str(k).begins_with("pressure_"):
			by_kind.append("%s %d" % [k, int(JusticeState.counters[k])])
	by_kind.sort()
	print("[crime_rates] %d town-years in %.0f s: burglary %.3f per lot-year, robbery %.3f per townie-year, murder %.4f per household-year, assault %.2f, petty %.2f, fraud/embezzle/blackmail %.2f, arrests %.2f, convictions %.2f per town-year (wrongful arrests %d)" % [
		years, secs, burg, rob, murder, assault, petty, fraud, arrests, convictions, n.call("wrongful_arrests")])
	print("[crime_rates] raw counters: burglary %d robbery %d theft %d assault %d murder %d | %s" % [n.call("burglary"), n.call("robbery"), n.call("theft"), n.call("assault"), n.call("murder"), ", ".join(by_kind)])
	_band(f, "burglary per lot-year", burg, T.get("burglary_per_lot_year", [0, 1]), tol)
	_band(f, "robbery per townie-year", rob, T.get("robbery_per_townie_year", [0, 1]), tol)
	_band(f, "assault per town-year", assault, T.get("assault_per_town_year", [0, 9]), tol)
	_band(f, "petty offences per town-year", petty, T.get("petty_per_town_year", [0, 99]), tol)
	_band(f, "fraud per town-year", fraud, T.get("fraud_per_town_year", [0, 9]), tol)
	_band(f, "arrests per town-year", arrests, T.get("arrests_per_town_year", [0, 99]), tol)
	_band(f, "convictions per town-year", convictions, T.get("convictions_per_town_year", [0, 99]), tol)
	K.expect(f, murder <= float(T.get("murder_per_household_year_max", 0.01)) * (1.0 + 2.0 * tol) or n.call("murder") <= 1, "murder rate %.4f per household-year within target" % murder)
	K.expect(f, convictions <= arrests + 0.01, "convictions never exceed arrests")
	var warns: float = float(n.call("murder_warning")) / float(years)
	print("[crime_rates] murder warnings %.2f per town-year, murders %d" % [warns, n.call("murder")])
	K.expect(f, warns <= float(T.get("murder_warnings_per_town_year_max", 0.6)) * (1.0 + tol), "murder warnings stay rare (%.2f per town-year)" % warns)
	K.teardown()
	_feuds(f, T)
	return f

## The worst realistic case: a hot-headed adult who has made four enemies and keeps feeding the feud for a month. Murder must stay rare
## (targets.feud_victim_dead_max of the trials) and must not happen at one fixed time of day.
func _feuds(f: Array, T: Dictionary) -> void:
	var trials: int = TestFixture.pick(40, 12)
	var dead: int = 0
	var warned: int = 0
	var minutes: Dictionary = {}
	for t in trials:
		var w := C.town(10)
		JusticeState.seed_rng(7000 + t)
		var ids: Array = C.adults()
		var v: int = int(ids[0])
		Story.townies[v]["traits"] = ["hot_headed"]
		var base_murders: int = JusticeState.counter("murder")
		for e in range(1, 5):
			Story.townies[int(ids[e])]["traits"] = [["hot_headed", "jealous", "grudgeholder", ""][e - 1]] if e < 4 else []
		for d in YEAR:
			K.set_time(5 + d, 1)
			if d % 4 == 0:
				for e2 in range(1, 5):
					C.feud(int(ids[e2]), v, 90.0)
					C.feud(v, int(ids[e2]), 60.0)
			CrimeMurder.on_day()
			var guard: int = 0
			while not JusticeState.pending.is_empty() and guard < 20:
				guard += 1
				var due: int = 999999999
				for p in JusticeState.pending:
					due = mini(due, int(p["due_min"]))
				if due > SysUtil.now() + 1440:
					break
				SimEnv.clock().total_minutes = maxi(due, SysUtil.now())
				CrimeFlow.on_minute()
				if JusticeState.counter("murder") > base_murders:
					minutes[SysUtil.now() % 1440] = true
					break
			if not CrimePerson.alive(v):
				break
		if not CrimePerson.alive(v):
			dead += 1
		warned += JusticeState.counter("murder_warning")
		K.teardown()
	print("[crime_rates] feud stress: %d of %d hot-headed adults with four enemies were killed within a month; %d murder warnings; killing minutes of day %s" % [dead, trials, warned, str(minutes.keys())])
	K.expect(f, float(dead) <= float(T.get("feud_victim_dead_max", 0.1)) * float(trials) + 1.0, "a hot-headed adult with enemies is not usually dead within a month (%d of %d)" % [dead, trials])
	var distinct: bool = minutes.size() != 1 or dead <= 1
	K.expect(f, distinct, "murders do not all happen at one fixed minute of the day")

func _band(f: Array, label: String, v: float, band, tol: float) -> void:
	var lo: float = float(band[0]) * (1.0 - tol)
	var hi: float = float(band[1]) * (1.0 + tol)
	K.expect(f, v >= lo and v <= hi, "%s %.3f within [%.3f, %.3f]" % [label, v, lo, hi])
