extends RefCounted
## Task 14 health, part 2: long-term conditions (onset, symptoms, diagnosis, medicine, flares), counselling and therapy for grief, burnout and
## trauma, work strain and burnout, and the save round trip.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_conditions(f)
	_medicine(f)
	_counselling(f)
	_burnout(f)
	_save(f)
	return f

func _world(coins: int = 2000) -> StubWorld:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	return w

func _conditions(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var r: Dictionary = HealthLife.rec(1)
	r["fitness"] = 90.0
	r["diet"] = 90.0
	var fit_chance: float = HealthCond.onset_chance(1, "diabetes", "adult")
	r["fitness"] = 5.0
	r["diet"] = 5.0
	var unfit_chance: float = HealthCond.onset_chance(1, "diabetes", "adult")
	K.expect(f, unfit_chance > fit_chance * 3.0, "poor habits make diabetes more likely (x%.1f)" % (unfit_chance / fit_chance))
	K.expect(f, unfit_chance < 0.02, "but it stays rare (%.4f a day)" % unfit_chance)
	K.expect(f, HealthCond.onset_chance(1, "arthritis", "adult") == 0.0 and HealthCond.onset_chance(1, "arthritis", "elder") > 0.0, "arthritis is for elders")
	K.expect(f, HealthCond.onset_chance(1, "diabetes", "child") == 0.0, "children do not get adult conditions")
	# a condition shows up, is noticed after a few days, and only a check-up (or a flare) names it
	HealthCond.give(1, "asthma")
	K.expect(f, HealthCond.has(1, "asthma") and not HealthCond.diagnosed(1, "asthma"), "it starts hidden")
	K.set_time(2, 8)
	LifeDefs.config["health_life"]["conditions_symptom_days"] = 1
	for d in range(SysUtil.day() + 1, SysUtil.day() + 4):
		K.set_time(d, 8)
		HealthCond.day(1, "adult", true)
		if HealthCond.has(1, "asthma") and float(HealthLife.rec(1)["conds"]["asthma"]["flares"]) > 0:
			break
	K.expect(f, K.has_note("keeps coughing") or HealthCond.diagnosed(1, "asthma"), "the household hears about the symptoms")
	# a flare of a hidden condition diagnoses it and makes the person ill
	K.teardown()
	var w2 := _world()
	var bob = SysUtil.folk(1)
	HealthCond.give(1, "diabetes")
	HealthCond.flare(1, "diabetes", true)
	K.expect(f, HealthCond.diagnosed(1, "diabetes") and (Health.is_ill(bob) or Hospital.is_in(1)), "a flare-up diagnoses it and makes the person ill")
	K.expect(f, K.has_note("dizzy spell"), "in plain words")
	# townies: the same, quietly, and a serious flare means hospital
	var t: Dictionary = Story.alive_townies()[0]
	var tid: int = int(t["id"])
	HealthCond.give(tid, "hypertension")
	HealthLife.rec(tid)["conds"]["hypertension"]["since"] = SysUtil.day() - 10
	t["coins"] = 500
	HealthCond.day(tid, "adult", false)
	K.expect(f, HealthCond.diagnosed(tid, "hypertension") and HealthCond.doses(tid, "hypertension") > 0 and int(t["coins"]) < 500, "a townie is diagnosed after a few days and buys the medicine")
	K.teardown()

func _medicine(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(2, 12)
	HealthCond.give(1, "asthma", true)
	K.expect(f, not HealthCond.managed(1, "asthma"), "no medicine, not managed")
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "pharmacy_counter", "refill_asthma", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == coins - 14 and HealthCond.managed(1, "asthma") and HealthCond.doses(1, "asthma") == 14, "the pharmacy counter sells two weeks of medicine (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(1, "pharmacy_counter", "refill_diabetes").find("no prescription") >= 0, "only for conditions the person has")
	K.set_time(3, 12)
	for i in 13:
		HealthCond.day(1, "adult", true)
		HealthLife.rec(1)["conds"]["asthma"]["flares"] = 0
	K.expect(f, HealthCond.doses(1, "asthma") == 1, "a dose goes every day")
	HealthCond.day(1, "adult", true)
	K.expect(f, HealthCond.doses(1, "asthma") == 0 and K.has_note("run out"), "and the household is told when the medicine runs out")
	# flares are far rarer with medicine
	var unmanaged := 0
	var managed := 0
	HealthLife.rec(1)["conds"]["asthma"]["doses"] = 0
	for i in 400:
		var c: Dictionary = HealthLife.rec(1)["conds"]["asthma"]
		var before: int = int(c["flares"])
		c["doses"] = 0
		HealthCond._condition_day(1, "asthma", c, false)
		unmanaged += int(c["flares"]) - before
		before = int(c["flares"])
		c["doses"] = 5
		HealthCond._condition_day(1, "asthma", c, false)
		managed += int(c["flares"]) - before
	K.expect(f, unmanaged > managed * 3 and unmanaged > 10, "medicine keeps flare-ups down (%d unmanaged vs %d managed in 400 days)" % [unmanaged, managed])
	K.teardown()

func _counselling(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(2, 11)
	ann.add_buff("grieving")
	ann.add_buff("burnt_out")
	ann.add_buff("shaken")
	HealthLife.rec(1)["strain"] = 70.0
	var rem: Dictionary = {}
	for b in ann.buffs:
		rem[str(b["id"])] = float(b["remaining"])
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "therapy", "counselling", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == coins - 40, "a session costs 40 coins (%s)" % str(r.get("reason", "")))
	var after: Dictionary = {}
	for b2 in ann.buffs:
		after[str(b2["id"])] = float(b2["remaining"])
	K.expect(f, float(after.get("grieving", 0.0)) <= float(rem["grieving"]) * 0.55, "grief is cut by about half")
	K.expect(f, not after.has("burnt_out") or float(after["burnt_out"]) <= float(rem["burnt_out"]) * 0.45, "burnout is eased")
	K.expect(f, not after.has("shaken") or float(after["shaken"]) <= float(rem["shaken"]) * 0.45, "shock from a bad night too")
	K.expect(f, float(HealthLife.rec(1)["strain"]) <= 36.0 and ann.has_buff("in_therapy"), "work strain drops and the person is in therapy")
	K.expect(f, str(r["text"]).find("lighter") >= 0, "and the text says so")
	K.expect(f, K.count_events("counselling_done") == 1, "a game event reports it")
	# the old home action now also covers burnout
	K.teardown()
	var w2 := _world()
	var bob = SysUtil.folk(1)
	var ci: Interaction = Interaction.create("seek_counselling", bob, -1, true)
	K.expect(f, ci != null and not ci.can_run(bob), "nothing to talk about, no counsellor action")
	bob.add_buff("burnt_out")
	K.expect(f, ci.can_run(bob), "burnout makes 'Talk to a Counsellor' available")
	ci = null
	var rem2: float = 0.0
	for b3 in bob.buffs:
		if str(b3["id"]) == "burnt_out":
			rem2 = float(b3["remaining"])
	PregnancyLoss.counsel(1)
	var after2: float = 0.0
	for b4 in bob.buffs:
		if str(b4["id"]) == "burnt_out":
			after2 = float(b4["remaining"])
	K.expect(f, after2 < rem2 * 0.5, "and the old session helps too (%.0f -> %.0f)" % [rem2, after2])
	# insurance pays its share of a session
	BankInsurance.toggle(1, "health")
	var c2: int = Economy.balance(1)
	K.set_time(3, 11)
	var r2: Dictionary = PlaceUse.use(1, "therapy", "counselling", {"instant": true})
	K.expect(f, bool(r2["ok"]) and Economy.balance(1) > c2 - 40, "health insurance pays part of a session (%d paid)" % (c2 - Economy.balance(1)))
	K.teardown()

func _burnout(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	Careers.hire(ann, "coder", 1)
	var days := 0
	for d in range(2, 40):
		K.set_time(d, 18)
		ann.needs["energy"].value = -40.0                     # worn out after every shift
		LifeTick.on_game_event("returned_from_work", {"folk_id": 1, "skipped": false})
		K.set_time(d + 1, 0)
		HealthLifeDay.on_day(d + 1)
		days = d
		if ann.has_buff("burnt_out"):
			break
	K.expect(f, ann.has_buff("burnt_out") and days < 32, "worked every day while worn out, burnout comes (day %d)" % days)
	K.expect(f, HealthLife.counts.get("burnout", 0) == 1 and float(HealthLife.rec(1)["strain"]) == 40.0, "it resets the strain to a level that needs real work to climb again")
	# days off ease the strain; a holiday more
	HealthLife.rec(1)["strain"] = 60.0
	K.set_time(60, 0)
	HealthLifeDay.on_day(60)
	K.expect(f, float(HealthLife.rec(1)["strain"]) == 54.0, "a day off eases it by 6")
	ann.add_buff("vacation_glow")
	HealthLifeDay.on_day(61)
	K.expect(f, float(HealthLife.rec(1)["strain"]) <= 44.0, "a holiday glow eases it more")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "burnout"), "burnout is in the chronicle")
	K.teardown()

func _save(f: Array) -> void:
	var w := _world()
	HealthCond.give(1, "asthma", true)
	HealthCond.prescribe(1, "asthma")
	HealthLife.rec(1)["fitness"] = 61.5
	HealthLife.rec(1)["shot_until"] = 99
	var d: Dictionary = JSON.parse_string(JSON.stringify(LifeTick.to_dict()))
	LifeTick.from_dict(d, true)
	K.expect(f, absf(float(HealthLife.rec(1)["fitness"]) - 61.5) < 0.001 and HealthCond.managed(1, "asthma") and HealthCond.doses(1, "asthma") == 14 and int(HealthLife.rec(1)["shot_until"]) == 99, "meters, conditions and doses survive a save and load")
	K.teardown()
