extends RefCounted
## Household chaos (task 07), water: a burst pipe (warning, check the pipes, damage by the hour, mould, DIY with the handiness skill, plumber),
## an overflowing toilet that stops by itself, costs through Economy, save/load mid-leak, and the schema of data/incidents/07_chaos.json.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	var errs: Array = IncidentDefs.validate_all()
	var mine: Array = errs.filter(func(e): return str(e).contains("burst_pipe") or str(e).contains("toilet_overflow") or str(e).contains("appliance_breakdown") or str(e).contains("roach_infestation") or str(e).contains("07_chaos"))
	K.expect(f, mine.is_empty(), "the 07_chaos.json schema is valid: %s" % str(mine))
	_burst(f)
	_diy(f)
	_plumber(f)
	_warning(f)
	_overflow(f)
	_save(f)
	return f

func _burst(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var r: Dictionary = Incidents.force("burst_pipe", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]), "forced")
	var lk: Dictionary = ChaosState.leak_of(1)
	K.expect(f, not lk.is_empty() and str(lk["kind"]) == "pipe", "water is running")
	var o = WorldIface.get_object(int(lk["obj"]))
	K.expect(f, bool(WorldIface.state_get(o, "broken", false)), "the fixture is broken")
	K.expect(f, ada.has_buff("plumbing_trouble") and ada.has_buff("home_damaged"), "residents know: water and a damaged home")
	K.expect(f, K.has_note("plumber") and K.has_note("handiness"), "the player is told what to do (plumber, handiness)")
	var cost0: int = int(DisasterState.lot("home:1")["cost"])
	K.expect(f, cost0 >= 40, "the burst costs damage straight away (%d)" % cost0)
	C.hours(3)
	var cost3: int = int(DisasterState.lot("home:1")["cost"])
	K.expect(f, cost3 == cost0 + 3 * 14, "damage grows 14 coins an hour (%d -> %d)" % [cost0, cost3])
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) == 0.0, "no mould yet")
	C.hours(8)
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) >= 0.35 and ada.has_buff("mouldy_home"), "left alone, damp turns to mould (%.2f)" % float(DisasterState.lot("home:1")["mould"]))
	# the repairers fix the damage (existing mailbox interaction) after the leak is stopped
	ChaosClock.stop_leak(1, "someone")
	var q: int = DisasterAftermath.repair_quote(1)
	K.expect(f, q > 0, "water damage has a repair quote (%d)" % q)
	var bal: int = Economy.balance(1)
	DisasterAftermath.repair(1)
	K.expect(f, Economy.balance(1) == bal - q and int(DisasterState.lot("home:1")["cost"]) == 0, "the repairers are paid through Economy")
	K.teardown()

