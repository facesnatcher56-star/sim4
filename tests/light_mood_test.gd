extends RefCounted
## Task 41 part C (fast): lighting and weather mood maths. Night readability floor, the Night brightness setting, windows lit by the hour,
## dusk vs dawn colour, winter greyer, wet streets and puddles, fixture light temperatures. Pure functions, no window needed.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var start: String = Looks.current_id()
	# --- the Night brightness setting
	var d := GameSettings.def_of("night_brightness")
	_check(not d.is_empty() and d.get("t") == "range" and int(d["min"]) == 0 and int(d["max"]) == 100, "Night brightness is a 0..100 range setting")
	_check(GameSettings.default_of("night_brightness") == 65, "Night brightness defaults to 65%")
	_check(LightMood.floor_energy(0.0) < LightMood.floor_energy(0.5) and LightMood.floor_energy(0.5) < LightMood.floor_energy(1.0), "floor energy rises with the setting")
	# --- readability floor: never darker than the floor at night, no effect by day
	var night_look := 0.22
	for nb in [0.0, 0.35, 0.7, 1.0]:
		var e: float = LightMood.ambient_energy(night_look, 0.42, 0.0, 1.0, nb)
		_check(e >= LightMood.floor_energy(nb) - 0.0001, "night ambient (setting %.2f) is at least the floor" % nb)
		_check(nb < LightMood.NB_DEFAULT or e >= night_look - 0.0001, "from the default up the setting never darkens the look's own night")
		_check(e >= 0.05, "even true night keeps a floor (%.3f)" % e)
	_check(is_equal_approx(LightMood.ambient_energy(night_look, 0.42, 0.0, 1.0, LightMood.NB_DEFAULT), night_look), "the default setting is the look's own night")
	_check(LightMood.ambient_energy(night_look, 0.42, 0.0, 1.0, 0.0) < night_look * 0.5, "Night brightness 0 is a truer, darker night")
	_check(LightMood.ambient_color(Color(0.13, 0.16, 0.27), Color.WHITE, 0.0, 1.0).b > 0.4 and LightMood.ambient_color(Color(0.13, 0.16, 0.27), Color.WHITE, 0.0, 0.35) == Color(0.13, 0.16, 0.27), "high Night brightness lifts the night colour, the default keeps it")
	_check(LightMood.ambient_energy(0.05, 0.42, 0.0, 1.0, 1.0) >= 0.4, "a very dark look is lifted to the floor at full Night brightness")
	_check(is_equal_approx(LightMood.ambient_energy(0.22, 0.42, 1.0, 1.0, 1.0), 0.42), "the floor does not touch full daylight")
	_check(LightMood.ambient_energy(0.22, 0.42, 0.0, 0.5, 0.0) < LightMood.ambient_energy(0.22, 0.42, 1.0, 1.0, 0.0), "night is darker than day")
	# the selected folk keep a fill light in the dark, none by day
	_check(LightMood.fill_energy(0.0, 1.0) == 0.0 and LightMood.fill_energy(1.0, 0.0) > 0.1, "fill light: none by day, a floor of 0.25 even at Night brightness 0")
	_check(LightMood.fill_energy(1.0, 1.0) > LightMood.fill_energy(1.0, 0.0), "fill light grows with the setting")
	# --- windows lit by the hour
	_check(LightMood.occupancy(21.0) > 0.85 and LightMood.occupancy(3.0) < 0.2 and LightMood.occupancy(7.0) > LightMood.occupancy(3.0), "evening busy, small hours quiet, morning stirring")
	_check(LightMood.window_lit(0.3, 21.0) > 0.99 and LightMood.window_lit(0.3, 3.0) < 0.01, "a window with threshold 0.3 is lit at 21:00 and dark at 03:00")
	_check(LightMood.window_lit(0.0, 21.0) > 0.99, "a window with threshold 0 is lit in the evening")
	_check(is_equal_approx(LightMood.occupancy(0.0), LightMood.occupancy(24.0)), "the occupancy curve wraps at midnight")
	# --- dusk / dawn / seasons
	var dusk := Color("#ff8040")
	var dawn := Color("#a0a0b0")
	_check(LightMood.twilight_color(18.5, dusk, dawn) == dusk and LightMood.twilight_color(6.0, dusk, dawn) == dawn, "dusk is warm, dawn is cooler")
	Looks.set_look("grounded")
	_check(Looks.ec("dawn") != Looks.ec("twilight"), "grounded has a dawn colour apart from dusk")
	var ss: Array = Looks.earr("season_sat")
	_check(ss.size() == 4 and float(ss[3]) < float(ss[1]), "grounded winter is greyer than summer")
	_check(LightMood.season_value(ss, 3.5) < LightMood.season_value(ss, 1.5), "season_value: winter < summer")
	_check(absf(LightMood.season_value(ss, 3.99) - LightMood.season_value(ss, 4.01)) < 0.02, "seasonal grey changes smoothly over the year turn")
	Looks.set_look("reference")
	_check(is_equal_approx(LightMood.season_value(Looks.earr("season_sat"), 3.5), 1.0), "reference has no seasonal grey")
	_check(Looks.ec("dawn").is_equal_approx(Looks.ec("twilight")), "reference dawn = today's twilight")
	# --- wet streets and puddles
	var w0: Dictionary = LightMood.wet_mood(0.0, 0.5)
	var w1: Dictionary = LightMood.wet_mood(1.0, 0.5)
	_check(float(w0["dark"]) == 0.0 and float(w1["dark"]) > 0.4, "streets darken only when wet")
	_check(float(w1["rough"]) < float(w0["rough"]) and float(w1["dim"]) < 1.0, "wet streets are glossier and the light a touch dimmer")
	var n := 0
	for y in 40:
		for x in 40:
			var t := Vector2i(x, y)
			_check(LightMood.puddle(t) == LightMood.puddle(t), "puddles are deterministic")
			if LightMood.puddle(t):
				n += 1
	_check(n > 40 and n < 480, "about one road tile in five holds a puddle (%d of 1600)" % n)
	_check(LightMood.wet_tile_alpha(Vector2i(0, 0)) in [0.6, 1.0], "wet film alpha is 0.6 or 1.0")
	# --- fixture lights: warm lamps, a fire, cold screens; all real objects
	var defs: Dictionary = LightMood.light_defs()
	for k in ["lamp", "pendant_light", "nightstand", "fireplace", "tv", "computer"]:
		_check(defs.has(k), "light row for %s" % k)
		_check(not World.get_def(k).is_empty(), "%s is a real object" % k)
	_check(not LightMood.is_cold(defs["lamp"]) and not LightMood.is_cold(defs["fireplace"]), "lamps and fire are warm")
	_check(LightMood.is_cold(defs["tv"]) and LightMood.is_cold(defs["computer"]), "screens are cold")
	_check(float(defs["tv"].get("flicker", 0.0)) > 0.0, "the TV flickers")
	for k in defs:
		var row: Dictionary = defs[k]
		_check(float(row["range"]) > 0.0 and float(row["energy"]) > 0.0, "%s has a range and energy" % k)
		var sk := str(row.get("state", "on"))
		if sk != "":
			var st: Dictionary = World.get_def(k).get("state", {})
			_check(st.has(sk) or k == "lamp" or k == "pendant_light", "%s switches by a real state key (%s)" % [k, sk])
	Looks.set_look(start)
	return fails
