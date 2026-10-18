extends RefCounted
## Autonomy: formula, sleep when exhausted, trait refusals/weights, memory bias, routines, debug breakdown.

const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	var w := Kit.setup()
	_test_formula(f, w)
	_test_sleep_when_exhausted(f, w)
	_test_trait_refusal(f, w)
	_test_trait_weights(f, w)
	_test_memory_bias(f, w)
	_test_memory_from_outcomes(f, w)
	_test_routine(f, w)
	_test_debug(f, w)
	_test_social(f, w)
	Kit.teardown()
	return f

func _fresh_world() -> StubWorld:
	var w := Kit.setup()
	Kit.set_time(1, 15, 0)   # 15:00 - no routine windows active
	return w

func _score_of(folk: Folk, iid: String, obj_def: String = "") -> float:
	for cand in Autonomy.gather(folk):
		if cand["id"] == iid and (obj_def == "" or (cand["obj"] != null and cand["obj"].def_id == obj_def)):
			var r := Autonomy.evaluate(folk, cand)
			if not r["skipped"]:
				return float(r["score"])
	return -9999.0

func _test_formula(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	var folk := Folk.create("Calc")
	w.add_folk(folk, Vector2i(10, 10))
	var fridge := w.add_object("fridge", Vector2i(10, 10))   # slot offset [0,1] -> use tile (10,11), distance 1
	(folk.needs["hunger"] as Stat).set_value(-50)
	folk.update_thresholds()   # -> hungry (autonomy_mult hunger x1.4)
	# urgency(-50) = ((100+50)/200)^2 * 10 = 5.625 ; strength 3.0 ; hungry x1.4 ; distance 1 * 0.15
	var expected := 5.625 * 3.0 * 1.4 - 0.15 * 1.0
	var got := _score_of(folk, "grab_snack", "fridge")
	Kit.expect(f, Kit.near(got, expected, 0.02), "formula: grab_snack score %f != expected %f" % [got, expected])
	# memory multiplier is applied last
	folk.remember("obj:%d" % fridge.id, -0.2)
	var got2 := _score_of(folk, "grab_snack", "fridge")
	Kit.expect(f, Kit.near(got2, expected * 0.8, 0.02), "formula: memory bias scales final score (%f vs %f)" % [got2, expected * 0.8])
	Kit.teardown()

func _test_sleep_when_exhausted(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	Kit.furnish(w)
	var folk := Folk.create("Sleepy")
	w.add_folk(folk, Vector2i(12, 12))
	(folk.needs["energy"] as Stat).set_value(-90)
	folk.update_thresholds()
	var sleeps := 0
	var trials := 40
	for i in trials:
		var c := Autonomy.choose(folk)
		var d: Dictionary = SimEnv.data().interaction_def(str(c.get("interaction_id", "")))
		if (d.get("tags", []) as Array).has("sleep"):
			sleeps += 1
	Kit.expect(f, sleeps == trials, "sleep: exhausted folk picked a sleep interaction %d/%d times" % [sleeps, trials])
	var top: Dictionary = (Autonomy.last_debug[folk.id]["candidates"] as Array)[0]
	Kit.expect(f, top["interaction"] == "sleep_bed", "sleep: top-scored candidate is sleep_bed, was %s" % top["interaction"])
	# a rested folk with the same house does not pick sleep
	var fresh := Folk.create("Fresh")
	w.add_folk(fresh, Vector2i(12, 12))
	(fresh.needs["energy"] as Stat).set_value(95)
	var any_sleep := false
	for i in 20:
		var c2 := Autonomy.choose(fresh)
		if str(c2.get("interaction_id", "")) in ["sleep_bed", "nap_bed", "nap_sofa"]:
			any_sleep = true
	Kit.expect(f, not any_sleep, "sleep: rested folk never chooses to sleep (tests gate it)")
	# bladder emergency picks toilet
	var needy := Folk.create("Needy")
	w.add_folk(needy, Vector2i(12, 12))
	(needy.needs["bladder"] as Stat).set_value(-80)
	needy.update_thresholds()
	var c3 := Autonomy.choose(needy)
	Kit.expect(f, c3.get("interaction_id", "") == "use_toilet", "sleep: bursting bladder -> use_toilet, got %s" % str(c3.get("interaction_id", "")))
	Kit.teardown()

func _test_trait_refusal(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	w.add_object("treadmill", Vector2i(10, 10))
	var normal := Folk.create("Norm")
	var lazy := Folk.create("Lazy", ["lazy"])
	w.add_folk(normal, Vector2i(10, 12))
	w.add_folk(lazy, Vector2i(10, 12))
	var n_ex := 0
	var l_ex := 0
	for i in 30:
		if Autonomy.choose(normal).get("interaction_id", "") == "exercise":
			n_ex += 1
		if Autonomy.choose(lazy).get("interaction_id", "") == "exercise":
			l_ex += 1
	Kit.expect(f, n_ex > 0, "refusal: non-lazy folk exercises when it is the only fun option (%d)" % n_ex)
	Kit.expect(f, l_ex == 0, "refusal: lazy folk refuses exercise (%d picks)" % l_ex)
	var skipped := false
	for r in Autonomy.last_debug[lazy.id]["candidates"]:
		if r["interaction"] == "exercise" and r["skipped"] and "refuses" in str(r["skip_reason"]):
			skipped = true
	Kit.expect(f, skipped, "refusal: debug shows exercise skipped because the trait refuses it")
	# loner refuses flirting
	var a := Folk.create("A", ["loner"])
	var b := Folk.create("B")
	w.add_folk(a, Vector2i(11, 12))
	w.add_folk(b, Vector2i(12, 12))
	a.add_rel(b.id, "friendship", 50)
	var flirted := false
	for i in 30:
		if Autonomy.choose(a).get("interaction_id", "") == "flirt":
			flirted = true
	Kit.expect(f, not flirted, "refusal: loner never flirts")
	Kit.teardown()

func _test_trait_weights(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	Kit.furnish(w)
	var base := Folk.create("Base")
	var glut := Folk.create("Glut", ["glutton"])
	var book := Folk.create("Book", ["bookworm"])
	for p in [base, glut, book]:
		w.add_folk(p, Vector2i(12, 12))
		(p.needs["hunger"] as Stat).set_value(-10)
	var sb := _score_of(base, "grab_snack", "fridge")
	var sg := _score_of(glut, "grab_snack", "fridge")
	Kit.expect(f, sg > sb * 1.5, "weights: glutton values snacks much more (%f vs %f)" % [sg, sb])
	var rb := _score_of(base, "read_book")
	var rw := _score_of(book, "read_book")
	Kit.expect(f, rw > rb * 1.8, "weights: bookworm values reading much more (%f vs %f)" % [rw, rb])
	var tvb := _score_of(base, "watch_tv")
	var tvw := _score_of(book, "watch_tv")
	Kit.expect(f, tvw < tvb, "weights: bookworm dislikes TV (%f vs %f)" % [tvw, tvb])
	# decisions differ in practice: a bored bookworm picks reading most often
	for p in [base, book]:
		(p.needs["fun"] as Stat).set_value(-40)
	var reads := 0
	for i in 30:
		if Autonomy.choose(book).get("interaction_id", "") == "read_book":
			reads += 1
	var top: Dictionary = (Autonomy.last_debug[book.id]["candidates"] as Array)[0]
	Kit.expect(f, top["interaction"] == "read_book" and reads >= 8, "weights: bored bookworm's best option is reading (top=%s, picked %d/30)" % [top["interaction"], reads])
	# cooldown: after finishing, an interaction is not re-chosen for a while
	var shelf = _first_obj(w, "bookshelf")
	var rb2 := Interaction.create("read_book", book, shelf.id)
	rb2.start()
	rb2.finish(true)
	Kit.expect(f, _score_of(book, "read_book") < -1000.0, "cooldown: read_book unavailable right after finishing")
	SimEnv.clock().advance_minutes(125)
	Kit.expect(f, _score_of(book, "read_book") > 0.0, "cooldown: read_book available again after cooldown_min")
	Kit.teardown()

func _test_memory_bias(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	var tv1 := w.add_object("tv", Vector2i(2, 5))
	var tv2 := w.add_object("tv", Vector2i(8, 5))
	var folk := Folk.create("Mem")
	w.add_folk(folk, Vector2i(5, 5))
	(folk.needs["fun"] as Stat).set_value(-60)
	var s1 := 0.0
	var s2 := 0.0
	for cand in Autonomy.gather(folk):
		if cand["id"] != "watch_tv":
			continue
		var r := Autonomy.evaluate(folk, cand)
		if cand["target_id"] == tv1.id:
			s1 = float(r["score"])
		else:
			s2 = float(r["score"])
	Kit.expect(f, Kit.near(s1, s2, 0.001) and s1 > 0.0, "memory: symmetric TVs score the same without memory (%f / %f)" % [s1, s2])
	folk.remember("obj:%d" % tv1.id, -0.4)
	Kit.expect(f, Kit.near(folk.memory_bias("obj:%d" % tv1.id), -0.4, 0.001), "memory: bias recorded")
	var n1 := 0
	var n2 := 0
	for cand in Autonomy.gather(folk):
		if cand["id"] == "watch_tv":
			var r2 := Autonomy.evaluate(folk, cand)
			if cand["target_id"] == tv1.id:
				n1 = int(round(float(r2["score"]) * 1000.0))
			else:
				n2 = int(round(float(r2["score"]) * 1000.0))
	Kit.expect(f, n1 > 0 and Kit.near(float(n1) / float(n2), 0.6, 0.01), "memory: bad memory cuts score to 60%% (ratio %f)" % (float(n1) / float(max(n2, 1))))
	# choose() prefers the good TV
	var picks_good := 0
	for i in 40:
		var c := Autonomy.choose(folk)
		if c.get("interaction_id", "") == "watch_tv" and c["target_id"] == tv2.id:
			picks_good += 1
	var picks_bad := 0
	for i in 40:
		var c2 := Autonomy.choose(folk)
		if c2.get("interaction_id", "") == "watch_tv" and c2["target_id"] == tv1.id:
			picks_bad += 1
	Kit.expect(f, picks_good > picks_bad, "memory: remembered-bad TV picked less often (%d vs %d)" % [picks_bad, picks_good])
	# clamp
	for i in 10:
		folk.remember("obj:%d" % tv1.id, -0.4)
	Kit.expect(f, folk.memory_bias("obj:%d" % tv1.id) >= -0.5 - 0.0001, "memory: bias clamped to -0.5")
	for i in 10:
		folk.remember("obj:%d" % tv2.id, 0.4)
	Kit.expect(f, folk.memory_bias("obj:%d" % tv2.id) <= 0.5 + 0.0001, "memory: bias clamped to +0.5")
	# decays over days
	folk.remember("obj:999", -0.4)
	var before := folk.memory_bias("obj:999")
	SimEnv.clock().advance_minutes(1440 * 2)
	var mid := folk.memory_bias("obj:999")
	SimEnv.clock().advance_minutes(1440 * 6)
	var later := folk.memory_bias("obj:999")
	Kit.expect(f, absf(mid) < absf(before) and absf(later) < 0.05, "memory: bias decays over days (%f -> %f -> %f)" % [before, mid, later])
	folk.prune_memory()
	Kit.expect(f, folk.memory.size() < 21, "memory: prune drops faded entries")
	Kit.teardown()

func _test_memory_from_outcomes(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	var folk := Folk.create("Out")
	w.add_folk(folk, Vector2i(5, 5))
	var tm := w.add_object("treadmill", Vector2i(5, 5))
	# interruption
	var ir := Interaction.create("exercise", folk, tm.id)
	ir.start()
	ir.tick(3.0)
	ir.cancel("interrupted")
	var after_int := folk.memory_bias("obj:%d" % tm.id)
	Kit.expect(f, after_int < 0.0, "outcome memory: interruption lowers preference (%f)" % after_int)
	# a negative buff caused during an interaction is remembered
	var tv := w.add_object("tv", Vector2i(9, 9))
	var ir2 := Interaction.create("watch_tv", folk, tv.id)
	ir2.start()
	folk.add_buff("embarrassed", true)   # caused by this interaction, negative mood
	ir2.finish(true)
	Kit.expect(f, folk.memory_bias("obj:%d" % tv.id) < 0.0, "outcome memory: negative buff during interaction makes it less attractive")
	# object broke on finish (chance 1.0 variant)
	var tm2 := w.add_object("treadmill", Vector2i(7, 9))
	var ir3 := Interaction.create("exercise", folk, tm2.id)
	ir3.start()
	tm2.state["broken"] = true
	ir3.finish(true)
	Kit.expect(f, folk.memory_bias("obj:%d" % tm2.id) <= -0.35, "outcome memory: breaking an object is strongly negative")
	Kit.teardown()

func _test_routine(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	Kit.furnish(w)
	var folk := Folk.create("Worker")
	w.add_folk(folk, Vector2i(10, 12))
	folk.work_start = 9.5
	folk.work_end = 17.5
	Kit.set_time(2, 7, 30)
	var shower_ev := _eval(folk, "take_shower")
	Kit.expect(f, float(shower_ev["sub"]["routine_bonus"]) > 3.0, "routine: shower boosted before work (bonus %s)" % str(shower_ev["sub"]["routine_bonus"]))
	Kit.expect(f, "getting ready for work" in str(shower_ev["reason"]), "routine: reason mentions the routine")
	var tv_ev := _eval(folk, "watch_tv")
	Kit.expect(f, float(tv_ev["sub"]["routine_bonus"]) == 0.0, "routine: unrelated interaction unboosted")
	Kit.set_time(2, 14, 0)
	var later := _eval(folk, "take_shower")
	Kit.expect(f, float(later["sub"]["routine_bonus"]) == 0.0, "routine: no boost at 14:00")
	# job-less folk gets only the milder morning routine
	Kit.set_time(2, 7, 30)
	var lazybones := Folk.create("NoJob")
	w.add_folk(lazybones, Vector2i(10, 12))
	var nj := _eval(lazybones, "take_shower")
	Kit.expect(f, float(nj["sub"]["routine_bonus"]) < float(shower_ev["sub"]["routine_bonus"]), "routine: job-holder prepares harder than job-less folk")
	# "once": after showering, no further boost the same day
	var bath := Interaction.create("take_shower", folk, _first_obj(w, "shower").id)
	bath.start()
	bath.finish(true)
	folk.remove_buff("fresh")
	var again := _eval(folk, "take_shower")
	Kit.expect(f, float(again["sub"]["routine_bonus"]) == 0.0, "routine: 'once' routine does not re-boost a finished interaction")
	# end-to-end: a worker with decent needs picks a "prepare" interaction in the morning
	var runner := Folk.create("Early")
	w.add_folk(runner, Vector2i(10, 12))
	runner.work_start = 9.0
	Kit.set_time(3, 7, 0)
	var prepared := 0
	for i in 30:
		var c := Autonomy.choose(runner)
		var d: Dictionary = SimEnv.data().interaction_def(str(c.get("interaction_id", "")))
		if (d.get("tags", []) as Array).has("prepare") or (d.get("tags", []) as Array).has("food"):
			prepared += 1
	Kit.expect(f, prepared >= 20, "routine: working folk pick get-ready actions in the morning (%d/30)" % prepared)
	# night routine favours sleeping
	Kit.set_time(3, 23, 0)
	var night := Folk.create("Night")
	w.add_folk(night, Vector2i(10, 12))
	(night.needs["energy"] as Stat).set_value(30)
	var s_night := _eval(night, "sleep_bed")
	Kit.set_time(3, 15, 0)
	var s_day := _eval(night, "sleep_bed")
	Kit.expect(f, float(s_night["score"]) > float(s_day["score"]) * 1.5, "routine: sleep preferred at night (%f vs %f)" % [float(s_night["score"]), float(s_day["score"])])
	Kit.teardown()

func _first_obj(w: StubWorld, def_id: String):
	for o in w.objects.values():
		if o.def_id == def_id:
			return o
	return null

func _eval(folk: Folk, iid: String) -> Dictionary:
	for cand in Autonomy.gather(folk):
		if cand["id"] == iid:
			var r := Autonomy.evaluate(folk, cand)
			if not r["skipped"]:
				return r
	return {"score": -1.0, "sub": {"routine_bonus": -1.0}, "reason": ""}

func _test_debug(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	Kit.furnish(w)
	var folk := Folk.create("Dbg", ["neat"])
	w.add_folk(folk, Vector2i(12, 12))
	(folk.needs["hygiene"] as Stat).set_value(-70)
	folk.update_thresholds()
	var c := Autonomy.choose(folk)
	Kit.expect(f, Autonomy.last_debug.has(folk.id), "debug: last_debug[folk_id] populated")
	var dbg: Dictionary = Autonomy.last_debug[folk.id]
	var cands: Array = dbg["candidates"]
	Kit.expect(f, cands.size() > 15, "debug: lists every candidate (%d)" % cands.size())
	var with_sub := 0
	for r in cands:
		if not r["skipped"] and r["sub"].has("base") and r["sub"].has("memory_bias") and r["sub"].has("distance_penalty"):
			with_sub += 1
	Kit.expect(f, with_sub > 3, "debug: scored candidates carry sub-scores")
	Kit.expect(f, str(dbg["reason"]) != "" and str(c.get("reason", "")) == str(dbg["reason"]), "debug: reason string recorded and returned")
	Kit.expect(f, "Hygiene" in str(dbg["reason"]) or "hygiene" in str(dbg["reason"]), "debug: reason names the driving need (%s)" % str(dbg["reason"]))
	var skipped := 0
	for r in cands:
		if r["skipped"] and str(r["skip_reason"]) != "":
			skipped += 1
	Kit.expect(f, skipped > 0, "debug: skipped candidates carry a skip reason")
	Kit.teardown()

func _test_social(f: Array, _w0: StubWorld) -> void:
	var w := _fresh_world()
	var a := Folk.create("A", ["social"])
	var b := Folk.create("B")
	w.add_folk(a, Vector2i(5, 5))
	w.add_folk(b, Vector2i(6, 5))
	(a.needs["social"] as Stat).set_value(-60)
	var seen := {}
	for i in 30:
		var c := Autonomy.choose(a)
		seen[c.get("interaction_id", "")] = c.get("target_id", -1)
	Kit.expect(f, seen.has("chat") or seen.has("tell_joke") or seen.has("compliment"), "social: lonely folk seeks out another folk (%s)" % str(seen.keys()))
	for k in seen:
		if k in ["chat", "tell_joke", "compliment"]:
			Kit.expect(f, seen[k] == b.id, "social: target is the other folk")
	Kit.expect(f, not seen.has("flirt") and not seen.has("insult"), "social: flirt gated by friendship, insult by trait/mood")
	# run a chat and check both sides and relationship
	var ir := Interaction.create("chat", a, b.id)
	Kit.expect(f, ir.can_run(a), "social: chat can run")
	ir.start()
	var b0: float = (b.needs["social"] as Stat).value
	for i in 40:
		if a.current == null:
			break
		ir.tick(1.0)
	Kit.expect(f, (b.needs["social"] as Stat).value > b0 + 10.0, "social: target_per_min raised partner's social")
	Kit.expect(f, a.get_rel(b.id, "friendship") >= 3.0 and b.get_rel(a.id, "friendship") >= 3.0, "social: friendship grew both ways")
	# a sleeping partner is not a valid target
	b.posture = "lie"
	Kit.expect(f, not Interaction.create("chat", a, b.id).can_run(a), "social: cannot chat with someone lying down")
	Kit.teardown()
