extends RefCounted
## Task 20.4: child abuse is its own very rare path. It needs risk factors, gives warnings first, is an event only, is found by teachers / doctors /
## relatives / the child, is handled by child services (visit, placement), by the courts (charge, harsh sentence, order, loss of custody) and by
## a parenting course before the child returns.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_risk(f)
	_incident_and_discovery(f)
	_services_and_justice(f)
	return f

## Ivo (carer), Tess (partner) and Tobin (child) in the player household.
func _home(w: StubWorld, traits: Array, coins: int) -> Array:
	var ivo := K.make_folk(w, "Ivo Orr", traits, 1, Vector2i(13, 12))
	var tess := K.make_folk(w, "Tess Orr", [], 1, Vector2i(14, 12))
	var kid := K.make_folk(w, "Tobin Orr", [], 1, Vector2i(15, 12), "child")
	Family.link_parent(kid.id, ivo.id)
	Family.link_parent(kid.id, tess.id)
	WorldIface.coins[1] = coins
	return [int(ivo.id), int(tess.id), int(kid.id)]

func _risk(f: Array) -> void:
	var w := C.town(6)
	var h: Array = _home(w, ["easygoing", "optimist"], 5000)
	var ivo: int = h[0]
	var kid: int = h[2]
	JusticePlayer.auto = "ignore"
	var calm: Dictionary = CrimeChildAbuse.assess(ivo, kid)
	K.expect(f, float(calm["raw"]) < 0.35, "a calm carer with money has low risk (%.2f)" % float(calm["raw"]))
	for d in 300:
		K.set_time(3 + d, 12)
		CrimeChildAbuse.on_day()
	K.expect(f, JusticeState.counter("child_abuse_incident") == 0 and CrimeChildAbuse.score_of(ivo) < 0.2, "a low-risk home never comes near it over a year")
	K.teardown()
	var w2 := C.town(6)
	var h2: Array = _home(w2, ["hot_headed", "vengeful"], 0)
	var ivo2: int = h2[0]
	var kid2: int = h2[2]
	JusticePlayer.auto = "ignore"
	for p in [ivo2, kid2]:
		RelationshipRomance.add_tension(ivo2, kid2, 80.0)
		RelationshipRomance.add_tension(kid2, ivo2, 80.0)
	var high: Dictionary = CrimeChildAbuse.assess(ivo2, kid2)
	K.expect(f, float(high["raw"]) > 0.7 and (high["risk"] as Dictionary).has("money") and (high["risk"] as Dictionary).has("hot_headed"), "stress, temper and tension raise the risk (%.2f)" % float(high["raw"]))
	var f_ivo = SysUtil.folk(ivo2)
	f_ivo.add_buff("in_therapy")
	var healed: Dictionary = CrimeChildAbuse.assess(ivo2, kid2)
	K.expect(f, float(healed["raw"]) < float(high["raw"]) - 0.25, "therapy lowers it")
	f_ivo.remove_buff("in_therapy")
	var warned: bool = false
	var hurt_day: int = -1
	for d in 400:
		K.set_time(3 + d, 12)
		RelationshipRomance.add_tension(ivo2, kid2, 60.0)
		CrimeChildAbuse.on_day()
		for e in JusticePlayer.log:
			if str(e["title"]) == "Tension at home":
				warned = true
		if JusticeState.counter("child_abuse_incident") > 0:
			hurt_day = d
			break
	K.expect(f, warned, "the player's own carer gets a warning prompt first")
	var opts: Array = []
	for e2 in JusticePlayer.log:
		if str(e2["title"]) == "Tension at home":
			opts = e2["options"]
	K.expect(f, opts.has("break") and opts.has("help"), "with ways to step in (a break, ask for help)")
	K.expect(f, hurt_day > 20, "it takes weeks of strain, never a sudden event (first incident on day %d)" % hurt_day)
	# stepping in works: a break halves the score
	var rec: Dictionary = JusticeState.abuse["carers"][ivo2]
	rec["score"] = 1.0
	CrimeChildAbuse._warn_choice("break", ivo2)
	K.expect(f, CrimeChildAbuse.score_of(ivo2) < 0.5, "taking a break lowers the strain")
	JusticePlayer.auto = ""
	K.teardown()

