extends RefCounted
## Starvation, exhaustion, collapse, rescue and the neglect meter: stages, warnings, recovery, and that death only happens past the thresholds
## (and is not scaled by the Surprises setting).

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_starvation(f)
	_thresholds(f)
	_rescue(f)
	_exhaustion(f)
	_doctor(f)
	_neglect(f)
	_town_help(f)
	return f

func _world() -> StubWorld:
	var w := K.setup()
	SysContent.install_all()
	Incidents.reset()
	Weather.force("sunny")
	K.set_time(6, 9, 0)             # a weekend: nobody leaves for school
	return w

## Keep a need pinned at the very bottom for n minutes (the real decay would do the same, just slower).
func _pin(dir, folk: Folk, need: String, value: float, n: int) -> void:
	for i in n:
		folk.needs[need].set_value(value)
		K.run(dir, 1)

func _starvation(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var dir = K.director()
	dir.autonomy_enabled = false
	var r: Dictionary = Health.rec_of(a.id)
	_pin(dir, a, "hunger", -100.0, 100)                        # the real clock for the first stretch, then jump ahead with the record
	K.expect(f, not a.has_buff("weak_hunger") and not Health.is_collapsed(a), "a short time at the bottom: nothing yet")
	r["hunger_min"] = 700.0
	_pin(dir, a, "hunger", -100.0, 10)
	K.expect(f, not a.has_buff("weak_hunger"), "under 12 hours at the bottom: no warning yet")
	_pin(dir, a, "hunger", -100.0, 20)
	K.expect(f, a.has_buff("weak_hunger") and K.has_note("faint with hunger"), "after 12 hours: warning toast + weak_hunger buff")
	K.expect(f, Health.stage_of(a)["hunger"] == 2 and not Health.is_collapsed(a), "stage 2 (faint), not collapsed")
	r["hunger_min"] = 2860.0
	_pin(dir, a, "hunger", -100.0, 10)
	K.expect(f, not Health.is_collapsed(a), "just under 2 days: still on their feet")
	_pin(dir, a, "hunger", -100.0, 15)
	K.expect(f, Health.is_collapsed(a) and a.has_buff("collapsed") and K.has_note("collapsed from hunger"), "2 days at the bottom: Collapsed")
	K.run(dir, 3)
	K.expect(f, a.current != null and a.current.def_id == "collapse_floor" and a.posture == "lie", "collapsed folk lie on the floor (emergency interaction)")
	K.expect(f, Health.stage_of(a)["hunger"] == 3, "stage 3")
	K.expect(f, Hospital.status_chips(a).any(func(c): return c["text"] == "Collapsed"), "folk panel chip says Collapsed")
	# nobody to help and no ambulance in time: no death before 3 days, even with a certain death chance
	IncidentDefs.config["health"]["rescue"]["town_help_min"] = 100000
	IncidentDefs.config["health"]["needs"]["hunger"]["death_per_hour"] = 1.0
	r["hunger_min"] = 4000.0
	_pin(dir, a, "hunger", -100.0, 200)
	K.expect(f, w.get_folk(a.id) != null and float(r["hunger_min"]) > 4100.0, "before 3 days total: no death (%d min)" % int(r["hunger_min"]))
	_pin(dir, a, "hunger", -100.0, 130)
	K.expect(f, w.get_folk(a.id) == null and str(K.last_event("died").get("cause", "")) == "starvation", "after 3 days: death by starvation (cause recorded)")
	K.teardown()
	# deterministic, not a Surprises dice: with Surprises Off the same neglect still kills
	var w2 := _world()
	Incidents.set_level("off")
	var b := K.make_folk(w2, "Bo", [], 1)
	var dir2 = K.director()
	dir2.autonomy_enabled = false
	IncidentDefs.config["health"]["needs"]["hunger"]["death_per_hour"] = 1.0
	Health.rec_of(b.id)["hunger_min"] = 4300.0
	_pin(dir2, b, "hunger", -100.0, 130)
	K.expect(f, w2.get_folk(b.id) == null, "Surprises Off does not switch off needs deaths")
	K.teardown()

## Thresholds are per age stage and death is limited to the stages in data.
func _thresholds(f: Array) -> void:
	var w := _world()
	IncidentDefs.config["health"]["needs"]["hunger"]["death_per_hour"] = 1.0
	IncidentDefs.config["health"]["needs"]["energy"]["death_per_hour"] = 1.0
	var adult := K.make_folk(w, "Ada", [], 1)
	var elder := K.make_folk(w, "Eli", [], 1, Vector2i(14, 12), "elder")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(16, 12), "child")
	var ra: Dictionary = Health.rec_of(adult.id)
	var rk: Dictionary = Health.rec_of(kid.id)
	ra["hunger_min"] = 4319.0
	HealthNeeds.hourly(adult, ra)
	K.expect(f, w.get_folk(adult.id) != null, "adult one minute before the death threshold: alive")
	var re: Dictionary = Health.rec_of(elder.id)
	re["hunger_min"] = 4320.0 * 0.8 - 1.0
	HealthNeeds.hourly(elder, re)
	K.expect(f, w.get_folk(elder.id) != null, "elders have a shorter fuse, but not yet")
	re["hunger_min"] = 4320.0 * 0.8
	HealthNeeds.hourly(elder, re)
	K.expect(f, w.get_folk(elder.id) == null, "elder past their (shorter) threshold dies")
	rk["hunger_min"] = 100000.0
	HealthNeeds.hourly(kid, rk)
	K.expect(f, w.get_folk(kid.id) != null, "children never die of starvation here (they are taken to hospital instead)")
	ra["hunger_min"] = 4320.0
	HealthNeeds.hourly(adult, ra)
	K.expect(f, w.get_folk(adult.id) == null, "adult at the threshold dies")
	K.teardown()
	# exhaustion: elders only
	var w2 := _world()
	IncidentDefs.config["health"]["needs"]["energy"]["death_per_hour"] = 1.0
	var a2 := K.make_folk(w2, "Ada", [], 1)
	var e2 := K.make_folk(w2, "Eli", [], 1, Vector2i(14, 12), "elder")
	Health.rec_of(a2.id)["energy_min"] = 100000.0
	HealthNeeds.hourly(a2, Health.rec_of(a2.id))
	K.expect(f, w2.get_folk(a2.id) != null, "exhaustion never kills an adult")
	Health.rec_of(e2.id)["energy_min"] = 7200.0 * 0.8 - 1.0
	HealthNeeds.hourly(e2, Health.rec_of(e2.id))
	K.expect(f, w2.get_folk(e2.id) != null, "elder below the very long exhaustion threshold: alive")
	Health.rec_of(e2.id)["energy_min"] = 7200.0 * 0.8
	HealthNeeds.hourly(e2, Health.rec_of(e2.id))
	K.expect(f, w2.get_folk(e2.id) == null and str(K.last_event("died").get("cause", "")) == "exhaustion", "elder after very long exhaustion dies of exhaustion")
	K.teardown()

