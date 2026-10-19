extends RefCounted
## A short full-systems run of a mixed household (parents, teen, child, adult siblings, an unrelated adult) plus the townies: nothing romantic,
## intimate, flirty or cheating ever involves a minor or a relative (the long version is romance_longrun_test.gd).

const K = preload("res://tests/systems_kit.gd")
const Probe = preload("res://tests/romance_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(101, true)
	var kit = load("res://tests/sim_testkit.gd")
	var objs: Dictionary = kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	w.add_object("bed", Vector2i(14, 14))
	w.add_object("toilet", Vector2i(16, 14))
	w.add_object("sofa", Vector2i(16, 18))
	var cast: Array = []
	for spec in [["Mum", "adult", ["romantic", "flirty"]], ["Dad", "adult", ["romantic"]], ["Teen", "teen", ["flirty"]], ["Kid", "child", []],
			["Aunt", "adult", ["flirty", "romantic"]], ["Sis", "adult", ["flirty", "romantic"]], ["Bro", "adult", ["romantic"]]]:
		var fk := Folk.create(spec[0], spec[2])
		fk.household_id = 1
		fk.age_stage = spec[1]
		cast.append(fk)
		w.add_folk(fk, Vector2i(10 + cast.size(), 12))
		Aging.register(fk)
	K.mgr.new_game([1])
	for i in [2, 3, 5]:                  # the parents' children and siblings
		Family.link_parent(cast[i].id, cast[0].id)
		Family.link_parent(cast[i].id, cast[1].id)
	Family.link_parent(cast[4].id, cast[0].id)
	Family.link_parent(cast[4].id, cast[1].id)      # both parents: with only the mother linked, Dad and Aunt were strangers until Mum and Dad paired up (a step relation formed AFTER the romance)
	Careers.auto_accept_offers = false
	for a in cast:                       # everyone knows everyone: the kind of household where trouble would start
		for b in cast:
			if a != b:
				RelationshipService.add_value(a.id, b.id, "friendship", 45.0)
	var probe = Probe.new()
	probe.start()
	var dir = K.director()
	var days: int = 2
	for minute in days * 1440:
		if minute % 1440 == 1439:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10
		K.run(dir, 1)
		if minute % 60 == 59:
			probe.scan(cast)
	print("  romance run: %d romantic runs, %d romance events, %d violations" % [probe.romantic_runs, probe.events_seen, probe.violations.size()])
	for v in probe.violations.slice(0, 8):
		f.append("forbidden romance: " + str(v))
	K.teardown()
	return f
