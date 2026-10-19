extends RefCounted
## Two adults at home, a hungry baby overnight: a parent is woken and the baby is fed before it collapses.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	for seed_value in [5, 6, 7]:
		_night(f, int(seed_value))
	_asleep_parent_is_woken(f)
	return f

## Both parents asleep, the baby just under the hungry line: a parent is pulled out of bed at once, not only once the baby cries.
func _asleep_parent_is_woken(f: Array) -> void:
	var w := K.setup(9)
	Kit.furnish(w)
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(11, 14))
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 14))
	var baby := _make_baby(w, [a, b])
	var dir = K.director()
	K.set_time(3, 2, 0)
	dir.autonomy_enabled = false
	for p in [a, b]:
		p.enqueue(Interaction.create("sleep_bed", p, int(Kit.furnish(w, Vector2i(30, 30))["bed"].id), false))
	K.run(dir, 3)
	var asleep: bool = a.current != null and a.current.def_id == "sleep_bed" or b.current != null and b.current.def_id == "sleep_bed"
	(baby.needs["hunger"] as Stat).set_value(-25.0)
	BabyCare.evaluate(10.0)
	var fed_by: bool = false
	for p2 in [a, b]:
		for q in p2.queue:
			if (q as Interaction).def_id == "feed_baby":
				fed_by = true
		if p2.current != null and p2.current.def_id == "feed_baby":
			fed_by = true
	K.expect(f, asleep, "setup: a parent is asleep")
	K.expect(f, fed_by and not baby.has_buff("crying"), "a parent is sent to feed the baby before it even cries")
	K.teardown()

func _night(f: Array, seed_value: int) -> void:
	var w := K.setup(seed_value)
	Kit.furnish(w)
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(11, 14))
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 14))
	var baby := _make_baby(w, [a, b])
	baby.tile = Vector2i(12, 13)
	var dir = K.director()
	K.set_time(3, 0, 30)
	for p in [a, b]:
		(p.needs["energy"] as Stat).set_value(-40.0)
		(p.needs["hunger"] as Stat).set_value(-50.0)        # the parents are hungry and tired too
	(baby.needs["hunger"] as Stat).set_value(-15.0)
	var woke: bool = false
	var worst: float = 100.0
	for _m in 300:
		K.run(dir, 1)
		worst = minf(worst, (baby.needs["hunger"] as Stat).value)
		for p2 in [a, b]:
			if p2.current != null and p2.current.def_id == "feed_baby":
				woke = true
	K.expect(f, woke, "seed %d: a parent got up to feed the baby" % seed_value)
	K.expect(f, worst > -60.0, "seed %d: the baby never collapsed from hunger (lowest %.0f)" % [seed_value, worst])
	K.expect(f, BabyCare.neglect_minutes(baby.id) < 60.0, "seed %d: no real neglect (%.0f min)" % [seed_value, BabyCare.neglect_minutes(baby.id)])
	K.teardown()

func _make_baby(w: StubWorld, parents: Array) -> Folk:
	var baby := Folk.create("Pip Rowe")
	baby.household_id = 1
	baby.age_stage = "baby"
	w.add_folk(baby, Vector2i(12, 13))
	Aging.register(baby, 0.0, [parents[0].id, parents[1].id])
	Family.on_birth(baby, parents[0].id, parents[1].id)
	Aging.apply_stage_buff(baby)
	return baby
