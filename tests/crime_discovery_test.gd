extends RefCounted
## 09b: hidden killings are found by the missing-person score (family within about a day, a worker in a day or two, a jobless loner in about a
## week), bodies can be found, investigation reveals the culprit's trace over days and arrests (usually the right person), weak cases go cold
## and are reopened by a tip, witnessed crimes are reported at once.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_delays(f)
	_investigation(f)
	_cold(f)
	_witnessed(f)
	return f

## Hours until a hidden murder of `victim` is reported (missing or body), 600 = never.
func _hours_to_report(w: StubWorld, killer: int, victim: int) -> int:
	C.quiet_witnesses()
	K.set_time(2, 22, 0)
	var c: Dictionary = CrimeMurder.kill(killer, victim, CrimePerson.home_key(victim), "murder", {})
	for h in 600:
		SimEnv.clock().total_minutes += 60
		CaseDiscovery.on_hour()
		if str(c["state"]) != "hidden":
			return h + 1
	return 600

func _delays(f: Array) -> void:
	var fam_total: int = 0
	var worker_total: int = 0
	var loner_total: int = 0
	var n: int = 6
	for round in n:
		var w := C.town(10)
		JusticeState.seed_rng(100 + round)
		var ids: Array = C.adults()
		var killer: int = int(ids[0])
		var fam: int = int(ids[1])
		var wk: int = int(ids[2])
		var lo: int = int(ids[3])
		for t in ids:
			Story.townies[t]["career"] = ""
		C.set_family(fam, int(ids[4]))
		C.set_family(fam, int(ids[5]))
		Story.townies[wk]["career"] = "cook"
		Story.townies[lo]["traits"] = ["loner"]
		for o in RelationshipService.all_known(lo):
			RelationshipService.pairs.erase(SysUtil.pair_key(lo, int(o)))
		for o2 in RelationshipService.all_known(wk):
			RelationshipService.pairs.erase(SysUtil.pair_key(wk, int(o2)))
		fam_total += _hours_to_report(w, killer, fam)
		worker_total += _hours_to_report(w, killer, wk)
		loner_total += _hours_to_report(w, killer, lo)
		K.teardown()
	var fam_avg: float = float(fam_total) / n
	var worker_avg: float = float(worker_total) / n
	var loner_avg: float = float(loner_total) / n
	K.expect(f, fam_avg <= 30.0, "a family member is reported missing within about a day (avg %.0f h)" % fam_avg)
	K.expect(f, worker_avg <= 96.0 and worker_avg > fam_avg, "a worker within a few days (avg %.0f h)" % worker_avg)
	K.expect(f, loner_avg >= 72.0 and loner_avg <= 300.0, "a jobless loner after about a week (avg %.0f h = %.1f days)" % [loner_avg, loner_avg / 24.0])

func _investigation(f: Array) -> void:
	var right: int = 0
	var wrong: int = 0
	var none: int = 0
	var runs: int = 14
	for round in runs:
		var w := C.town(10)
		JusticeState.seed_rng(500 + round)
		C.quiet_witnesses()
		var ids: Array = C.adults()
		var killer: int = int(ids[0])
		var victim: int = int(ids[1])
		C.feud(killer, victim, 40.0)               # an old quarrel: a motive the police can find
		RelationshipService.add_history(killer, victim, "insult", -1.0, victim)
		K.set_time(2, 23, 0)
		C.set_family(victim, int(ids[2]))
		var c: Dictionary = CrimeMurder.kill(killer, victim, CrimePerson.home_key(victim), "murder", {})
		C.hours(30)                                 # reported, body found
		if str(c["state"]) == "hidden":
			CaseDiscovery.report(c, int(ids[2]), "missing")
		if not bool(c.get("found", true)):
			CaseDiscovery._found(c, "search")
		for d in 25:
			CaseInvestigation.work(c)
			SimEnv.clock().total_minutes += 1440
			if int(c["accused"]) >= 0:
				break
		if int(c["accused"]) == killer:
			right += 1
		elif int(c["accused"]) >= 0:
			wrong += 1
		else:
			none += 1
		K.teardown()
	K.expect(f, right >= runs * 0.6, "investigation usually arrests the real culprit (%d right, %d wrong, %d open of %d)" % [right, wrong, none, runs])
	K.expect(f, wrong <= 1, "a wrongful arrest is rare (%d of %d)" % [wrong, runs])

func _cold(f: Array) -> void:
	var w := C.town(10)
	C.quiet_witnesses()
	var ids: Array = C.adults()
	K.set_time(2, 12, 0)
	var c: Dictionary = CaseStore.create("burglary", int(ids[0]), -1, CrimePerson.home_key(int(ids[1])), {"trace": 0.0, "vhid": 0})
	CaseDiscovery.report(c, int(ids[1]), "noticed")
	for d in 40:
		SimEnv.clock().total_minutes += 1440
		CaseInvestigation.work(c)
		c["tips"] = 0.0
		if str(c["state"]) == "cold":
			break
	K.expect(f, str(c["state"]) == "cold", "a case without evidence goes cold")
	var n: int = 0
	for d2 in 80:
		SimEnv.clock().total_minutes += 1440
		CaseInvestigation.work(c)
		if int(c["reopened"]) > 0:
			n += 1
			break
	K.expect(f, int(c["reopened"]) > 0 and str(c["state"]) in ["open", "arrested", "charged", "trial", "closed"], "the police keep checking: a new tip reopens it (state %s)" % str(c["state"]))
	K.teardown()

func _witnessed(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var c: Dictionary = CaseStore.create("robbery", int(ids[0]), int(ids[1]), "street", {"witnessed": true, "witness_clarity": 0.9, "witnesses": [int(ids[1])]})
	CaseDiscovery.report(c, int(ids[1]), "victim")
	K.expect(f, str(c["state"]) == "open", "a witnessed crime is reported at once")
	var n: int = 0
	for d in 6:
		SimEnv.clock().total_minutes += 1440
		if CaseInvestigation.work(c) >= 0:
			n += 1
			break
	K.expect(f, int(c["accused"]) == int(ids[0]), "a clear eyewitness gets the culprit arrested within days")
	K.teardown()
