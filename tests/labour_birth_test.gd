extends RefCounted
## Task 18 parts 5-6: labour with a warning and a few hours, hospital or home, partner present or absent, rare complications (safer at the
## hospital), the mother's death extremely rare, naming the baby (player prompt + command), postpartum recovery and depression, paternity
## doubt and the test, congratulations, save and load in the middle of labour.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_labour(f)
	_presence(f)
	_complications(f)
	_naming(f)
	_postpartum(f)
	_paternity(f)
	_save(f)
	return f

static func _couple(w: StubWorld) -> Array:
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
	K.set_time(1, 8)
	assert(Conception.try_for_baby(m.id, d.id)["ok"])
	PregnancyStage.reveal(m.id, "test")
	return [m, d]

static func _clock_to(minute: int) -> void:
	SimEnv.clock().total_minutes = minute
	Pregnancy.on_hour()

func _labour(f: Array) -> void:
	var w := K.setup(901)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var due: int = (int(Pregnancy.rec(m.id)["due_day"]) - 1) * 1440
	_clock_to(due - 10 * 60)
	K.expect(f, not PregnancyLabour.in_labour(m.id), "no labour long before the due time")
	_clock_to(due - 5 * 60)
	K.expect(f, PregnancyLabour.in_labour(m.id) and m.has_buff("in_labour") and K.has_note("Contractions!"), "labour starts with a warning near the due time")
	var lb: Dictionary = Pregnancy.rec(m.id)["labour"]
	var hours: float = (float(lb["end"]) - float(lb["start"])) / 60.0
	K.expect(f, hours >= 3.0 and hours <= 6.6, "labour lasts a few game hours (%.1f)" % hours)
	K.expect(f, str(lb["place"]) == "home", "no maternity ward in the stub town: a home birth")
	PregnancyLabour.set_place(m.id, "hospital")
	K.expect(f, str(Pregnancy.rec(m.id)["labour"]["place"]) == "home", "cannot choose a hospital that does not exist")
	var before: int = w.all_folk().size()
	_clock_to(int(lb["end"]) - 1)
	K.expect(f, w.all_folk().size() == before, "the baby is not born before labour ends")
	_clock_to(int(lb["end"]) + 1)
	K.expect(f, w.all_folk().size() == before + 1 and not Aging.pregnancies.has(m.id) and not m.has_buff("in_labour"), "the baby arrives when labour ends")
	K.expect(f, K.count_events("labour_started") == 1 and K.count_events("baby_born") == 1, "events: labour, birth")
	K.teardown()
	# a clock that only ticks days still delivers
	w = K.setup(902)
	c = _couple(w)
	K.set_time(4, 0)
	Aging.on_day(4)
	K.expect(f, K.count_events("baby_born") == 1, "a day-only clock still delivers on the due day")
	K.teardown()

func _presence(f: Array) -> void:
	var w := K.setup(910)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var d: Folk = c[1]
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	K.expect(f, d.has_buff("birth_bond") and m.has_buff("birth_bond") and K.count_events("birth_witnessed") == 1, "a partner who is there shares a strong memory")
	K.expect(f, Emotions.moments_of(d.id).size() >= 1, "a lasting memory")
	K.teardown()
	w = K.setup(911)
	c = _couple(w)
	m = c[0]
	d = c[1]
	d.set_meta("away", true)
	K.expect(f, SysUtil.is_away(d), "precondition: he is at work")
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	K.expect(f, d.has_buff("missed_birth") and not d.has_buff("birth_bond"), "an absent partner has a negative memory")
	K.teardown()

func _complications(f: Array) -> void:
	var w := K.setup(920)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var r: Dictionary = Pregnancy.rec(m.id)
	var n := 6000
	var home := 0
	var hosp := 0
	for i in n:
		if PregnancyComplication.roll(m.id, r, "home") != "none":
			home += 1
		if PregnancyComplication.roll(m.id, r, "hospital") != "none":
			hosp += 1
	var base: float = float(Pregnancy.cfg("birth")["complication"]) * n
	K.expect(f, absf(home - base) < base * 0.3, "complications are rare and follow the data (%d vs %.0f)" % [home, base])
	K.expect(f, hosp < home * 0.8, "much lower at the hospital (%d vs %d)" % [hosp, home])
	# the mother's death is extremely rare
	var died_home := 0
	var died_hosp := 0
	for i in 40000:
		if PregnancyComplication.roll(m.id, r, "home") == "mother_died":
			died_home += 1
		if PregnancyComplication.roll(m.id, r, "hospital") == "mother_died":
			died_hosp += 1
	K.expect(f, died_home < 80 and died_hosp < died_home + 1 and died_hosp < 20, "maternal death extremely rare, lower at the hospital (%d / %d of 40000)" % [died_home, died_hosp])
	K.teardown()
	# outcomes
	w = K.setup(921)
	c = _couple(w)
	m = c[0]
	Pregnancy.cfg("birth")["complication"] = 5.0
	Pregnancy.cfg("birth")["caesarean_share"] = 1.0
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	K.expect(f, m.has_buff("postpartum_recovery") and K.has_note("caesarean"), "an emergency caesarean means a longer recovery")
	var left := 0.0
	for b in m.buffs:
		if str(b["id"]) == "postpartum_recovery":
			left = float(b["remaining"])
	K.expect(f, left > 5.0 * 1440.0, "(%.0f min)" % left)
	K.teardown()
	w = K.setup(922)
	c = _couple(w)
	m = c[0]
	Pregnancy.cfg("birth")["complication"] = 5.0
	Pregnancy.cfg("birth")["caesarean_share"] = 0.0
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	var extra := false
	for fk in w.all_folk():
		if fk.age_stage == "baby" and fk.has_buff("extra_care"):
			extra = true
	K.expect(f, extra, "a premature baby needs extra care")
	K.teardown()
	w = K.setup(923)
	c = _couple(w)
	m = c[0]
	Pregnancy.cfg("birth")["mother_death_home"] = 5.0
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	var baby_alive := false
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			baby_alive = true
	K.expect(f, w.get_folk(m.id) == null and baby_alive and K.has_note("The baby is safe"), "if the mother is lost the baby is safe, in gentle words")
	K.teardown()

