extends RefCounted
## Task 09: arrest -> charges -> bail -> lawyer -> trial -> verdict -> sentence -> prison / parole / visits / release -> appeal.
## Forced cases with fixed evidence give the expected verdict probabilities (strong evidence ~85% guilty, weak evidence on an innocent < 5%).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_rates(f)
	_process(f)
	_plea_and_sentences(f)
	_prison(f)
	_player_jail(f)
	_testimony(f)
	_appeal(f)
	_civil(f)
	_careers(f)
	_save(f)
	return f

func _case(kind: String, culprit: int, accused: int, clarity: float, trace: float) -> Dictionary:
	var c: Dictionary = CaseStore.create(kind, culprit, -1, "town:2", {"witnessed": clarity > 0.0, "witness_clarity": clarity, "witnesses": [], "trace": trace})
	c["state"] = "open"
	c["disc_day"] = SysUtil.day() - 3
	c["progress"] = 1.0
	c["accused"] = accused
	c["wrongful"] = accused != culprit
	c["charge"] = "burglary" if kind == "burglary" else kind
	c["lawyer_skill"] = 0.3
	return c

func _avg_p(c: Dictionary, pid: int, n: int) -> float:
	var t: float = 0.0
	for i in n:
		t += float(JusticeTrial.breakdown(c, pid)["p_guilty"])
	return t / n

