extends RefCounted
## Task 20 + 19.2: the charge table, guideline sentencing, escalation, extra charges, records, the Town Law book, and the wording of
## arrests / verdicts / sentences (victims and suspects are named, never "someone").

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

const REQUIRED := ["domestic_violence", "aggravated_assault", "child_abuse", "child_endangerment", "child_neglect", "elder_abuse", "attempted_murder", "threats", "harassment",
	"kidnapping", "custodial_interference", "dui", "reckless_driving", "vehicular_manslaughter", "hit_and_run", "car_theft", "order_violation", "probation_violation",
	"resisting_arrest", "escape", "perjury", "false_report", "contempt", "bribery", "receiving_stolen", "forgery", "identity_theft", "insurance_fraud", "extortion",
	"animal_cruelty", "public_intoxication", "murder", "manslaughter", "burglary", "robbery", "assault", "theft"]

func run() -> Array:
	var f: Array = []
	_table(f)
	_sentencing(f)
	_extra_charges(f)
	_words(f)
	_records(f)
	_book(f)
	return f

func _table(f: Array) -> void:
	var w := C.town(4)
	var ch: Dictionary = JusticeState.sect("charges")
	for id in REQUIRED:
		K.expect(f, ch.has(id), "the charge table has %s" % id)
	var fac_a: Dictionary = JusticeState.sect("sentencing")["aggravating"]
	var fac_m: Dictionary = JusticeState.sect("sentencing")["mitigating"]
	var bad: Array = []
	for id in ch:
		var d: Dictionary = ch[id]
		for key in ["label", "class", "grade", "description", "elements", "bail", "guideline", "aggravating", "mitigating", "record", "phrase", "jury", "severity"]:
			if not d.has(key):
				bad.append("%s lacks %s" % [id, key])
		if not (str(d.get("class", "")) in ["petty", "misdemeanour", "felony"]):
			bad.append("%s has a strange class" % id)
		if (d.get("elements", []) as Array).is_empty() or str(d.get("description", "")) == "":
			bad.append("%s has no description or elements" % id)
		if not (d.get("record", {}) as Dictionary).has("expunge_days") or not (d.get("record", {}) as Dictionary).has("job_bans"):
			bad.append("%s has no record effect" % id)
		for a in d.get("aggravating", []):
			if not fac_a.has(a):
				bad.append("%s: unknown aggravating factor %s" % [id, a])
		for m in d.get("mitigating", []):
			if not fac_m.has(m):
				bad.append("%s: unknown mitigating factor %s" % [id, m])
		if bool(d.get("petty", false)) and bool(d.get("jury", true)):
			bad.append("%s is petty but needs a jury" % id)
		if (d.get("guideline", {}) as Dictionary).is_empty():
			bad.append("%s has no sentence guideline" % id)
	K.expect(f, bad.is_empty(), "every charge has the required fields: %s" % str(bad.slice(0, 4)))
	K.teardown()

func _case(kind: String, charge: String, accused: int, victim: int, extra: Dictionary = {}) -> Dictionary:
	var c: Dictionary = CaseStore.create(kind, accused, victim, "town:2", {})
	c["accused"] = accused
	c["charge"] = charge
	c["lawyer_skill"] = 0.3
	c["severity"] = 2
	c["domestic"] = true
	for k in extra:
		c[k] = extra[k]
	return c

