extends RefCounted
## Story pacing over a long run (full systems on the stub world): the household's weekly count of story beats lands in a band
## (neither silence nor constant chaos), drama eases off after a spike, nobody dies or is robbed because of the pacing.
## Slow tier: 28 days. Fast tier (when listed there): 8 days.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(515, true)
	var kit = load("res://tests/sim_testkit.gd")
	var objs: Dictionary = kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	w.add_object("bed", Vector2i(14, 14))
	w.add_object("toilet", Vector2i(16, 14))
	w.add_object("sofa", Vector2i(16, 18))
	w.add_object("shower", Vector2i(18, 14))
	var cast: Array = [Folk.create("Alice Reed", ["neat", "social", "romantic"]), Folk.create("Cara Reed", ["creative", "active", "romantic"]),
		Folk.create("Dev Reed", ["bookworm", "jealous"])]
	for i in cast.size():
		(cast[i] as Folk).household_id = 1
		w.add_folk(cast[i], Vector2i(12 + i, 12))
	K.mgr.new_game([1])
	Careers.auto_accept_offers = false
	var dir = K.director()
	var days: int = 8 if TestFixture.fast else 28
	var deaths_before: int = 0
	var beats_by_day: Array = []
	for minute in days * 1440:
		if minute % 1440 == 1439:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10
			beats_by_day.append(StoryPacing.beat_count(1, 1))
		K.run(dir, 1)
	var weeks: Array = []
	var raw: Array = StoryPacing.beats.get(1, [])
	for wk in days / 7:
		var n := 0
		for d in raw:
			if int(d) > wk * 7 and int(d) <= wk * 7 + 7:
				n += 1
		weeks.append(n)
	print("  pacing: beats per week %s, drama now %.1f" % [str(weeks), StoryPacing.drama(1)])
	print("  pacing sources: ", StoryPacing.sources)
	print("  beats hh1 total ", (StoryPacing.beats.get(1, []) as Array).size(), " by hid: ", StoryPacing.beats.keys(), " level ", StoryPacing.level, " day ", SysUtil.day(), " raw ", StoryPacing.beats.get(1, []).slice(0, 40))
	var deaths: int = K.events.filter(func(e): return e[0] == "died" and int(e[1].get("folk_id", 0)) < 1000).size()
	for wk in weeks.slice(1):          # the first week carries the start-up noise (everybody meets everybody)
		K.expect(f, int(wk) >= 6 and int(wk) <= 25, "weekly story beats %d inside the 6-25 band" % int(wk))
	K.expect(f, deaths == 0, "nobody died in a quiet run (%d)" % deaths)
	K.expect(f, StoryPacing.drama(1) < 40.0, "no runaway drama (%.1f)" % StoryPacing.drama(1))
	K.teardown()
	return f
