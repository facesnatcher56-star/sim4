extends RefCounted
## Only grown-ups host gatherings, and only in waking hours; a baby's and toddler's company comes from a parent (BabyCare).

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_who_and_when(f)
	_baby_company(f)
	return f

func _who_and_when(f: Array) -> void:
	var w := K.setup(21)
	Kit.furnish(w)
	var mom := K.make_folk(w, "Mia Rowe", [], 1, Vector2i(11, 14))
	var friend := K.make_folk(w, "Fay Rowe", [], 1, Vector2i(13, 14))
	RelationshipService.add_both(int(mom.id), int(friend.id), "friendship", 60.0)
	var kids: Array = []
	for st in ["baby", "toddler", "child"]:
		var k := K.make_folk(w, "Kit " + st, [], 1, Vector2i(12, 13), st)
		kids.append(k)
	K.set_time(3, 14, 0)
	for k in kids:
		K.expect(f, SocialGatherings.start_gathering(int(k.id)).is_empty(), "a %s never hosts" % k.age_stage)
	K.expect(f, not Interaction.create("host_gathering", kids[1], int(kids[1].id), false) == null and not Interaction.create("host_gathering", kids[1], int(kids[1].id), false).can_run(kids[1]), "a toddler is not offered 'Host a Gathering'")
	K.set_time(3, 5, 0)
	K.expect(f, SocialGatherings.start_gathering(int(mom.id)).is_empty(), "no gathering at 5 in the morning")
	K.set_time(3, 14, 0)
	K.expect(f, not SocialGatherings.start_gathering(int(mom.id)).is_empty(), "an adult hosts in the afternoon")
	K.teardown()

## Two adults at home, a baby and a toddler, a day and a night: their social need is met by cuddles and play, not by events.
func _baby_company(f: Array) -> void:
	var w := K.setup(22)
	Kit.furnish(w)
	WorldIface.coins[1] = 3000
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(11, 14))
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 14))
	var tod := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(12, 13), "toddler")
	var baby := Folk.create("Pip Rowe")
	baby.household_id = 1
	baby.age_stage = "baby"
	w.add_folk(baby, Vector2i(12, 13))
	Aging.register(baby, 0.0, [a.id, b.id])
	Family.on_birth(baby, a.id, b.id)
	Aging.apply_stage_buff(baby)
	var dir = K.director()
	K.set_time(2, 7, 0)
	var worst: float = 100.0
	for m in 1440:
		K.run(dir, 1)
		worst = minf(worst, minf((baby.needs["social"] as Stat).value, (tod.needs["social"] as Stat).value))
	K.expect(f, worst > -40.0, "baby and toddler social stayed above -40 over a day (lowest %.0f)" % worst)
	K.teardown()
