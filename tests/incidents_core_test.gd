extends RefCounted
## Incident framework: rate maths, Surprises levels, risk / prevention, forced incidents end to end, warnings + doctor, handlers,
## notify policy, statistical (townie / far lot) resolution, town scope per lot, chronicle hook, determinism, save round trip.

const K = preload("res://tests/systems_kit.gd")
const Stub = preload("res://tests/incidents_handler_stub.gd")

func run() -> Array:
	var f: Array = []
	_rate_maths(f)
	_levels(f)
	_risk(f)
	_force(f)
	_warning(f)
	_handlers(f)
	_statistical(f)
	_town_scope(f)
	_determinism(f)
	_roundtrip(f)
	return f

func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _world() -> StubWorld:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	Incidents.set_level("rare")
	return w

func _elder(w: StubWorld, nm: String, hid: int = 1, traits: Array = []) -> Folk:
	var e := K.make_folk(w, nm, traits, hid, Vector2i(12, 12), "elder")
	Aging.set_age_days(e, 182.0)
	return e

func _rate_maths(f: Array) -> void:
	_world()
	var n_day: float = 28.0
	var p: float = IncidentRisk.rate_to_chance(1.0, "day")
	K.expect(f, _near(p, 1.0 / n_day, 0.0001), "1/yr per day check = %.5f" % p)
	var ph: float = IncidentRisk.rate_to_chance(1.0, "hour")
	K.expect(f, _near(ph, 1.0 / (28.0 * 24.0), 0.00001), "1/yr per hour check")
	K.expect(f, _near(IncidentRisk.chance_to_rate(p, "day"), 1.0, 0.0001), "chance_to_rate inverts rate_to_chance")
	K.expect(f, IncidentRisk.rate_to_chance(1000.0, "hour") <= 0.9 + 0.0001, "chance is capped")
	K.expect(f, IncidentRisk.rate_to_chance(0.0, "day") == 0.0, "zero rate never happens")
	K.teardown()

func _levels(f: Array) -> void:
	var w := _world()
	var h := K.make_folk(w, "Hana", [], 1)
	var want := {"off": 0.0, "rare": 1.0, "normal": 3.0, "chaotic": 10.0}
	for lv in want:
		Incidents.set_level(lv)
		K.expect(f, Incidents.surprise_mult() == want[lv], "Surprises %s = x%s" % [lv, want[lv]])
		K.expect(f, _near(Incidents.effective_rate("found_money", IncidentSubject.of_household(1)), 1.0 * want[lv], 0.0001), "found_money effective rate follows the level (%s)" % lv)
	# Off: nothing ever happens; Chaotic: lots happen
	Incidents.set_level("off")
	var days: int = TestFixture.pick(120, 40)
	for d in days:
		K.set_time(2 + d, 3)
		Incidents.on_day()
	K.expect(f, int(Incidents.stat("found_money")["triggered"]) == 0 and Incidents.history(5).is_empty(), "Off: no incident in %d days" % days)
	Incidents.set_level("chaotic")
	var chaotic_days: int = TestFixture.pick(120, 50)           # expected hits ~ days x 0.34 (10/yr over a 28-day year): 41 in the full run, 17 in the short one
	for d2 in chaotic_days:
		K.set_time(200 + d2, 3)
		Incidents.on_day()
	K.expect(f, int(Incidents.stat("found_money")["triggered"]) > TestFixture.pick(20, 8), "Chaotic: found_money often (%d)" % int(Incidents.stat("found_money")["triggered"]))
	# old age ignores the setting
	Incidents.set_level("off")
	var old := _elder(w, "Olga", 2)
	Aging.set_age_days(old, 263.0)
	Aging.on_day(500)
	K.expect(f, w.get_folk(old.id) == null, "old age still kills with Surprises Off")
	K.teardown()