func _diy(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	ada.skills["handiness"]["level"] = 10
	Incidents.force("burst_pipe", {"lot": "home:1", "outcome": 0})
	var done := false
	for i in 20:
		C.ev("fix_leak", ada)
		if ChaosState.leak_of(1).is_empty():
			done = true
			break
	K.expect(f, done, "a handy sim stops the leak themselves")
	K.expect(f, not ada.has_buff("plumbing_trouble") and K.has_note("is fixed by Ada"), "buff gone, told who fixed it")
	K.expect(f, int(ChaosState.stats.get("leaks_fixed", 0)) == 1, "counted")
	K.teardown()
	# an unskilled sim fails sometimes: with level 0 the chance is 30 percent; across seeds some fail and parts cost coins
	var fails_n := 0
	var wins := 0
	for s in 16:
		var h2: Dictionary = C.setup()
		Incidents.seed_rng(100 + s)
		Incidents.force("burst_pipe", {"lot": "home:1", "outcome": 0})
		var coins0: int = Economy.balance(1)
		C.ev("fix_leak", h2["ada"])
		if ChaosState.leak_of(1).is_empty():
			wins += 1
		else:
			fails_n += 1
			K.expect(f, Economy.balance(1) == coins0 - 12, "a failed patch costs spare parts")
		K.teardown()
	K.expect(f, wins >= 1 and wins <= 11 and fails_n >= 5, "level 0 handiness: %d of 16 DIY attempts worked (about 30 percent)" % wins)

func _plumber(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	Incidents.force("burst_pipe", {"lot": "home:1", "outcome": 0})
	var o = WorldIface.get_object(int(ChaosState.leak_of(1)["obj"]))
	var bal: int = Economy.balance(1)
	C.ev("call_plumber", ada)
	K.expect(f, Economy.balance(1) == bal - 90, "the plumber costs 90 coins (paid now)")
	C.ev("call_plumber", ada)
	K.expect(f, Economy.balance(1) == bal - 90 and K.has_note("already on the way"), "calling twice does not charge twice")
	K.expect(f, not ChaosState.leak_of(1).is_empty(), "still leaking until they arrive")
	C.minutes(100)
	K.expect(f, ChaosState.leak_of(1).is_empty() and not bool(WorldIface.state_get(o, "broken", false)), "the plumber stopped it and the fixture works again")
	K.teardown()
	# too poor
	var h2: Dictionary = C.setup()
	WorldIface.coins[1] = 20
	Incidents.force("burst_pipe", {"lot": "home:1", "outcome": 0})
	C.ev("call_plumber", h2["ada"])
	K.expect(f, ChaosState.jobs.is_empty() and K.has_note("cannot afford"), "a poor household is told it cannot afford the plumber")
	K.teardown()

func _warning(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var r: Dictionary = IncidentFlow.start("burst_pipe", IncidentSubject.of_household(1))
	K.expect(f, str(r.get("mode", "")) == "warned" and Incidents.active().size() == 1, "the pipes knock first")
	K.expect(f, K.has_note("knocking") and ChaosState.leak_of(1).is_empty(), "warning toast, no water yet")
	C.minutes(61)
	K.expect(f, not ChaosState.leak_of(1).is_empty(), "left alone, the pipe bursts an hour later")
	K.teardown()
	var h2: Dictionary = C.setup()
	IncidentFlow.start("burst_pipe", IncidentSubject.of_household(1))
	h2["ada"].add_buff("pipes_checked")
	C.minutes(61)
	K.expect(f, ChaosState.leak_of(1).is_empty() and K.has_note("pipes held"), "checking the pipes in time averts it")
	K.expect(f, Incidents.effective_rate("burst_pipe", IncidentSubject.of_household(1)) < 0.18 * 0.2, "checked pipes cut the rate")
	K.teardown()

func _overflow(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	Incidents.force("toilet_overflow", {"lot": "home:1", "outcome": 0})
	var lk: Dictionary = ChaosState.leak_of(1)
	var toilet = h["objs"]["toilet"]
	K.expect(f, str(lk["kind"]) == "overflow" and int(lk["obj"]) == int(toilet.id) and bool(WorldIface.state_get(toilet, "broken", false)), "the toilet overflows and breaks")
	K.expect(f, K.has_note("overflowing"), "told in plain words")
	C.hours(4)
	K.expect(f, ChaosState.leak_of(1).is_empty() and not ada.has_buff("plumbing_trouble"), "the water stops by itself after a few hours")
	K.expect(f, bool(WorldIface.state_get(toilet, "broken", false)) and ada.has_buff("broken_things"), "the toilet stays broken until repaired")
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) == 0.0, "an overflow does not cause mould")
	C.ev("call_handyperson", ada)
	C.minutes(90)
	K.expect(f, not bool(WorldIface.state_get(toilet, "broken", false)) and not ada.has_buff("broken_things"), "a handyperson fixes it")
	K.teardown()

func _save(f: Array) -> void:
	var h: Dictionary = C.setup()
	Incidents.force("burst_pipe", {"lot": "home:1", "outcome": 0})
	C.ev("call_plumber", h["ada"])
	C.minutes(10)
	var snap: Dictionary = Incidents.to_dict()
	var before: Dictionary = ChaosState.to_dict()
	ChaosState.reset()
	Incidents.from_dict(snap)
	K.expect(f, K.deep_eq(before, ChaosState.to_dict()), "leaks, jobs and counters survive save and load")
	K.expect(f, not ChaosState.leak_of(1).is_empty() and ChaosState.job_pending(1, "plumber"), "still leaking, plumber still coming")
	K.teardown()