func _sentencing(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var v: int = int(ids[1])
	K.set_time(10, 12)
	var c: Dictionary = _case("assault", "domestic_violence", a, v)
	var s1: Dictionary = JusticeGuideline.one(c, a, "domestic_violence", false, false)
	var s2: Dictionary = JusticeGuideline.one(c, a, "domestic_violence", false, false)
	K.expect(f, s1 == s2, "a fixed case gives the same sentence without the judge's spread")
	JusticeState.records[a] = [{"day": 1, "charge": "domestic_violence", "case": 1, "result": "guilty", "victim": v}]
	var days: Array = []
	var scores: Array = []
	for i in 40:
		var sp: Dictionary = JusticeGuideline.compute(c, a, false)
		days.append(int(sp["days"]))
		scores.append(float(sp["score"]))
	days.sort()
	scores.sort()
	K.expect(f, float(scores[scores.size() - 1]) - float(scores[0]) <= 2.0 * float(JusticeState.sect("sentencing")["spread"]) + 0.002, "the judge's spread is small (score %.3f to %.3f)" % [scores[0], scores[scores.size() - 1]])
	K.expect(f, int(days[days.size() - 1]) - int(days[0]) <= 5, "a few days either way (%d to %d days)" % [days[0], days[days.size() - 1]])
	# priors escalate: the third assault on the same person is never a small fine
	var last_score: float = -1.0
	var rising: bool = true
	var third: Dictionary = {}
	for n in 4:
		JusticeState.records[a] = []
		for i in n:
			JusticeRecords.add(a, "domestic_violence", 100 + i, "guilty", v, "a fine")
		var s: Dictionary = JusticeGuideline.compute(c, a, false, false)
		if float(s["score"]) <= last_score and float(s["score"]) < 1.0:
			rising = false
		last_score = float(s["score"])
		if n == 3:
			third = s
	K.expect(f, rising, "each earlier conviction makes the sentence heavier")
	K.expect(f, str(third["type"]) in ["jail", "prison"] and int(third["days"]) >= 5, "the fourth assault on the same person means real time away (%s)" % CaseText.sentence(third))
	K.expect(f, bool(third["order"]) and not (third["courses"] as Array).is_empty(), "with a protective order and an anger management course")
	# a plea, a first offence and a good lawyer make it lighter
	JusticeState.records[a] = []
	var plain: Dictionary = JusticeGuideline.compute(c, a, false, false)
	var plea: Dictionary = JusticeGuideline.compute(c, a, true, false)
	K.expect(f, float(plea["score"]) < float(plain["score"]), "a guilty plea lowers the score")
	# consecutive charges add on, concurrent ones do not
	var mix: Dictionary = _case("burglary", "burglary", a, -1)
	mix["domestic"] = false
	mix["charges"] = ["burglary", "order_violation"]
	JusticeState.records[a] = [{"day": 1, "charge": "burglary", "case": 1, "result": "guilty", "victim": -1}, {"day": 2, "charge": "burglary", "case": 2, "result": "guilty", "victim": -1}]
	var both: Dictionary = JusticeGuideline.compute(mix, a, false, false)
	var parts: Array = both["parts"]
	var only: Dictionary = JusticeGuideline.one(mix, a, "burglary", false, false)
	K.expect(f, int(both["days"]) >= int(only["days"]), "a consecutive charge adds to the term (%d vs %d days)" % [int(both["days"]), int(only["days"])])
	var two: Dictionary = _case("burglary", "burglary", a, -1)
	two["charges"] = ["burglary", "theft"]
	K.expect(f, int(JusticeGuideline.compute(two, a, false, false)["days"]) == maxi(int(JusticeGuideline.one(two, a, "burglary", false, false)["days"]), int(JusticeGuideline.one(two, a, "theft", false, false)["days"])), "concurrent charges run together (the longest counts)")
	K.expect(f, parts.size() == 2, "both charges are in the sentence")
	K.teardown()

func _extra_charges(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var v: int = int(ids[1])
	C.set_family(a, v)
	K.set_time(10, 12)
	var c: Dictionary = CrimeAssault.fight(a, v, 2, "hit")
	JusticeState.sect("domestic")["domestic_report"] = 1.0
	if c.is_empty():
		c = CrimeAssault.report(a, v, 2, "x", true, "hit")
	c["accused"] = a
	K.expect(f, JusticeProcess.charge_for(c) == "domestic_violence", "a hit on a relative is domestic violence")
	K.expect(f, JusticeProcess.charges_for(c) == ["domestic_violence"], "one charge at first")
	JusticeOrders.issue(c, 20)
	K.expect(f, JusticeProcess.charges_for(c).has("order_violation"), "a new offence against the protected person adds a breach of the order")
	JusticeState.probation[a] = SysUtil.day() + 10
	K.expect(f, JusticeProcess.charges_for(c).has("probation_violation"), "and a probation violation when on probation")
	var c2: Dictionary = _case("assault", "assault", a, v)
	c2["domestic"] = false
	c2["severity"] = 2
	K.expect(f, JusticeProcess.charge_for(c2) == "aggravated_assault", "a serious injury outside the home is aggravated assault")
	K.teardown()

func _words(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var tess: int = int(ids[0])
	var ivo: int = int(ids[1])
	K.set_time(10, 12)
	var m: Dictionary = CaseStore.create("murder", tess, ivo, "town:2", {})
	m["accused"] = tess
	m["charge"] = "murder"
	m["state"] = "arrested"
	Story.townies[ivo]["alive"] = false
	var arrested: String = CaseText.arrested(m, tess)
	K.expect(f, arrested.find(CrimePerson.name_of(ivo)) >= 0 and arrested.to_lower().find("someone") < 0, "the arrest names the dead person: " + arrested)
	m["verdict"] = "not_guilty"
	var acq: String = CaseText.acquitted(m, tess)
	K.expect(f, acq.find("not guilty") >= 0 and acq.find("the death of " + CrimePerson.name_of(ivo)) >= 0 and acq.find("the case stays open") >= 0, "the acquittal says whose death and that the case stays open: " + acq)
	var charged: String = CaseText.charged(m, tess)
	K.expect(f, charged.find(CrimePerson.name_of(ivo)) >= 0 and charged.find("murder") >= 0, "the charge line names the charge and the victim: " + charged)
	# a household folk who died is still called by name
	var dead := K.make_folk(w, "Ivo Orr", [], 1, Vector2i(14, 12))
	var did: int = int(dead.id)
	Family.note_person(did, "Ivo Orr")
	FamilyHousehold.on_death(did, [])
	CrimePerson.hide_death(did, "murder")
	K.expect(f, CrimePerson.name_of(did) == "Ivo Orr", "a resident who died is still named (%s)" % CrimePerson.name_of(did))
	# the conviction line: charge, victim and the whole sentence
	var d: Dictionary = _case("assault", "domestic_violence", tess, ivo)
	d["charges"] = ["domestic_violence"]
	var s: Dictionary = {"type": "jail", "days": 6, "fine": 0, "courses": [{"kind": "anger_management", "days": 3}], "order": true}
	var line: String = CaseText.convicted(d, tess, s, false)
	K.expect(f, line.find("was found guilty of domestic violence against " + CrimePerson.name_of(ivo)) >= 0 and line.find("6 days in jail") >= 0 and line.find("anger management course") >= 0 and line.find("protective order") >= 0, "the verdict line names charge, victim and sentence: " + line)
	# through the real flow: impose writes it to the chronicle notes
	d["verdict"] = "guilty"
	d["accused"] = tess
	JusticeSentence.impose(d)
	var found: bool = false
	for n in d["notes"]:
		if str(n["text"]).find("domestic violence against") >= 0 and str(n["text"]).find(":") >= 0:
			found = true
	K.expect(f, found, "the case note after sentencing names charge, victim and sentence")
	K.teardown()

func _records(f: Array) -> void:
	var w := C.town(6)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	K.set_time(10, 12)
	JusticeRecords.add(a, "shoplifting", 1, "petty")
	JusticeRecords.add(a, "burglary", 2, "guilty", -1, "5 days in jail")
	K.expect(f, CrimePerson.record_count(a) == 2, "two entries on the record")
	K.set_time(10 + 80, 12)
	JusticeRecords.on_day()
	K.expect(f, CrimePerson.record_count(a) == 1, "a petty offence is cleared from the record after a clean stretch; the burglary stays")
	K.expect(f, JusticeRecords.bans(a, "police_officer") and not JusticeRecords.bans(a, "cook"), "a burglary conviction closes police work but not other jobs")
	K.teardown()

func _book(f: Array) -> void:
	var w := C.town(4)
	var n: int = (JusticeState.sect("charges") as Dictionary).size()
	var es: Array = TownLaw.entries()
	K.expect(f, es.size() == n, "the Town Law book lists every charge (%d of %d)" % [es.size(), n])
	var ok: bool = true
	var last_rank: int = -1
	for e in es:
		var rank: int = TownLaw.CLASSES.find(str(e["class"]))
		if rank < last_rank:
			ok = false
		last_rank = rank
		if str(e["description"]) == "" or str(e["sentence"]) == "" or str(e["mitigating"]) == "" and str(e["aggravating"]) == "":
			ok = false
	K.expect(f, ok, "grouped by class, each with a description, sentence range and factors")
	var d := TownLawDialog.new()
	Engine.get_main_loop().root.add_child(d)
	d.show_for(-1)
	var labels: int = 0
	for c in d.body.get_children():
		if c is Label:
			labels += 1
	K.expect(f, labels >= n * 3, "the dialog shows the whole book (%d lines)" % labels)
	var board := CaseBoard.new()
	Engine.get_main_loop().root.add_child(board)
	board.show_for(1)
	var has_button: bool = false
	for c2 in board.body.get_children():
		if c2 is Button and (c2 as Button).text.begins_with("Town Law"):
			has_button = true
	K.expect(f, has_button, "the case board has a Town Law button")
	d.queue_free()
	board.queue_free()
	K.teardown()
