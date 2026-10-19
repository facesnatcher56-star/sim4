extends RefCounted
## Fertility window (task 19j): a woman's fertility reaches 0 well before the elder birthday, so no pregnancy can run into elderhood (Madrina turned elder on
## d93 and gave birth on d95). Tested across ages and across the ageing speeds ("short" 1.6 age days per game day ... "epic" 0.3).

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_curve(f)
	_every_speed(f)
	_conception(f)
	return f

func _woman(w: StubWorld, age: float) -> Folk:
	var m := K.make_folk(w, "Mina Lane", [])
	m.sex = "female"
	Aging.set_age_days(m, age)
	Fertility.state(m.id)["infertile"] = false
	return m

func _curve(f: Array) -> void:
	var w := K.setup(61)
	var elder_from: float = float(Aging.stage_def("elder")["from_day"])
	var end_age: float = Fertility.end_age()
	K.expect(f, end_age < elder_from - float(Pregnancy.length_days()), "the window closes before the elder start minus a whole pregnancy (%.1f vs %.0f)" % [end_age, elder_from])
	var m := _woman(w, 100.0)
	K.expect(f, Fertility.by_age(m.id) == 1.0, "a woman in her prime is fully fertile")
	var prev: float = 1.0
	var zero_from: float = -1.0
	var a: float = 100.0
	while a < elder_from + 5.0:
		Aging.set_age_days(m, a)
		var v: float = Fertility.by_age(m.id)
		K.expect(f, v <= prev + 0.0001, "fertility never rises with age (%.1f: %.2f after %.2f)" % [a, v, prev])
		if v <= 0.0 and zero_from < 0.0:
			zero_from = a
		if zero_from >= 0.0:
			K.expect(f, v <= 0.0, "once at 0 it stays 0 (%.1f)" % a)
		prev = v
		a += 0.5
	K.expect(f, zero_from >= 0.0 and zero_from <= end_age + 0.6, "fertility is 0 from the end of the window (%.1f)" % zero_from)
	K.expect(f, elder_from - zero_from >= float(Pregnancy.length_days()) + 5.0, "and that is well before the elder birthday (%.1f days)" % (elder_from - zero_from))
	Aging.set_age_days(m, end_age - 12.0)
	K.expect(f, Fertility.by_age(m.id) > 0.2, "twelve days before the end she is still reasonably fertile (%.2f)" % Fertility.by_age(m.id))
	K.teardown()

## For each ageing speed: any age with fertility above 0 plus the age gained during a whole pregnancy stays below the elder start.
func _every_speed(f: Array) -> void:
	for setting in ["short", "normal", "long", "epic"]:
		var w := K.setup(62)
		SimEnv.data().get_table("aging")["lifespan"]["setting"] = setting
		Aging.lifespan_setting = ""
		var rate: float = Aging.age_rate()
		var elder_from: float = float(Aging.stage_def("elder")["from_day"])
		var m := _woman(w, 100.0)
		var worst: float = 0.0
		var a: float = 76.0
		while a < elder_from + 3.0:
			Aging.set_age_days(m, a)
			if Fertility.by_age(m.id) > 0.0:
				worst = maxf(worst, a + float(Pregnancy.length_days()) * rate)
			a += 0.25
		K.expect(f, worst < elder_from, "%s (x%.1f): the latest possible birth is at age %.1f, before the elder start (%.0f)" % [setting, rate, worst, elder_from])
		K.teardown()

func _conception(f: Array) -> void:
	var w := K.setup(63)
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	var man := K.make_folk(w, "Sam Lane", [], 1, Vector2i(13, 12))
	man.sex = "male"
	Aging.set_age_days(man, 100.0)
	Fertility.state(man.id)["infertile"] = false
	var mom := _woman(w, Fertility.end_age() + 1.0)
	RelationshipService.add_both(mom.id, man.id, "romance", 60.0)
	RelationshipService.add_both(mom.id, man.id, "friendship", 60.0)
	RelationshipBits.set_flag(mom.id, man.id, "sweetheart", true, false)
	var res: Dictionary = Aging.try_for_baby(mom.id, man.id)
	K.expect(f, not res["ok"] and res["reason"] == "too_old" and Aging.pregnancies.is_empty(), "a late-adult woman past the window cannot conceive: %s" % str(res))
	K.expect(f, Conception.why_not(mom.id, man.id).find("Too old") >= 0, "and is told so in plain words")
	Aging.set_age_days(mom, 100.0)
	res = Aging.try_for_baby(mom.id, man.id)
	K.expect(f, res["ok"] and Aging.pregnancies.has(mom.id), "in her prime she can: %s" % str(res))
	K.teardown()
