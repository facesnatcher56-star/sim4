extends RefCounted
## Task 18 part 3: the pregnancy from conception to birth: discovery (feeling off, test, doctor, showing), telling the partner and the
## secret / gossip path, trimesters and the visible third trimester, prenatal care and the ultrasound, late limits, leave, risk factors,
## twins at birth, and save / load in the middle.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_discovery(f)
	_telling(f)
	_secret(f)
	_care_and_limits(f)
	_leave_and_multiples(f)
	_risk(f)
	_save(f)
	return f

static func _couple(w: StubWorld, planned: bool = true) -> Array:
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	var m := K.make_folk(w, "Ann Rowe", ["creative"])
	m.sex = "female"
	var d := K.make_folk(w, "Bo Rowe", ["gamer"], 1, Vector2i(13, 12))
	d.sex = "male"
	Aging.set_age_days(m, 92.0)
	Aging.set_age_days(d, 92.0)
	for x in [m, d]:
		Fertility.state(x.id)["infertile"] = false
	RelationshipService.add_both(m.id, d.id, "romance", 70.0)
	RelationshipService.add_both(m.id, d.id, "friendship", 60.0)
	RelationshipBits.set_flag(m.id, d.id, "partner", true, false)
	WorldIface.add_coins(1, 500)
	K.set_time(1, 8)
	var res: Dictionary = Conception.try_for_baby(m.id, d.id) if planned else {"ok": false}
	if not planned:
		for _i in 400:
			res = Conception.intimate(m.id, d.id, "none")
			if res["ok"]:
				break
	assert(res["ok"])
	return [m, d]

## Move the clock to pregnancy progress p (the couple conceived at day 1, 08:00; the due day is day 4).
static func _at(p: float) -> void:
	SimEnv.clock().total_minutes = 480 + int(p * 3840.0)
	Pregnancy.on_hour()
	Family.update_pregnancies()

static func _advance(minutes: int) -> void:
	SimEnv.clock().total_minutes = SysUtil.now() + minutes
	Pregnancy.on_hour()
	Family.update_pregnancies()

func _discovery(f: Array) -> void:
	var w := K.setup(601)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	K.expect(f, Aging.pregnancies.has(m.id) and not Pregnancy.known(m.id), "she does not know at first")
	K.expect(f, not m.has_buff("pregnant") and not m.has_buff("pregnant_t1"), "no Expecting buff until she knows")
	var r: Dictionary = Pregnancy.rec(m.id)
	K.expect(f, int(r["due_day"]) - int(r["started"]) == 3, "length is data-driven (3 days by default)")
	# too early: nothing felt, a test says negative
	var res: Dictionary = PregnancyStage.take_test(m.id)
	K.expect(f, res["ok"] and res["result"] == "negative" and not Pregnancy.known(m.id), "a very early test says negative")
	# symptoms
	_at(0.2)
	K.expect(f, m.has_buff("feeling_off"), "she feels off after a while")
	K.expect(f, m.get_mood() != null, "mood readable")
	var coins: int = WorldIface.get_coins(1)
	res = PregnancyStage.take_test(m.id)
	K.expect(f, res["result"] == "positive" and Pregnancy.known(m.id) and m.has_buff("pregnant") and not m.has_buff("feeling_off"), "the test is positive: she knows now")
	K.expect(f, WorldIface.get_coins(1) < coins, "the test costs coins")
	K.expect(f, K.count_events("pregnancy_known") == 1 and K.has_note("positive"), "event and plain-word note")
	K.teardown()
	# found out by herself (showing) and by a doctor
	w = K.setup(602)
	c = _couple(w)
	m = c[0]
	_at(0.55)
	K.expect(f, Pregnancy.known(m.id), "by the middle of the pregnancy she knows by herself")
	K.teardown()
	w = K.setup(603)
	c = _couple(w)
	m = c[0]
	var cres: Dictionary = PregnancyStage.checkup(m.id)
	K.expect(f, cres["ok"] and Pregnancy.known(m.id) and K.has_note("doctor confirms"), "a doctor's visit confirms it")
	K.teardown()

