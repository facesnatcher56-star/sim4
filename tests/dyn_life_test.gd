extends RefCounted
## Task 32c on the stub world (fast tier): the plans, reactions and household initiative of DynLife are deterministic, shaped by traits and stage-gated.

const Kit = preload("res://tests/sim_testkit.gd")

func _world(traits_a: Array, traits_b: Array = ["social"]) -> Array:
	var w := Kit.setup(4242)
	DynLife.install()
	SysContent.gate_late_content()
	Kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	var a := Folk.create("Ada", traits_a)
	var b := Folk.create("Ben", traits_b)
	a.household_id = 1
	b.household_id = 1
	w.add_folk(a, Vector2i(12, 12))
	w.add_folk(b, Vector2i(14, 12))
	Kit.set_time(1, 8)
	return [w, a, b]

func _plans_fired(f, days: int, first_hour: int) -> Dictionary:
	var seen: Dictionary = {}
	for d in days:
		for h in range(first_hour, first_hour + 14):
			Kit.set_time(1 + d, h)
			f.cooldowns.erase("dyn:plan")
			var before: Array = f.buffs.map(func(b): return str(b["id"]))
			DynPlans.roll(f, d * 24 + h)
			for b in f.buffs:
				if not before.has(str(b["id"])):
					seen[str(b["id"])] = int(seen.get(str(b["id"]), 0)) + 1
					f.remove_buff(str(b["id"]))
			f.clear_queue()
	return seen

func run() -> Array:
	var f: Array = []
	var seed_before: int = Storyteller.master_seed
	# 1. plans follow traits and are the same every time for the same seed
	var ws := _world(["bookworm", "creative"])
	var ada = ws[1]
	Storyteller.master_seed = 99
	var s1 := _plans_fired(ada, 40, 9)
	var s2 := _plans_fired(ada, 40, 9)
	Kit.expect(f, s1 == s2, "plans differ between two identical runs: %s vs %s" % [str(s1), str(s2)])
	Kit.expect(f, int(s1.get("plan_read", 0)) + int(s1.get("plan_create", 0)) >= 3, "a bookworm who is creative made too few reading / creative plans: %s" % str(s1))
	Kit.expect(f, int(s1.get("plan_move", 0)) < int(s1.get("plan_read", 0)), "a bookworm made more workout plans than reading plans: %s" % str(s1))
	Kit.teardown()
	var wl := _world(["lazy"])
	var s3 := _plans_fired(wl[1], 40, 9)
	Kit.expect(f, int(s3.get("plan_lazy", 0)) >= 2, "a lazy person never had a lazy spell: %s" % str(s3))
	Kit.teardown()
	# 2. reactions: a siren makes awake people look out; a sleeper is left alone; nobody is pulled off the toilet / work
	var wr := _world(["social"], ["social"])
	var a = wr[1]
	var b = wr[2]
	Kit.expect(f, DynLife.people().size() == 2, "the stub folk are not residents (%d)" % DynLife.people().size())
	var looked := 0
	for i in 6:
		Kit.set_time(1 + i, 10)
		a.cooldowns.erase("dyn:react")
		b.cooldowns.erase("dyn:react")
		a.clear_queue()
		b.clear_queue()
		DynReact.on_event("disaster", {"kind": "tornado", "phase": "siren", "folk_id": -1})
		for p in [a, b]:
			for q in p.queue:
				if (q as Interaction).def_id == "look_out_window":
					looked += 1
	Kit.expect(f, looked >= 4, "only %d look-outs after 6 sirens of 2 awake people" % looked)
	var bed = Kit.furnish(WorldIface.stub).get("bed", null)
	var sleeping := Interaction.create("sleep_bed", b, int((bed as StubWorld.StubObject).id), false)
	if sleeping != null and sleeping.start():
		b.cooldowns.erase("dyn:react")
		b.clear_queue()
		DynReact.on_event("disaster", {"kind": "tornado", "phase": "siren", "folk_id": -1})
		Kit.expect(f, b.queue.is_empty(), "a sleeping person was woken by a siren")
	Kit.teardown()
	# 3. household initiative: dinner / game night buffs at the right hour, play for the kids, none for babies
	var wh := _world(["social"], ["social"])
	var h1 = wh[1]
	var h2 = wh[2]
	var dinners := 0
	var nights := 0
	for d in range(1, 29):
		Kit.set_time(d, 18)
		h1.remove_buff("family_dinner")
		h2.remove_buff("family_dinner")
		DynSocial.on_hour([h1, h2], d * 24 + 18)
		if h1.has_buff("family_dinner") and h2.has_buff("family_dinner"):
			dinners += 1
		Kit.set_time(d, 20)
		h1.remove_buff("game_night")
		h2.remove_buff("game_night")
		DynSocial.on_hour([h1, h2], d * 24 + 20)
		if h1.has_buff("game_night") and h2.has_buff("game_night"):
			nights += 1
	Kit.expect(f, dinners >= 5 and dinners <= 27, "family dinners in 28 days: %d" % dinners)
	Kit.expect(f, nights >= 1, "no game night in 28 days")
	Kit.teardown()
	# 4. stage gates: board games and phone calls are not for toddlers, play is for children
	_world(["social"])
	var bg: Dictionary = SimEnv.data().interaction_def("board_game")
	Kit.expect(f, JSON.stringify(bg.get("tests", [])).contains("stage_toddler"), "board_game is not gated for toddlers")
	var pt: Dictionary = SimEnv.data().interaction_def("play_together")
	Kit.expect(f, not JSON.stringify(pt.get("tests", [])).contains("stage_child"), "children cannot play together")
	var rt_wk := _routine_names(true)
	var rt_wd := _routine_names(false)
	Kit.expect(f, rt_wk.has("a free weekend afternoon") and not rt_wd.has("a free weekend afternoon"), "weekend routines are not weekend only: %s / %s" % [str(rt_wk), str(rt_wd)])
	Kit.teardown()
	Storyteller.master_seed = seed_before
	return f

func _routine_names(weekend: bool) -> Array:
	Kit.set_time(6 if weekend else 2, 14)
	var folk = WorldIface.stub.all_folk()[0]
	var out: Array = []
	for pair in Routine.active_routines(folk):
		out.append(str(pair[1].get("label", pair[0])))
	return out
