extends RefCounted
## Injuries: severity, slow walking, no exercise / physical work, rest and first aid, hospital for serious ones, the sport / fishing /
## scuffle sources, and the save round trip of the whole health state.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_basics(f)
	_limits(f)
	_sources(f)
	_save(f)
	return f

func _world() -> StubWorld:
	var w := K.setup()
	SysContent.install_all()
	Incidents.reset()
	Weather.force("sunny")
	K.set_time(6, 9, 0)
	return w

func _basics(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	K.expect(f, not Health.is_injured(a) and Health.speed_mult(a) == 1.0, "healthy: full speed")
	K.expect(f, Health.injure(a, 1, "a trip") and Health.is_injured(a) and Health.injury_severity(a) == 1, "minor injury")
	K.expect(f, Health.speed_mult(a) < 0.9 and not Hospital.is_in(a), "slower, but not in hospital")
	Health.injure(a, 1, "again")
	K.expect(f, Health.injury_severity(a) == 1, "same severity stays")
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(14, 12))
	WorldIface.coins[1] = 1000
	Hospital.injure(b, 2, "a bad fall")                 # the framework entry point goes through Health
	K.expect(f, Hospital.is_in(b) and Health.injury_severity(b) == 2 and Health.speed_mult(b) < Health.speed_mult(a), "serious injury: hospital, slower than a minor one")
	var c := K.make_folk(w, "Cy", [], 1, Vector2i(16, 12))
	Health.injure(c, 3, "a serious accident")
	K.expect(f, Health.speed_mult(c) < 0.5 and Health.speed_mult(c) >= 0.3, "severity 3 is the slowest (%.2f) but never a standstill" % Health.speed_mult(c))
	# walking really takes longer
	var tm = w.add_object("treadmill", Vector2i(40, 12))
	var d := K.make_folk(w, "Di", [], 1, Vector2i(12, 14))
	var e := K.make_folk(w, "Ed", [], 1, Vector2i(12, 16))
	Health.injure(e, 1, "a trip")
	var ir_d := Interaction.create("exercise", d, tm.id, false)
	var ir_e := Interaction.create("exercise", e, tm.id, false)
	ir_d.start()
	ir_e.state = "queued"
	K.expect(f, ir_d.travel_total > 5.0, "baseline walk takes time (%.1f)" % ir_d.travel_total)
	# compare on equal footing: the same tile for both
	e.tile = d.tile
	d.current = null
	ir_d.cancel("x")
	var ir_d2 := Interaction.create("exercise", d, tm.id, false)
	var ir_e2 := Interaction.create("exercise", e, tm.id, false)
	ir_d2.start()
	ir_d2.cancel("x")
	d.current = null
	ir_e2.start()
	K.expect(f, ir_e2.travel_total > 0.0 and ir_d2.travel_total > 0.0 and absf(ir_e2.travel_total * Health.speed_mult(e) - ir_d2.travel_total) < 0.01, "an injured walker takes 1/speed times as long (%.1f vs %.1f)" % [ir_e2.travel_total, ir_d2.travel_total])
	# healing: the buff runs out
	a.tick_buffs(24.0 * 60.0 + 1.0)
	HealthInjury.tick_minute(a, Health.rec_of(a.id))
	K.expect(f, not Health.is_injured(a) and K.has_note("has healed"), "minor injury heals after a day")
	# rest doubles recovery
	Health.injure(a, 1, "a trip")
	var before: float = _remaining(a, "injured")
	a.posture = "lie"
	for i in 30:
		HealthInjury.tick_minute(a, Health.rec_of(a.id))
	K.expect(f, before - _remaining(a, "injured") >= 29.0, "lying down speeds recovery")
	K.teardown()

func _remaining(fk, buff: String) -> float:
	for b in fk.buffs:
		if str(b["id"]) == buff:
			return float(b["remaining"])
	return 0.0