func _rescue(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(14, 12))
	var dir = K.director()
	dir.autonomy_enabled = false
	b.needs["hunger"].set_value(50.0)
	Health.rec_of(a.id)["hunger_min"] = 2860.0
	_pin(dir, a, "hunger", -100.0, 30)
	K.expect(f, Health.is_collapsed(a), "Ada collapsed")
	# a housemate notices after a short delay and helps (help_collapsed -> health_rescue)
	for i in 80:
		b.needs["hunger"].set_value(50.0)
		K.run(dir, 1)
	K.expect(f, int(Health.counters.get("auto_help", 0)) >= 1, "a housemate was sent to help")
	K.expect(f, not Health.is_collapsed(a) and a.needs["hunger"].value > 0.0, "helped up and fed: hunger %.0f" % a.needs["hunger"].value)
	K.expect(f, float(Health.rec_of(a.id).get("hunger_min", 0.0)) == 0.0 and not a.has_buff("weak_hunger"), "the neglect clock reset")
	K.run(dir, 5)
	K.expect(f, a.current == null or a.current.def_id != "collapse_floor", "the collapse interaction ended")
	K.teardown()
	# collapsed folk cannot be talked to: social interactions need a target who is not lying down
	var w2 := _world()
	var c := K.make_folk(w2, "Cy", [], 1)
	var d := K.make_folk(w2, "Di", [], 1, Vector2i(13, 12))
	Health.collapse(c, "hunger")
	var dir2 = K.director()
	dir2.autonomy_enabled = false
	K.run(dir2, 3)
	var chat := Interaction.create("chat", d, c.id, false)
	K.expect(f, chat != null and not chat.can_run(d, null, false), "nobody can chat with a collapsed person")
	var help := Interaction.create("help_collapsed", d, c.id, false)
	K.expect(f, help != null and help.can_run(d, null, false), "but a housemate can help them up")
	K.teardown()

