extends RefCounted
## Task 23: addiction. An addicted townie's money and health decline with the level (a dose a day costs coins, frailty rises, overdoses get likelier),
## moods swing for a player's folk, work is lost, and REHAB at the clinic lowers the level, with relapses afterwards (likelier when a dealer still has
## their number). An overdose can end in hospital or death (cause "overdose").

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_decline(f)
	_overdose(f)
	_folk(f)
	_rehab(f)
	_relapse(f)
	_death(f)
	return f

func _hook(pid: int, level: float = 0.5) -> void:
	CrimeUnderAddict.try_onset(pid, "glow", -1, true)
	CrimeUnderAddict.rec(pid)["level"] = level

func _decline(f: Array) -> void:
	var w := C.town(14)
	var t: int = int(C.adults()[0])
	Story.townies[t]["coins"] = 800
	Story.townies[t]["career"] = "cook"
	_hook(t, 0.5)
	CrimeUnderState.sect("addict")["overdose"]["base"] = 0.0
	CrimeUnderState.sect("addict")["overdose"]["level"] = 0.0
	CrimeUnderState.sect("addict")["desperate_theft"] = 0.0
	CrimeUnderState.sect("addict")["job_loss_daily"] = 1.0
	var coins0: int = CrimePerson.coins(t)
	var frail0: float = float(CrimeUnderAddict.rec(t)["frail"])
	for d in 10:
		CrimeUnderAddict.day_of(t)
	K.expect(f, CrimePerson.coins(t) < coins0 - 150, "a habit drains the money (%d -> %d)" % [coins0, CrimePerson.coins(t)])
	K.expect(f, float(CrimeUnderAddict.rec(t)["frail"]) > frail0 + 0.02, "and wears the body down (frailty %.3f)" % float(CrimeUnderAddict.rec(t)["frail"]))
	K.expect(f, float(CrimeUnderAddict.rec(t)["level"]) > 0.55, "the level climbs with doses (%.2f)" % float(CrimeUnderAddict.rec(t)["level"]))
	K.expect(f, not CrimePerson.has_job(t), "a bad enough habit loses the job")
	# broke: doses are missed, level falls, cravings
	Story.townies[t]["coins"] = 0
	var lv: float = float(CrimeUnderAddict.rec(t)["level"])
	for d in 5:
		CrimeUnderAddict.day_of(t)
	K.expect(f, float(CrimeUnderAddict.rec(t)["level"]) < lv, "without money the doses stop and the level falls")
	K.teardown()

