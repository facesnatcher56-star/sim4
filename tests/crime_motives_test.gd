extends RefCounted
## Task 09c: pressure + conscience -> property crime, crime traits, blackmail (four answers), fraud (audit window, scams, insurance arson),
## small offences without a trial, revenge chains (start, escalate, end by forgiveness / apology / conviction), the town crime rate.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_traits(f)
	_pressure(f)
	_petty(f)
	_blackmail(f)
	_fraud(f)
	_revenge(f)
	_rate(f)
	return f

func _pressure_total() -> int:
	var n: int = 0
	for k in JusticeState.counters:
		if str(k).begins_with("pressure_"):
			n += int(JusticeState.counters[k])
	return n

func _traits(f: Array) -> void:
	var w := C.town(12)
	var td: Dictionary = SimEnv.data().traits()
	for t in ["dishonest", "kleptomaniac", "vengeful", "reckless"]:
		K.expect(f, td.has(t), "trait %s is installed in the traits table" % t)
	# townie generation: low frequency
	var big := 0
	for i in 60:
		var t2: Dictionary = Story.add_townie()
		big += 1 if (t2["traits"] as Array).has("dishonest") else 0
	CrimeTraits.roll_townies()
	var any: int = 0
	for tid in C.ids():
		for t3 in CrimeTraits.IDS:
			if (Story.townies[tid]["traits"] as Array).has(t3):
				any += 1
	K.expect(f, any >= 2 and any < 40, "townies get crime traits at low frequency (%d among %d townies)" % [any, Story.townies.size()])
	# inheritance: a dishonest parent passes it on sometimes
	var pa := {"traits": ["dishonest"], "appearance": Genetics.random_appearance()}
	var pb := {"traits": ["vengeful"], "appearance": Genetics.random_appearance()}
	var got: int = 0
	for i in 200:
		var kid: Array = Genetics.inherit_traits(pa, pb, null, {"extra": 0})
		if kid.has("dishonest") or kid.has("vengeful"):
			got += 1
	K.expect(f, got > 40, "crime traits are inheritable through genetics (%d of 200)" % got)
	K.teardown()

func _pressure(f: Array) -> void:
	var totals: Array = []
	for mode in ["high", "low"]:
		var w := C.town(12)
		JusticeState.seed_rng(31)
		for tid in C.adults():
			var t: Dictionary = Story.townies[tid]
			if mode == "high":
				t["coins"] = 10
				t["career"] = ""
				t["traits"] = ["dishonest"]
			else:
				t["coins"] = 3000
				t["career"] = "cook"
				t["traits"] = ["honest"]
		K.set_time(2, 12, 0)
		for d in 300:
			SimEnv.clock().total_minutes += 1440
			CrimePressure.on_day()
		totals.append(_pressure_total())
		if mode == "high":
			var r: float = CrimePressure.risk(int(C.adults()[0]))
			K.expect(f, r > 0.4, "a broke, jobless, dishonest person is high risk (%.2f)" % r)
		else:
			K.expect(f, CrimePressure.risk(int(C.adults()[0])) < 0.05, "a comfortable honest worker is low risk")
		K.teardown()
	K.expect(f, int(totals[0]) >= 10 and int(totals[0]) > int(totals[1]) * 4, "high-pressure townies commit far more property crime (%d vs %d)" % [totals[0], totals[1]])
	# help lowers the pressure
	var w2 := C.town(12)
	var p: int = int(C.adults()[0])
	Story.townies[p]["coins"] = 10
	Story.townies[p]["career"] = ""
	var before: float = CrimePressure.pressure(p)
	CrimePressure.help(p, "charity")
	K.expect(f, CrimePressure.pressure(p) < before, "charity lowers the pressure (%.2f -> %.2f)" % [before, CrimePressure.pressure(p)])
	K.teardown()

func _petty(f: Array) -> void:
	var w := C.town(12)
	w.add_object("door", Vector2i(10, 10))
	var off: int = int(C.adults()[0])
	JusticeState.sect("petty")["vandalism"]["caught"] = 5.0
	var coins0: int = WorldIface.get_coins(1)
	var c: Dictionary = CrimePetty.commit("vandalism", off, "home:1")
	K.expect(f, WorldIface.get_coins(1) < coins0 and K.has_note("Vandals"), "vandals cost the owner a cleanup (%d -> %d)" % [coins0, WorldIface.get_coins(1)])
	K.expect(f, not c.is_empty() and str(c["state"]) == "closed" and str(c["verdict"]) == "petty", "caught vandals are dealt with by a fine or service, no trial")
	K.expect(f, JusticeState.records.has(off) and Prison.job_ok(off, "judge") == true, "petty offences never close jobs")
	# an arrest for a petty charge also skips the trial
	var c2: Dictionary = CaseStore.create("shoplifting", off, -1, "street", {"witnessed": true, "witness_clarity": 0.9})
	c2["state"] = "open"
	JusticeProcess.arrest(c2, off)
	K.expect(f, str(c2["state"]) == "closed" and not JusticeState.inmates.has(off), "arrest for shoplifting = settled on the spot")
	K.teardown()

