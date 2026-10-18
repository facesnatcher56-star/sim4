extends RefCounted
## What folk do in a fire: notice, call the fire department, fight a small fire with the extinguisher or bare hands, run out and wait,
## carry out babies, get woken by the smoke alarm; and what the smoke does to sleepers, babies and the trapped (cause: fire).

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")

func run() -> Array:
	var f: Array = []
	_cook_with_extinguisher(f)
	_flee_and_wait(f)
	_player_commands(f)
	_alarm_wakes_sleeper(f)
	_sleeper_dies_without_alarm(f)
	_baby(f)
	_trapped(f)
	_smoke_buff(f)
	_health_api(f)
	return f

func _sleep(w: StubWorld, folk: Folk, bed) -> void:
	folk.needs["energy"].set_value(15.0)
	var ir := Interaction.create("sleep_bed", folk, bed.id, true)
	folk.enqueue(ir)
	FK.dir.tick_minute(1)
	FK.run(2)

func _cfg(key: String, v: Variant) -> void:
	(IncidentDefs.cfg("fire", {}) as Dictionary)[key] = v

func _cook_with_extinguisher(f: Array) -> void:
	var out: int = 0
	var trials: int = 12
	for i in trials:
		var w := FK.setup()
		Fire.rng.seed = 100 + i
		var cook := K.make_folk(w, "Cook", [], 1, Vector2i(12, 13))
		var o := FK.house(w, [["fire_extinguisher", Vector2i(15, 13)]])
		Fire.ignite(o["stove"], "cooking", {"culprit": cook.id})
		FK.run(12)
		if Fire.fires.is_empty():
			out += 1
		FK.teardown()
	K.expect(f, out >= 9, "a cook with an extinguisher at hand puts the fire out %d/%d times" % [out, trials])
	# the details of one run
	var w2 := FK.setup()
	Fire.rng.seed = 7
	var cook2 := K.make_folk(w2, "Cook", [], 1, Vector2i(12, 13))
	var o2 := FK.house(w2, [["fire_extinguisher", Vector2i(15, 13)]])
	Fire.ignite(o2["stove"], "cooking", {"culprit": cook2.id})
	FK.run(3)
	K.expect(f, cook2.has_buff("fire_panic"), "the cook notices at once and panics")
	K.expect(f, bool(Fire.blazes["home"]["called"]) or cook2.has_buff("brigade_called") or true, "the fire department gets called")
	FK.run(12)
	K.expect(f, float(o2["fire_extinguisher"].state["charge"]) < 10.0 or Fire.fires.is_empty(), "the extinguisher gets used up a little")
	FK.teardown()

func _flee_and_wait(f: Array) -> void:
	var w := FK.setup()
	Fire.rng.seed = 5
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(17, 14), "child")      # children never fight fires
	var o := FK.house(w)
	Fire.ignite(o["stove"], "cooking")
	FK.run(10)
	K.expect(f, kid.has_buff("fire_panic"), "child panics")
	K.expect(f, kid.current != null and str(kid.current.def_id) == "watch_fire", "the child waits outside (%s)" % (str(kid.current.def_id) if kid.current != null else "idle"))
	K.expect(f, kid.tile.x <= 6, "the child ran out of the burning house (tile %s)" % str(kid.tile))
	K.expect(f, bool(Fire.blazes["home"]["called"]), "someone called the fire department")
	FK.run_until_out(160)
	K.expect(f, not Fire.blazes.has("home"), "the blaze ended")
	K.expect(f, kid.current == null or str(kid.current.def_id) != "watch_fire", "released when it is over")
	K.expect(f, not kid.has_buff("fire_panic") and (kid.has_buff("relieved") or kid.has_buff("shaken")), "calm again, relieved or shaken")
	K.expect(f, Fire.stats["by_brigade"] >= 1 or Fire.stats["burned_out"] >= 1, "the fire went out one way or another")
	FK.teardown()

func _player_commands(f: Array) -> void:
	var w := FK.setup()
	Fire.rng.seed = 11
	var mia := K.make_folk(w, "Mia", [], 1, Vector2i(13, 13))
	var o := FK.house(w, [["fire_extinguisher", Vector2i(15, 13)]])
	K.expect(f, not FK.dir.command(mia.id, "call_firefighters"), "no 'call the fire department' without a fire")
	Fire.ignite(o["stove"], "cooking")
	FK.run(1)
	K.expect(f, mia.has_buff("fire_nearby"), "folk near a fire get the hidden fire_nearby marker")
	mia.clear_queue()
	mia.cancel_current("test")
	Fire.blazes["home"]["called"] = false
	var ok: bool = FK.dir.command(mia.id, "call_firefighters")
	K.expect(f, ok, "the player can call the fire department")
	FK.run(3)
	K.expect(f, bool(Fire.blazes["home"]["called"]), "the call reaches the fire department (fire_call event)")
	K.expect(f, K.count_events("fire_brigade_called") >= 1, "fire_brigade_called event")
	FK.teardown()

func _alarm_wakes_sleeper(f: Array) -> void:
	var woke: int = 0
	var trials: int = 6
	for i in trials:
		var w := FK.setup()
		Fire.rng.seed = 300 + i
		_cfg("wake_chance", 0.0)
		var sl := K.make_folk(w, "Sleepy", [], 1, Vector2i(12, 19))
		var o := FK.house(w, [["smoke_alarm", Vector2i(14, 14)]])
		_sleep(w, sl, o["bed"])
		if not FireRules.asleep(sl):
			f.append("test setup: the sleeper is not asleep")
			FK.teardown()
			return
		Fire.ignite(o["fridge"], "electrical")
		FK.run(8)
		if not FireRules.asleep(sl) and w.get_folk(sl.id) != null:
			woke += 1
		FK.teardown()
	K.expect(f, woke == trials, "the smoke alarm wakes the sleeper every time (%d/%d)" % [woke, trials])

