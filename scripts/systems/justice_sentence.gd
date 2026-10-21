class_name JusticeSentence
extends RefCounted
## Sentences (task 20): the sentence comes from the charge GUIDELINES in data/justice.json through JusticeGuideline (aggravating and mitigating
## factors, a small judge spread), not from dice. Parts: fine, restitution, community service, probation, jail, prison, mandatory courses,
## a protective order, loss of custody. Several charges: concurrent unless a charge is consecutive. Every conviction goes on the record
## (JusticeRecords) and into one notice that names the charge, the victim and the sentence (CaseText).
## A murder sentence can outlast the rest of a playthrough (a folk lives ~200 days): the player is warned in the plea and sentence prompts.

static func cfg() -> Dictionary:
	return JusticeState.sect("sentences")

## "up to 160 days in prison, or life" - used by the plea prompt so the player knows what is at stake.
static func describe_range(charge: String) -> String:
	var g: Dictionary = JusticeProcess.charge_def(charge).get("guideline", {})
	if g.has("life_at"):
		return "up to life in prison"
	if g.has("prison"):
		return "up to %d days in prison" % int(g["prison"][1])
	if g.has("jail"):
		return "up to %d days in jail" % int(g["jail"][1])
	return "a fine or community service"

static func prior_same(pid: int, charge: String) -> int:
	return JusticeGuideline.prior_same(pid, charge)

## The sentence the case would get now (spread included).
static func pick(c: Dictionary, plea: bool) -> Dictionary:
	return JusticeGuideline.compute(c, int(c["accused"]), plea)

