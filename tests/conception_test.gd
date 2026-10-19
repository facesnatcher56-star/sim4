extends RefCounted
## Task 18 part 2: conception rules (female adult + male adult, RomanceRules never bypassed, the female carries whoever starts it),
## protection lowers the rate, fertility falls with life stage and is none for elders, infertility is found after trying and the clinic helps,
## twins / triplets rates follow the data.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_rules(f)
	_protection(f)
	_fertility(f)
	_infertility(f)
	_multiples(f)
	return f

static func _pair(w: StubWorld, sa: String, sb: String, age_a: float = 92.0, age_b: float = 92.0) -> Array:
	var a := K.make_folk(w, "Pat Lane", [])
	var b := K.make_folk(w, "Sam Lane", [], 1, Vector2i(13, 12))
	a.sex = sa
	b.sex = sb
	Aging.set_age_days(a, age_a)
	Aging.set_age_days(b, age_b)
	RelationshipService.add_both(a.id, b.id, "romance", 60.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipBits.set_flag(a.id, b.id, "sweetheart", true, false)
	return [a, b]

func _rules(f: Array) -> void:
	var w := K.setup(501)
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	# the male starts the action: the female still carries
	var p: Array = _pair(w, "male", "female")
	Fertility.state(p[0].id)["infertile"] = false
	Fertility.state(p[1].id)["infertile"] = false
	var res: Dictionary = Aging.try_for_baby(p[0].id, p[1].id)
	K.expect(f, res["ok"] and int(res["carrier"]) == p[1].id and Aging.pregnancies.has(p[1].id) and not Aging.pregnancies.has(p[0].id), "the woman carries even when the man starts: %s" % str(res))
	K.teardown()
	w = K.setup(502)
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	var same: Array = _pair(w, "female", "female")
	res = Aging.try_for_baby(same[0].id, same[1].id)
	K.expect(f, not res["ok"] and res["reason"] == "same_sex" and Aging.pregnancies.is_empty(), "a same-sex couple cannot conceive: %s" % str(res))
	K.expect(f, Conception.why_not(same[0].id, same[1].id).find("adopt") >= 0, "and is pointed to adoption")
	K.expect(f, Intimacy.daily_couple(same[0].id, same[1].id) in [true, false] and Aging.pregnancies.is_empty(), "same-sex intimacy never starts a pregnancy")
	K.teardown()
	w = K.setup(503)
	var elder: Array = _pair(w, "female", "male", 180.0, 92.0)
	elder[0].age_stage = "elder"
	K.expect(f, Conception.check(elder[0].id, elder[1].id)["reason"] == "too_old", "an elder cannot conceive")
	K.teardown()
	w = K.setup(504)
	var teen := K.make_folk(w, "Tina", [], 1, Vector2i(12, 12), "teen")
	teen.sex = "female"
	var man := K.make_folk(w, "Max", [], 1, Vector2i(13, 12))
	man.sex = "male"
	Aging.set_age_days(man, 92.0)
	K.expect(f, not Conception.check(teen.id, man.id)["ok"] and Aging.try_for_baby(teen.id, man.id).get("reason", "") in ["not_allowed", "too_young"], "never a teen")
	# family: a mother and her son
	var mom := K.make_folk(w, "Mia", [], 1, Vector2i(14, 12))
	mom.sex = "female"
	var son := K.make_folk(w, "Sol", [], 1, Vector2i(15, 12))
	son.sex = "male"
	Aging.set_age_days(mom, 92.0)
	Aging.set_age_days(son, 92.0)
	Family.link_parent(son.id, mom.id)
	K.expect(f, Conception.check(son.id, mom.id)["reason"] == "not_allowed" and Aging.try_for_baby(son.id, mom.id)["reason"] == "not_allowed", "RomanceRules still guards family pairs")
	K.expect(f, Intimacy.daily_couple(son.id, mom.id) == false and Aging.pregnancies.is_empty(), "and the daily couple dice")
	K.teardown()

func _protection(f: Array) -> void:
	var w := K.setup(510)
	var p: Array = _pair(w, "female", "male")
	Fertility.state(p[0].id)["infertile"] = false
	Fertility.state(p[1].id)["infertile"] = false
	var n := 4000
	var open := 0
	var careful := 0
	for i in n:
		Aging.pregnancies.clear()
		if Conception.intimate(p[0].id, p[1].id, "none")["ok"]:
			open += 1
		Aging.pregnancies.clear()
		if Conception.intimate(p[0].id, p[1].id, "protected")["ok"]:
			careful += 1
	Aging.pregnancies.clear()
	var cc: Dictionary = Pregnancy.cfg("conception")
	var want_open: float = float(cc["unprotected_chance"]) * n
	var want_careful: float = float(cc["protected_chance"]) * n
	K.expect(f, absf(open - want_open) < want_open * 0.25, "unprotected rate near the data (%d vs %.0f)" % [open, want_open])
	K.expect(f, careful < open / 4 and absf(careful - want_careful) < want_careful * 0.6 + 6, "protection lowers it a lot (%d vs %d, data %.0f)" % [careful, open, want_careful])
	K.teardown()

func _fertility(f: Array) -> void:
	var w := K.setup(520)
	var ages := [92.0, 120.0, 150.0, 158.0]
	var last := 2.0
	for a in ages:
		var p: Array = _pair(w, "female", "male", a, 92.0)
		Fertility.state(p[0].id)["infertile"] = false
		var fe: float = Fertility.of(p[0].id)
		K.expect(f, fe <= last + 0.0001, "fertility falls with age (%.0f days: %.2f)" % [a, fe])
		last = fe
		K.expect(f, fe > 0.0, "still some fertility late in adult life (%.0f days)" % a)
	var young := K.make_folk(w, "Yan", [])
	young.sex = "female"
	Aging.set_age_days(young, 80.0)
	Fertility.state(young.id)["infertile"] = false
	K.expect(f, Fertility.of(young.id) > 0.95, "young adults are highly fertile (%.2f)" % Fertility.of(young.id))
	var old := K.make_folk(w, "Olga", [], 1, Vector2i(16, 12), "elder")
	old.sex = "female"
	Aging.set_age_days(old, 180.0)
	Fertility.state(old.id)["infertile"] = false
	K.expect(f, Fertility.of(old.id) == 0.0, "elders have none")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(17, 12), "child")
	K.expect(f, Fertility.of(kid.id) == 0.0, "children have none")
	# health and stress lower it
	var base: float = Fertility.of(young.id)
	young.add_buff("exhausted")
	K.expect(f, Fertility.of(young.id) < base, "exhaustion lowers it")
	K.teardown()

