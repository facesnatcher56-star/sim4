extends RefCounted
## Household chaos (task 07b), slow mould as its own incident: only damp homes (wet bathroom surfaces, long rain, unrepaired flood water) can get it,
## a first patch is a warning that grows by the day until scrubbed, a home that already has mould does not roll again, far lots resolve statistically.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_gate(f)
	_growth_and_scrub(f)
	_far(f)
	return f

func _wet(h: Dictionary, on: bool) -> void:
	for id in ["sink", "bathtub", "shower"]:
		WorldIface.state_set(h["objs"][id], "dirtiness", 8.0 if on else 0.0)

func _gate(f: Array) -> void:
	var h: Dictionary = C.setup()
	var subj := IncidentSubject.of_household(1)
	_wet(h, false)
	K.expect(f, Incidents.effective_rate("mould_growth", subj) == 0.0, "a clean dry home gets no mould")
	_wet(h, true)
	K.expect(f, absf(Incidents.effective_rate("mould_growth", subj) - 0.4) < 0.001, "a damp, grubby bathroom can (%.2f a year)" % Incidents.effective_rate("mould_growth", subj))
	_wet(h, false)
	DisasterState.rain_days = 5
	K.expect(f, Incidents.effective_rate("mould_growth", subj) > 0.0, "a long wet spell makes any bathroom damp")
	DisasterState.rain_days = 0
	DisasterState.lot("home:1")["flood"] = 0.2
	K.expect(f, Incidents.effective_rate("mould_growth", subj) > 0.0, "so does flood water that was never dealt with")
	DisasterState.lot("home:1")["flood"] = 0.0
	DisasterState.lot("home:1")["mould"] = 0.4
	_wet(h, true)
	K.expect(f, Incidents.effective_rate("mould_growth", subj) == 0.0, "mould that is already there does not roll again")
	K.teardown()

func _growth_and_scrub(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	_wet(h, true)
	var r: Dictionary = Incidents.force("mould_growth", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]) and absf(float(DisasterState.lot("home:1")["mould"]) - 0.3) < 0.001, "a first patch of mould (0.30)")
	K.expect(f, ada.has_buff("mouldy_home"), "the household feels it (Mouldy Home)")
	K.expect(f, K.has_note("Scrub"), "and is told to scrub it")
	DisasterAftermath._mould(0)
	DisasterAftermath._mould(0)
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) >= 0.55, "left alone it spreads day by day (%.2f)" % float(DisasterState.lot("home:1")["mould"]))
	C.ev("scrubbed_mould", ada)
	C.ev("scrubbed_mould", ada)
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) == 0.0 and not ada.has_buff("mouldy_home"), "scrubbing clears it")
	K.teardown()

func _far(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var n := -1
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) > 0:
			n = int(t["lot"])
			break
	var seen := 0
	for wk in 30:
		K.set_time(1 + wk * 7, 12)
		if Incidents.effective_rate("mould_growth", IncidentSubject.of_town_lot(n)) > 0.0:
			seen += 1
	K.expect(f, seen > 0 and seen < 20, "about a fifth of far lots are damp in a given week (%d of 30)" % seen)
	var notes0: int = K.notes.size()
	var r: Dictionary = Incidents.resolve_statistical("mould_growth", IncidentSubject.of_town_lot(n), 0)
	K.expect(f, bool(r["ok"]) and str(r["text"]).contains("mould"), "a far lot gets one line (%s)" % str(r["text"]))
	K.expect(f, K.notes.size() == notes0 and DisasterState.lots.get("home:1", {}).is_empty(), "no toast and nothing at the player's home")
	K.teardown()
