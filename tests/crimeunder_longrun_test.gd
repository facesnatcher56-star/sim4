extends RefCounted
## SLOW tier (task 23): with the underworld lines enabled, the town stays mostly peaceful when the player's folk is a good citizen (the background
## crime rates of 19.3 still hold). A town = the player household, two neighbour households and 12 townies; a year = 28 days; the daily crime
## ticks run as in crimelife_longrun_test. Counts per town-year: townies in each line, contracts posted and carried out, addicts (share of adults),
## overdoses, gangs and wars, busts, corrupt cops, and the average town crime rate. The player's folk never acts here (only commands move it).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	var quiet: Dictionary = _sim(TestFixture.pick(6, 3), false)
	var years: int = int(quiet["years"])
	print("[crimeunder_rates] PEACEFUL town, %d town-years in %.0f s: %s" % [years, float(quiet["secs"]), _line(quiet)])
	K.expect(f, float(quiet["avg_rate"]) < 30.0, "a town with no underworld to speak of stays safe (average crime rate %.1f)" % float(quiet["avg_rate"]))
	K.expect(f, float(quiet["posted"]) <= 0.5 and int(quiet["wars"]) == 0 and float(quiet["peak_share"]) <= 0.1, "and nothing breaks out (contracts %.2f per year, wars %d, addiction share %.2f)" % [float(quiet["posted"]), int(quiet["wars"]), float(quiet["peak_share"])])
	var busy: Dictionary = _sim(TestFixture.pick(6, 3), true)
	years = int(busy["years"])
	print("[crimeunder_rates] SEEDED underworld (6 path members), %d town-years in %.0f s: %s" % [years, float(busy["secs"]), _line(busy)])
	K.expect(f, float(busy["posted"]) <= 2.5, "even with an underworld, contracts on people stay rare: %.2f per town-year" % float(busy["posted"]))
	K.expect(f, float(busy["done"]) <= 1.2, "and carried-out contracts rarer still: %.2f per town-year" % float(busy["done"]))
	K.expect(f, float(busy["peak_share"]) <= 0.35, "addiction stays a minority problem: peak share of adults %.2f" % float(busy["peak_share"]))
	K.expect(f, float(busy["wars_py"]) <= 1.5, "gang wars are rare: %.2f per town-year" % float(busy["wars_py"]))
	K.expect(f, int(busy["peak_gangs"]) <= 3, "at most three gangs (%d)" % int(busy["peak_gangs"]))
	K.expect(f, float(busy["avg_rate"]) < 60.0, "the town is not made lawless by it (average crime rate %.1f)" % float(busy["avg_rate"]))
	K.expect(f, float(busy["overdose_deaths"]) <= float(years) * 1.5, "overdose deaths stay low (%d)" % int(busy["overdose_deaths"]))
	K.expect(f, int(busy["activity"]) > 0, "and the underworld does something when it has people (%d events)" % int(busy["activity"]))
	return f

func _line(r: Dictionary) -> String:
	var c: Dictionary = r["c"]
	return "contracts posted %.2f / done %.2f per town-year, addicted %d (peak %d using, share %.2f), overdoses %d (deaths %d), line joins %d (peak %d in lines), gangs founded %d (peak %d), wars %d, busts %d, sales %d, bribes %d, loans %d, average crime rate %.1f; counters %s" % [
		float(r["posted"]), float(r["done"]), int(c.get("addicted", 0)), int(r["peak_addicts"]), float(r["peak_share"]), int(c.get("overdose", 0)), int(r["overdose_deaths"]),
		int(r["joins"]), int(r["peak_lines"]), int(c.get("gang_founded", 0)), int(r["peak_gangs"]), int(r["wars"]), int(c.get("gang_bust", 0)), int(c.get("deal_sold", 0)),
		int(c.get("bribe_taken", 0)), int(c.get("loan", 0)), float(r["avg_rate"]), str(c)]