func _infertility(f: Array) -> void:
	var w := K.setup(530)
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	var p: Array = _pair(w, "female", "male")
	Fertility.state(p[0].id)["infertile"] = true
	Fertility.state(p[1].id)["infertile"] = false
	var tries := 0
	for d in range(1, 9):
		K.set_time(d * 5, 8)
		var res: Dictionary = Aging.try_for_baby(p[0].id, p[1].id)
		K.expect(f, not res["ok"], "an infertile woman does not conceive")
		tries += 1
		if Fertility.revealed(p[0].id):
			break
	K.expect(f, Fertility.revealed(p[0].id) and tries >= 3, "it is found out only after trying for a while (%d tries)" % tries)
	K.expect(f, K.has_note("fertility clinic"), "the notification points to the clinic")
	WorldIface.add_coins(1, 1000)
	var cfg: Dictionary = Fertility.cfg()
	cfg["clinic"]["cure_chance"] = 1.0
	var coins_before: int = WorldIface.get_coins(1)
	var tr: Dictionary = Fertility.treat(p[0].id)
	K.expect(f, tr["ok"] and tr["cured"] and not Fertility.is_infertile(p[0].id) and WorldIface.get_coins(1) < coins_before, "the clinic treats her for a fee: %s" % str(tr))
	K.expect(f, Fertility.treated(p[0].id), "and the odds are boosted for a while")
	K.teardown()

func _multiples(f: Array) -> void:
	K.setup(540)
	var n := 40000
	var tw := 0
	var tr := 0
	for i in n:
		match Pregnancy.roll_kids(0):
			2: tw += 1
			3: tr += 1
	var cc: Dictionary = Pregnancy.cfg("conception")
	K.expect(f, absf(float(tw) / n - float(cc["twins"])) < 0.006, "twins about %.1f%% (%.2f%%)" % [float(cc["twins"]) * 100, tw * 100.0 / n])
	K.expect(f, float(tr) / n < 0.004 and tr > 0, "triplets are very rare (%d of %d)" % [tr, n])
	K.teardown()