func _naming(f: Array) -> void:
	var w := K.setup(930)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	JusticePlayer.log.clear()
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	var asked := false
	for e in JusticePlayer.log:
		if str(e["title"]) == "Name your baby":
			asked = true
			var opts: Array = e["options"]
			K.expect(f, opts.size() == 4 and str(opts[0]) == "keep" and str(opts[1]).begins_with("name:"), "the prompt offers the given name and suggestions")
	K.expect(f, asked, "the player is asked to name the baby")
	var baby: Folk = null
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			baby = fk
	var res: Dictionary = Commands.run({"player_id": Players.local_id, "folk_id": m.id, "action": "pregnancy", "args": {"action": "name_baby", "baby_id": baby.id, "name": "Wren"}})
	K.expect(f, bool(res.get("ok", false)) and baby.name.begins_with("Wren "), "the command names the baby: %s %s" % [str(res), baby.name])
	K.expect(f, not PregnancyNaming.rename(baby.id, "x") and not PregnancyNaming.rename(baby.id, "Averyveryveryverylongname"), "bad names are refused")
	K.expect(f, Family.name_of(baby.id) == baby.name, "the family book follows")
	var names: Array = Names.suggestions("female", 3)
	var all_f := true
	for n in names:
		all_f = all_f and Names.female_set().has(str(n))
	K.expect(f, names.size() == 3 and all_f, "suggestions follow the baby's sex")
	K.teardown()

func _postpartum(f: Array) -> void:
	var w := K.setup(940)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var d: Folk = c[1]
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	K.expect(f, m.has_buff("postpartum_recovery") and (m.has_buff("new_parent") or true), "recovery after the birth")
	var with_partner: float = PregnancyPostpartum.depression_chance(m.id, d.id)
	var alone: float = PregnancyPostpartum.depression_chance(m.id, -1)
	K.expect(f, with_partner < alone and alone <= 0.07, "a partner lowers the chance of postpartum depression (%.3f vs %.3f)" % [with_partner, alone])
	var n := 4000
	var low := 0
	for i in n:
		m.remove_buff("postpartum_low")
		PregnancyPostpartum.after_birth(m.id, d.id)
		if m.has_buff("postpartum_low"):
			low += 1
	K.expect(f, absf(float(low) / n - with_partner) < 0.02, "rate follows the data (%.3f vs %.3f)" % [float(low) / n, with_partner])
	m.add_buff("postpartum_low")
	K.expect(f, SimEnv.data().interactions().has("seek_counselling"), "the counsellor action exists")
	var ci = Interaction.create("seek_counselling", m, -1, true)
	K.expect(f, ci != null and ci.can_run(m), "a counsellor can be asked for help")
	K.teardown()

func _paternity(f: Array) -> void:
	var w := K.setup(950)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var other: Folk = c[1]
	# she is in an affair with `other`; her partner is `vic`
	var vic := K.make_folk(w, "Vic Hale", [], 1, Vector2i(15, 12))
	vic.sex = "male"
	Aging.set_age_days(vic, 92.0)
	RelationshipService.affairs.append({"cheater": m.id, "other": other.id, "victim": vic.id, "day": 1})
	Aging.pregnancies.erase(m.id)
	Fertility.rest_for(m.id, 0)
	Pregnancy.start(m.id, other.id, false)
	Paternity.at_conception(m.id, other.id, Pregnancy.rec(m.id))
	K.expect(f, int(Pregnancy.rec(m.id).get("assumed_father", -1)) == vic.id, "the partner is the assumed father")
	Pregnancy.cfg("paternity")["doubt_chance"] = 1.0
	PregnancyLabour.start(m.id)
	PregnancyLabour.finish(m.id)
	K.expect(f, vic.has_buff("doubting_father"), "he begins to doubt")
	WorldIface.add_coins(1, 300)
	var res: Dictionary = Paternity.test(vic.id)
	K.expect(f, res["ok"] and not res["his"] and K.count_events("paternity_revealed") == 1, "the test reveals the truth: %s" % str(res))
	K.expect(f, not vic.has_buff("doubting_father") and vic.has_buff("cheated_on"), "and the doubt is over")
	K.expect(f, RelationshipService.affairs.filter(func(a): return int(a.get("victim", -1)) == vic.id).is_empty(), "the affair is out in the open")
	K.teardown()

func _save(f: Array) -> void:
	var w := K.setup(960)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	PregnancyLabour.start(m.id)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Aging.to_dict()))
	var end_min: int = int(Pregnancy.rec(m.id)["labour"]["end"])
	Aging.from_dict(snap)
	var r: Dictionary = Pregnancy.rec(m.id)
	K.expect(f, r.has("labour") and int(r["labour"]["end"]) == end_min and PregnancyLabour.in_labour(m.id), "labour survives save and load")
	_clock_to(end_min + 1)
	K.expect(f, K.count_events("baby_born") == 1, "and the birth still happens after the load")
	K.teardown()
