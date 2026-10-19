extends RefCounted
## Not a test (no _test suffix: not discovered by run_all): how often do children of two parents without crime traits end up with one? 60 babies inherit traits at birth and grow through
## every stage (toddler, child, teen, adult), exactly the game's trait picks. Prints the counts per crime trait and the trait table size.
##   powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless,--path,.,--script,res://tests/run_one.gd,--,trait_pick_probe"

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var w := K.setup()
	SysContent.install_all()
	CrimeFlow.reset()
	CrimeFlow.install()
	var pa := K.make_folk(w, "Pa", ["neat", "active", "social", "bookworm"], 1)
	var pb := K.make_folk(w, "Ma", ["honest", "foodie", "musical", "outdoorsy"], 1)
	Aging.register(pa, 30.0 * 4.0)
	Aging.register(pb, 30.0 * 4.0)
	var counts: Dictionary = {}
	var total := 0
	var with_crime := 0
	for i in 60:
		var inh: Array = Genetics.inherit_traits(pa, pb, null, {"chance": 0.35, "cap": 2})
		var baby := Folk.create("Kid%d" % i, [])
		baby.household_id = 1
		baby.age_stage = "baby"
		w.add_folk(baby, Vector2i(10, 10))
		Aging.register(baby, 0.0, [int(pa.id), int(pb.id)])
		(Aging.records[int(baby.id)] as Dictionary)["inherited"] = inh
		for st in ["toddler", "child", "teen", "adult"]:
			Aging._age_up(baby, st)
		total += 1
		var any := false
		for t in baby.traits:
			if str(t) in ["dishonest", "kleptomaniac", "vengeful", "reckless"]:
				counts[t] = int(counts.get(t, 0)) + 1
				any = true
		if any:
			with_crime += 1
	print("TRAITS table=%d kids=%d with a crime trait=%d per trait=%s" % [SimEnv.data().traits().size(), total, with_crime, str(counts)])
	K.teardown()
	return []