func _telling(f: Array) -> void:
	var w := K.setup(610)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var d: Folk = c[1]
	Pregnancy.rec(m.id)["secret"] = false
	PregnancyStage.reveal(m.id, "test")
	_advance(7 * 60)
	K.expect(f, Pregnancy.rec(m.id)["told"].has(d.id), "the partner is told within hours")
	K.expect(f, str(Pregnancy.rec(m.id).get("partner_reaction", "")) in ["joy", "shock", "anger", "breakup"], "and reacts")
	# reaction depends on the situation
	var happy: float = PregnancyTell.reaction_score(m.id, d.id, true)
	var rough: float = PregnancyTell.reaction_score(m.id, d.id, false)
	K.expect(f, happy > rough, "a planned baby is welcomed more (%.2f vs %.2f)" % [happy, rough])
	RelationshipBits.set_flag(m.id, d.id, "spouse", true, false)
	K.expect(f, PregnancyTell.reaction_score(m.id, d.id, false) > rough, "marriage helps")
	WorldIface.add_coins(1, -WorldIface.get_coins(1))
	K.expect(f, PregnancyTell.reaction_score(m.id, d.id, true) < happy + 0.31, "no money weighs on the reaction")
	d.traits.append("pessimist")
	d.traits.append("workaholic")
	K.expect(f, PregnancyTell.reaction_score(m.id, d.id, false) <= 0.0, "an unplanned baby with a gloomy, broke partner goes badly")
	K.teardown()

func _secret(f: Array) -> void:
	var w := K.setup(620)
	var c: Array = _couple(w, false)
	var m: Folk = c[0]
	var d: Folk = c[1]
	var friend := K.make_folk(w, "Fay Hale", ["social"], 2, Vector2i(15, 12))
	RelationshipService.add_both(m.id, friend.id, "friendship", 60.0)
	var friend2 := K.make_folk(w, "Gus Hale", ["social"], 3, Vector2i(16, 12))
	RelationshipService.add_both(m.id, friend2.id, "friendship", 60.0)
	var r: Dictionary = Pregnancy.rec(m.id)
	r["known"] = false
	Pregnancy.cfg("tell")["keep_secret_unplanned"] = 1.0
	PregnancyStage.reveal(m.id, "test")
	K.expect(f, bool(r["secret"]) and not bool(r.get("public", false)), "she keeps it secret")
	var found := false
	for s in RelationshipKnowledge.ensure_secrets(m.id):
		if int(s["id"]) == PregnancyTell.SECRET_ID:
			found = true
	K.expect(f, found, "it is a secret in the gossip system")
	Pregnancy.cfg("tell")["notice_chance_per_day"] = 1.0
	_at(0.5)                                              # second trimester: she is showing
	for day in 3:
		PregnancyTell.on_day(m.id, r)
		if bool(r.get("public", false)):
			break
	K.expect(f, bool(r.get("public", false)) and K.count_events("pregnancy_public") == 1, "somebody notices and word gets out")
	K.expect(f, not ChronicleHook.recent.is_empty() and str(ChronicleHook.recent[ChronicleHook.recent.size() - 1]["kind"]) == "pregnancy", "chronicle line")
	K.teardown()
	w = K.setup(621)
	c = _couple(w)
	m = c[0]
	JusticePlayer.auto = "tell"
	K.teardown()

func _care_and_limits(f: Array) -> void:
	var w := K.setup(630)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	PregnancyStage.reveal(m.id, "test")
	var r: Dictionary = Pregnancy.rec(m.id)
	K.expect(f, PregnancyStage.ultrasound(m.id).get("reason", "") == "too_early", "the scan needs a few weeks")
	_at(0.4)
	r["kids"] = 2
	r["kid_sexes"] = ["female", "male"]
	var sc: Dictionary = PregnancyStage.ultrasound(m.id)
	K.expect(f, sc["ok"] and str(sc["text"]).find("Twins") >= 0 and str(sc["text"]).find("girl") >= 0 and str(sc["text"]).find("boy") >= 0, "ultrasound reveals sexes and twins: %s" % str(sc.get("text", "")))
	PregnancyRisk.on_day(m.id, r)
	var before: float = PregnancyRisk.multiplier(r)
	r["visits"] = 0
	PregnancyRisk.on_day(m.id, r)
	var no_care: float = PregnancyRisk.multiplier(r)
	PregnancyStage.checkup(m.id)
	PregnancyRisk.on_day(m.id, r)
	K.expect(f, PregnancyRisk.multiplier(r) < no_care, "prenatal visits lower the risk (%.2f -> %.2f)" % [no_care, PregnancyRisk.multiplier(r)])
	PregnancyStage.set_bed_rest(m.id, true)
	PregnancyRisk.on_day(m.id, r)
	K.expect(f, m.has_buff("bed_rest"), "bed rest is a choice")
	PregnancyStage.set_bed_rest(m.id, false)
	# late pregnancy: exercise is blocked, early is not
	_at(0.8)
	K.expect(f, Pregnancy.is_late(m.id) and Health.blocks_activity(m, ["exercise"]) != "", "late pregnancy limits exercise: %s" % Health.blocks_activity(m, ["exercise"]))
	K.expect(f, Health.blocks_activity(m, ["cook"]) == "", "but not cooking")
	_at(0.2)
	K.expect(f, Health.blocks_activity(m, ["exercise"]) == "", "early pregnancy has no limits")
	K.expect(f, before > 0.0, "risk is a number")
	K.teardown()