func _limits(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var tm = w.add_object("treadmill", Vector2i(16, 12))
	var wt = w.add_object("dumbbell_rack", Vector2i(18, 12))
	a.needs["fun"].set_value(0.0)
	var ex := Interaction.create("exercise", a, tm.id, false)
	var lift := Interaction.create("lift_weights", a, wt.id, false)
	K.expect(f, ex.can_run(a, null, false) and lift.can_run(a, null, false), "healthy people can exercise")
	Health.injure(a, 1, "a trip")
	K.expect(f, not ex.can_run(a, null, false) and not lift.can_run(a, null, false), "injured folk cannot exercise or lift")
	K.expect(f, Health.blocks_activity(a, ["exercise"]) != "" and Health.blocks_activity(a, ["read"]) == "", "blocks_activity API")
	# jobs: a physical job is skipped, a desk job is not (unless the injury is serious)
	K.expect(f, Health.work_block(a, "cook") != "" and Health.work_block(a, "coder") == "", "minor injury: physical jobs only")
	Health.injure(a, 2, "worse")
	K.expect(f, Health.work_block(a, "coder") != "", "serious injury: no work at all")
	K.teardown()
	# the attendance code uses it: an unwell worker stays home and a smaller penalty is recorded
	var w2 := _world()
	var dir = K.director()
	var b := K.make_folk(w2, "Bo", [], 1)
	Careers.hire(b, "coder", 1)
	Incidents.force("catch_flu", {"folk_id": b.id})
	var pb: float = CareerProgress.performance_of(int(b.id))
	K.set_time(2, 8, 55)
	K.run(dir, 10)
	K.expect(f, not SysUtil.is_away(b) and CareerProgress.performance_of(int(b.id)) == pb - 4.0 and K.has_note("too unwell to go to work"), "flu: stays home from work, -4 performance")
	var c := K.make_folk(w2, "Cy", [], 1, Vector2i(14, 14))
	Careers.hire(c, "coder", 1)
	Health.injure(c, 1, "a trip")
	var pc: float = CareerProgress.performance_of(int(c.id))
	K.set_time(3, 8, 55)
	K.run(dir, 10)
	K.expect(f, SysUtil.is_away(c) and CareerProgress.performance_of(int(c.id)) == pc, "a minor injury does not stop a desk job")
	K.teardown()

func _sources(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	# scuffle: picking a fight sometimes hurts the other person
	var c := K.make_folk(w, "Cy", [], 1, Vector2i(26, 12))
	IncidentDefs.config["health"]["injury"]["scuffle_chance"] = 1.0
	SysUtil.game_event("social_done", {"folk_id": a.id, "target_id": c.id, "interaction": "insult"})
	K.expect(f, Health.is_injured(c) and K.has_note("scuffle"), "a fight can leave the other person hurt")
	var d := K.make_folk(w, "Di", [], 1, Vector2i(28, 12))
	SysUtil.game_event("social_done", {"folk_id": a.id, "target_id": d.id, "interaction": "chat"})
	K.expect(f, not Health.is_injured(d), "but a chat does not")
	Incidents.set_level("off")
	var e := K.make_folk(w, "Ed", [], 1, Vector2i(30, 12))
	SysUtil.game_event("social_done", {"folk_id": a.id, "target_id": e.id, "interaction": "insult"})
	K.expect(f, not Health.is_injured(e), "Surprises Off: no scuffle injuries")
	Incidents.set_level("rare")
	# any other task hurts people through the public API and gets the same limits
	var g := K.make_folk(w, "Gi", [], 1, Vector2i(32, 12))
	K.expect(f, Health.injure(g, 2, "a traffic accident") and Hospital.is_in(g), "Health.injure from another task: severity 2 goes to hospital")
	K.teardown()

func _save(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(14, 12))
	Health.injure(a, 2, "x")
	Hospital.discharge(a.id)
	Health.injure(b, 1, "x")
	Incidents.force("catch_flu", {"folk_id": b.id})
	Health.collapse(a, "hunger")
	Health.rec_of(a.id)["hunger_min"] = 3000.0
	Health.count("test", 3)
	var before: Dictionary = Health.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(before))
	Health.reset()
	Health.from_dict(parsed)
	var diffs: Array = []
	var after: Dictionary = Health.to_dict()
	K.expect(f, str(Health.rng.state) == str(parsed["rng_state"]) and Health.counters.get("test", 0) == 3, "rng and counters survive")
	K.expect(f, Health.rec_of(a.id).get("collapse", "") == "hunger" and float(Health.rec_of(a.id)["hunger_min"]) == 3000.0 and Health.is_ill(b), "records survive JSON")
	K.expect(f, K.deep_eq(JSON.parse_string(JSON.stringify(before)), JSON.parse_string(JSON.stringify(after)), "health", diffs), "round trip equal: %s" % str(diffs))
	K.expect(f, SaveLoad.save(95, "health") and SaveLoad.load_slot(95), "whole-game save + load")
	SaveLoad.delete_slot(95)
	var a2 = w.get_folk(a.id)
	var b2 = w.get_folk(b.id)
	K.expect(f, a2 != null and Health.is_collapsed(a2) and Health.rec_of(a2.id).get("collapse", "") == "hunger", "the collapse is still there after loading")
	K.expect(f, b2 != null and Health.is_injured(b2) and Health.illness_of(b2).get("kind", "") == "flu", "injury and flu are still there after loading")
	var dir = K.director()
	dir.autonomy_enabled = false
	K.run(dir, 3)
	K.expect(f, a2.current != null and a2.current.def_id == "collapse_floor", "and the collapsed person is lying down again")
	K.teardown()
