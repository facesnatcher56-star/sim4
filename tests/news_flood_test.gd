extends RefCounted
## 19i: everyday mishaps stay out of the town chronicle (a twisted ankle, a bruise): the household still gets the toast, a bad fall still makes the
## news; a long-lost sibling is a once-per-family-line event and far townie lots never roll a text-only one; rare-in-a-life events are rare for a
## 28-day game year.

const K = preload("res://tests/systems_kit.gd")

func _chronicle_has(kind: String) -> bool:
	for e in ChronicleHook.recent:
		if str(e["kind"]) == kind:
			return true
	return false

func run() -> Array:
	var f: Array = []
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	IncidentContent.install()
	Incidents.set_level("rare")
	K.set_time(5, 12, 0)
	WorldIface.coins[1] = 2000
	ChronicleHook.reset()
	var a := K.make_folk(w, "Ada", [], 1)
	K.notes.clear()
	Incidents.force("slip_fall", {"folk_id": a.id, "outcome": 2})
	K.expect(f, K.has_note("twisted an ankle"), "the household still hears about the twisted ankle")
	K.expect(f, not _chronicle_has("slip_fall"), "but a twisted ankle is not town news")
	Incidents.force("slip_fall", {"folk_id": a.id, "outcome": 3})
	K.expect(f, not _chronicle_has("slip_fall"), "nor is a bruise")
	var e := K.make_folk(w, "Eli", [], 1, Vector2i(12, 12), "elder")
	Incidents.force("slip_fall", {"folk_id": e.id, "outcome": 1})
	K.expect(f, _chronicle_has("slip_fall"), "a bad fall that ends in hospital is news")
	ChronicleHook.reset()
	# rare in a life: per 28-day game year the everyday life events are well under one in ten per person
	for id in ["layoff", "identity_theft"]:
		K.expect(f, float(IncidentDefs.get_def(id)["base_rate_per_year"]) <= 0.05, "%s is rare for a 28-day year (%.3f)" % [id, float(IncidentDefs.get_def(id)["base_rate_per_year"])])
	# a far townie lot never rolls a long-lost sibling that is only words
	var st: Array = (IncidentDefs.get_def("long_lost_family")["statistical"] as Dictionary)["outcomes"]
	K.expect(f, str(st[0].get("summary", "x")) == "", "far homes say nothing about a long-lost sibling")
	K.teardown()
	return f
