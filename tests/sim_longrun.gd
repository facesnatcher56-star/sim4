extends RefCounted
## 3-day headless simulation of 3 folk on the stub world. They must stay alive and keep doing things.

const Kit = preload("res://tests/sim_testkit.gd")
const DAYS := 3

func run() -> Array:
	var f: Array = []
	var w := Kit.setup(777)
	var objs := Kit.furnish(w)
	# one bed each, second toilet for flow
	w.add_object("bed", Vector2i(2, 4) + Vector2i(10, 10))
	w.add_object("bed", Vector2i(4, 4) + Vector2i(10, 10) - Vector2i(0, 2))
	w.add_object("toilet", Vector2i(16, 14))
	var alice := Folk.create("Alice", ["neat", "social"])
	var bob := Folk.create("Bob", ["lazy", "gamer"])
	var cara := Folk.create("Cara", ["creative", "active", "romantic"])
	alice.work_start = 9.0
	alice.work_end = 17.0
	var start_tiles := [Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12)]
	var folks := [alice, bob, cara]
	for i in 3:
		w.add_folk(folks[i], start_tiles[i])
	var dir = Kit.director()
	# bookkeeping
	var min_need: Dictionary = {}
	var sum_mood: Dictionary = {}
	var mood_counts: Dictionary = {}
	for p in folks:
		min_need[p.id] = {}
		mood_counts[p.id] = {}
	var cnt := {"fin": 0, "acc": 0, "pass": 0}
	SimEnv.events().interaction_finished.connect(func(_i, d, _s):
		cnt["fin"] += 1
		if d == "have_accident":
			cnt["acc"] += 1
		if d == "pass_out":
			cnt["pass"] += 1)
	var total := DAYS * 1440
	var t0 := Time.get_ticks_msec()
	for minute in total:
		SimEnv.clock().advance_minutes(1)
		if minute % 1440 == 1439:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10   # groceries arrive nightly
		dir.tick_minute(1)
		for p in folks:
			for n in p.needs:
				var v: float = (p.needs[n] as Stat).value
				var mn: Dictionary = min_need[p.id]
				if not mn.has(n) or v < float(mn[n]):
					mn[n] = v
			var mc: Dictionary = mood_counts[p.id]
			mc[p.mood_name] = int(mc.get(p.mood_name, 0)) + 1
	var ms := Time.get_ticks_msec() - t0
	var accidents: int = cnt["acc"]
	var passouts: int = cnt["pass"]
	var fin_events: int = cnt["fin"]
	print("")
	print("  3-day simulation: %d game minutes in %d ms real, %d interactions finished, %d accidents, %d pass-outs" % [total, ms, fin_events, accidents, passouts])
	for p in folks:
		var mn: Dictionary = min_need[p.id]
		var parts: Array = []
		for n in ["hunger", "energy", "bladder", "hygiene", "social", "fun"]:
			parts.append("%s %.0f" % [n, float(mn[n])])
		print("  %-6s traits=%s  min needs: %s" % [p.name, str(p.traits), ", ".join(parts)])
		var top: Array = []
		var keys: Array = p.history_counts.keys()
		keys.sort_custom(func(a, b): return int(p.history_counts[a]) > int(p.history_counts[b]))
		for k in keys.slice(0, 7):
			top.append("%s x%d" % [k, int(p.history_counts[k])])
		print("         top actions: " + ", ".join(top))
		var mcs: Dictionary = mood_counts[p.id]
		var mparts: Array = []
		for m in mcs:
			mparts.append("%s %d%%" % [m, int(100.0 * float(mcs[m]) / float(total))])
		print("         mood time: " + ", ".join(mparts))
		print("         skills: " + str(_skill_levels(p)) + "  final mood: %s(%d)  coins(household): %d" % [p.mood_name, p.mood_intensity, WorldIface.get_coins(p.household_id)])
		# assertions
		Kit.expect(f, float(mn["hunger"]) > -95.0, "%s nearly starved: min hunger %.1f" % [p.name, float(mn["hunger"])])
		Kit.expect(f, float(mn["energy"]) > -99.0, "%s hit the energy floor: %.1f" % [p.name, float(mn["energy"])])
		Kit.expect(f, float(mn["hygiene"]) > -95.0, "%s became unbearably dirty: %.1f" % [p.name, float(mn["hygiene"])])
		Kit.expect(f, float(mn["bladder"]) > -99.0, "%s had a bladder emergency: %.1f" % [p.name, float(mn["bladder"])])
		var done := 0
		for k in p.history_counts:
			done += int(p.history_counts[k])
		Kit.expect(f, done >= 20, "%s only completed %d interactions in 3 days" % [p.name, done])
		Kit.expect(f, int(p.history_counts.get("sleep_bed", 0)) + int(p.history_counts.get("nap_bed", 0)) >= 2, "%s never slept in a bed" % p.name)
		Kit.expect(f, int(p.history_counts.get("use_toilet", 0)) >= 3, "%s rarely used the toilet" % p.name)
		var ate := int(p.history_counts.get("eat_meal", 0)) + int(p.history_counts.get("grab_snack", 0))
		Kit.expect(f, ate >= 3, "%s hardly ate (%d)" % [p.name, ate])
	Kit.expect(f, accidents <= 2, "too many bladder accidents: %d" % accidents)
	Kit.expect(f, passouts == 0, "folk passed out %d times" % passouts)
	# traits changed behaviour: lazy Bob never exercised
	Kit.expect(f, int(bob.history_counts.get("exercise", 0)) == 0, "lazy Bob should never exercise")
	# no leaked reservations at the end beyond the folk's current interactions
	var held := 0
	for o in w.objects.values():
		held += o.slots_reserved.size()
	var running := 0
	for p in folks:
		if p.current != null and p.current.slot_idx >= 0:
			running += 1
	Kit.expect(f, held == running, "reservation leak: %d held vs %d running" % [held, running])
	dir.free()
	Kit.teardown()
	return f

func _skill_levels(p: Folk) -> String:
	var parts: Array = []
	for s in p.skills:
		if int(p.skills[s]["level"]) > 0 or float(p.skills[s]["xp"]) > 0.0:
			parts.append("%s L%d(%.0fxp)" % [s, int(p.skills[s]["level"]), float(p.skills[s]["xp"])])
	return ", ".join(parts)
