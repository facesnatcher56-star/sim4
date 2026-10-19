extends RefCounted
## SLOW tier (task 21 / 19.3): townie crime rates stay RARE overall with the criminal path enabled. A town = the player household, two neighbour
## households and 12 townies, a year = 28 days; the daily crime ticks run exactly as in tests/crime_rates_test.gd. Checks how many townies take up the
## path, how many jobs they do per town-year, that heists stay rare but happen (about one per 3 to 6 town-years), and that the combined burglary / robbery / petty numbers still sit in the
## bands of data/justice.json targets. The player's own folk never acts here (only commands move it).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	var w := C.town(12)
	for h in 2:
		K.make_folk(w, "Neighbour%d" % h, [], h + 2, Vector2i(20 + h * 4, 12))
		WorldIface.coins[h + 2] = 800
	var env_seed: String = OS.get_environment("CRIMELIFE_SEED")     # measuring other seeds: CRIMELIFE_SEED=7 (the default run keeps the stored seed)
	if env_seed != "":
		CrimeLifeState.seed_rng(int(env_seed))
	var years: int = TestFixture.pick(12, 4)
	var hh: int = Economy.household_ids().size()
	var member_days: int = 0
	var peak: int = 0
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
			if CrimeFlow.sliced():                          # the harness has a scheduler but never runs it: run the bucketed townie dice by hand
				CrimeLifeTownie.on_day_all()
			for r in SysUtil.residents():
				for n in r.needs:
					(r.needs[n] as Stat).set_value(60.0)
			while Story.alive_townies().size() < 12:
				Story.add_townie()
			var members: int = CrimeLifeState.members.size()
			member_days += members
			peak = maxi(peak, members)
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var jobs: int = 0
	var job_kinds: Array = []
	for k in CrimeLifeState.counters:
		if str(k).begins_with("job_"):
			jobs += int(CrimeLifeState.counters[k])
			job_kinds.append("%s %d" % [str(k).trim_prefix("job_"), int(CrimeLifeState.counters[k])])
	job_kinds.sort()
	var joined: int = CrimeLifeState.counter("joined")
	var avg_members: float = float(member_days) / float(years * YEAR)
	var heists: int = CrimeLifeState.counter("heists_planned") + CrimeLifeState.counter("job_heist")
	var jobs_per_year: float = float(jobs) / float(years)
	var burg: float = float(JusticeState.counter("burglary")) / (float(years) * float(hh + 6))
	var rob: float = float(maxi(JusticeState.counter("robbery") - heists, 0)) / (float(years) * 12.0)   # heists have their own band below
	var petty: float = float(JusticeState.counter("vandalism") + JusticeState.counter("trespassing") + JusticeState.counter("disturbance") + JusticeState.counter("shoplifting")) / float(years)
	print("[crimelife_rates] %d town-years in %.0f s: %d joined, average %.2f members (peak %d), %.2f jobs per town-year (%s), heists %d, burglary %.3f per lot-year, robbery %.3f per townie-year, petty %.2f, snitches %d, stash found %d, fenced %d (traced %d)" % [
		years, secs, joined, avg_members, peak, jobs_per_year, ", ".join(job_kinds), heists, burg, rob, petty, CrimeLifeState.counter("snitches"), CrimeLifeState.counter("stash_found"),
		CrimeLifeState.counter("fenced_items"), CrimeLifeState.counter("fenced_traced")])
	var T: Dictionary = JusticeState.sect("targets")
	var tol: float = float(T.get("tolerance", 0.3))
	K.expect(f, avg_members <= 2.5, "criminals stay rare: %.2f members on average among 12 townies" % avg_members)
	K.expect(f, jobs_per_year <= 6.0, "townie jobs stay rare: %.2f per town-year" % jobs_per_year)
	K.expect(f, float(joined) / float(years) <= 3.0, "few take up the path: %.2f per town-year" % (float(joined) / float(years)))
	K.expect(f, float(heists) / float(years) <= 0.5, "heists are very rare: %.2f per town-year" % (float(heists) / float(years)))
	if years >= 12:       # rare but possible: about one every 3 to 6 town-years (1 to 6 in 12; seeds measured 1 to 4)
		K.expect(f, heists >= 1 and heists <= 6, "a townie heist now and then: %d in %d town-years" % [heists, years])
	var lo_b: Array = T.get("burglary_per_lot_year", [0, 1])
	K.expect(f, burg <= float(lo_b[1]) * (1.0 + tol), "burglary still within its band (%.3f)" % burg)
	var lo_r: Array = T.get("robbery_per_townie_year", [0, 1])
	K.expect(f, rob <= float(lo_r[1]) * (1.0 + tol), "robbery still within its band (%.3f)" % rob)
	var lo_p: Array = T.get("petty_per_town_year", [0, 99])
	K.expect(f, petty <= float(lo_p[1]) * (1.0 + tol), "petty offences still within their band (%.2f)" % petty)
	K.expect(f, jobs > 0 or avg_members < 0.05, "the path does something when it has members")
	K.teardown()
	return f