func _overdose(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	_hook(int(ids[0]), 0.2)
	_hook(int(ids[1]), 0.9)
	CrimeUnderAddict.rec(int(ids[1]))["frail"] = 0.6
	for t in [ids[0], ids[1]]:
		Story.townies[t]["coins"] = 100000
	var lo: int = 0
	var hi: int = 0
	CrimeUnderState.sect("addict")["overdose"]["death"] = 0.0
	CrimeUnderState.sect("addict")["desperate_theft"] = 0.0
	var c0: int = CrimeUnderState.counter("overdose")
	for d in 400:
		CrimeUnderAddict.rec(int(ids[0]))["level"] = 0.2
		CrimeUnderAddict.rec(int(ids[0]))["state"] = "using"
		CrimeUnderAddict._overdose(int(ids[0]), true, CrimeUnderAddict.rec(int(ids[0])), CrimeUnderAddict.cfg())
		Hospital.patients.clear()
	lo = CrimeUnderState.counter("overdose") - c0
	c0 = CrimeUnderState.counter("overdose")
	for d in 400:
		CrimeUnderAddict.rec(int(ids[1]))["level"] = 0.9
		CrimeUnderAddict.rec(int(ids[1]))["state"] = "using"
		CrimeUnderAddict._overdose(int(ids[1]), true, CrimeUnderAddict.rec(int(ids[1])), CrimeUnderAddict.cfg())
		Hospital.patients.clear()
	hi = CrimeUnderState.counter("overdose") - c0
	K.expect(f, hi > lo * 2 and hi >= 3, "overdose risk rises with the level and the frailty (%d vs %d in 400 doses)" % [lo, hi])
	K.teardown()

func _folk(f: Array) -> void:
	var w := C.town(10)
	WorldIface.coins[1] = 1000
	var folk = SysUtil.folk(1)
	_hook(1, 0.4)
	CrimeUnderState.sect("addict")["mood_chance"] = 1.0
	CrimeUnderState.sect("addict")["overdose"]["base"] = 0.0
	CrimeUnderState.sect("addict")["overdose"]["level"] = 0.0
	CrimeUnderAddict.day_of(1)
	K.expect(f, folk.has_buff("high") or folk.has_buff("crash"), "a player's folk swings in mood after a dose")
	WorldIface.coins[1] = 0
	CrimeUnderAddict.day_of(1)
	K.expect(f, folk.has_buff("craving") or folk.has_buff("withdrawal"), "and craves when there is no money")
	K.teardown()

func _rehab(f: Array) -> void:
	var w := C.town(14)
	var t: int = int(C.adults()[0])
	Story.townies[t]["coins"] = 5000
	_hook(t, 0.8)
	var r: Dictionary = CrimeUnderAddict.rehab(t)
	K.expect(f, bool(r["ok"]) and str(CrimeUnderAddict.rec(t)["state"]) == "rehab" and CrimePerson.coins(t) < 5000, "the clinic takes a fee")
	K.teardown()
	# the success rate: many stays
	var ok: int = 0
	var n: int = 300
	var w2 := C.town(14)
	var t2: int = int(C.adults()[0])
	Story.townies[t2]["coins"] = 999999
	for i in n:
		_hook(t2, 0.8)
		CrimeUnderAddict.rehab(t2)
		SimEnv.clock().total_minutes += 4 * 1440
		CrimeUnderAddict.day_of(t2)
		if str(CrimeUnderAddict.rec(t2).get("state", "")) == "clean":
			ok += 1
			K.expect(f, float(CrimeUnderAddict.rec(t2)["level"]) < 0.8, "after a good stay the level is lower")
			ok += 0
		CrimeUnderState.addicts.erase(t2)
	var rate: float = float(ok) / float(n)
	K.expect(f, rate > 0.2 and rate < 0.7, "rehab works about as often as the data says (%.2f)" % rate)
	K.teardown()

func _relapse(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	var relapsed: int = 0
	var relapsed_with: int = 0
	CrimeUnderState.dealers[int(ids[2])] = {"stock": {}, "corner": "", "customers": [b], "tips": 0.0, "sales": 0, "stung": 0, "stash_hidden": false, "last_sale_day": -1}
	for i in 250:
		for p in [a, b]:
			CrimeUnderState.addicts[p] = {"sub": "glow", "level": 0.2, "frail": 0.0, "since": 0, "last_dose": 0, "state": "clean", "rehab_until": -1, "clean_days": 0, "relapses": 0, "dealer": -1}
			CrimeUnderAddict._clean_day(p, CrimeUnderState.addicts[p])
			if str(CrimeUnderState.addicts[p]["state"]) == "using":
				if p == a:
					relapsed += 1
				else:
					relapsed_with += 1
	K.expect(f, relapsed_with > relapsed and relapsed_with >= 3, "a dealer who still has the number makes relapse likelier (%d vs %d)" % [relapsed_with, relapsed])
	# clean for long enough = recovered
	CrimeUnderState.addicts[a] = {"sub": "glow", "level": 0.1, "frail": 0.0, "since": 0, "last_dose": 0, "state": "clean", "rehab_until": -1, "clean_days": 29, "relapses": 0, "dealer": -1}
	CrimeUnderState.sect("addict")["rehab"]["relapse_daily"] = 0.0
	CrimeUnderAddict._clean_day(a, CrimeUnderState.addicts[a])
	K.expect(f, not CrimeUnderState.addicts.has(a), "a month clean counts as recovered")
	K.teardown()

func _death(f: Array) -> void:
	var w := C.town(14)
	var t: int = int(C.adults()[0])
	Story.townies[t]["coins"] = 99999
	_hook(t, 1.0)
	CrimeUnderAddict.rec(t)["frail"] = 1.0
	var o: Dictionary = CrimeUnderAddict.cfg()["overdose"]
	o["base"] = 1.0
	o["death"] = 1.0
	CrimeUnderAddict._overdose(t, true, CrimeUnderAddict.rec(t), CrimeUnderAddict.cfg())
	K.expect(f, not CrimeUnderState.addicts.has(t) and not CrimePerson.alive(t), "a fatal overdose ends a life")
	K.teardown()