func _incident_and_discovery(f: Array) -> void:
	var w := C.town(6)
	var h: Array = _home(w, ["hot_headed"], 50)
	var ivo: int = h[0]
	var kid: int = h[2]
	K.set_time(10, 12)
	var c: Dictionary = CrimeChildAbuse.incident(ivo, kid)
	var fk = SysUtil.folk(kid)
	K.expect(f, not c.is_empty() and str(c["kind"]) == "child_abuse" and str(c["state"]) == "hidden", "an incident opens a hidden case")
	K.expect(f, Health.is_injured(fk) and fk.has_buff("afraid_at_home"), "the child is injured and frightened (an event only)")
	K.expect(f, JusticeState.abuse["hist"].has(kid) and CrimeChildAbuse.trauma_of(kid) >= 0.5, "a trauma is on file")
	var text: String = ""
	for n in K.notes:
		text += str(n[0]) + "\n"
	K.expect(f, text.find("hurt at home") >= 0 and text.to_lower().find("hit") < 0 and text.to_lower().find("beat") < 0, "the notice is short and non-graphic")
	# a doctor reports almost always
	var reported: int = 0
	for i in 100:
		var kd: Dictionary = JusticeState.abuse["kids"][kid]
		kd["reported"] = false
		kd["last_day"] = SysUtil.day()
		ChildServices.on_treated(kid)
		if bool(JusticeState.abuse["kids"][kid]["reported"]):
			reported += 1
	K.expect(f, reported >= 90, "a doctor who treats the child reports the injuries (%d of 100)" % reported)
	# a teacher notices within weeks
	var kd2: Dictionary = JusticeState.abuse["kids"][kid]
	kd2["reported"] = false
	kd2["visited"] = false
	kd2["last_day"] = SysUtil.day()
	var got: String = ""
	for d in 30:
		K.set_time(11 + d, 12)
		kd2["last_day"] = SysUtil.day()
		ChildServices.on_day()
		if bool(kd2["reported"]):
			got = str(kd2.get("source", ""))
			break
	K.expect(f, got != "", "a teacher or a relative notices and reports it (%s)" % got)
	# nobody reports when there is no incident
	var w2_kid: int = h[1]
	ChildServices.on_treated(w2_kid)
	K.expect(f, not JusticeState.abuse["kids"].has(w2_kid), "treating an unharmed person reports nothing")
	K.teardown()

func _services_and_justice(f: Array) -> void:
	var w := C.town(8)
	var h: Array = _home(w, ["hot_headed"], 400)
	var ivo: int = h[0]
	var kid: int = h[2]
	K.set_time(10, 12)
	JusticeState.sect("child_abuse")["services"]["substantiated_base"] = 1.0
	CrimeChildAbuse.incident(ivo, kid)
	var kd: Dictionary = JusticeState.abuse["kids"][kid]
	kd["serious"] = true
	kd["incidents"] = 2
	ChildServices.report(kid, "teacher")
	K.set_time(12, 12)
	ChildServices.on_day()
	kd = JusticeState.abuse["kids"][kid]
	K.expect(f, bool(kd["visited"]) and not (kd["placed"] as Dictionary).is_empty(), "serious harm: child services visit and place the child")
	K.expect(f, SysUtil.folk(kid) == null and Story.townies.has(kid) and Story.townies[kid].has("placed"), "the child no longer lives in the home")
	var seen: String = ""
	for n in K.notes:
		seen += str(n[0]) + "\n"
	K.expect(f, seen.find("placed") >= 0 and seen.find("Tobin Orr") >= 0, "the player is told, by name")
	var cs: Dictionary = CaseStore.get_case(int(kd["case"]))
	K.expect(f, str(cs["state"]) in ["arrested", "charged", "open"] and int(cs["accused"]) == ivo, "the police are involved when there is evidence: the carer is arrested")
	K.expect(f, JusticeProcess.charge_for(cs) == "child_abuse", "charged with child abuse")
	var line: String = CaseText.arrested(cs, ivo)
	K.expect(f, line.find("child abuse of Tobin Orr") >= 0, "the arrest names the charge and the child: " + line)
	# conviction: harsh sentence, order, loss of custody, a parenting course
	cs["verdict"] = "guilty"
	cs["lawyer_skill"] = 0.3
	JusticeSentence.impose(cs)
	var s: Dictionary = cs["sentence"]
	K.expect(f, str(s["type"]) in ["jail", "prison"] and int(s["days"]) >= 10, "a far harsher sentence than an adult assault (%s)" % CaseText.sentence(s))
	K.expect(f, bool(s["order"]) and bool(s["custody_loss"]) and not (s["courses"] as Array).is_empty(), "with a protective order, loss of custody and a parenting course")
	var verdict_line: String = ""
	for nn in cs["notes"]:
		if str(nn["text"]).find("child abuse of Tobin Orr") >= 0 and str(nn["text"]).find("loss of custody") >= 0:
			verdict_line = str(nn["text"])
	K.expect(f, verdict_line != "", "the verdict line names the charge, the child and the sentence")
	# the child stays away until the carer is free and has done the parenting course
	K.set_time(13, 12)
	ChildServices.on_day()
	K.expect(f, not (JusticeState.abuse["kids"][kid]["placed"] as Dictionary).is_empty(), "no return while the carer is locked away")
	Prison.release(ivo, false)
	JusticeState.orders.clear()
	for d in 40:
		K.set_time(14 + d, 12)
		JusticeSentence.on_day()
	K.expect(f, int(JusticeState.abuse["parenting"].get(ivo, -1)) >= 0, "the parenting course was completed")
	for d2 in 20:
		K.set_time(60 + d2, 12)
		ChildServices.on_day()
	K.expect(f, (JusticeState.abuse["kids"][kid]["placed"] as Dictionary).is_empty(), "after the course the child can go home")
	K.teardown()