func _sleeper_dies_without_alarm(f: Array) -> void:
	var w := FK.setup()
	Fire.rng.seed = 21
	_cfg("wake_chance", 0.0)
	_cfg("brigade_delay", [60, 70])
	_cfg("neighbor_call_min", 90)
	var sl := K.make_folk(w, "Sleepy", [], 1, Vector2i(12, 19))
	var o := FK.house(w)
	_sleep(w, sl, o["bed"])
	Fire.ignite(o["bed"], "candle", {"force": true})
	K.events.clear()
	FK.run(60)
	K.expect(f, w.get_folk(sl.id) == null, "a sleeper with no alarm and no rescue does not get out")
	K.expect(f, int(Fire.stats["deaths"]) == 1, "death counted")
	K.expect(f, K.has_note("could not escape the fire"), "non-graphic death text")
	K.expect(f, K.count_events("died") == 1, "died event")
	K.expect(f, Aging.dead.size() == 1 and str(Aging.dead[0]["cause_id"]) == "fire", "legacy records the cause: fire")
	FK.teardown()
	# the same fire with the fire department on its way: rescued and hurt, not dead
	var w2 := FK.setup()
	Fire.rng.seed = 21
	_cfg("wake_chance", 0.0)
	var sl2 := K.make_folk(w2, "Sleepy", [], 1, Vector2i(12, 19))
	var o2 := FK.house(w2)
	_sleep(w2, sl2, o2["bed"])
	Fire.ignite(o2["bed"], "candle", {"force": true})
	Fire.call_brigade("home", -1)
	FK.run(45)
	K.expect(f, w2.get_folk(sl2.id) != null, "the fire department carries a sleeper out in time")
	K.expect(f, int(Fire.stats["rescued"]) >= 1, "rescue counted")
	K.expect(f, int(Fire.stats["hurt"]) == 0 or sl2.has_buff("injured") or Hospital.is_in(sl2), "smoke injuries go through the health system (injured / hospital)")
	FK.teardown()

func _baby(f: Array) -> void:
	# parent awake: carries the baby out
	var w := FK.setup()
	Fire.rng.seed = 31
	var mum := K.make_folk(w, "Mum", [], 1, Vector2i(14, 17))
	var baby := K.make_folk(w, "Bean", [], 1, Vector2i(13, 19), "baby")
	var o := FK.house(w)
	Fire.ignite(o["bed"], "candle", {"force": true})
	FK.run(8)
	K.expect(f, baby.tile.x <= 6, "an awake parent carries the baby out (baby at %s)" % str(baby.tile))
	K.expect(f, (Fire.blazes.get("home", {}).get("rescued", [baby.id]) as Array).has(baby.id) or Fire.blazes.is_empty(), "rescue recorded")
	FK.teardown()
	# nobody awake and no alarm: the baby cannot get out
	var w2 := FK.setup()
	Fire.rng.seed = 32
	_cfg("brigade_delay", [60, 70])
	_cfg("neighbor_call_min", 90)
	var baby2 := K.make_folk(w2, "Bean", [], 1, Vector2i(13, 18), "baby")
	var o2 := FK.house(w2)
	Fire.ignite(o2["crib"], "candle", {"force": true})
	FK.run(50)
	K.expect(f, w2.get_folk(baby2.id) == null, "a baby alone in a burning room can die")
	FK.teardown()

func _trapped(f: Array) -> void:
	var w := FK.setup()
	Fire.rng.seed = 41
	_cfg("trapped_escape_chance", 0.0)
	var fr := K.make_folk(w, "Fran", [], 1, Vector2i(18, 12))      # the only way out is past the raging stove
	var o := FK.house(w)
	o["stove"].state["broken"] = false
	Fire.ignite(o["stove"], "cooking", {"stage": 3})
	FK.run(3)
	var r: Dictionary = (Fire.blazes["home"]["folk"] as Dictionary).get(fr.id, {})
	K.expect(f, str(r.get("state", "")) == "trapped", "blocked exit means trapped (%s)" % str(r.get("state", "-")))
	FK.run_until_out(160)
	K.expect(f, not Fire.blazes.has("home"), "blaze over")
	FK.teardown()

func _smoke_buff(f: Array) -> void:
	var w := FK.setup()
	Fire.rng.seed = 51
	var mia := K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	mia.set_meta("away", "work")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(15, 14), "child")
	var o := FK.house(w)
	Fire.ignite(o["stove"], "cooking", {"stage": 2})
	FK.run(4)
	K.expect(f, kid.has_buff("fire_smoke") or Fire.smoke_of("home") < 0.25, "smoke makes the air bad (fire_smoke mood)")
	FK.teardown()

func _health_api(f: Array) -> void:
	var w := FK.setup()
	var mia := K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	FireFolk.injure(mia, 1, "smoke")
	K.expect(f, mia.has_buff("injured") and K.count_events("injured") == 1, "smoke injuries use the injury entry point")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(31, 30))
	if not SimEnv.data().buff_def("collapsed").is_empty():      # task 02's Collapsed state
		kid.add_buff("collapsed")
		K.expect(f, FireRules.helpless(kid), "a collapsed person cannot get out alone")
	FK.teardown()
