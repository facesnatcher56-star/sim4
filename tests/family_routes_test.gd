extends RefCounted
## Task 18 part 7: other routes to a family: adoption for a single adult and for a same-sex couple, the fertility clinic route for a couple of
## any sexes (a woman carries; two men use a surrogate), cost, and the guards (RomanceRules, elders, money).

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_adoption(f)
	_clinic(f)
	return f

static func _pair(w: StubWorld, sa: String, sb: String) -> Array:
	var a := K.make_folk(w, "Pat Lane", [])
	var b := K.make_folk(w, "Sam Lane", [], 1, Vector2i(13, 12))
	a.sex = sa
	b.sex = sb
	Aging.set_age_days(a, 92.0)
	Aging.set_age_days(b, 92.0)
	RelationshipService.add_both(a.id, b.id, "romance", 60.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipBits.set_flag(a.id, b.id, "partner", true, false)
	WorldIface.add_coins(1, 3000)
	K.set_time(1, 8)
	return [a, b]

func _adoption(f: Array) -> void:
	var w := K.setup(1001)
	var solo := K.make_folk(w, "Una Reed", [])
	Aging.set_age_days(solo, 92.0)
	var kids: Array = FamilyHousehold.adoptable(true)
	K.expect(f, not kids.is_empty(), "children are up for adoption")
	var res: Dictionary = FamilyHousehold.adopt(int(kids[0]["id"]), solo.id)
	K.expect(f, bool(res["ok"]), "a single adult can adopt: %s" % str(res))
	K.teardown()
	w = K.setup(1002)
	var p: Array = _pair(w, "female", "female")
	kids = FamilyHousehold.adoptable(true)
	res = FamilyHousehold.adopt(int(kids[0]["id"]), p[0].id)
	K.expect(f, bool(res["ok"]) and FamilyTree.parents_of(int(kids[0]["id"])).has(p[0].id) and FamilyTree.parents_of(int(kids[0]["id"])).has(p[1].id), "a same-sex couple adopts together: both are parents")
	K.teardown()

func _clinic(f: Array) -> void:
	var w := K.setup(1010)
	var p: Array = _pair(w, "female", "male")
	Fertility.state(p[0].id)["infertile"] = true
	Pregnancy.cfg("clinic_route")["success"] = 1.0
	var coins: int = WorldIface.get_coins(1)
	var res: Dictionary = ClinicRoute.start(p[0].id, p[1].id)
	K.expect(f, res["ok"] and Aging.pregnancies.has(p[0].id) and WorldIface.get_coins(1) < coins, "a couple that cannot conceive on their own can use the clinic (it costs money)")
	K.teardown()
	w = K.setup(1011)
	p = _pair(w, "female", "female")
	Pregnancy.cfg("clinic_route")["success"] = 1.0
	res = ClinicRoute.start(p[1].id, p[0].id)
	K.expect(f, res["ok"] and Aging.pregnancies.has(p[1].id) and bool(Pregnancy.rec(p[1].id).get("donor", false)), "a female couple: one carries, with a donor")
	K.expect(f, Conception.try_for_baby(p[0].id, p[1].id)["reason"] == "same_sex", "but they still cannot conceive without it")
	K.teardown()
	w = K.setup(1012)
	p = _pair(w, "male", "male")
	Pregnancy.cfg("clinic_route")["success"] = 1.0
	res = ClinicRoute.start(p[0].id, p[1].id)
	K.expect(f, res["ok"] and res["reason"] == "surrogate" and Aging.pregnancies.is_empty(), "two men use a surrogate")
	var before: int = w.all_folk().size()
	K.set_time(5, 8)
	ClinicRoute.on_day()
	K.expect(f, w.all_folk().size() > before and K.count_events("baby_born") >= 1, "the baby joins the household")
	var baby: Folk = null
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			baby = fk
	K.expect(f, baby != null and FamilyTree.parents_of(baby.id).has(p[0].id) and FamilyTree.parents_of(baby.id).has(p[1].id), "both men are the parents")
	K.teardown()
	# guards
	w = K.setup(1013)
	p = _pair(w, "female", "male")
	WorldIface.add_coins(1, -WorldIface.get_coins(1))
	K.expect(f, ClinicRoute.start(p[0].id, p[1].id)["reason"] == "no_money", "needs the money")
	WorldIface.add_coins(1, 3000)
	var mum := K.make_folk(w, "Mia", [], 1, Vector2i(15, 12))
	mum.sex = "female"
	var son := K.make_folk(w, "Sol", [], 1, Vector2i(16, 12))
	son.sex = "male"
	Aging.set_age_days(mum, 92.0)
	Aging.set_age_days(son, 92.0)
	Family.link_parent(son.id, mum.id)
	K.expect(f, ClinicRoute.start(son.id, mum.id)["reason"] == "not_possible", "RomanceRules still guards the clinic route")
	K.teardown()