func _rates(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var culprit: int = int(ids[0])
	var other: int = int(ids[1])
	K.set_time(5, 9, 0)
	var strong: Dictionary = _case("burglary", culprit, culprit, 0.75, 0.35)
	var weak: Dictionary = _case("burglary", culprit, culprit, 0.0, 0.1)
	var innocent: Dictionary = _case("burglary", culprit, other, 0.0, 0.3)
	# an innocent with every bit of soft evidence stacked against them
	RelationshipService.set_value(other, other, "friendship", 0.0)
	JusticeState.records[other] = [{"day": 1, "charge": "theft", "case": 0, "result": "guilty"}]
	RelationshipKnowledge.add_reputation(other, -40.0)
	var ps: float = _avg_p(strong, culprit, 200)
	var pw: float = _avg_p(weak, culprit, 200)
	var pi: float = _avg_p(innocent, other, 200)
	K.expect(f, ps >= 0.8 and ps <= 0.95, "guilty with strong evidence is convicted about 85%% of the time (%.2f)" % ps)
	K.expect(f, pw < ps - 0.2, "weak evidence convicts far less often (%.2f)" % pw)
	K.expect(f, pi < 0.05, "an innocent person is convicted under 5%% (%.3f)" % pi)
	# a better lawyer, a good reputation and friends lower the odds
	var rich: Dictionary = strong.duplicate(true)
	rich["lawyer_skill"] = 0.85
	K.expect(f, _avg_p(rich, culprit, 200) < ps - 0.1, "a star lawyer helps")
	K.teardown()

func _process(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var culprit: int = int(ids[0])
	Story.townies[culprit]["coins"] = 5000
	K.set_time(5, 9, 0)
	var c: Dictionary = _case("burglary", culprit, -1, 0.9, 0.3)
	JusticeProcess.arrest(c, culprit)
	K.expect(f, int(c["accused"]) == culprit and str(c["state"]) == "charged" and str(c["charge"]) == "burglary", "arrest -> charged")
	K.expect(f, int(c["trial_day"]) >= SysUtil.day() + 3 and int(c["trial_day"]) <= SysUtil.day() + 5, "a trial date a few days later (day %d)" % int(c["trial_day"]))
	K.expect(f, not JusticeState.inmates.has(culprit) and int(c.get("bail_paid", 0)) > 0, "a rich townie pays bail and goes home")
	K.expect(f, float(c["lawyer_skill"]) > 0.3, "and hires a private lawyer (%s)" % str(c["lawyer_name"]))
	var poor: int = int(ids[1])
	Story.townies[poor]["coins"] = 5
	var c2: Dictionary = _case("burglary", poor, -1, 0.9, 0.3)
	JusticeProcess.arrest(c2, poor)
	K.expect(f, str(JusticeState.inmates.get(poor, {}).get("kind", "")) == "remand" and float(c2["lawyer_skill"]) == 0.3, "a poor suspect stays in jail until the trial with a public defender")
	# wrongful arrest is recorded
	var innocent: int = int(ids[2])
	var c3: Dictionary = _case("burglary", culprit, -1, 0.0, 0.3)
	JusticeProcess.arrest(c3, innocent)
	K.expect(f, bool(c3["wrongful"]) and JusticeState.counter("wrongful_arrests") == 1, "a wrongful arrest is possible and counted")
	# trial runs through the queue at its day
	K.set_time(int(c2["trial_day"]), 9, 0)
	C.minutes(1)
	K.expect(f, str(c2["state"]) == "trial", "the trial opens on its day")
	C.minutes(200)
	K.expect(f, str(c2["verdict"]) != "" and str(c2["state"]) in ["closed", "charged", "cold", "open"], "and the verdict follows (%s)" % str(c2["verdict"]))
	K.teardown()

func _plea_and_sentences(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	K.set_time(5, 9, 0)
	var murder: Dictionary = _case("murder", a, a, 0.9, 0.5)
	murder["charge"] = "murder"
	var full: int = 0
	var life: int = 0
	var spree: Dictionary = murder.duplicate(true)
	spree["counts"] = 2                          # more than one victim
	for i in 40:
		var s: Dictionary = JusticeSentence.pick(murder, false)
		if str(s["type"]) == "prison" and not bool(s.get("life", false)):
			full += 1
		if bool(JusticeSentence.pick(spree, false).get("life", false)):
			life += 1
	K.expect(f, full == 40 and life == 40, "murder means prison, and life for more than one victim (%d of 40 life)" % life)
	var theft: Dictionary = _case("theft", a, a, 0.9, 0.5)
	theft["charge"] = "theft"
	var types: Dictionary = {}
	for i in 60:
		types[str(JusticeSentence.pick(theft, false)["type"])] = true
	K.expect(f, types.has("fine") or types.has("service") or types.has("probation"), "a first theft gets fines / community service / probation: %s" % str(types.keys()))
	K.expect(f, not types.has("prison") and not types.has("jail"), "and no custody")
	var plea_days: float = 0.0
	var trial_days: float = 0.0
	for i in 80:
		plea_days += float(JusticeSentence.pick(murder, true)["days"] if not bool(JusticeSentence.pick(murder, true).get("life", false)) else 160)
		trial_days += float(JusticeSentence.pick(murder, false)["days"] if not bool(JusticeSentence.pick(murder, false).get("life", false)) else 160)
	K.expect(f, plea_days < trial_days, "a plea deal lightens the sentence")
	K.expect(f, JusticeSentence.describe_range("murder").find("life") >= 0, "the warning text says murder can mean life: %s" % JusticeSentence.describe_range("murder"))
	# probation makes a repeat offence harsher
	JusticeState.probation[a] = SysUtil.day() + 10
	var harsh: float = 0.0
	for i in 60:
		var s2: Dictionary = JusticeSentence.pick(_case("robbery", a, a, 0.9, 0.5), false)
		harsh += float(s2["days"])
	JusticeState.probation.erase(a)
	var base: float = 0.0
	for i in 60:
		base += float(JusticeSentence.pick(_case("robbery", a, a, 0.9, 0.5), false)["days"])
	K.expect(f, harsh > base, "probation makes a new crime punished harder")
	K.teardown()

func _prison(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var rel: int = int(ids[1])
	C.set_family(a, rel)
	K.set_time(5, 9, 0)
	var c: Dictionary = _case("robbery", a, a, 0.9, 0.5)
	Story.townies[a]["career"] = "cook"
	JusticeSentence._apply(c, a, {"type": "prison", "days": 20, "fine": 0})
	K.expect(f, Prison.is_inside(a) and bool(Story.townies[a].get("in_prison", false)), "a townie is taken to prison")
	K.expect(f, str(Story.townies[a]["career"]) == "", "and loses their job")
	var fr0: float = RelationshipService.value(rel, a, "friendship")
	K.expect(f, Prison.visit(rel, a) and RelationshipService.value(rel, a, "friendship") > fr0, "family can visit, which strengthens the bond")
	var released_early: bool = false
	for d in 30:
		SimEnv.clock().total_minutes += 1440
		JusticeState.sect("prison")["fight_chance"] = 0.0
		Prison.on_day()
		if not JusticeState.inmates.has(a):
			released_early = SysUtil.day() < 5 + 20
			break
	K.expect(f, not JusticeState.inmates.has(a) and not bool(Story.townies[a].get("in_prison", false)), "released after serving the sentence")
	K.expect(f, JusticeState.fresh_start.has(a), "a fresh start begins")
	JusticeState.records[a] = [{"day": SysUtil.day(), "charge": "robbery", "case": 1, "result": "guilty"}]
	K.expect(f, not Prison.job_ok(a, "police_officer") and Prison.job_ok(a, "cook"), "a record closes some jobs (police) but not others")
	var pf = w.get_folk(1)
	K.expect(f, not Careers.qualify(pf, "judge", 1)["ok"], "qualify mentions requirements")
	JusticeState.records[1] = [{"day": SysUtil.day(), "charge": "robbery", "case": 1, "result": "guilty"}]
	var miss: Array = Careers.qualify(pf, "police_officer", 1)["missing"]
	K.expect(f, miss.has("a clean record"), "Careers.qualify says a clean record is needed: %s" % str(miss))
	JusticeState.records.erase(1)
	# parole for good behaviour, extra time for fights
	var b: int = int(ids[2])
	JusticeSentence._apply(_case("robbery", b, b, 0.9, 0.5), b, {"type": "prison", "days": 60, "fine": 0})
	JusticeState.sect("prison")["fight_chance"] = 0.0
	JusticeState.sect("prison")["parole_chance"] = 1.0
	for d in 40:
		SimEnv.clock().total_minutes += 1440
		Prison.on_day()
		if not JusticeState.inmates.has(b):
			break
	K.expect(f, not JusticeState.inmates.has(b) and SysUtil.day() < 5 + 60, "good behaviour earns early parole")
	var h: int = int(ids[3])
	JusticeSentence._apply(_case("robbery", h, h, 0.9, 0.5), h, {"type": "jail", "days": 5, "fine": 0})
	var until0: int = int(JusticeState.inmates[h]["until"])
	JusticeState.sect("prison")["fight_chance"] = 1.0
	Prison.on_day()
	K.expect(f, int(JusticeState.inmates[h]["until"]) > until0, "a fight inside adds time")
	K.teardown()

func _player_jail(f: Array) -> void:
	var w := C.town(12)
	var ada = w.get_folk(1)
	var dir = K.director()
	K.set_time(5, 9, 0)
	var ids: Array = C.adults()
	var c: Dictionary = _case("assault", 1, 1, 0.9, 0.5)
	c["victim"] = int(ids[0])
	WorldIface.coins[1] = 20
	JusticePlayer.log.clear()
	JusticeProcess.arrest(c, 1)
	C.minutes(3)
	K.run(dir, 6)
	K.expect(f, SysUtil.is_away(ada) and JusticeState.inmates.has(1), "a player folk who cannot pay bail is held away (jail) until the trial")
	K.expect(f, JusticePlayer.status_chips(ada).size() >= 1 and str(JusticePlayer.status_chips(ada)[0]["text"]).find("Held") >= 0, "a clear status chip is shown: %s" % str(JusticePlayer.status_chips(ada)))
	var titles: String = ",".join(JusticePlayer.log.map(func(e): return str(e["title"])))
	K.expect(f, titles.find("Arrested") >= 0, "the player sees an arrest prompt (%s)" % titles)
	JusticeState.pending.clear()                 # (the queued trial is not part of this check)
	JusticePlayer.log.clear()
	JusticeSentence._apply(c, 1, {"type": "jail", "days": 4, "fine": 0})
	K.run(dir, 5)
	K.expect(f, SysUtil.is_away(ada) and str(Away.info(1).get("reason", "")) == "jail", "jail sends the folk away for days")
	K.expect(f, JusticePlayer.status_chips(ada)[0]["text"] == "In jail", "status says In jail")
	for d in 5:
		SimEnv.clock().total_minutes += 1440
		Prison.on_day()
	K.run(dir, 3)
	K.expect(f, not JusticeState.inmates.has(1) and not SysUtil.is_away(ada) and not ada.has_buff("in_custody"), "released after the sentence: the folk is home (inmate %s away %s buff %s)" % [JusticeState.inmates.has(1), SysUtil.is_away(ada), ada.has_buff("in_custody")])
	# a life sentence prompt warns the player
	JusticePlayer.log.clear()
	var m: Dictionary = _case("murder", 1, 1, 0.9, 0.5)
	m["verdict"] = "guilty"
	m["charge"] = "murder"
	m["victim"] = int(ids[1])
	JusticeSentence.impose(m)
	var warned: bool = false
	for e in JusticePlayer.log:
		if str(e["title"]) == "Sentence" and str(e["text"]).find("outlast") >= 0:
			warned = true
	K.expect(f, warned and JusticeState.inmates.has(1), "a long murder sentence warns that it may outlast the rest of their life")
	K.teardown()

func _testimony(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	K.set_time(5, 9, 0)
	RelationshipService.add_both(1, a, "friendship", 60.0)
	var c: Dictionary = _case("assault", a, a, 0.5, 0.3)
	var base: float = JusticeTrial.testimony(c, a)
	JusticeCourt_test_helper(c, 1, "against", false)
	var against: float = JusticeTrial.testimony(c, a)
	c["testimony"] = []
	JusticeCourt_test_helper(c, 1, "for", false)
	var pro: float = JusticeTrial.testimony(c, a)
	K.expect(f, against > base and pro < base, "player witnesses move the verdict (%.2f / %.2f / %.2f)" % [against, base, pro])
	# perjury risk
	c["testimony"] = []
	var caught: int = 0
	for i in 40:
		var e: Dictionary = {"pid": 1, "side": "for", "lie": true, "exposed": false}
		c["testimony"] = [e]
		c["accused"] = a
		JusticeTrial._perjury_check(c)
		if bool(e["exposed"]):
			caught += 1
	K.expect(f, caught > 3 and caught < 30, "lying on the stand risks perjury (%d of 40 exposed)" % caught)
	K.teardown()

func JusticeCourt_test_helper(c: Dictionary, w: int, side: String, lie: bool) -> void:
	Courthouse.testify(int(c["id"]), w, side + ("_lie" if lie else ""))

func _appeal(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	var innocent: int = int(ids[0])
	var real: int = int(ids[1])
	K.set_time(5, 9, 0)
	var c: Dictionary = _case("burglary", real, innocent, 0.0, 0.2)
	c["verdict"] = "guilty"
	c["charge"] = "burglary"
	JusticeSentence._apply(c, innocent, {"type": "prison", "days": 40, "fine": 0})
	c["state"] = "closed"
	c["sentence"] = {"type": "prison", "days": 40}
	JusticeState.sect("appeal")["new_evidence_innocent"] = 1.0
	JusticeAppeal.on_day()
	K.expect(f, not JusticeState.inmates.has(innocent) and JusticeState.counter("exonerations") == 1, "new evidence exonerates an innocent prisoner")
	K.expect(f, str(c["state"]) == "open" and int(c["accused"]) == -1, "and the case is open again for the real culprit")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "exonerated"), "the exoneration makes the news")
	K.teardown()

func _civil(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	K.set_time(5, 9, 0)
	JusticeState.sect("civil")["lawsuit"]["chance"] = 1.0
	SysUtil.game_event("accident_on_property", {"victim": int(ids[0]), "lot": "home:1", "owner": 1, "cause": "fall", "fatal": false})
	K.expect(f, JusticeState.civil.size() == 1 and str(JusticeState.civil[0]["kind"]) == "lawsuit", "an injury on someone's property leads to a lawsuit")
	for d in 8:
		SimEnv.clock().total_minutes += 1440
		JusticeCivil.on_day()
	K.expect(f, str(JusticeState.civil[0]["state"]) == "settled" and str(JusticeState.civil[0]["result"]) != "", "and it is settled in court (%s)" % str(JusticeState.civil[0]["result"]))
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	var before: int = CrimePerson.coins(a) + CrimePerson.coins(b)
	SysUtil.game_event("divorced", {"folk_id": a, "target_id": b})
	var div: Dictionary = JusticeState.civil[JusticeState.civil.size() - 1]
	K.expect(f, str(div["kind"]) == "divorce", "a divorce is settled by the court")
	for d in 8:
		SimEnv.clock().total_minutes += 1440
		JusticeCivil.on_day()
	K.expect(f, CrimePerson.coins(a) + CrimePerson.coins(b) == before, "the settlement only moves coins between them")
	var sc: Dictionary = JusticeCivil.small_claim(a, b, 80, "a damaged fence")
	K.expect(f, str(sc["kind"]) == "small_claims", "small claims exist")
	K.teardown()

func _careers(f: Array) -> void:
	var w := C.town(12)
	for cid in ["police_officer", "detective", "lawyer", "judge"]:
		K.expect(f, not Careers.career_def(cid).is_empty(), "career %s is installed" % cid)
	JusticeCareers.staff_town()
	var roles: Dictionary = {}
	for t in C.ids():
		roles[CrimePerson.career(int(t))] = true
	K.expect(f, roles.has("police_officer") and roles.has("detective") and roles.has("lawyer") and roles.has("judge"), "the town is staffed with police, a detective, a lawyer and a judge")
	var before: float = Police.strength()
	K.expect(f, before > 0.55, "officers raise the police strength (%.2f)" % before)
	var ids: Array = C.adults()
	var c: Dictionary = CaseStore.create("burglary", int(ids[0]), -1, "town:2", {"trace": 0.0})
	CaseDiscovery.report(c, int(ids[1]), "noticed")
	var det = w.get_folk(1)
	Careers.hire(det, "detective", 1)
	var c2: Dictionary = CaseStore.create("burglary", int(ids[0]), -1, "town:2", {"trace": 0.0})
	CaseDiscovery.report(c2, int(ids[1]), "noticed")
	SysUtil.game_event("work_case", {"folk_id": 1})
	K.expect(f, bool(c.get("assist", false)) or bool(c2.get("assist", false)), "a player detective's work marks a case for extra effort")
	JusticeState.seed_rng(7)
	CaseInvestigation.work(c)
	JusticeState.seed_rng(7)
	CaseInvestigation.work(c2)
	K.expect(f, absf(float(c["progress"]) - float(c2["progress"])) > 0.0, "and it speeds the investigation (%.2f vs %.2f)" % [float(c["progress"]), float(c2["progress"])])
	K.teardown()

func _save(f: Array) -> void:
	var w := C.town(12)
	var ids: Array = C.adults()
	K.set_time(5, 9, 0)
	var c: Dictionary = _case("burglary", int(ids[0]), int(ids[0]), 0.8, 0.3)
	JusticeProcess.arrest(c, int(ids[0]))
	JusticeState.records[int(ids[1])] = [{"day": 2, "charge": "theft", "case": 1, "result": "guilty"}]
	C.minutes(5)
	CrimeRevenge.start(int(ids[1]), int(ids[2]), int(c["id"]))
	RelationshipKnowledge.ensure_secrets(int(ids[3]))
	RelationshipKnowledge.learn_secret(int(ids[4]), int(ids[3]), 0)
	JusticePlayer.auto = "pay"
	CrimeBlackmail.demand(int(ids[4]), int(ids[3]), 0, 30)
	CrimePressure.help(int(ids[5]), "loan")
	JusticeState.rate_now = 33.0
	JusticeState.rate_hist.append({"day": 7, "rate": 33.0, "dir": 1, "streak": 1})
	var before: Dictionary = JusticeState.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(before))
	JusticeState.reset()
	JusticeState.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(before, JusticeState.to_dict(), "justice", diffs), "case record survives a JSON round trip: %s" % str(diffs.slice(0, 4)))
	K.expect(f, SaveLoad.save(95, "justice") and SaveLoad.load_slot(95), "whole-game save and load")
	SaveLoad.delete_slot(95)
	K.expect(f, JusticeState.cases.has(1) and int(JusticeState.cases[1]["accused"]) == int(ids[0]), "cases are back after loading")
	K.teardown()