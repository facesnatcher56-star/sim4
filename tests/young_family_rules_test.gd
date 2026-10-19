extends RefCounted
## A baby's family name is never a parent's first name; nobody young can move out on their own.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_names(f)
	_move_out(f)
	return f

func _baby_of(w: StubWorld, mom, dad) -> Folk:
	Aging._birth(int(mom.id), int(dad.id))
	var kids: Array = Aging.children_of(int(mom.id))
	return SysUtil.folk(int(kids[kids.size() - 1]))

func _names(f: Array) -> void:
	var w := K.setup(31)
	var mom := K.make_folk(w, "Madrina", [], 1)
	var dad := K.make_folk(w, "Kenneth", [], 1, Vector2i(14, 12))
	Aging.house_names[1] = "Fernwood"
	var b := _baby_of(w, mom, dad)
	K.expect(f, b != null and str(b.name).ends_with(" Fernwood") and str(b.name).find("Madrina") < 0, "no surnames: the baby takes the household name (%s)" % str(b.name))
	Aging.house_names.clear()
	var b2 := _baby_of(w, mom, dad)
	K.expect(f, b2 != null and str(b2.name).find(" ") < 0, "no surnames and no household name: a first name only (%s)" % str(b2.name))
	K.teardown()
	var w2 := K.setup(32)
	var m2 := K.make_folk(w2, "Mina Okoro", [], 1)
	var d2 := K.make_folk(w2, "Dev Tran", [], 1, Vector2i(14, 12))
	var b3 := _baby_of(w2, m2, d2)
	K.expect(f, b3 != null and str(b3.name).ends_with(" Okoro"), "surnamed parents: the mother's surname (%s)" % str(b3.name))
	var b3r: bool = PregnancyNaming.rename(int(b3.id), "Rae")
	K.expect(f, b3r and str(b3.name) == "Rae Okoro", "renaming keeps the surname")
	K.teardown()

func _move_out(f: Array) -> void:
	var w := K.setup(33)
	Kit.furnish(w)
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(11, 14))
	var tod := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(12, 13), "toddler")
	var baby := K.make_folk(w, "Pip Rowe", [], 1, Vector2i(12, 14), "baby")
	var child := K.make_folk(w, "Cy Rowe", [], 1, Vector2i(13, 14), "child")
	for k in [tod, baby, child]:
		K.expect(f, not FamilyHousehold.move_out(int(k.id)), "a %s cannot move out on their own" % k.age_stage)
		K.expect(f, SysUtil.folk(int(k.id)) != null and int(k.household_id) == 1, "and is still at home")
	K.expect(f, FamilyHousehold.move_out(int(baby.id), 0.0, true), "child services can still take a neglected baby (orphan)")
	var dir = K.director()
	dir.autonomy_enabled = false
	for d in 30:
		K.set_time(2 + d, 8)
		K.run(dir, 5)
	K.expect(f, SysUtil.folk(int(tod.id)) != null and SysUtil.is_resident(SysUtil.folk(int(tod.id))), "the toddler is still at home after 30 days")
	K.teardown()
