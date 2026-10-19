extends RefCounted
## Toddlers and young children are looked after like babies: a hungry, dirty or tired little one pulls an adult at home, care beats the adult's own whims.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_three_days(f, "toddler", 7)
	_three_days(f, "child", 8)
	_beats_whims(f)
	return f

## A hungry toddler pulls the adult off a whim; with the first adult stuck in something that cannot be interrupted, the second takes over.
func _beats_whims(f: Array) -> void:
	var w := K.setup(9)
	var o: Dictionary = Kit.furnish(w)
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(11, 14))
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 14))
	var kid := _kid(w, "Pip Rowe", "toddler", Vector2i(12, 13))
	var dir = K.director()
	dir.autonomy_enabled = false
	K.set_time(3, 12, 0)
	a.enqueue(Interaction.create("read_book", a, int(o["bookshelf"].id), false))
	K.run(dir, 3)
	(kid.needs["hunger"] as Stat).set_value(-40.0)
	BabyCare.evaluate(10.0)
	var fed: bool = false
	for p in [a, b]:
		if p.current != null and p.current.def_id == "feed_baby":
			fed = true
		for q in p.queue:
			if (q as Interaction).def_id == "feed_baby":
				fed = true
	K.expect(f, fed, "a hungry toddler is fed by a parent, not left to the parent's whim")
	K.teardown()

func _kid(w: StubWorld, name: String, stage: String, tile: Vector2i) -> Folk:
	var k := K.make_folk(w, name, [], 1, tile, stage)
	return k

func _three_days(f: Array, stage: String, seed_value: int) -> void:
	var w := K.setup(seed_value)
	Kit.furnish(w)
	WorldIface.coins[1] = 3000
	var mom := K.make_folk(w, "Mia Rowe", [], 1, Vector2i(11, 14))
	var k1 := _kid(w, "Pip Rowe", stage, Vector2i(12, 13))
	var k2 := _kid(w, "Kit Rowe", stage, Vector2i(13, 13))
	var dir = K.director()
	K.set_time(2, 6, 0)
	var worst: float = 100.0
	for m in 3 * 1440:
		K.run(dir, 1)
		if m % 10 == 0:
			for k in [k1, k2]:
				for n in ["hunger", "bladder", "hygiene", "energy"]:
					worst = minf(worst, (k.needs[n] as Stat).value)
	K.expect(f, worst > -40.0, "%s: needs stayed above 20%% (lowest %.0f)" % [stage, worst])
	K.expect(f, not K.has_note("looked after properly") and not K.has_note("child services"), "%s: no neglect warning" % stage)
	K.expect(f, not K.has_note("faint with hunger"), "%s: nobody faint with hunger" % stage)
	K.teardown()