func _risk(f: Array) -> void:
	var w := _world()
	var young := K.make_folk(w, "Yan", [], 1)
	var e := _elder(w, "Edda", 2, ["glutton"])
	var base: float = 0.02
	K.expect(f, Incidents.effective_rate("heart_attack", young) == 0.0, "heart attacks only for elders (conditions)")
	var r0: float = Incidents.effective_rate("heart_attack", e)
	K.expect(f, _near(r0, base * 1.6 * 1.4, 0.0001), "low fitness x1.6 and glutton x1.4: %.4f" % r0)
	e.add_buff("checked_up")
	K.expect(f, _near(Incidents.effective_rate("heart_attack", e), r0 * 0.4, 0.0001), "check-up prevention x0.4")
	e.remove_buff("checked_up")
	e.skills["fitness"]["level"] = 6
	K.expect(f, _near(Incidents.effective_rate("heart_attack", e), base * 0.5 * 1.4, 0.0001), "high fitness x0.5")
	e.add_buff("exhausted")
	K.expect(f, _near(Incidents.effective_rate("heart_attack", e), base * 0.5 * 1.4 * 1.4, 0.0001), "buff risk (exhausted) x1.4")
	# block + object + weather conditions
	IncidentDefs.defs["t_block"] = {"label": "T", "scope": "folk", "check": "day", "base_rate_per_year": 2.0, "conditions": [],
		"risk_mults": [{"when": [{"weather_is": ["rain"]}], "mult": 3.0}], "prevent": [{"when": [{"has_object": "lamp"}], "block": true, "label": "Lamp"}],
		"outcomes": [{"weight": 1, "effects": []}]}
	Weather.force("sunny")
	K.expect(f, _near(Incidents.effective_rate("t_block", young), 2.0, 0.0001), "no rain: base")
	Weather.force("rain")
	K.expect(f, _near(Incidents.effective_rate("t_block", young), 6.0, 0.0001), "weather risk x3")
	w.add_object("lamp", Vector2i(3, 3))
	Economy.refresh_objects()
	K.expect(f, Incidents.effective_rate("t_block", young) == 0.0, "an object that blocks the incident (lamp) zeroes the rate")
	var bd: Array = IncidentRisk.breakdown(IncidentDefs.defs["t_block"], IncidentSubject.of_folk(young))
	K.expect(f, bd.size() == 2, "debug breakdown lists risk and prevent entries")
	Weather.unforce()
	K.teardown()

func _force(f: Array) -> void:
	var w := _world()
	var e := _elder(w, "Tobin Rowe", 1)
	var kid := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(14, 12), "child")
	RelationshipBits.set_flag(e.id, kid.id, "family")
	WorldIface.coins[1] = 500
	K.events.clear()
	K.notes.clear()
	var r: Dictionary = Incidents.force("heart_attack", {"folk_id": e.id, "outcome": 0})
	K.expect(f, bool(r["ok"]) and w.get_folk(e.id) == null, "forced heart attack kills (%s)" % str(r))
	K.expect(f, K.has_note("collapsed suddenly"), "death toast has the non-graphic cause text")
	K.expect(f, int(Incidents.stat("heart_attack")["forced"]) == 1 and Incidents.history(1)[0]["forced"] == true, "forced counter and history")
	K.expect(f, K.count_events("incident") == 1 and K.count_events("chronicle") >= 1, "incident + chronicle events")
	K.expect(f, kid.has_buff("grieving_heavy"), "child grieves hard (stronger than old age)")
	# outcome 1: hospital
	var e2 := _elder(w, "Maud Rowe", 1)
	r = Incidents.force("heart_attack", {"folk_id": e2.id, "outcome": 1})
	K.expect(f, w.get_folk(e2.id) != null and Hospital.is_in(e2), "forced survivable outcome goes to hospital")
	# found money (lot scope)
	var before: int = WorldIface.get_coins(1)
	K.notes.clear()
	r = Incidents.force("found_money", {"lot": 1})
	K.expect(f, WorldIface.get_coins(1) >= before + 15 and WorldIface.get_coins(1) <= before + 60 and K.has_note("coins tucked"), "found_money adds coins and says how many: %s" % str(r.get("text")))
	# fall -> injured
	var m := K.make_folk(w, "Mia", [], 1, Vector2i(9, 9))
	Incidents.force("minor_fall", {"folk_id": m.id, "outcome": 0})
	K.expect(f, m.has_buff("injured") and not Hospital.is_in(m), "minor fall bruises without hospital")
	Incidents.force("minor_fall", {"folk_id": m.id, "outcome": 1})
	K.expect(f, Hospital.is_in(m), "bad fall is admitted")
	K.expect(f, Incidents.history(50).size() >= 4 and Incidents.list().size() >= 4, "history + list")
	K.teardown()

