extends RefCounted
## Flood: floor-level things get wet / broken, sandbags hold it back, mould follows the flood and spreads until it is scrubbed,
## the forecast watch and the rain-streak conditions.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	D.cfg_set("flood", "object_hit", [1.0, 1.0, 1.0])
	D.cfg_set("flood", "destroy_share", 1.0)
	# conditions: needs a long wet spell
	Weather.force("rain")
	var subj := IncidentSubject.of_town_lot(0)
	DisasterState.rain_days = 0
	K.expect(f, Incidents.effective_rate("flood", subj) == 0.0, "no flood without days of rain")
	DisasterState.rain_days = 3
	K.expect(f, Incidents.effective_rate("flood", subj) > 0.0, "after days of rain a flood is possible")
	Weather.force("sunny")
	K.expect(f, Incidents.effective_rate("flood", subj) == 0.0, "no flood in the sunshine")
	# the flood
	var fridge = h["objs"]["fridge"]
	var fridge_id: int = fridge.id
	var r: Dictionary = D.force_home("flood", 1)
	K.expect(f, bool(r["ok"]) and K.has_note("flooded"), "the flood is announced")
	K.expect(f, w.get_object(fridge_id) == null or bool(WorldIface.state_get(fridge, "broken", false)), "ground-floor appliances are ruined")
	K.expect(f, float(DisasterState.lot("home:1")["flood"]) > 0.0 and ada.has_buff("home_damaged"), "the lot is marked flooded and damaged")
	K.expect(f, DisasterState.running("flood"), "the flood runs for hours")
	D.run_hours(31)
	K.expect(f, not DisasterState.running("flood") and float(DisasterState.lot("home:1")["mould"]) > 0.0, "after the water: mould (%.2f)" % float(DisasterState.lot("home:1")["mould"]))
	K.expect(f, ada.has_buff("mouldy_home"), "mouldy home buff")
	var m0: float = float(DisasterState.lot("home:1")["mould"])
	DisasterAftermath.on_day(20)
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) > m0, "mould creeps on each day")
	# scrubbing
	for i in 4:
		SimEnv.emit("game_event", "scrubbed_mould", {"folk_id": ada.id, "object_id": -1, "target_id": -1})
	K.expect(f, float(DisasterState.lot("home:1")["mould"]) == 0.0 and not ada.has_buff("mouldy_home"), "scrubbing clears the mould")
	# sandbags
	DisasterState.reset()
	w.add_object("sandbags", Vector2i(35, 35))
	Economy.refresh_objects()
	D.force_home("flood", 0)
	K.expect(f, float(DisasterState.lot("home:1")["flood"]) == 0.0 and K.has_note("preparations paid off"), "sandbags hold back a light flood")
	var with_bags: float = Incidents.effective_rate("flood", IncidentSubject.of_household(1))
	K.expect(f, with_bags >= 0.0, "effective rate callable for a prepared home")
	# watch from the forecast
	DisasterState.reset()
	Weather.force("rain")
	DisasterState.rain_days = 3
	K.expect(f, DisasterOdds.day_chance("flood", "rain", "spring") > 0.0 and DisasterOdds.day_chance("flood", "sunny", "spring") == 0.0, "flood chance exists only after days of rain")
	Weather.unforce()
	K.teardown()
	return f