func _blackmail(f: Array) -> void:
	var results: Dictionary = {}
	for choice in ["pay", "refuse", "police", "confront"]:
		var w := C.town(12)
		JusticeState.seed_rng(77)
		var ids: Array = C.adults()
		var bm: int = int(ids[0])
		var friend: int = int(ids[1])
		RelationshipService.add_both(bm, friend, "friendship", 60.0)
		RelationshipKnowledge.ensure_secrets(1)
		RelationshipKnowledge.learn_secret(bm, 1, 0)
		WorldIface.coins[1] = 500
		JusticePlayer.auto = choice
		var rep0: float = RelationshipKnowledge.reputation(1)
		var b: Dictionary = CrimeBlackmail.demand(bm, 1, 0, 100)
		results[choice] = str(b["state"])
		match choice:
			"pay":
				K.expect(f, WorldIface.get_coins(1) == 400 and CrimePerson.coins(bm) > 0 and str(b["state"]) == "paying", "pay: coins change hands and it will come again")
				K.set_time(SysUtil.day() + 8, 12, 0)
				JusticePlayer.auto = "pay"
				CrimeBlackmail.on_day()
				K.expect(f, int(b["paid"]) == 2 and WorldIface.get_coins(1) == 300, "the demand returns on schedule (paid %d times)" % int(b["paid"]))
			"refuse":
				K.expect(f, str(b["state"]) == "exposed" and RelationshipKnowledge.reputation(1) < rep0, "refuse: the secret is exposed and reputation drops")
				K.expect(f, RelationshipKnowledge.knows_secret(friend, 1, 0) or RelationshipKnowledge.secrets_known_by(friend).size() > 0, "gossip carries it to the blackmailer's friends")
			"police":
				var cases: Array = JusticeState.cases.values().filter(func(c): return str(c["kind"]) == "blackmail")
				K.expect(f, str(b["state"]) in ["police", "exposed"] and cases.size() == 1 and int(cases[0]["culprit"]) == bm, "police: blackmail is a crime with a case (%s %d)" % [str(b["state"]), cases.size()])
			"confront":
				K.expect(f, str(b["state"]) in ["ended", "exposed"], "confront: they back off or expose the secret (%s)" % str(b["state"]))
		K.teardown()
	# townie victims choose by themselves
	var w2 := C.town(12)
	var ids2: Array = C.adults()
	RelationshipKnowledge.ensure_secrets(int(ids2[1]))
	RelationshipKnowledge.learn_secret(int(ids2[0]), int(ids2[1]), 0)
	var b2: Dictionary = CrimeBlackmail.demand(int(ids2[0]), int(ids2[1]), 0, 50)
	K.expect(f, str(b2["state"]) in ["paying", "exposed", "police", "ended"], "a townie victim answers on their own (%s)" % str(b2["state"]))
	K.expect(f, CrimeBlackmail.inclination(int(ids2[0])) > 0.0, "inclination exists")
	Story.townies[int(ids2[2])]["traits"] = ["dishonest"]
	Story.townies[int(ids2[3])]["traits"] = ["honest"]
	K.expect(f, CrimeBlackmail.inclination(int(ids2[2])) > CrimeBlackmail.inclination(int(ids2[3])) * 5.0, "dishonest folk are far likelier to blackmail than honest ones")
	K.teardown()