func _warning(f: Array) -> void:
	var w := _world()
	var e := _elder(w, "Wren", 1)
	WorldIface.coins[1] = 1000
	K.set_time(5, 10, 0)
	K.notes.clear()
	var r: Dictionary = Incidents.force("heart_attack", {"folk_id": e.id, "warn": true})
	K.expect(f, r["mode"] == "warned" and Incidents.active().size() == 1 and K.has_note("holding their chest"), "warning first, then pending: %s" % str(r))
	K.set_time(5, 10, 30)
	Incidents.on_minute()
	K.expect(f, Incidents.active().size() == 1, "not due yet")
	var doc: Dictionary = Incidents.call_doctor(e.id)
	K.expect(f, bool(doc["ok"]) and int(doc["defused"]) == 1 and WorldIface.get_coins(1) == 880 and e.has_buff("checked_up"), "doctor defuses (cost 120): %s" % str(doc))
	K.set_time(5, 23, 0)
	Incidents.on_minute()
	K.expect(f, w.get_folk(e.id) != null and Incidents.active().is_empty() and int(Incidents.stat("heart_attack")["averted"]) == 1 and K.has_note("doctor arrived in time"), "averted, nobody died")
	# without the doctor it happens when due
	var e2 := _elder(w, "Wynn", 2)
	Incidents.force("heart_attack", {"folk_id": e2.id, "warn": true})
	K.set_time(6, 14, 0)
	Incidents.on_minute()
	K.expect(f, Incidents.active().is_empty() and (w.get_folk(e2.id) == null or Hospital.is_in(e2)), "unprevented warning resolves into the outcome")
	# the warning is a real window (hours), and a household with money calls the doctor on its own part-way through
	var e4 := _elder(w, "Hale", 4)
	WorldIface.coins[4] = 1000
	K.set_time(7, 8, 0)
	Incidents.force("heart_attack", {"folk_id": e4.id, "warn": true})
	var win: int = int(Incidents.active()[0]["due_min"]) - SysUtil.now()
	K.expect(f, win >= 600 and win <= 1440, "heart attack warning gives hours to act (%d min)" % win)
	K.set_time(7, 15, 0)
	Incidents.on_minute()
	K.expect(f, e4.has_buff("checked_up") and WorldIface.get_coins(4) < 1000, "the household called the doctor itself")
	K.set_time(7, 21, 0)
	Incidents.on_minute()
	K.expect(f, w.get_folk(e4.id) != null and Incidents.active().is_empty() and int(Incidents.stat("heart_attack")["averted"]) >= 2, "and it was averted")
	var e5 := _elder(w, "Hope", 5)
	K.set_time(8, 8, 0)
	Incidents.force("heart_attack", {"folk_id": e5.id, "warn": true})
	e5.add_buff("in_hospital")
	K.set_time(8, 22, 0)
	Incidents.on_minute()
	K.expect(f, w.get_folk(e5.id) != null and Incidents.active().is_empty(), "being admitted to hospital in time defuses it")
	var broke := _elder(w, "Poor", 3)
	WorldIface.coins[3] = 10
	K.expect(f, not bool(Incidents.call_doctor(broke.id)["ok"]), "no doctor without coins")
	K.teardown()