## One town for `years` years. `seeded`: a few dishonest, broke path members already exist.
func _sim(years: int, seeded: bool) -> Dictionary:
	var w := C.town(12)
	for h in 2:
		K.make_folk(w, "Neighbour%d" % h, [], h + 2, Vector2i(20 + h * 4, 12))
		WorldIface.coins[h + 2] = 800
	if seeded:
		_seed_members(6)
	var t0: int = Time.get_ticks_msec()
	var rate_sum: float = 0.0
	var rate_days: int = 0
	var out: Dictionary = {"peak_addicts": 0, "peak_share": 0.0, "peak_lines": 0, "peak_gangs": 0, "years": years}
	for y in years:
		for d in YEAR:
			var day: int = 2 + y * YEAR + d
			if seeded and d % 14 == 0:
				_seed_members(6)                              # a steady pool: members quit, die or are locked away, new ones come
			for hr in 24:
				K.set_time(day, hr)
				IncidentChecks.run("hour")
				if hr == 0 or hr == 6 or hr == 12 or hr == 18:
					CrimeFlow.on_hour()
				if not JusticeState.pending.is_empty() or not CrimeLifeState.pending.is_empty():
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
				for tid in CrimePerson.townies_only():
					CrimeUnderFlow.person_day(int(tid))
			for r in SysUtil.residents():
				for n in r.needs:
					(r.needs[n] as Stat).set_value(60.0)
			while Story.alive_townies().size() < 12:
				Story.add_townie()
			rate_sum += CrimeRate.value()
			rate_days += 1
			var adults: int = CrimeUnderAddict.adult_townies()
			out["peak_addicts"] = maxi(int(out["peak_addicts"]), CrimeUnderAddict.count_using())
			out["peak_share"] = maxf(float(out["peak_share"]), float(CrimeUnderAddict.count_using()) / float(maxi(adults, 1)))
			var in_lines: int = 0
			for pid in CrimeUnderState.lines:
				in_lines += (CrimeUnderState.lines[pid] as Dictionary).size()
			out["peak_lines"] = maxi(int(out["peak_lines"]), in_lines)
			out["peak_gangs"] = maxi(int(out["peak_gangs"]), CrimeUnderState.gangs.size())
	out["secs"] = float(Time.get_ticks_msec() - t0) / 1000.0
	out["posted"] = float(CrimeUnderState.counter("contract_posted")) / float(years)
	out["done"] = float(CrimeUnderState.counter("contract_done")) / float(years)
	out["avg_rate"] = rate_sum / float(maxi(rate_days, 1))
	out["wars"] = CrimeUnderState.counter("gang_war")
	out["wars_py"] = float(CrimeUnderState.counter("gang_war")) / float(years)
	out["overdose_deaths"] = CrimeUnderState.counter("overdose_death")
	out["joins"] = CrimeUnderState.counter("join_hit") + CrimeUnderState.counter("join_deal") + CrimeUnderState.counter("join_racket")
	var act: int = 0
	for k in CrimeUnderState.counters:
		act += int(CrimeUnderState.counters[k])
	out["activity"] = act
	out["c"] = CrimeUnderState.counters.duplicate()
	K.teardown()
	return out

## Keep `n` hardened, broke, dishonest path members among the townies.
func _seed_members(n: int) -> void:
	var have: int = 0
	for pid in CrimeLifeState.members:
		if not CrimePerson.is_player(int(pid)):
			have += 1
	var ids: Array = C.adults()
	for i in ids.size():
		if have >= n:
			return
		var pid2: int = int(ids[i])
		if CrimeLifePath.is_member(pid2) or not CrimePerson.alive(pid2) or CrimePerson.in_custody(pid2):
			continue
		CrimeLifePath.join(pid2, "chose")
		var m: Dictionary = CrimeLifePath.member(pid2)
		m["cred"] = 70.0 if have < 2 else 45.0
		m["jobs"] = 8
		m["heists"] = 2 if have < 2 else 0
		m["fenced"] = 4
		m["skills"] = {"stealth": 6, "logic": 4, "handiness": 3, "charisma": 4}
		CrimeLifePath.update_rank(pid2)
		Story.townies[pid2]["traits"] = ["dishonest"]
		Story.townies[pid2]["coins"] = 40
		have += 1