func _leave_and_multiples(f: Array) -> void:
	var w := K.setup(640)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var d: Folk = c[1]
	Careers.hire(m, "office", 1) if Careers.career_ids().has("office") else null
	PregnancyStage.reveal(m.id, "test")
	var r: Dictionary = Pregnancy.rec(m.id)
	r["kids"] = 2
	r["kid_sexes"] = ["female", "male"]
	K.expect(f, not PregnancyLeave.on_leave(m.id), "no leave early on")
	r["due_day"] = SysUtil.day() + 1
	K.expect(f, PregnancyLeave.on_leave(m.id), "maternity leave starts before the due day")
	var before: int = w.all_folk().size()
	K.set_time(int(r["due_day"]), 6)
	Aging.on_day(int(r["due_day"]))
	var babies: int = 0
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			babies += 1
			K.expect(f, Aging.records[fk.id]["parents"].has(m.id) and Aging.records[fk.id]["parents"].has(d.id), "twin has both parents")
	K.expect(f, babies == 2 and w.all_folk().size() == before + 2, "twins are born (%d)" % babies)
	K.expect(f, K.count_events("baby_born") == 2 and K.has_note("Twins"), "two birth events and a twins note")
	var sx: Array = []
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			sx.append(fk.sex)
	sx.sort()
	K.expect(f, sx == ["female", "male"], "the sexes the scan promised: %s" % str(sx))
	K.expect(f, PregnancyLeave.on_leave(m.id) and PregnancyLeave.on_leave(d.id), "both parents are on leave after the birth")
	K.set_time(SysUtil.day() + 6, 8)
	K.expect(f, not PregnancyLeave.on_leave(m.id) and not PregnancyLeave.on_leave(d.id), "and back to work later")
	K.expect(f, Conception.try_for_baby(m.id, d.id)["reason"] in ["cooldown", "no_luck", "ok", "pregnant"], "pause after birth is a plain rule")
	K.teardown()

func _risk(f: Array) -> void:
	var w := K.setup(650)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	PregnancyStage.reveal(m.id, "test")
	var r: Dictionary = Pregnancy.rec(m.id)
	PregnancyRisk.on_day(m.id, r)
	var calm: float = PregnancyRisk.multiplier(r)
	m.add_buff("injured")
	m.add_buff("starving")
	PregnancyRisk.on_day(m.id, r)
	var bad: float = PregnancyRisk.multiplier(r)
	K.expect(f, bad > calm * 1.5, "injury and hunger raise the risk (%.2f -> %.2f)" % [calm, bad])
	m.remove_buff("injured")
	m.remove_buff("starving")
	SysUtil.game_event("fell_on_stairs", {"folk_id": m.id, "severity": 2, "level": 0})
	K.expect(f, float(r["risk"]) >= 3.0, "a fall adds risk that fades (%.1f)" % float(r["risk"]))
	K.set_time(SysUtil.day() + 8, 8)
	PregnancyRisk.on_day(m.id, r)
	K.expect(f, PregnancyRisk.multiplier(r) <= calm + 0.01, "and it fades with days")
	K.teardown()

func _save(f: Array) -> void:
	var w := K.setup(660)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	PregnancyStage.reveal(m.id, "test")
	var r: Dictionary = Pregnancy.rec(m.id)
	r["kids"] = 2
	r["kid_sexes"] = ["male", "female"]
	r["visits"] = 2
	var snap: Dictionary = Aging.to_dict()
	var back: Dictionary = JSON.parse_string(JSON.stringify(snap))
	Aging.from_dict(back)
	var r2: Dictionary = Pregnancy.rec(m.id)
	K.expect(f, not r2.is_empty() and int(r2["kids"]) == 2 and r2["kid_sexes"] == ["male", "female"] and int(r2["visits"]) == 2 and bool(r2["known"]), "a pregnancy survives save and load")
	K.expect(f, Pregnancy.extra.has(m.id) and not Fertility.is_infertile(m.id), "fertility state survives")
	K.teardown()
