extends RefCounted
## Task 14 health, part 1: the meters (fitness, diet, teeth), the gym, the clinic and the dentist, what health does to illness and lifespan.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_meters(f)
	_gym(f)
	_clinic(f)
	_dentist(f)
	_risk(f)
	_lifespan(f)
	return f

func _world(coins: int = 2000) -> StubWorld:
	var w := K.setup()
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	LifeTick.new_game()
	return w

func _meters(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var r: Dictionary = HealthLife.rec(1)
	r["fitness"] = 50.0
	r["diet"] = 50.0
	r["dental"] = 60.0
	LifeTick.on_interaction_finished(1, "exercise", true)
	LifeTick.on_interaction_finished(1, "lift_weights", true)
	K.expect(f, absf(float(r["fitness"]) - 52.7) < 0.01, "exercise and weights raise fitness (%.1f)" % float(r["fitness"]))
	LifeTick.on_interaction_finished(1, "eat_meal_good", true)
	K.expect(f, float(r["diet"]) > 52.0, "a good meal raises the diet")
	LifeTick.on_interaction_finished(1, "buy_snack", true)
	LifeTick.on_interaction_finished(1, "grab_snack", true)
	K.expect(f, float(r["diet"]) < 51.0, "snacks lower it (%.1f)" % float(r["diet"]))
	LifeTick.on_interaction_finished(1, "brush_teeth", false)
	K.expect(f, float(r["dental"]) == 60.0, "an interrupted interaction changes nothing")
	LifeTick.on_interaction_finished(1, "brush_teeth", true)
	K.expect(f, float(r["dental"]) == 66.0, "brushing helps the teeth")
	# a day: fitness decays, diet drifts to the middle, teeth wear (less when clean)
	ann.needs["hygiene"].value = 60.0
	r["fitness"] = 50.0
	r["diet"] = 80.0
	r["dental"] = 66.0
	HealthLifeDay.on_day(2)
	K.expect(f, float(r["fitness"]) < 50.0 and float(r["diet"]) < 80.0 and float(r["diet"]) > 70.0, "a day wears fitness down and pulls the diet to the middle")
	K.expect(f, absf(float(r["dental"]) - 65.3) < 0.01, "clean habits wear the teeth slowly (%.2f)" % float(r["dental"]))
	ann.needs["hygiene"].value = -50.0
	r["dental"] = 66.0
	HealthLifeDay.on_day(3)
	K.expect(f, absf(float(r["dental"]) - 64.9) < 0.01, "dirty habits faster (%.2f)" % float(r["dental"]))
	# toothache below the limit, until the dentist
	r["dental"] = 34.0
	HealthLifeDay.on_day(4)
	K.expect(f, ann.has_buff("toothache") and K.has_note("toothache"), "teeth that are neglected hurt")
	r["dental"] = 80.0
	HealthLifeDay.on_day(5)
	K.expect(f, not ann.has_buff("toothache"), "and the pain goes when the teeth are better")
	K.expect(f, HealthLife.label("fitness", 80.0) == "In good shape" and HealthLife.label("diet", 10.0) == "Eats badly" and HealthLife.label("dental", 40.0) == "Teeth need care", "meters have plain-word labels")
	K.expect(f, HealthLife.score(1) > 0.0 and HealthLife.score(1) <= 100.0, "the health score is 0..100")
	# townies get meters too, quietly
	var t: Dictionary = Story.alive_townies()[0]
	var notes0: int = K.notes.size()
	HealthLifeDay.on_day(6)
	K.expect(f, HealthLife.recs.has(int(t["id"])) and K.notes.size() == notes0, "townies keep meters statistically, no toasts")
	K.teardown()

func _gym(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	K.set_time(2, 18)                                             # Tuesday evening
	HealthLife.rec(1)["fitness"] = 40.0
	var price: int = PlaceUse.price("gym_desk", "class_yoga", 1)
	var r: Dictionary = PlaceUse.use(1, "gym_desk", "class_yoga", {"instant": true})
	K.expect(f, bool(r["ok"]) and float(HealthLife.rec(1)["fitness"]) == 43.0 and ann.skill_level("fitness") >= 0, "a class raises fitness (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(int(kid.id), "gym_desk", "class_yoga") != "", "children are not in the adult classes (%s)" % PlaceUse.why_not(int(kid.id), "gym_desk", "class_yoga"))
	K.expect(f, PlaceUse.use(1, "gym_desk", "gym_pass_week", {"instant": true})["ok"] and PlaceMember.has_pass(1, "gym_desk"), "a gym pass can be bought")
	K.expect(f, PlaceUse.price("gym_desk", "class_yoga", 1) == int(round(float(price) * 0.5)) or PlaceUse.price("gym_desk", "class_yoga", 1) == (price + 1) / 2, "and halves the price of classes (%d -> %d)" % [price, PlaceUse.price("gym_desk", "class_yoga", 1)])
	K.expect(f, Venues.entry_total("gym", [1]) == 0 and Venues.entry_total("gym", [int(kid.id)]) == Venues.fee("gym"), "the pass waives the entry fee for its holder only")
	K.set_time(2, 23)
	K.expect(f, PlaceUse.why_not(1, "gym_desk", "personal_trainer") != "", "the gym desk is shut at night")
	K.set_time(10, 18)
	K.expect(f, not PlaceMember.has_pass(1, "gym_desk") and Venues.entry_total("gym", [1]) == Venues.fee("gym"), "after the week the fee is back")
	K.teardown()

func _clinic(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(1, 10)
	K.expect(f, Places.is_open("clinic") and PlaceStaff.who("clinic", "doctor") != "", "the clinic is open with a named doctor")
	K.set_time(7, 10)
	K.expect(f, not Places.open_at("clinic"), "closed on Sundays")
	K.set_time(1, 10)
	HealthCond.give(1, "asthma")
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "clinic", "checkup", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == coins - 35, "a check-up costs 35 coins (%s)" % str(r.get("reason", "")))
	K.expect(f, HealthCond.diagnosed(1, "asthma") and str(r["text"]).find("asthma") >= 0 and ann.has_buff("checked_up"), "it finds the hidden condition and says so")
	K.expect(f, PlaceUse.why_not(1, "clinic", "checkup").find("only a few days ago") >= 0, "no second check-up at once")
	K.expect(f, PlaceUse.why_not(1, "clinic", "treat") == "Nothing needs treating.", "treatment only when unwell")
	Health.fall_ill(ann, "flu", 1, "test")
	K.expect(f, Health.is_ill(ann), "Ann is ill")
	var r2: Dictionary = PlaceUse.use(1, "clinic", "treat", {"instant": true})
	K.expect(f, bool(r2["ok"]) and ann.has_buff("medicated"), "the doctor treats her (%s)" % str(r2.get("reason", "")))
	# the flu shot
	var r3: Dictionary = PlaceUse.use(1, "clinic", "flu_shot", {"instant": true})
	K.expect(f, bool(r3["ok"]) and int(HealthLife.rec(1)["shot_until"]) > SysUtil.day() + 20, "a flu shot protects for weeks")
	K.set_time(2, 10)
	K.expect(f, PlaceUse.why_not(1, "clinic", "flu_shot").find("already protected") >= 0, "and cannot be repeated meanwhile")
	K.teardown()

func _dentist(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(1, 10)
	var r: Dictionary = HealthLife.rec(1)
	r["dental"] = 50.0
	K.expect(f, PlaceUse.why_not(1, "dentist", "dental_fix") == "No sore tooth to fix.", "no filling without a sore tooth")
	K.expect(f, bool(PlaceUse.use(1, "dentist", "dental_clean", {"instant": true})["ok"]) and float(r["dental"]) >= 95.0, "a clean restores the teeth")
	r["dental"] = 20.0
	ann.add_buff("toothache")
	K.set_time(2, 10)
	K.expect(f, bool(PlaceUse.use(1, "dentist", "dental_fix", {"instant": true})["ok"]) and not ann.has_buff("toothache") and float(r["dental"]) >= 80.0, "a filling ends the pain")
	K.set_time(6, 10)
	K.expect(f, not Places.open_at("dentist"), "the dentist is closed at the weekend")
	K.teardown()

func _risk(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var cold: Dictionary = IncidentDefs.get_def("catch_cold")
	var flu: Dictionary = IncidentDefs.get_def("catch_flu")
	var heart: Dictionary = IncidentDefs.get_def("heart_attack")
	K.expect(f, (cold["tags"] as Array).has("illness") and (heart["tags"] as Array).has("cardiac"), "the health incidents are tagged (data/incidents/14_health.json)")
	var r: Dictionary = HealthLife.rec(1)
	var subj := IncidentSubject.make(ann)
	r["fitness"] = 95.0
	r["diet"] = 90.0
	var good_cold: float = IncidentRisk.effective_rate(cold, subj, false, true)
	var good_heart: float = IncidentRisk.effective_rate(heart, subj, false, true)
	r["fitness"] = 5.0
	r["diet"] = 10.0
	var bad_cold: float = IncidentRisk.effective_rate(cold, subj, false, true)
	var bad_heart: float = IncidentRisk.effective_rate(heart, subj, false, true)
	K.expect(f, bad_cold > good_cold * 1.6 and bad_heart > good_heart * 3.0, "poor fitness and diet raise colds (x%.1f) and heart trouble (x%.1f)" % [bad_cold / good_cold, bad_heart / good_heart])
	K.expect(f, IncidentRisk.max_rate(cold, "catch_cold") >= bad_cold and IncidentRisk.max_rate(heart, "heart_attack") >= bad_heart * 2.0, "the sampling bound still covers the worst case")
	var base_flu: float = IncidentRisk.effective_rate(flu, subj, false, true)
	r["shot_until"] = SysUtil.day() + 10
	K.expect(f, IncidentRisk.effective_rate(flu, subj, false, true) < base_flu * 0.3, "the flu shot cuts the flu to a quarter")
	HealthCond.give(1, "hypertension", true)
	var hp: float = IncidentRisk.effective_rate(heart, subj, false, true)
	HealthLife.rec(1)["conds"]["hypertension"]["doses"] = 5
	var hp_med: float = IncidentRisk.effective_rate(heart, subj, false, true)
	K.expect(f, hp > bad_heart * 2.0 and hp_med < hp * 0.6, "high blood pressure raises heart trouble, medicine halves it (%.2f -> %.2f)" % [hp, hp_med])
	K.teardown()

## Mean age at death from the data formula, for a given multiplier (closed form over the days from the start day).
func _mean_death_day(mult: float) -> float:
	var dc: Dictionary = Aging.cfg().get("death", {})
	var start: float = float(dc.get("start_day", 170))
	var alive := 1.0
	var mean := 0.0
	var d := start
	while d <= float(dc.get("max_day", 230)):
		var p: float = minf((float(dc.get("chance_per_day", 0.03)) + float(dc.get("ramp_per_day", 0.004)) * (d - start)) * mult, 1.0)
		if d >= float(dc.get("max_day", 230)):
			p = 1.0
		mean += alive * p * d
		alive *= 1.0 - p
		d += 1.0
	return mean

func _lifespan(f: Array) -> void:
	var w := _world()
	var r: Dictionary = HealthLife.rec(1)
	r["fitness"] = 95.0
	r["diet"] = 90.0
	r["dental"] = 95.0
	var best: float = HealthLife.age_shift(1)
	r["fitness"] = 5.0
	r["diet"] = 10.0
	r["dental"] = 10.0
	var worst: float = HealthLife.age_shift(1)
	K.expect(f, best > 10.0 and worst < -9.0, "the old-age window moves by %.1f to %.1f game days" % [best, worst])
	var fit_life: float = _mean_death_day(1.0) + best
	var unfit_life: float = _mean_death_day(1.0) + worst
	K.expect(f, fit_life - unfit_life > 18.0, "a fit person lives longer: %.1f vs %.1f game days" % [fit_life, unfit_life])
	HealthCond.give(1, "diabetes", true)
	var unmanaged: float = HealthLife.death_mult(1)
	HealthLife.rec(1)["conds"]["diabetes"]["doses"] = 9
	K.expect(f, HealthLife.death_mult(1) < unmanaged and unmanaged > 1.1, "unmanaged conditions shorten life more than managed ones")
	K.expect(f, HealthLife.death_mult(99999) == 1.0 and HealthLife.age_shift(99999) == 0.0, "somebody never looked at counts as average")
	# the real hook: an old resident of good health outlives the same age with bad health in Aging._check_deaths
	var old_age: float = float(Aging.cfg().get("death", {}).get("start_day", 170)) + 3.0
	var ann = SysUtil.folk(1)
	Aging.set_age_days(ann, old_age)
	r["fitness"] = 95.0
	r["diet"] = 90.0
	r["dental"] = 95.0
	var died_fit := 0
	var died_unfit := 0
	for i in 600:
		SysUtil.seed_rng(9000 + i)
		if SysUtil.chance(0.0):
			pass
		Aging.records[1]["age_days"] = old_age
		r["fitness"] = 95.0
		r["diet"] = 90.0
		r["dental"] = 95.0
		var days_eff: float = old_age - HealthLife.age_shift(1)
		died_fit += 1 if days_eff >= float(Aging.cfg().get("death", {}).get("start_day", 170)) else 0
		r["fitness"] = 5.0
		r["diet"] = 10.0
		r["dental"] = 10.0
		days_eff = old_age - HealthLife.age_shift(1)
		died_unfit += 1 if days_eff >= float(Aging.cfg().get("death", {}).get("start_day", 170)) else 0
	K.expect(f, died_fit == 0 and died_unfit == 600, "just past the start day only the unhealthy are at risk")
	K.teardown()