func _handlers(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	Stub.calls.clear()
	Incidents.register_handler("t_code", func(ctx, args):
		Stub.calls.append({"code": true, "args": args})
		return {})
	IncidentDefs.handler_specs["t_script"] = {"script": "res://tests/incidents_handler_stub.gd", "method": "on_incident"}
	IncidentDefs.defs["t_h"] = {"label": "H", "scope": "folk", "check": "day", "base_rate_per_year": 0.0, "outcomes": [
		{"weight": 1, "effects": [{"handler": "t_code", "args": {"x": 1}}, {"handler": "t_script", "args": {"tag": "hi"}}], "text": "never shown", "kind": "info"}]}
	K.expect(f, IncidentDefs.validate_def("t_h", IncidentDefs.defs["t_h"]).is_empty(), "handler names validate against code + data registrations")
	K.notes.clear()
	var r: Dictionary = Incidents.force("t_h", {"folk_id": a.id})
	K.expect(f, Stub.calls.size() == 2 and Stub.calls[0].has("code") and Stub.calls[1]["name"] == "Ada" and Stub.calls[1]["args"]["tag"] == "hi", "both handler kinds ran with ctx + args")
	K.expect(f, str(r["text"]).find("touched by the handler (hi)") >= 0, "handler return value overrides the outcome text")
	var spec_err: Array = IncidentDefs.validate_all()
	K.expect(f, spec_err.is_empty(), "declared script handler is valid: %s" % str(spec_err))
	IncidentDefs.handler_specs["t_bad"] = {"script": "res://tests/incidents_handler_stub.gd", "method": "missing"}
	K.expect(f, IncidentDefs.validate_all().size() == 1, "a handler spec with a missing method fails validation")
	Incidents.clear_handlers()
	K.teardown()

func _statistical(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	var ids: Array = Story.townies.keys()
	ids.sort()
	var tid: int = int(ids[0])
	var t: Dictionary = Story.townies[tid]
	t["traits"] = ["clumsy"]
	var subj := IncidentSubject.of_townie(tid)
	K.expect(f, IncidentCond.check([{"has_trait": "clumsy"}], subj) and not IncidentCond.check([{"has_trait": "neat"}], subj), "townie traits feed conditions")
	t["career"] = "cook"
	t["level"] = 2
	K.expect(f, subj.skill_level("cooking") == 3 and IncidentCond.check([{"skill_at_least": ["cooking", 3]}], subj), "townie career skill feeds conditions")
	var base: float = 0.5
	t["age_days"] = 132.0
	K.expect(f, _near(Incidents.effective_rate("minor_fall", subj), base * 2.5, 0.0001), "clumsy townie has the same x2.5 fall risk as a Folk")
	t["age_days"] = 182.0
	K.expect(f, _near(Incidents.effective_rate("minor_fall", subj), base * 2.5 * 3.0, 0.0001), "elder townie x3 as well")
	# statistical resolve: summary, determinism, chronicle
	K.events.clear()
	Incidents.seed_rng(5)
	var s1: Array = []
	for i in 6:
		s1.append(str(Incidents.resolve_statistical("minor_fall", tid)["summary"]))
	var sample: Dictionary = Incidents.resolve_statistical("minor_fall", tid, 0)
	K.expect(f, bool(sample["ok"]) and sample["mode"] == "statistical" and str(sample["summary"]).find(str(t["name"])) >= 0, "one-line summary names the townie: %s" % sample["summary"])
	Incidents.seed_rng(5)
	var s2: Array = []
	for i in 6:
		s2.append(str(Incidents.resolve_statistical("minor_fall", tid)["summary"]))
	K.expect(f, s1 == s2, "statistical resolution is deterministic for a seed")
	K.expect(f, K.count_events("chronicle") >= 7, "every statistical outcome emits the chronicle hook")
	var ch: Dictionary = K.events.filter(func(e): return e[0] == "chronicle")[0][1]
	for key in ["kind", "text", "day", "subjects", "lot", "severity", "public"]:
		K.expect(f, ch.has(key), "chronicle payload has '%s'" % key)
	# far lot: summary uses the house name; coins go to a member
	var lot_n: int = int(t["lot"])
	var lr: Dictionary = Incidents.resolve_statistical("found_money", IncidentSubject.of_town_lot(lot_n))
	K.expect(f, bool(lr["ok"]) and str(lr["summary"]).begins_with("The ") and str(lr["summary"]).find("house") > 0, "far lot summary: %s" % lr["summary"])
	# notify policy: unknown townie = quiet, known = toast
	K.notes.clear()
	Incidents.force("townie_mishap", {"townie_id": tid, "outcome": 0})
	K.expect(f, K.notes.is_empty(), "far townie nobody knows: chronicle only, no toast")
	RelationshipService.add_both(a.id, tid, "friendship", 30.0)
	Incidents.force("townie_mishap", {"townie_id": tid, "outcome": 0})
	K.expect(f, K.has_note("hospital after a mishap"), "a townie the household knows: toast")
	K.expect(f, Hospital.is_in(tid) and bool(Story.townies[tid].get("in_hospital", false)), "townie is statistically in hospital")
	# fallback: an incident with no statistical block still resolves (handlers skipped)
	var fb: Dictionary = Incidents.resolve_statistical("townie_mishap", Story.alive_townies()[3]["id"], 0)
	K.expect(f, bool(fb["ok"]), "outcomes are reused when there is no statistical block")
	# hourly/daily checks reach far townies
	Incidents.reset()
	Incidents.set_level("chaotic")
	for d in TestFixture.pick(60, 25):
		K.set_time(2 + d, 3)
		Incidents.on_day()
	K.expect(f, int(Incidents.stat("townie_mishap")["statistical"]) > 0, "far townies roll for their own incidents")
	K.teardown()

func _town_scope(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	var storm := {"label": "Storm", "scope": "town", "check": "day", "base_rate_per_year": 28.0, "lot_hit": 1.0, "notify_policy": "town",
		"conditions": [{"weather_is": ["thunderstorm"]}], "risk_mults": [{"when": [{"has_object": "umbrella_stand"}], "block": true, "per_lot": true}],
		"outcomes": [{"weight": 1, "effects": [{"coins_range": [5, 5]}], "text": "{house} was hit by the storm.", "summary": "{house} was hit by the storm."}]}
	IncidentDefs.defs["t_storm"] = storm
	Weather.force("sunny")
	Incidents.set_level("normal")
	var lots: int = IncidentChecks.lot_subjects().size()
	K.expect(f, lots >= 2, "home + townie lots are candidates (%d)" % lots)
	for d in 3:
		K.set_time(2 + d, 3)
		Incidents.on_day()
	K.expect(f, int(Incidents.stat("t_storm")["triggered"]) == 0, "town condition (weather) gates the roll")
	var r: Dictionary = Incidents.force("t_storm", {})
	var hist: Array = Incidents.history(30).filter(func(h): return h["id"] == "t_storm")
	var modes: Array = hist.map(func(h): return h["mode"])
	K.expect(f, hist.size() == lots and modes.has("full") and modes.has("statistical"), "forced town incident rolls damage per lot, full for home and statistical for the rest (%s)" % str(modes))
	K.expect(f, bool(r["ok"]), "force reports ok")
	Weather.force("thunderstorm")
	Incidents.reset()
	IncidentDefs.defs["t_storm"] = storm
	Incidents.set_level("chaotic")
	K.set_time(10, 3)
	for i in 5:
		Incidents.on_day()
	var hit: int = int(Incidents.stat("t_storm")["triggered"])
	K.expect(f, hit >= lots, "in a storm the town roll hits lots (%d)" % hit)
	Weather.unforce()
	K.teardown()

func _determinism(f: Array) -> void:
	var run_a: String = _history_run(77)
	var run_b: String = _history_run(77)
	var run_c: String = _history_run(78)
	K.expect(f, run_a == run_b and run_a != "", "same seed, same incident history")
	K.expect(f, run_a != run_c, "another seed gives another history")

func _history_run(seed_v: int) -> String:
	var w := _world()
	K.make_folk(w, "Ada", [], 1)
	_elder(w, "Edda", 2)
	Story.generate_townies()
	Incidents.set_level("chaotic")
	Incidents.seed_rng(seed_v)
	for d in TestFixture.pick(90, 30):
		K.set_time(2 + d, 3)
		Incidents.on_day()
		for h in 3:
			Incidents.on_hour()
	var out: String = JSON.stringify(Incidents.history(200))
	K.teardown()
	return out

func _roundtrip(f: Array) -> void:
	var w := _world()
	var e := _elder(w, "Edda", 1)
	Incidents.set_level("normal")
	Incidents.seed_rng(31)
	Incidents.force("minor_fall", {"folk_id": e.id, "outcome": 0})
	Incidents.force("heart_attack", {"folk_id": e.id, "warn": true})
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Incidents.to_dict()))
	var next_a: float = Incidents.rng.randf()
	Incidents.seed_rng(31)
	Incidents.from_dict(snap)
	K.expect(f, Incidents.level_id() == "normal" and Incidents.surprise_mult() == 3.0, "Surprises level is saved with the game")
	K.expect(f, int(Incidents.stat("minor_fall")["forced"]) == 1 and Incidents.history(10).size() == 1 and int(Incidents.stat("heart_attack")["warned"]) == 1, "counters + history survive the round trip")
	K.expect(f, Incidents.active().size() == 1 and int(Incidents.active()[0]["due_min"]) > 0, "pending warnings survive")
	K.expect(f, _near(Incidents.rng.randf(), next_a, 0.0000001), "rng continues exactly after a load")
	# whole-game snapshot carries the block
	var s: Dictionary = SaveLoad.snapshot("t")
	K.expect(f, s["systems"].has("incidents") and s["systems"]["incidents"]["level"] == "normal", "SaveLoad snapshot has the incidents block")
	K.teardown()
