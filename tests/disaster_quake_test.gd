extends RefCounted
## Earthquake: no warning, things fall and break, cracks need repairs, exposed people can be hurt, hiding helps.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	var bo: Folk = h["bo"]
	D.cfg_set("quake", "object_hit", [1.0, 1.0, 1.0])
	D.cfg_set("quake", "destroy_share", 1.0)
	D.cfg_set("quake", "in_hurt", [1.0, 1.0, 1.0])
	D.cfg_set("quake", "cover_hurt", [0.0, 0.0, 0.0])
	D.cfg_set("quake", "in_kill", [0.0, 0.0, 0.0])
	bo.tile = Vector2i(14, 15)                    # next to the toilet: hiding
	var subj := IncidentSubject.of_town_lot(0)
	K.expect(f, Incidents.effective_rate("earthquake", subj) > 0.0 and IncidentDefs.get_def("earthquake")["check"] == "day", "quakes can happen any day, no weather needed")
	var n0: int = w.objects.size()
	var r: Dictionary = D.force_home("earthquake", 1)
	K.expect(f, bool(r["ok"]) and K.has_note("ground is shaking"), "no warning, just the quake")
	K.expect(f, w.objects.size() < n0 or bool(h["objs"]["tv"].state.get("broken", false)), "things fell and broke")
	K.expect(f, float(DisasterState.lot("home:1")["cracks"]) > 0.0 and int(DisasterState.lot("home:1")["cost"]) > 0, "walls cracked: repairs needed")
	K.expect(f, ada.has_buff("injured") and not bo.has_buff("injured"), "an exposed person is hurt, one taking cover is not")
	K.expect(f, int(DisasterState.counts.get("quake", 0)) == 1, "counted once")
	K.teardown()
	return f