static func impose(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	var plea: bool = str(c["verdict"]) == "plea"
	var s: Dictionary = pick(c, plea)
	s.erase("parts")                           # keep the case record small; the factors are in the notes
	c["sentence"] = s
	c["state"] = "closed"
	c["closed_day"] = SysUtil.day()
	CaseStore.mark_solved(c)
	JusticeState.count("convictions")
	JusticeState.count("conviction_" + str(c["kind"]))
	var text: String = CaseText.convicted(c, pid, s, plea)
	for ch in JusticeGuideline.charges_of(c):
		JusticeRecords.add(pid, str(ch), int(c["id"]), "plea" if plea else "guilty", int(c.get("victim", -1)), CaseText.sentence(s))
	RelationshipKnowledge.add_reputation(pid, -8.0 * float(int(JusticeProcess.charge_def(str(c["charge"])).get("severity", 2))) / 2.0)
	for oid in (c.get("joined", []) as Array):
		var o: Dictionary = CaseStore.get_case(int(oid))
		if not o.is_empty():
			o["state"] = "closed"
			o["accused"] = pid
			o["verdict"] = c["verdict"]
			CaseStore.mark_solved(o)
	if bool(s.get("order", false)) or bool(c.get("domestic", false)):
		JusticeOrders.issue(c, JusticeOrders.days_for(pid))
		s["order"] = true
	if str(c["kind"]) in ["murder", "serial"]:
		Police.stir_town(c)
		JusticeState.uneasy_until = SysUtil.day()          # the town breathes again
		for r in SysUtil.residents():
			r.remove_buff("uneasy_at_night")
	_apply(c, pid, s)
	if bool(s.get("custody_loss", false)):
		CrimeChildAbuse.on_custody_loss(c, pid)
	CrimeRevenge.end_for_case(int(c["id"]))
	if str(s["type"]) in ["fine", "service", "probation"] or (str(s["type"]) == "jail" and int(s["days"]) <= 3):
		CrimeRevenge.on_escaped(c)             # a very light sentence: the family may not accept it
	CaseStore.note(c, text, "sentence", 4)
	var why: String = JusticeGuideline.explain(c, pid, plea)
	if why != "":
		CaseStore.note(c, "The court weighed " + why + ".", "", 1)
	if CaseStore.household_involved(c) or CrimePerson.is_player(pid):
		SysUtil.notify(text, "story" if not CrimePerson.is_player(pid) else "bad")
	if CrimePerson.is_player(pid):
		var warn: String = ""
		if bool(s.get("life", false)) or (str(s["type"]) == "prison" and int(s["days"]) >= int(cfg().get("long_warning_days", 80))):
			warn = " This sentence may outlast the rest of their life."
		JusticePlayer.tell(pid, "Sentence", text + warn)
	SysUtil.game_event("sentenced", {"folk_id": pid, "case": int(c["id"]), "type": str(s["type"]), "days": int(s["days"])})

static func describe(s: Dictionary) -> String:
	return CaseText.sentence(s)

## Carry the sentence out. Also accepts the old short form {type, days, fine}.
static func _apply(c: Dictionary, pid: int, s: Dictionary) -> void:
	JusticeState.inmates.erase(pid)
	JusticePlayer.release(CrimePerson.folk(pid))
	var t: String = str(s.get("type", "fine"))
	var days: int = int(s.get("days", 0))
	var probation: int = int(s.get("probation_days", days if t == "probation" else 0))
	var service: int = int(s.get("service_days", days if t == "service" else 0))
	var custody: bool = t in ["jail", "prison"] and days > 0
	if custody:
		if days >= 4:
			_lose_job(pid)
		Prison.admit(pid, c, days, t)
		if probation > 0:
			JusticeState.probation[pid] = SysUtil.day() + days + probation
	else:
		if service > 0:
			JusticeState.service[pid] = {"days_left": service, "last_day": -1}
		if probation > 0 or service > 0:
			JusticeState.probation[pid] = SysUtil.day() + maxi(probation, service + 7)
	if int(s.get("fine", 0)) > 0:
		_fine(pid, int(s["fine"]))
	if int(s.get("restitution", 0)) > 0 and int(c.get("victim", -1)) >= 0:
		var paid: int = CrimePerson.pay(pid, int(s["restitution"]), "restitution")
		if paid > 0:
			CrimePerson.add_coins(int(c["victim"]), paid, "restitution")
		if paid < int(s["restitution"]):
			JusticeDebt.add_restitution(pid, int(c["victim"]), int(s["restitution"]) - paid)          # the rest is a civil claim by the victim, paid by instalments
	for co in (s.get("courses", []) as Array):
		var list: Array = JusticeState.courses.get(pid, [])
		list.append({"kind": str(co["kind"]), "days_left": int(co["days"]), "last_day": -1})
		JusticeState.courses[pid] = list

static func _fine(pid: int, amount: int) -> void:
	if amount <= 0:
		return
	var paid: int = CrimePerson.pay(pid, amount, "court fine")
	if paid < amount:
		JusticeDebt.add_fine(pid, amount - paid)          # what cannot be paid becomes court debt, taken from income by instalments
		if CrimePerson.is_player(pid):
			SysUtil.notify("A court fine of %d coins is unpaid. It is now court debt: a share of your money goes to it every day." % (amount - paid), "bill")

static func _lose_job(pid: int) -> void:
	var f = CrimePerson.folk(pid)
	if f != null and Careers.has_job(pid):
		Careers.quit_job(f, "jailed")
	elif Story.townies.has(pid) and str(Story.townies[pid].get("career", "")) != "":
		Story.townies[pid]["career"] = ""
		Story.townies[pid]["level"] = 1

# ------------------------------------------------------------------ community service, courses, probation (daily)
static func on_day() -> void:
	for pid in JusticeState.service.keys():
		var sv: Dictionary = JusticeState.service[pid]
		if int(sv["last_day"]) == SysUtil.day():
			continue
		sv["last_day"] = SysUtil.day()
		var f = CrimePerson.folk(int(pid))
		if f != null and CrimePerson.is_player(int(pid)) and not SysUtil.is_away(f):
			f.add_buff("community_service")
			JusticePlayer.hold(f, 240.0, "service", "Community service")
		sv["days_left"] = int(sv["days_left"]) - 1
		if int(sv["days_left"]) <= 0:
			JusticeState.service.erase(pid)
			if CrimePerson.is_player(int(pid)):
				SysUtil.notify("%s finished the community service." % CrimePerson.name_of(int(pid)), "good")
	_courses_day()
	JusticeDebt.on_day()
	for pid2 in JusticeState.probation.keys():
		if int(JusticeState.probation[pid2]) < SysUtil.day():
			JusticeState.probation.erase(pid2)
	JusticeRecords.on_day()

## Mandatory courses run while the person is free: one session a day.
static func _courses_day() -> void:
	for pid in JusticeState.courses.keys():
		if JusticeState.inmates.has(pid):
			continue
		var list: Array = JusticeState.courses[pid]
		for co in list.duplicate():
			if int(co["last_day"]) == SysUtil.day():
				continue
			co["last_day"] = SysUtil.day()
			co["days_left"] = int(co["days_left"]) - 1
			if int(co["days_left"]) <= 0:
				list.erase(co)
				course_done(int(pid), str(co["kind"]))
		if list.is_empty():
			JusticeState.courses.erase(pid)

static func course_done(pid: int, kind: String) -> void:
	match kind:
		"anger_management":
			CrimeAssault.on_course_done(pid)
		"parenting":
			CrimeChildAbuse.on_parenting_done(pid)