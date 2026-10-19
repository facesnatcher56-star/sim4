extends RefCounted
## Gameplay effects: marker + comfort buffs, shelter, interaction gating, autonomy weights, crops, bills, lightning, fishing, walking.

const W = preload("res://tests/weather_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_markers_and_shelter(f)
	_comfort_buffs(f)
	_gating_and_autonomy(f)
	_crops(f)
	_frost(f)
	_bills(f)
	_lightning(f)
	_fishing(f)
	_walk_and_events(f)
	return f

func _markers_and_shelter(f: Array) -> void:
	var w: StubWorld = W.setup()
	var a: Folk = K.make_folk(w, "Ann")
	SimEnv.clock().total_minutes = W.at(3, 10)
	Weather.force("rain")
	W.outdoors(a, true)
	W.run_min(10)
	W.expect(f, a.has_buff("wx_wet"), "rain marker wx_wet applied")
	W.expect(f, a.has_buff("wx_outside"), "outside marker applied")
	W.expect(f, a.has_buff("soaked"), "10 minutes in the rain soaks you")
	W.expect(f, not a.has_buff("wx_clear"), "no clear-sky marker in the rain")
	# shelter: go indoors, soaked wears off faster than its 90 minute timer
	W.outdoors(a, false)
	W.run_min(2)
	W.expect(f, not a.has_buff("wx_outside"), "outside marker removed indoors")
	var hyg: float = a.get_stat_value("hygiene")
	W.run_min(60)
	W.expect(f, not a.has_buff("soaked"), "indoors you dry off quickly")
	W.expect(f, absf(a.get_stat_value("hygiene") - hyg) < 0.01, "no weather need-drain indoors")
	# clearing up swaps the markers
	Weather.force("sunny")
	W.run_min(2)
	W.expect(f, a.has_buff("wx_clear") and not a.has_buff("wx_wet"), "markers follow the weather")
	Weather.force("cloudy")
	W.run_min(2)
	W.expect(f, not a.has_buff("wx_clear") and not a.has_buff("wx_wet"), "cloudy has no marker")
	W.teardown()

func _comfort_buffs(f: Array) -> void:
	var w: StubWorld = W.setup()
	var a: Folk = K.make_folk(w, "Ann")
	# need drain while outside in the rain
	SimEnv.clock().total_minutes = W.at(3, 10)
	Weather.force("rain")
	W.outdoors(a, true)
	var h0: float = a.get_stat_value("hygiene")
	var c0: float = a.get_stat_value("comfort")
	W.run_min(30)
	W.expect(f, a.get_stat_value("hygiene") < h0 - 2.0, "rain/mud drains hygiene outdoors")
	W.expect(f, a.get_stat_value("comfort") < c0, "rain drains comfort outdoors")
	W.teardown()
	# cold
	w = W.setup()
	a = K.make_folk(w, "Bo")
	SimEnv.clock().total_minutes = W.at(22, 9)       # winter
	Weather.force("cold_snap")
	W.outdoors(a, true)
	W.run_min(20)
	W.expect(f, a.has_buff("cold"), "cold snap gives the cold buff outdoors (feels %.1f)" % Weather.feels_like())
	W.outdoors(a, false)
	W.run_min(70)
	W.expect(f, not a.has_buff("cold"), "warming up indoors removes cold")
	W.teardown()
	# heat + sunburn + fresh air
	w = W.setup()
	a = K.make_folk(w, "Cy")
	SimEnv.clock().total_minutes = W.at(11, 11)      # summer
	Weather.force("heatwave")
	W.outdoors(a, true)
	W.run_min(20)
	W.expect(f, a.has_buff("hot"), "heatwave gives hot outdoors (feels %.1f)" % Weather.feels_like())
	W.run_min(110)
	W.expect(f, a.has_buff("sunburn"), "two hours in the heatwave sun burns")
	W.teardown()
	w = W.setup()
	a = K.make_folk(w, "Di")
	SimEnv.clock().total_minutes = W.at(2, 10)       # mild spring morning
	Weather.force("sunny")
	W.outdoors(a, true)
	W.run_min(35)
	W.expect(f, a.has_buff("fresh_air"), "half an hour of mild weather outside gives fresh air (feels %.1f)" % Weather.feels_like())
	W.teardown()
	# cozy indoors in the rain
	w = W.setup()
	a = K.make_folk(w, "Ed")
	SimEnv.clock().total_minutes = W.at(3, 10)
	Weather.force("rain")
	for i in 40:
		W.run_min(60)
		if a.has_buff("cozy"):
			break
	W.expect(f, a.has_buff("cozy"), "sooner or later you feel cozy indoors during rain")
	W.teardown()

func _gating_and_autonomy(f: Array) -> void:
	var w: StubWorld = W.setup()
	var a: Folk = K.make_folk(w, "Ann")
	var spot = w.add_object("fishing_spot", Vector2i(14, 12))
	var garden = w.add_object("garden_plot", Vector2i(18, 12))
	a.needs["fun"].set_value(10.0)
	SimEnv.clock().total_minutes = W.at(3, 12)
	Weather.force("sunny")
	W.run_min(2)
	var ir := Interaction.create("fish_pond", a, spot.id)
	W.expect(f, ir != null and ir.can_run(a, spot), "fishing allowed in sunshine")
	var sun := Interaction.create("sunbathe", a, garden.id)
	W.expect(f, sun != null and sun.can_run(a, garden), "sunbathe allowed on a sunny midday")
	var clear_score: float = Autonomy.evaluate(a, {"id": "fish_pond", "target_id": spot.id, "kind": "object", "obj": spot, "folk": null})["score"]
	Weather.force("rain")
	W.run_min(2)
	W.expect(f, not sun.can_run(a, garden), "no sunbathing in the rain")
	var rd := Interaction.create("rain_dance", a, garden.id)
	W.expect(f, rd != null and rd.can_run(a, garden), "rain dance allowed in the rain")
	var wet_score: float = Autonomy.evaluate(a, {"id": "fish_pond", "target_id": spot.id, "kind": "object", "obj": spot, "folk": null})["score"]
	W.expect(f, wet_score < clear_score * 0.7, "folk prefer to stay in when it rains (%f vs %f)" % [wet_score, clear_score])
	Weather.force("thunderstorm")
	W.run_min(2)
	W.expect(f, not Interaction.create("fish_pond", a, spot.id).can_run(a, spot), "outdoor activities are blocked in a thunderstorm")
	W.expect(f, not Interaction.create("water_garden", a, garden.id).can_run(a, garden), "gardening is blocked in a thunderstorm")
	W.expect(f, not rd.can_run(a, garden), "no rain dance in a thunderstorm")
	Weather.force("snow", 0.6)
	W.run_min(2)
	W.expect(f, a.has_buff("wx_snowy"), "snow on the ground gives the wx_snowy marker")
	var sf := Interaction.create("build_snowfolk", a, garden.id)
	W.expect(f, sf != null and sf.can_run(a, garden), "snow folk can be built in the snow")
	Weather.force("sunny", 0.0)
	W.run_min(2)
	W.expect(f, not sf.can_run(a, garden), "no snow folk without snow")
	W.teardown()

func _crops(f: Array) -> void:
	var results: Array = []
	for mode in ["sunny", "rain"]:
		var w: StubWorld = W.setup()
		K.make_folk(w, "Ann")
		var g = w.add_object("garden_plot", Vector2i(18, 12))
		g.state["water"] = 4.0
		g.state["growth"] = 0.0
		SimEnv.clock().total_minutes = W.at(2, 1)       # spring, mild
		Weather.force(mode)
		W.run_coarse(23 * 60 + 5)                              # through midnight into day 3 (hourly / daily hooks only)
		results.append([float(g.state["growth"]), float(g.state["water"])])
		W.teardown()
	W.expect(f, float(results[1][0]) > float(results[0][0]) + 0.5, "rain makes crops grow faster (sunny %s, rain %s)" % [str(results[0]), str(results[1])])
	W.expect(f, float(results[1][1]) > float(results[0][1]), "rain waters the garden (%s vs %s)" % [str(results[1][1]), str(results[0][1])])
	var w2: StubWorld = W.setup()
	W.expect(f, Weather.crop_growth_mult() == 1.0, "no rain -> multiplier 1")
	W.teardown()

func _frost(f: Array) -> void:
	var w: StubWorld = W.setup()
	K.make_folk(w, "Ann")
	var g = w.add_object("garden_plot", Vector2i(18, 12))
	g.state["growth"] = 6.0
	g.state["water"] = 8.0
	SimEnv.clock().total_minutes = W.at(23, 1)          # winter: nights well below zero
	Weather.force("cold_snap")
	W.run_coarse(23 * 60 + 5)
	W.expect(f, float(g.state["growth"]) == 0.0, "frost kills the crops (growth %f)" % float(g.state["growth"]))
	W.expect(f, K.count_events("crops_frozen") >= 1, "crops_frozen event fired")
	W.teardown()

func _bills(f: Array) -> void:
	var w: StubWorld = W.setup()
	K.make_folk(w, "Ann")
	Economy.next_bill_day = 10000     # keep the bill cycle out of the way: it resets the weather bill period
	W.expect(f, Weather.bill_multiplier() == 1.0, "no history -> bill multiplier 1")
	SimEnv.clock().total_minutes = W.at(23, 0)          # winter
	Weather.force("cold_snap")
	W.run_coarse(48 * 60)
	var winter: float = Weather.bill_multiplier()
	W.expect(f, winter > 1.12 and winter <= 1.5, "heating raises the bill multiplier (%f)" % winter)
	var plain: int = int(round(float(Economy.compute_bill(1)) / winter))
	W.expect(f, Economy.compute_bill(1) > plain, "compute_bill includes the weather multiplier")
	Weather.reset_bill_period()
	W.expect(f, Weather.bill_multiplier() == 1.0, "reset_bill_period clears it")
	W.teardown()
	w = W.setup()
	K.make_folk(w, "Bo")
	Economy.next_bill_day = 10000
	SimEnv.clock().total_minutes = W.at(2, 0)           # mild spring
	Weather.force("sunny")
	W.run_coarse(48 * 60)
	var mild: float = Weather.bill_multiplier()
	W.expect(f, mild < winter, "a mild spell costs less than a cold snap (%f vs %f)" % [mild, winter])
	W.teardown()

func _lightning(f: Array) -> void:
	var w: StubWorld = W.setup()
	K.make_folk(w, "Ann")
	var tv = w.add_object("tv", Vector2i(12, 12))
	var chair = w.add_object("chair", Vector2i(14, 12))
	SimEnv.clock().total_minutes = W.at(11, 12)
	Storyteller.enabled = false              # the storyteller's own incidents must not break the set before the lightning does (the test is about the weather)
	Weather.force("thunderstorm")
	for i in 400:
		W.run_min(60)
		if bool(tv.state.get("broken", false)):
			break
	W.expect(f, bool(tv.state.get("broken", false)), "a long thunderstorm eventually breaks electronics")
	W.expect(f, not bool(chair.state.get("broken", false)), "furniture is not electronic")
	W.expect(f, K.count_events("lightning") >= 1, "lightning events fired")
	W.teardown()

func _fishing(f: Array) -> void:
	var w: StubWorld = W.setup()
	var a: Folk = K.make_folk(w, "Ann")
	WorldIface.coins[1] = 0
	SimEnv.clock().total_minutes = W.at(3, 10)
	Weather.force("rain")
	WeatherWorld.on_game_event("caught_fish", {"folk_id": a.id})
	var before: int = WorldIface.get_coins(1)
	WeatherWorld.on_interaction_finished(a.id, "fish_pond", true)
	W.expect(f, WorldIface.get_coins(1) > before, "a catch in the rain pays a bonus")
	Weather.force("sunny")
	WeatherWorld.on_game_event("caught_fish", {"folk_id": a.id})
	before = WorldIface.get_coins(1)
	WeatherWorld.on_interaction_finished(a.id, "fish_pond", true)
	W.expect(f, WorldIface.get_coins(1) == before, "no bonus in sunshine")
	W.teardown()

func _walk_and_events(f: Array) -> void:
	var w: StubWorld = W.setup()
	K.make_folk(w, "Ann")
	Weather.force("sunny", 0.0)
	W.expect(f, Weather.walk_speed_mult() == 1.0, "normal walking speed in sunshine")
	Weather.force("snow", 1.0)
	W.expect(f, Weather.walk_speed_mult() < 0.9 and Weather.walk_speed_mult() > 0.5, "snow slows walking (%f)" % Weather.walk_speed_mult())
	Weather.unforce()
	# weather_changed fires as steps pass
	SimEnv.clock().total_minutes = W.at(1, 0)
	var before: int = K.count_events("weather_changed")
	var days: int = TestFixture.pick(10, 3)
	W.run_min(days * 24 * 60)
	var n: int = K.count_events("weather_changed") - before
	W.expect(f, n >= days - 2, "weather_changed events over %d days: %d" % [days, n])
	var p: Dictionary = K.last_event("weather_changed")
	W.expect(f, p.has("from") and p.has("to") and p.has("temp") and p.has("season") and str(p["from"]) != str(p["to"]), "weather_changed payload: %s" % str(p))
	W.teardown()