func _fraud(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var p: int = int(ids[0])
	Story.townies[p]["career"] = "coder"
	K.set_time(3, 9, 0)
	var c: Dictionary = CrimeFraud.embezzle(p)
	K.expect(f, str(c["state"]) == "hidden" and int(c["audit_day"]) >= SysUtil.day() + 7 and int(c["audit_day"]) <= SysUtil.day() + 21, "embezzlement stays hidden until an audit in 7-21 days")
	var found: int = -1
	for d in 25:
		SimEnv.clock().total_minutes += 1440
		CrimeFraud.audit()
		if str(c["state"]) != "hidden":
			found = d + 1
			break
	K.expect(f, found >= 7 and found <= 21, "the audit catches it in its window (day %d)" % found)
	K.expect(f, CrimePerson.career(p) == "", "and the embezzler is fired")
	var arrested: int = -1
	for d2 in 20:
		SimEnv.clock().total_minutes += 1440
		arrested = CaseInvestigation.work(c)
		if arrested >= 0:
			break
	K.expect(f, int(c["accused"]) == p and str(c["charge"]) == "embezzlement", "the paper trail leads to charges")
	# scam
	Story.townies[int(ids[1])]["traits"] = ["dishonest"]
	var s: Dictionary = CrimeFraud.scam(int(ids[1]))
	K.expect(f, not s.is_empty() and str(s["kind"]) == "fraud" and int(s["stolen_coins"]) > 0, "a con artist takes money from a victim")
	# insurance arson: detected or passed off as an accident
	var det: int = 0
	for i in 40:
		var a: Dictionary = CrimeFraud.insurance_arson(int(ids[2]), "town:3")
		if not a.is_empty():
			det += 1
	K.expect(f, det > 5 and det < 40, "investigators tell arson from an accident only sometimes (%d of 40 caught)" % det)
	K.teardown()

func _revenge(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var culprit: int = int(ids[0])
	var victim: int = int(ids[1])
	var kin: int = int(ids[2])
	C.set_family(victim, kin)
	Story.townies[kin]["traits"] = ["vengeful"]
	var c: Dictionary = CaseStore.create("assault", culprit, victim, "street", {})
	c["charge"] = "assault"
	var started: int = 0
	for i in 60:
		started += CrimeRevenge.on_escaped(c)
		if started > 0:
			break
	K.expect(f, started > 0 and CrimeRevenge.active().size() == 1, "when the culprit got off, a vengeful relative starts a revenge chain")
	JusticeState.sect("revenge")["forgive_base"] = 0.0
	var acts: int = 0
	K.set_time(5, 12, 0)
	for d in 40:
		SimEnv.clock().total_minutes += 1440
		CrimeRevenge.on_day()
	var r: Dictionary = JusticeState.revenge[0]
	K.expect(f, bool(r.get("vandalised", false)) and bool(r.get("fought", false)), "the chain escalates: vandalism, then a fight")
	K.expect(f, K.count_events("assault") >= 1, "the fight happened")
	# an apology ends it
	JusticeState.sect("revenge")["apology_chance"] = 1.0
	Story.townies[kin]["traits"] = ["forgiving"]
	CrimeRevenge.on_apology(culprit, kin)
	K.expect(f, str(r["state"]) == "ended" and str(r["how"]) == "apology", "an apology can end the chain")
	# forgiving relatives drop it fast
	var r2: Dictionary = CrimeRevenge.start(kin, culprit, int(c["id"]))
	JusticeState.sect("revenge")["forgive_forgiving"] = 1.0
	CrimeRevenge.on_day()
	K.expect(f, str(r2["state"]) == "ended" and str(r2["how"]) == "forgave", "a forgiving relative lets go")
	# a conviction ends it
	var r3: Dictionary = CrimeRevenge.start(kin, culprit, int(c["id"]))
	CrimeRevenge.end_for_case(int(c["id"]))
	K.expect(f, str(r3["how"]) == "convicted", "a later conviction ends it")
	K.teardown()

func _rate(f: Array) -> void:
	var w := C.town(12)
	K.set_time(10, 12, 0)
	for tid in C.adults():
		Story.townies[tid]["career"] = "cook"
		Story.townies[tid]["coins"] = 500
	var base: float = CrimeRate.compute()
	for tid2 in C.adults():
		Story.townies[tid2]["career"] = ""
	var jobless: float = CrimeRate.compute()
	K.expect(f, jobless > base + 5.0, "unemployment raises the crime rate (%.1f -> %.1f)" % [base, jobless])
	var ids: Array = C.adults()
	for i in 3:
		Story.townies[ids[i]]["career"] = "police_officer"
	var policed: float = CrimeRate.compute()
	K.expect(f, policed < jobless - 5.0, "police officers lower it (%.1f -> %.1f)" % [jobless, policed])
	for i in 6:
		CaseStore.create("burglary", int(ids[3]), -1, "town:2", {})
	var crimey: float = CrimeRate.compute()
	K.expect(f, crimey > policed + 3.0, "recent crimes raise it (%.1f -> %.1f)" % [policed, crimey])
	CrimeRate.start_watch(int(ids[4]))
	K.expect(f, CrimeRate.compute() < crimey - 5.0, "a neighbourhood watch lowers it")
	JusticeState.rate_now = 80.0
	K.expect(f, CrimeRate.value_mult() < 1.0 and CrimeRate.crime_mult() > 1.5, "a high rate lowers property values and raises crime odds")
	JusticeState.rate_now = 10.0
	K.expect(f, CrimeRate.value_mult() == 1.0 and CrimeRate.crime_mult() < 1.0, "a low rate is calm")
	# season report: falls for the third season
	JusticeState.rate_hist.clear()
	for r in [70.0, 60.0, 50.0, 40.0]:
		JusticeState.rate_now = r
		K.set_time(10 + int(100 - r), 12, 0)
		CrimeRate.season_report()
	var last: Dictionary = ChronicleHook.recent[ChronicleHook.recent.size() - 1]
	K.expect(f, str(last["text"]).find("third season") >= 0, "the Chronicle says: %s" % str(last["text"]))
	# the player's lot value follows the rate
	JusticeState.rate_now = 90.0
	w.add_object("tv", Vector2i(14, 12))
	Economy.refresh_objects()
	var lowv: int = Economy.lot_value(1)
	JusticeState.rate_now = 0.0
	K.expect(f, lowv < Economy.lot_value(1), "property value of the home lot drops with a high crime rate (%d < %d)" % [lowv, Economy.lot_value(1)])
	K.teardown()
