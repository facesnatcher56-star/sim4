extends RefCounted
## Blizzard (roads closed, heating bills, exposure), hailstorm, wildfire (smoke, Fire hand-over), meteor (easter egg), forecast watch throttle.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	_blizzard(f)
	_hail(f)
	_wildfire(f)
	_meteor(f)
	_watches(f)
	return f

func _blizzard(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	Weather.force("snow")
	var subj := IncidentSubject.of_town_lot(0)
	K.set_time(2, 8)
	K.expect(f, Seasons.current() != "winter" or Incidents.effective_rate("blizzard", subj) > 0.0, "blizzard needs winter snow")
	D.cfg_set("blizzard", "object_hit", [1.0, 1.0, 1.0])
	var u0: float = float(Economy.usage.get(1, 0.0))
	ada.set_meta("outdoors", true)
	D.force_home("blizzard", 0)
	K.expect(f, DisasterState.travel_blocked() and K.has_note("roads are closed"), "roads close during a blizzard")
	var chk: Dictionary = NeighborhoodTravel.can_travel([ada.id], "home")
	K.expect(f, not bool(chk["ok"]) and str(chk["reason"]).find("blizzard") >= 0, "travel refused with a reason (%s)" % str(chk))
	D.run_hours(3)
	K.expect(f, float(Economy.usage.get(1, 0.0)) > u0 + 8.0, "heating bills climb (usage %.0f)" % float(Economy.usage.get(1, 0.0)))
	K.expect(f, ada.has_buff("cold"), "being outside in a blizzard is cold")
	D.run_hours(22)
	K.expect(f, not DisasterState.travel_blocked() and K.has_note("roads are open"), "the roads reopen")
	Weather.unforce()
	K.teardown()

func _hail(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	D.cfg_set("hail", "object_hit", [1.0, 1.0, 1.0])
	D.cfg_set("hail", "out_hurt", [0.0, 0.0, 0.0])
	D.force_home("hailstorm", 1)
	K.expect(f, K.has_note("hail") and float(WorldIface.state_get(h["objs"]["garden_plot"], "growth", 1.0)) == 0.0, "hail flattens the crops")
	K.expect(f, float(DisasterState.lot("home:1")["roof"]) > 0.0, "roof dented")
	K.teardown()

func _wildfire(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	Weather.force("heatwave")
	K.set_time(30, 12)
	DisasterState.dry_days = 0
	var subj := IncidentSubject.of_town_lot(0)
	K.expect(f, Incidents.effective_rate("wildfire", subj) == 0.0, "no wildfire without a dry spell")
	DisasterState.dry_days = 5
	K.expect(f, Seasons.current() != "summer" or Incidents.effective_rate("wildfire", subj) > 0.0, "a dry hot summer allows wildfires")
	ada.set_meta("outdoors", true)
	D.force_home("wildfire", 0)                   # power 1: smoke only
	D.run_hours(2)
	K.expect(f, DisasterState.running("wildfire") and ada.has_buff("smoky"), "smoke over town: outdoor folk breathe it")
	K.expect(f, K.has_note("wildfire is burning"), "headline")
	D.force_home("wildfire", 1)                   # power 2: hand over to Fire when it exists
	K.expect(f, K.has_note("alight") or K.has_note("wildfire"), "a bigger blaze reaches the lot")
	Weather.unforce()
	K.teardown()

func _meteor(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	var rate: float = Incidents.effective_rate("meteor_strike", IncidentSubject.of_town_lot(0))
	K.expect(f, absf(rate - 0.0005) < 0.00001, "freak meteor: about 1 in 2000 years (%.5f)" % rate)
	ada.tile = Vector2i(50, 50)
	D.force_home("meteor_strike")
	K.expect(f, D.count_objects(w, "meteorite") == 1, "something crashed down: a meteorite is left (%d)" % D.count_objects(w, "meteorite"))
	K.expect(f, not ada.has_buff("injured"), "harmless when nobody stands there")
	var rock: int = -1
	for o in w.objects.values():
		if o.def_id == "meteorite":
			rock = o.id
	if rock >= 0:
		var c0: int = WorldIface.get_coins(1)
		SimEnv.emit("game_event", "meteorite_found", {"folk_id": ada.id, "object_id": rock, "target_id": -1})
		K.expect(f, WorldIface.get_coins(1) > c0 and w.get_object(rock) == null, "a museum buys the meteorite")
	K.teardown()

func _watches(f: Array) -> void:
	var w := D.setup()
	D.home(w)
	K.set_time(40, 20)
	Weather.force("snow")
	DisasterForecast.on_day(40)
	var n: int = K.notes.size()
	DisasterForecast.on_day(41)
	K.expect(f, K.notes.size() == n, "forecast watches are throttled")
	Weather.unforce()
	K.teardown()
