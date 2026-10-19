extends RefCounted
## Household chaos (task 07), the whole town: far lots use the statistical outcomes ("The Ashby house had a burst pipe ..."), pay through the
## townie's coins, never toast the player, empty or all-baby lots never roll, and the far "messy" answer for roaches is stable and about a quarter.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_statistical(f)
	_empty_and_messy(f)
	return f

func _far_lot() -> int:
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) > 0:
			return int(t["lot"])
	return -1

func _coins(n: int) -> int:
	var c: int = 0
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) == n:
			c += int(t["coins"])
	return c

func _statistical(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var n: int = _far_lot()
	K.expect(f, n > 0, "there are far lots")
	var subj := IncidentSubject.of_town_lot(n)
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) == n:
			t["coins"] = 1000
	var before: int = _coins(n)
	for id in ["burst_pipe", "toilet_overflow", "appliance_breakdown", "roach_infestation"]:
		K.expect(f, Incidents.effective_rate(id, subj) >= 0.0, "%s can be rolled for a far lot" % id)
		var notes0: int = K.notes.size()
		var r: Dictionary = Incidents.resolve_statistical(id, subj, 0)
		K.expect(f, bool(r["ok"]) and str(r["mode"]) == "statistical", "%s resolves statistically" % id)
		K.expect(f, str(r["text"]).begins_with("The ") and str(r["text"]).contains(" house "), "%s: one plain line about the house (%s)" % [id, str(r["text"])])
		K.expect(f, K.notes.size() == notes0, "%s: no toast for a far lot (notify policy household)" % id)
	K.expect(f, _coins(n) == before - (90 + 60 + 80), "the repairs cost the far family 230 coins (%d -> %d)" % [before, _coins(n)])
	K.expect(f, ChaosState.leaks.is_empty() and ChaosState.pests.is_empty() and ChaosClock.broken_objects(1).is_empty(), "far events never touch the player's home")
	K.teardown()

func _empty_and_messy(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var empty := IncidentSubject.of_town_lot(9999)
	K.expect(f, empty.members().is_empty(), "an unused lot has no members")
	K.expect(f, not IncidentChecks.lot_subjects().any(func(s): return s.lot_key == "town:9999"), "empty lots are never rolled")
	K.expect(f, Incidents.effective_rate("burst_pipe", empty) == 0.0 and Incidents.effective_rate("roach_infestation", empty) == 0.0, "and have no rate")
	# far messy: stable within a week, about a quarter of lots over many weeks
	var messy := 0
	var total := 0
	for wk in 40:
		K.set_time(1 + wk * 7, 12)
		for lot in range(1, 11):
			total += 1
			var a: int = ChaosConds.far_mess("town:%d" % lot)
			K.set_time(3 + wk * 7, 12)
			if a != ChaosConds.far_mess("town:%d" % lot):
				K.expect(f, false, "far messy answer changed inside a week")
			K.set_time(1 + wk * 7, 12)
			messy += 1 if a > 0 else 0
	K.expect(f, messy >= total * 0.17 and messy <= total * 0.33, "about 25 percent of far lots are messy (%d of %d)" % [messy, total])
	K.teardown()
