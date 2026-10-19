extends RefCounted
## Household chaos (task 07b), gas leak: only homes with a stove, a smell warning (the alarm is faster and wakes sleepers), shutting the gas off or
## calling the gas company ends it, people who do nothing walk out on their own (and the gas company is called from the street), a leak left to
## run with somebody inside goes off (injuries, a broken stove, a real fire), far lots resolve statistically, save/load mid-leak.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	var errs: Array = IncidentDefs.validate_all().filter(func(e): return str(e).contains("gas_leak") or str(e).contains("07b"))
	K.expect(f, errs.is_empty(), "the 07b schema is valid: %s" % str(errs))
	_gate_and_warning(f)
	_shut_off(f)
	_walk_out(f)
	_blast(f)
	_far_and_save(f)
	return f

func _gate_and_warning(f: Array) -> void:
	var h: Dictionary = C.setup()
	var subj := IncidentSubject.of_household(1)
	K.expect(f, Incidents.effective_rate("gas_leak", subj) > 0.0, "a home with a stove can leak (%.3f a year)" % Incidents.effective_rate("gas_leak", subj))
	K.expect(f, Incidents.effective_rate("gas_leak", subj) < 0.1, "and it is rare")
	WorldIface.world().remove_object(int(h["objs"]["stove"].id))
	Economy.refresh_objects()
	K.expect(f, Incidents.effective_rate("gas_leak", subj) == 0.0, "no stove, no gas leak")
	K.teardown()
	var h2: Dictionary = C.setup()
	var ada: Folk = h2["ada"]
	var r: Dictionary = Incidents.force("gas_leak", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]) and ChaosGas.active(1), "forced: a leak is running")
	K.expect(f, K.has_note("rotten eggs") and K.has_note("gas company"), "the smell warning says what to do")
	K.expect(f, not ada.has_buff("gas_smell"), "nobody has smelled it in the first minutes")
	C.minutes(5)
	K.expect(f, ada.has_buff("gas_smell"), "after a few minutes they smell it")
	K.teardown()

func _shut_off(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	Incidents.force("gas_leak", {"lot": "home:1", "outcome": 0})
	C.minutes(6)
	C.ev("shut_off_gas", ada)
	K.expect(f, not ChaosGas.active(1) and not ada.has_buff("gas_smell"), "shutting off the gas ends it")
	K.expect(f, K.has_note("gas is off"), "and says so")
	C.minutes(120)
	var hurt: bool = Hospital.is_in(ada) or Health.is_injured(ada)
	K.expect(f, not hurt and ChaosState.stats.get("gas_blast", 0) == 0, "nothing blew up")
	# the gas company
	Incidents.force("gas_leak", {"lot": "home:1", "outcome": 0})
	var bal: int = Economy.balance(1)
	C.ev("call_gas_company", ada)
	K.expect(f, Economy.balance(1) == bal - 60 and ChaosState.job_pending(1, "gas"), "the gas company costs 60 coins and is on the way")
	C.minutes(80)
	K.expect(f, not ChaosGas.active(1), "they made the house safe")
	K.teardown()

func _walk_out(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var bo: Folk = h["bo"]
	Incidents.force("gas_leak", {"lot": "home:1", "outcome": 0})
	var bal: int = Economy.balance(1)
	C.minutes(16)
	var rec: Dictionary = ChaosState.gas.get(1, {})
	K.expect(f, (rec.get("out", {}) as Dictionary).has(int(ada.id)) and (rec.get("out", {}) as Dictionary).has(int(bo.id)), "people who do nothing walk out after a quarter of an hour")
	K.expect(f, ChaosState.job_pending(1, "gas") and Economy.balance(1) == bal - 60, "and the gas company is called from the street")
	C.minutes(100)
	K.expect(f, not ChaosGas.active(1) and ChaosState.stats.get("gas_blast", 0) == 0, "with everybody outside the gas company ends it, no blast")
	K.expect(f, not Hospital.is_in(ada) and not Hospital.is_in(bo), "nobody was hurt")
	K.teardown()

func _blast(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var cfg: Dictionary = ChaosState.cfg("gas")
	cfg["flee_after_min"] = 99999                  # a household that ignores it completely
	cfg["blast_chance"] = 1.0
	cfg["fire_chance"] = 1.0
	Incidents.force("gas_leak", {"lot": "home:1", "outcome": 0})
	var cost0: int = int(DisasterState.lot("home:1")["cost"])
	C.minutes(95)
	K.expect(f, not ChaosGas.active(1) and int(ChaosState.stats.get("gas_blast", 0)) == 1, "left running with people inside, it goes off")
	K.expect(f, Hospital.is_in(ada) or Health.is_injured(ada), "someone is hurt")
	K.expect(f, int(DisasterState.lot("home:1")["cost"]) > cost0 and bool(WorldIface.state_get(h["objs"]["stove"], "broken", false)), "the kitchen is damaged and the stove is broken")
	K.expect(f, Fire.is_burning(h["objs"]["stove"]) or Fire.stats.get("ignited", 0) > 0, "and it catches fire")
	K.expect(f, K.has_note("went off"), "the player is told")
	K.teardown()

func _far_and_save(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var n := -1
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) > 0:
			n = int(t["lot"])
			break
	var notes0: int = K.notes.size()
	var r: Dictionary = Incidents.resolve_statistical("gas_leak", IncidentSubject.of_town_lot(n), 1)
	K.expect(f, bool(r["ok"]) and str(r["mode"]) == "statistical" and str(r["text"]).contains(" house "), "a far lot gets one plain line (%s)" % str(r["text"]))
	K.expect(f, K.notes.size() == notes0 and ChaosState.gas.is_empty(), "no toast, nothing at the player's home")
	Incidents.force("gas_leak", {"lot": "home:1", "outcome": 0})
	C.minutes(8)
	var snap: Dictionary = Incidents.to_dict()
	var before: Dictionary = ChaosState.to_dict()
	Incidents.from_dict(snap)
	K.expect(f, K.deep_eq(before, ChaosState.to_dict()), "a running leak survives save and load")
	K.teardown()