func _exhaustion(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var dir = K.director()
	dir.autonomy_enabled = false
	SimEnv.data().interactions().erase("pass_out")           # the normal safety net would catch them long before this
	Health.rec_of(a.id)["energy_min"] = 2850.0
	_pin(dir, a, "energy", -100.0, 40)
	K.expect(f, Health.is_collapsed(a) and HealthCollapse.kind_of(a) == "exhaustion", "2 days at the bottom of energy: collapse (exhaustion)")
	K.expect(f, K.has_note("exhaustion"), "toast explains it")
	K.run(dir, 200)
	K.expect(f, not Health.is_collapsed(a) and a.needs["energy"].value >= -25.0, "they sleep it off on the floor and wake up (energy %.0f)" % a.needs["energy"].value)
	K.expect(f, a.has_buff("shaky") and w.get_folk(a.id) != null, "groggy, alive")
	K.teardown()

func _doctor(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	WorldIface.coins[1] = 500
	Health.collapse(a, "hunger")
	var res: Dictionary = Incidents.call_doctor(a.id)
	K.expect(f, bool(res["ok"]) and res["treated"].has("collapse") and not Health.is_collapsed(a), "a doctor revives the collapsed")
	K.expect(f, a.needs["hunger"].value >= 10.0 and WorldIface.get_coins(1) == 500 - 120, "fed, and the visit cost 120 coins")
	K.teardown()

func _neglect(f: Array) -> void:
	var w := _world()
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(12, 12), "child")
	var hits: Array = []
	Health.register_neglect_hook(func(folk, info): hits.append([folk.id, info["kind"]]))
	var dir = K.director()
	dir.autonomy_enabled = false
	for i in 500:
		kid.needs["hunger"].set_value(-80.0)
		K.run(dir, 1)
	K.expect(f, kid.has_buff("neglected") and hits.size() == 1 and hits[0][1] == "child", "a neglected child is flagged once and the task-07 hook is called")
	K.expect(f, K.count_events("neglect_noticed") == 1, "neglect_noticed game event")
	for i in 150:
		kid.needs["hunger"].set_value(60.0)
		K.run(dir, 1)
	K.expect(f, not kid.has_buff("neglected"), "cared for again: the flag clears")
	Health.neglect_hooks.clear()
	K.teardown()

func _town_help(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Lone", [], 1)
	K.make_folk(w, "Faraway", [], 1)
	Health.collapse(a, "hunger")
	var r: Dictionary = Health.rec_of(a.id)
	a.needs["hunger"].set_value(-100.0)
	r["hunger_min"] = 2900.0
	var t0: int = int(r["collapse_min"])
	HealthCollapse.tick(a, r, t0 + 200)
	K.expect(f, Health.is_collapsed(a), "after a few hours with no help they are still down")
	HealthCollapse.tick(a, r, t0 + 250)
	K.expect(f, not Health.is_collapsed(a) and a.needs["hunger"].value > 0.0, "passers-by call an ambulance: awake and no longer at the bottom (%.0f)" % a.needs["hunger"].value)
	K.expect(f, float(r.get("hunger_min", 1.0)) == 0.0 and Hospital.patients.has(a.id), "taken to hospital, the starvation clock reset")
	K.teardown()
