extends RefCounted
## SLOW tier: many game years of the whole town with the default Surprises setting. Checks the crime rates against the task targets (burglary
## around half a year per house, street robbery ~0.1 a year for a night-walker, murder < 0.01 a year per household), that wrongful convictions stay
## under 5%, that a forced serial killer is always caught within the victim cap, and that nothing grows without bound (cases, pending, civil).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	_town_years(f)
	_serial(f)
	return f

func _town_years(f: Array) -> void:
	var w := C.town(14)
	for h in 2:
		K.make_folk(w, "Neighbour%d" % h, [], h + 2, Vector2i(20 + h * 4, 12))
		WorldIface.coins[h + 2] = 800
	var years: int = TestFixture.pick(16, 6)
	var t0: int = Time.get_ticks_msec()
	var hh: int = Economy.household_ids().size()
	var guilty_t: int = 0
	var peak_cases: int = 0
	var peak_pending: int = 0
	for y in years:
		for d in YEAR:
			K.set_time(2 + y * YEAR + d, 0)
			for hr in 24:
				K.set_time(2 + y * YEAR + d, hr)
				IncidentChecks.run("hour")
				if hr == 0 or hr == 6 or hr == 12 or hr == 18:
					CrimeFlow.on_hour()
				if not JusticeState.pending.is_empty():
					for m in 90:
						SimEnv.clock().total_minutes += 1
						CrimeFlow.on_minute()
					K.set_time(2 + y * YEAR + d, hr)
			K.set_time(2 + y * YEAR + d, 23)
			Story.on_day(2 + y * YEAR + d)
			RelationshipService.on_day(2 + y * YEAR + d)
			IncidentChecks.run("day")
			CrimeFlow.on_day(2 + y * YEAR + d)
			for r in SysUtil.residents():          # keep the household fed and unharmed: this test is about crime
				for n in r.needs:
					(r.needs[n] as Stat).set_value(60.0)
			for pid in JusticeState.inmates.keys():
				pass
			while Story.alive_townies().size() < 14:
				Story.add_townie()
		peak_cases = maxi(peak_cases, JusticeState.cases.size())
		peak_pending = maxi(peak_pending, JusticeState.pending.size())
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var lots: float = float(hh + 6)
	var burg: float = float(JusticeState.counter("burglary")) / (float(years) * lots)
	var rob: float = float(JusticeState.counter("robbery")) / (float(years) * 14.0)
	var murders: int = JusticeState.counter("murder") + JusticeState.counter("serial")
	var murder_rate: float = float(JusticeState.counter("murder")) / maxf(float(JusticeState.counters.get("exposure_hh", 0.0)), 0.01)
	print("[crime_longrun] %d years in %.1f s: burglary %.2f/yr per lot, robbery %.3f/yr per townie, murder %d (%.4f per household-year), assault %d, arrests %d (wrongful %d), trials %d, convictions %d, innocent convicted %d of %d, civil %d, cases kept %d" % [
		years, elapsed, burg, rob, JusticeState.counter("murder"), murder_rate, JusticeState.counter("assault"), JusticeState.counter("arrests"),
		JusticeState.counter("wrongful_arrests"), JusticeState.counter("trials"), JusticeState.counter("convictions"), JusticeState.counter("innocent_convicted"),
		JusticeState.counter("innocent_tried"), JusticeState.civil.size(), JusticeState.cases.size()])
	K.expect(f, burg > 0.15 and burg < 1.0, "burglary is rare but real: %.2f a year per house" % burg)
	K.expect(f, rob < 0.4, "street robbery stays rare: %.3f a year per townie" % rob)
	var exposure: float = float(JusticeState.counters.get("exposure_hh", 0.0))
	K.expect(f, JusticeState.counter("murder") <= int(ceil(0.02 * exposure)), "murder stays rare, about 0.01 a year per household (limit 0.02 x %.0f household-years = %d): %.4f (%d)" % [exposure, int(ceil(0.02 * exposure)), murder_rate, murders])
	var it: int = JusticeState.counter("innocent_tried")
	if it >= 10:
		K.expect(f, float(JusticeState.counter("innocent_convicted")) / float(it) < 0.05, "innocent people convicted under 5%% (%d of %d)" % [JusticeState.counter("innocent_convicted"), it])
	K.expect(f, JusticeState.counter("wrongful_arrests") <= maxi(JusticeState.counter("arrests") / 8, 2), "wrongful arrests are rare (%d of %d)" % [JusticeState.counter("wrongful_arrests"), JusticeState.counter("arrests")])
	K.expect(f, peak_cases <= int(JusticeState.sect("general").get("case_cap", 160)) + 5 and peak_pending < 80 and JusticeState.civil.size() <= 80, "nothing grows without bound (cases %d, pending %d)" % [peak_cases, peak_pending])
	K.teardown()
	guilty_t += 0

func _serial(f: Array) -> void:
	var caught: int = 0
	var pattern: int = 0
	var worst: int = 0
	var runs: int = TestFixture.pick(20, 6)
	for r in runs:
		var w := C.town(14)
		JusticeState.seed_rng(2000 + r)
		CrimeSerial.start(int(C.adults()[r % C.adults().size()]))
		K.set_time(2, 8, 0)
		for d in 250:
			if not CrimeSerial.active():
				break
			C.days(1)
		var s: Dictionary = JusticeState.serial
		worst = maxi(worst, (s["victims"] as Array).size())
		if bool(s.get("caught", false)):
			caught += 1
		if int(s.get("pattern_day", -1)) >= 0:
			pattern += 1
		K.teardown()
	print("[crime_longrun] serial killer: caught %d of %d, pattern detection fired in %d, most victims %d (cap %d)" % [caught, runs, pattern, worst, int(JusticeState.sect("serial").get("victim_cap", 5))])
	K.expect(f, caught == runs and worst <= 5, "every serial killer is caught within the victim cap (most victims %d)" % worst)
	K.expect(f, pattern >= runs / 4, "pattern detection fires in many runs (%d of %d)" % [pattern, runs])
