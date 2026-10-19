extends RefCounted
## Interaction lifecycle, reservation, queue priority, cancel handling.

const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	var w := Kit.setup()
	_test_tests_and_run(f, w)
	_test_reservation(f, w)
	_test_per_min_and_outcome(f, w)
	_test_queue_priority(f, w)
	_test_cancel(f, w)
	_test_broken_cancels(f, w)
	_test_unknown_and_unreachable(f, w)
	Kit.teardown()
	return f

func _run_to_end(folk: Folk, max_min: int = 1000) -> int:
	var n := 0
	while folk.current != null and n < max_min:
		folk.current.tick(1.0)
		n += 1
	return n

func _test_tests_and_run(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("Sleeper")
	w.add_folk(folk, Vector2i(2, 2))
	var bed := w.add_object("bed", Vector2i(6, 2))
	var ir := Interaction.create("sleep_bed", folk, bed.id)
	Kit.set_time(1, 14)
	(folk.needs["energy"] as Stat).set_value(80)
	Kit.expect(f, not ir.can_run(folk, bed), "interaction: sleep_bed refused at 80 energy in the daytime")
	(folk.needs["energy"] as Stat).set_value(20)
	Kit.expect(f, ir.can_run(folk, bed), "interaction: sleep_bed runs at energy 20")
	var started: Array = []
	var finished: Array = []
	SimEnv.events().interaction_started.connect(func(i, d, t): started.append([i, d, t]))
	SimEnv.events().interaction_finished.connect(func(i, d, s): finished.append([i, d, s]))
	Kit.expect(f, ir.start(), "interaction: start ok")
	Kit.expect(f, ir.state == "walking" and folk.current == ir, "interaction: walking first (state %s)" % ir.state)
	Kit.expect(f, bed.slots_reserved.size() == 1, "interaction: slot reserved on start")
	Kit.expect(f, started.size() == 1 and started[0][1] == "sleep_bed" and started[0][2] == bed.id, "interaction: interaction_started emitted")
	var mins := _run_to_end(folk)
	Kit.expect(f, ir.state == "finished" and ir.success, "interaction: finished successfully")
	var energy: float = (folk.needs["energy"] as Stat).value
	Kit.expect(f, energy > 60.0, "interaction: sleep restored energy (%f)" % energy)
	Kit.expect(f, mins < 540, "interaction: end_when ended sleep early (%d min)" % mins)
	Kit.expect(f, folk.has_buff("well_rested"), "interaction: on_finish added well_rested")
	Kit.expect(f, bed.slots_reserved.is_empty(), "interaction: slot released on finish")
	Kit.expect(f, not bool(bed.state["made"]), "interaction: object_state_set made=false")
	Kit.expect(f, finished.size() == 1 and finished[0][2] == true, "interaction: interaction_finished(success) emitted")
	Kit.expect(f, folk.posture == "stand" and folk.current == null, "interaction: posture reset")
	Kit.expect(f, folk.tile == WorldIface.use_tile(bed, 0), "interaction: folk walked to the slot tile")

func _test_reservation(f: Array, w: StubWorld) -> void:
	var a := Folk.create("A")
	var b := Folk.create("B")
	w.add_folk(a, Vector2i(0, 0))
	w.add_folk(b, Vector2i(0, 1))
	var toilet := w.add_object("toilet", Vector2i(10, 10))
	(a.needs["bladder"] as Stat).set_value(-50)
	(b.needs["bladder"] as Stat).set_value(-50)
	var ia := Interaction.create("use_toilet", a, toilet.id)
	var ib := Interaction.create("use_toilet", b, toilet.id)
	Kit.expect(f, ia.start(), "reserve: A starts")
	Kit.expect(f, not ib.can_run(b, toilet), "reserve: B cannot run while the only slot is reserved")
	Kit.expect(f, not ib.start(), "reserve: B start refused")
	_run_to_end(a)
	var ib2 := Interaction.create("use_toilet", b, toilet.id)
	Kit.expect(f, ib2.can_run(b, toilet), "reserve: B can run after A is done")
	# Two-slot sofa lets both sit at once.
	var sofa := w.add_object("sofa", Vector2i(20, 20))
	Kit.expect(f, Interaction.create("sit_sofa", a, sofa.id).start(), "reserve: sofa slot 0")
	Kit.expect(f, Interaction.create("sit_sofa", b, sofa.id).start(), "reserve: sofa slot 1")
	Kit.expect(f, sofa.slots_reserved.size() == 2, "reserve: both sofa slots held")
	a.cancel_current("player")
	b.cancel_current("player")
	Kit.expect(f, sofa.slots_reserved.is_empty(), "reserve: cancel releases")

func _test_per_min_and_outcome(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("Eater")
	w.add_folk(folk, Vector2i(30, 31))   # already standing on the use tile -> no walking phase
	var fridge := w.add_object("fridge", Vector2i(30, 30))
	(folk.needs["hunger"] as Stat).set_value(-40)
	var ir := Interaction.create("grab_snack", folk, fridge.id)
	Kit.expect(f, ir.start(), "snack: start")
	# stat decay continues independently; measure only the interaction contribution through per_min
	var h0: float = (folk.needs["hunger"] as Stat).value
	var n := 0
	while ir.state == "walking" and n < 50:
		ir.tick(1.0)
		n += 1
	ir.tick(2.0)
	var h1: float = (folk.needs["hunger"] as Stat).value
	Kit.expect(f, Kit.near(h1 - h0, 12.0, 0.01), "snack: per_min hunger +6/min * 2 = +12, got %f" % (h1 - h0))
	_run_to_end(folk)
	Kit.expect(f, int(fridge.state["stock"]) == 9, "snack: consumed 1 stock (loot object_state_add), stock=%s" % str(fridge.state["stock"]))
	Kit.expect(f, folk.history_counts.get("grab_snack", 0) == 1, "snack: history_counts updated")
	Kit.expect(f, folk.memory_bias("obj:%d" % fridge.id) > 0.0, "snack: success remembered positively")
	# test fails when stock empty
	fridge.state["stock"] = 0
	Kit.expect(f, not Interaction.create("grab_snack", folk, fridge.id).can_run(folk, fridge), "snack: no stock -> cannot run")

func _test_queue_priority(f: Array, w: StubWorld) -> void:
	var dir = Kit.director()
	var folk := Folk.create("Q")
	w.add_folk(folk, Vector2i(40, 40))
	var tv := w.add_object("tv", Vector2i(40, 40))
	var toilet := w.add_object("toilet", Vector2i(42, 40))
	var shelf := w.add_object("bookshelf", Vector2i(44, 40))
	(folk.needs["fun"] as Stat).set_value(0)
	(folk.needs["bladder"] as Stat).set_value(0)
	dir.autonomy_enabled = false
	# autonomous-priority items sort behind player commands regardless of enqueue order
	var read := Interaction.create("read_book", folk, shelf.id)
	var watch := Interaction.create("watch_tv", folk, tv.id)
	var pee := Interaction.create("use_toilet", folk, toilet.id, true)   # player command
	folk.enqueue(read)
	folk.enqueue(watch)
	Kit.expect(f, folk.queue[0] == read and folk.queue[1] == watch, "queue: equal priority keeps FIFO order")
	folk.enqueue(pee)
	Kit.expect(f, folk.queue[0] == pee, "queue: player command jumps the queue")
	dir.tick_minute(1)
	Kit.expect(f, folk.current == pee, "queue: director started the player command first")
	# now a normal autonomous interaction is running; a player command preempts it
	var lowly := Interaction.create("watch_tv", folk, tv.id)
	folk.queue.clear()
	_run_to_end(folk)
	folk.enqueue(lowly)
	dir.tick_minute(1)
	Kit.expect(f, folk.current == lowly, "queue: watch_tv started")
	var cmd := Interaction.create("read_book", folk, shelf.id, true)
	var fin: Array = []
	SimEnv.events().interaction_finished.connect(func(_i, d, s): fin.append([d, s]))
	folk.enqueue(cmd)
	Kit.expect(f, lowly.state == "cancelled" and lowly.cancel_reason == "preempted", "queue: player command preempts running autonomous interaction")
	Kit.expect(f, not fin.is_empty() and fin[0] == ["watch_tv", false], "queue: preempted interaction_finished(false)")
	dir.tick_minute(1)
	Kit.expect(f, folk.current == cmd, "queue: preempting command starts next tick")
	# an equal-priority non-player item does NOT preempt
	var same := Interaction.create("watch_tv", folk, tv.id)
	folk.enqueue(same)
	Kit.expect(f, folk.current == cmd and cmd.state != "cancelled", "queue: normal item waits behind current")
	# Director.command API
	(folk.needs["bladder"] as Stat).set_value(-20)
	var ok: bool = dir.command(folk.id, "use_toilet", toilet.id)
	Kit.expect(f, ok and folk.current != null and folk.current.def_id == "use_toilet", "queue: Director.command preempts and starts")
	# unrunnable command is refused
	(folk.needs["energy"] as Stat).set_value(90)
	var bed := w.add_object("bed", Vector2i(46, 40))
	Kit.expect(f, not dir.command(folk.id, "sleep_bed", bed.id), "queue: command whose tests fail is refused")
	dir.free()

func _test_cancel(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("Canceller")
	w.add_folk(folk, Vector2i(50, 50))
	var table := w.add_object("table", Vector2i(50, 50))
	folk.add_buff("meal_ready")
	var ir := Interaction.create("eat_meal", folk, table.id)
	Kit.expect(f, ir.start(), "cancel: eat_meal starts with meal_ready")
	for i in 20:
		ir.tick(1.0)
		if ir.state == "running":
			break
	ir.tick(2.0)
	ir.cancel("interrupted")
	Kit.expect(f, ir.state == "cancelled" and not ir.success, "cancel: state cancelled")
	Kit.expect(f, not folk.has_buff("meal_ready"), "cancel: on_cancel loot removed meal_ready")
	Kit.expect(f, not folk.has_buff("well_fed"), "cancel: no on_finish reward")
	Kit.expect(f, table.slots_reserved.is_empty(), "cancel: reservation released")
	Kit.expect(f, folk.current == null, "cancel: folk freed")
	Kit.expect(f, folk.memory_bias("obj:%d" % table.id) < 0.0, "cancel: interruption remembered negatively")
	# cancelling a never-started interaction is harmless
	var ir2 := Interaction.create("eat_meal", folk, table.id)
	ir2.cancel("player")
	Kit.expect(f, ir2.state == "cancelled" and table.slots_reserved.is_empty(), "cancel: queued interaction cancel is a no-op")

func _test_broken_cancels(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("Runner")
	w.add_folk(folk, Vector2i(60, 60))
	var tm := w.add_object("treadmill", Vector2i(60, 60))
	var ir := Interaction.create("exercise", folk, tm.id)
	Kit.expect(f, ir.start(), "broken: exercise starts")
	ir.tick(5.0)
	tm.state["broken"] = true
	ir.tick(1.0)
	Kit.expect(f, ir.state == "cancelled" and ir.cancel_reason == "broken", "broken: object breaking mid-run cancels")
	Kit.expect(f, folk.memory_bias("obj:%d" % tm.id) <= -0.35, "broken: strong negative memory (%f)" % folk.memory_bias("obj:%d" % tm.id))
	var ir2 := Interaction.create("exercise", folk, tm.id)
	Kit.expect(f, not ir2.can_run(folk, tm), "broken: broken objects cannot be used")

func _test_unknown_and_unreachable(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("X")
	w.add_folk(folk, Vector2i(0, 0))
	Kit.expect(f, Interaction.create("does_not_exist", folk, 1) == null, "create: unknown id returns null")
	var ir3 := Interaction.create("sit_sofa", folk, 99999)
	Kit.expect(f, not ir3.can_run(folk), "create: missing object cannot run")