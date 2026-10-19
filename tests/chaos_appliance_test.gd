extends RefCounted
## Household chaos (task 07), broken appliances: one working appliance stops (fridge food starts to turn), the player is told the price of a
## handyperson, DIY repair (existing Repair interaction) or the handyperson fixes everything broken, the right gating (no appliance: no incident,
## nobody grown-up at home: no incident) and that handiness lowers the rate.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_breakdown(f)
	_handyperson(f)
	_gating(f)
	return f

func _breakdown(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var fridge = h["objs"]["fridge"]
	var r: Dictionary = Incidents.force("appliance_breakdown", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]), "forced")
	var broken: Array = ChaosClock.broken_objects(1)
	K.expect(f, broken.size() == 1, "exactly one appliance broke (%d)" % broken.size())
	K.expect(f, ada.has_buff("broken_things"), "residents notice (buff)")
	K.expect(f, K.has_note("has stopped working") and K.has_note("handyperson") and K.has_note("handiness"), "plain words: what broke, what to do")
	K.expect(f, ChaosClock.handy_quote(1) >= 15 + 12, "a handyperson quote exists (%d)" % ChaosClock.handy_quote(1))
	# a broken fridge: food turns
	WorldIface.state_set(fridge, "broken", false)
	for o in ChaosClock.broken_objects(1):
		ChaosClock.unbreak(1, o)
	var before: float = float(WorldIface.state_get(fridge, "spoiled", 0.0))
	ChaosState.leaks.clear()
	var res: Dictionary = {}
	for i in 30:
		res = ChaosEvents.appliance(1)
		if bool(WorldIface.state_get(fridge, "broken", false)):
			break
		for o2 in ChaosClock.broken_objects(1):
			ChaosClock.unbreak(1, o2)
	K.expect(f, bool(WorldIface.state_get(fridge, "broken", false)) and float(WorldIface.state_get(fridge, "spoiled", 0.0)) > before and str(res["text"]).contains("starting to turn"), "a broken fridge spoils food, and says so")
	K.teardown()

func _handyperson(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	WorldIface.state_set(h["objs"]["tv"], "broken", true)
	WorldIface.state_set(h["objs"]["stove"], "broken", true)
	ChaosClock.sync_markers(1)
	K.expect(f, ada.has_buff("broken_things"), "marker follows broken objects from any source")
	var quote: int = ChaosClock.handy_quote(1)
	var bal: int = Economy.balance(1)
	C.ev("call_handyperson", ada)
	K.expect(f, Economy.balance(1) == bal - quote, "the handyperson is paid the quote (%d) through Economy" % quote)
	K.expect(f, bool(WorldIface.state_get(h["objs"]["tv"], "broken", false)), "nothing fixed until they arrive")
	C.minutes(80)
	K.expect(f, ChaosClock.broken_objects(1).is_empty() and not ada.has_buff("broken_things"), "everything fixed after the visit")
	K.expect(f, K.has_note("fixed 2 broken things"), "told how many")
	K.teardown()

func _gating(f: Array) -> void:
	var h: Dictionary = C.setup()
	var subj := IncidentSubject.of_household(1)
	var base: float = Incidents.effective_rate("appliance_breakdown", subj)
	K.expect(f, absf(base - 0.9) < 0.001, "base rate 0.9 a year (%.3f)" % base)
	h["ada"].skills["handiness"]["level"] = 4
	K.expect(f, Incidents.effective_rate("appliance_breakdown", subj) < base * 0.7, "someone handy lowers it")
	h["ada"].skills["handiness"]["level"] = 0
	# nothing that can break: a home with only a bed
	K.teardown()
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	K.make_folk(w, "Solo", [], 1, Vector2i(5, 5))
	w.add_object("bed", Vector2i(8, 8))
	Economy.refresh_objects()
	K.expect(f, Incidents.effective_rate("appliance_breakdown", IncidentSubject.of_household(1)) == 0.0, "no appliance, no breakdown")
	K.teardown()
	# only a baby at home: nobody can notice or care, so no chaos
	var w2 := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	K.make_folk(w2, "Tiny", [], 1, Vector2i(5, 5), "baby")
	w2.add_object("fridge", Vector2i(8, 8))
	w2.add_object("sink", Vector2i(10, 8))
	Economy.refresh_objects()
	for id in ["appliance_breakdown", "burst_pipe", "toilet_overflow", "roach_infestation"]:
		K.expect(f, Incidents.effective_rate(id, IncidentSubject.of_household(1)) == 0.0, "%s never rolls for a home with only a baby" % id)
	K.teardown()
