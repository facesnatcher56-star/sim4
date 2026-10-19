extends RefCounted
## Power outage: lights, electronics and heating stop (marker buff + lamps off + gated interactions), the fridge spoils, a generator
## keeps a home lit, the utility cut-off for overdue bills, recovery, far lots are quiet.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	var lamp = h["objs"]["lamp"]
	var fridge = h["objs"]["fridge"]
	WorldIface.state_set(lamp, "on", true)
	WorldIface.state_set(fridge, "stock", 10.0)
	K.set_time(5, 20)
	var r: Dictionary = D.force_home("power_outage")
	K.expect(f, bool(r["ok"]) and ada.has_buff("power_out"), "forced outage marks the household (%s)" % str(r))
	K.expect(f, not bool(WorldIface.state_get(lamp, "on", true)), "lamps go dark")
	K.expect(f, DisasterState.affects("outage", 1) and DisasterState.running("outage"), "the outage is running for the home lot")
	var tv_tests: Array = SimEnv.data().interaction_def("watch_tv").get("tests", [])
	K.expect(f, tv_tests.has({"lacks_buff": "power_out"}), "TV interaction needs power")
	var fridge_tests: Array = SimEnv.data().interaction_def("grab_snack").get("tests", [])
	K.expect(f, not fridge_tests.has({"lacks_buff": "power_out"}), "the fridge can still be opened")
	K.expect(f, K.has_note("power"), "the home lot is told")
	D.run_hours(6)
	K.expect(f, int(float(WorldIface.state_get(fridge, "stock", 10.0))) < 10, "food spoils during a long outage (stock %s)" % str(WorldIface.state_get(fridge, "stock", 0)))
	K.expect(f, float(WorldIface.state_get(fridge, "spoiled", 0.0)) > 0.0, "spoiled items counted")
	D.run_hours(9)
	K.expect(f, not ada.has_buff("power_out") and bool(WorldIface.state_get(lamp, "on", false)), "power returns: marker gone, lamp back on")
	K.expect(f, not DisasterState.running("outage"), "the outage ended")
	# generator
	DisasterState.active.clear()
	var gen = w.add_object("generator", Vector2i(34, 34))
	Economy.refresh_objects()
	WorldIface.state_set(lamp, "on", true)
	DisasterState.cfg("outage")["hours"] = [6, 8]          # long enough for the fuel to run out (the shipped range starts at 3 hours: seed luck)
	D.force_home("power_outage")
	K.expect(f, not ada.has_buff("power_out") and bool(WorldIface.state_get(lamp, "on", false)), "a generator keeps the lights on")
	D.run_hours(3)
	K.expect(f, float(WorldIface.state_get(gen, "fuel", 10.0)) < 10.0, "the generator burns fuel")
	WorldIface.state_set(gen, "fuel", 0.0)
	D.run_hours(1)
	K.expect(f, ada.has_buff("power_out"), "out of fuel: the power is off after all")
	# utility cut-off for overdue bills
	DisasterState.active.clear()
	ada.remove_buff("power_out")
	w.objects.erase(gen.id)
	Economy.bills.append({"id": 99, "hid": 1, "amount": 80, "base": 80, "issued": 1, "due": 2, "paid": false, "late": true, "fee": 8})
	var rate: float = Incidents.effective_rate("utility_cutoff", IncidentSubject.of_household(1))
	K.expect(f, rate > 3.0, "overdue bills make a utility cut-off likely (%.1f/yr)" % rate)
	Economy.bills.clear()
	K.expect(f, Incidents.effective_rate("utility_cutoff", IncidentSubject.of_household(1)) == 0.0, "no cut-off when the bills are paid")
	# far lots: quiet record, no damage
	Story.generate_townies()
	var all: Dictionary = Incidents.force("power_outage", {})
	K.expect(f, bool(all["ok"]), "the whole town can lose power")
	K.teardown()
	return f
