class_name Weather
extends RefCounted
## Deterministic, seeded weather + temperature model (data/weather.json) and its gameplay effects.
##
## MODEL
##  * Weather is a Markov chain stepping every settings.step_hours game hours. Step k's weather is a pure function of
##    (seed, k, previous weather, season), so it can be recomputed, forecast and saved/loaded exactly.
##  * Temperature (deg C) = season base + day/night cosine + smooth daily noise + weather offset (blended over 2 h).
## PUBLIC API (static)
##   Weather.current() / label() / icon() / def()          Weather.temperature() / feels_like() / temp_string()
##   Weather.forecast(n) -> [{day, season, weather, label, icon, hi, lo, steps}]  for the next n days (tomorrow first)
##   Weather.is_precipitating() / precip_kind() / precip_intensity() / fog_amount() / cloud_cover() / wind() / light_factor()
##   Weather.daylight(hour_f) 0..1 / is_dark()               Weather.snow_cover() / wetness()   (0..1, updated hourly)
##   Weather.walk_speed_mult() / walk_speed_mult_at(tile)    Weather.crop_growth_mult() / bill_multiplier()
##   Weather.force(id) / unforce()                           (debug / screenshots; not saved)
##   Weather.to_dict() / from_dict(d) / reset(seed)
## HOOKS (called by SystemsManager): on_minute, on_hour, on_day, on_folk_added, on_interaction_finished, on_game_event.
## EVENTS: game_event "weather_changed" {from, to, label, temp, season, day}, "season_changed", "lightning", "crops_frozen".
## Folk get hidden marker buffs (wx_clear, wx_wet, wx_severe, wx_hot, wx_cold, wx_snowy, wx_outside) so interaction
## `tests` / `when` / `autonomy_mult` (which only know Cond keys) can react to the weather.

static var seed_value: int = 1337
static var _chain: Dictionary = {}          # step -> weather id
static var _hi: int = -1
static var _lo: int = 0
static var _noise: Dictionary = {}
static var forced: String = ""
static var forced_snow: float = -1.0

static var _snow: float = 0.0
static var _wet: float = 0.0
static var _heat_dh: float = 0.0
static var _cool_dh: float = 0.0
static var _bill_hours: float = 0.0
static var _min_today: float = 99.0
static var _rain_hours: float = 0.0
static var _heat_hours: float = 0.0
static var _last_weather: String = ""
static var _last_season: String = ""
static var _marker_sig: Dictionary = {}     # folk id -> signature of the markers last applied
static var _exposure: Dictionary = {}       # folk id -> {cold, hot, sun, wet, air}
static var _caught: Dictionary = {}         # folk id -> true when Loot just fired caught_fish
static var _puddles: Dictionary = {}        # Vector2i -> amount we added to World.mess
static var outdoors_fn: Callable = Callable()   # optional override (folk) -> bool, for tests

# ------------------------------------------------------------------ data
static func cfg() -> Dictionary:
	return SysUtil.table("weather")

static func settings() -> Dictionary:
	return cfg().get("settings", {})

static func effects() -> Dictionary:
	return cfg().get("effects", {})

static func weather_ids() -> Array:
	return (cfg().get("weathers", {}) as Dictionary).keys()

static func def(id: String = "") -> Dictionary:
	var wid: String = current() if id == "" else id
	return (cfg().get("weathers", {}) as Dictionary).get(wid, {})

static func label(id: String = "") -> String:
	var wid: String = current() if id == "" else id
	return str(def(wid).get("label", wid.capitalize()))

static func icon(id: String = "") -> String:
	var wid: String = current() if id == "" else id
	return str(def(wid).get("icon", "cloud"))

static func season_weights(season: String) -> Dictionary:
	return ((cfg().get("seasons", {}) as Dictionary).get(season, {}) as Dictionary).get("weights", {})

static func valid_in_season(id: String, season: String) -> bool:
	return season_weights(season).has(id)

# ------------------------------------------------------------------ lifecycle
static func reset(new_seed: int = -1) -> void:
	seed_value = int(settings().get("default_seed", 1337)) if new_seed < 0 else new_seed
	_chain.clear()
	_noise.clear()
	_hi = -1
	_lo = 0
	forced = ""
	forced_snow = -1.0
	_snow = 0.0
	_wet = 0.0
	_heat_dh = 0.0
	_cool_dh = 0.0
	_bill_hours = 0.0
	_min_today = 99.0
	_rain_hours = 0.0
	_heat_hours = 0.0
	_last_weather = ""
	_last_season = ""
	_marker_sig.clear()
	_exposure.clear()
	_caught.clear()
	_puddles.clear()
	Seasons.reset()
	Holidays.reset()

## Fresh game: random seed when a window exists, the fixed default seed when headless (keeps tests deterministic).
static func new_game() -> void:
	reset()
	if DisplayServer.get_name() != "headless":
		seed_value = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	_last_weather = current()
	_last_season = Seasons.current()

# ------------------------------------------------------------------ Markov chain
static func _mix(a: int, b: int) -> int:
	return ((a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995) & 0x7fffffffffff

static func step_minutes() -> int:
	return maxi(30, int(float(settings().get("step_hours", 4)) * 60.0))

static func step_index(total: int = -1) -> int:
	var t: int = SimEnv.now_min() if total < 0 else total
	return maxi(t, 0) / step_minutes()

static func _season_of_step(k: int) -> String:
	return Seasons.season_at_day(k * step_minutes() / 1440 + 1)

## P(next | prev, season) as a normalised dictionary (the fresh-start draw when prev is not valid in the season).
static func transition_probs(prev: String, season: String) -> Dictionary:
	var weights: Dictionary = season_weights(season)
	var follow: Dictionary = (cfg().get("follow", {}) as Dictionary).get(prev, {})
	var out: Dictionary = {}
	var total: float = 0.0
	var start: String = str(((cfg().get("seasons", {}) as Dictionary).get(season, {}) as Dictionary).get("start", ""))
	var ids: Array = weights.keys()
	ids.sort()
	for id in ids:
		var w: float = float(weights[id])
		if weights.has(prev):
			w *= float(follow.get(id, 1.0))
		elif str(id) == start:
			w *= 3.0
		out[id] = maxf(w, 0.0)
		total += maxf(w, 0.0)
	if total <= 0.0:
		return {start: 1.0} if start != "" else {}
	for id2 in out:
		out[id2] = float(out[id2]) / total
	return out

static func _gen(k: int, prev: String) -> String:
	var season: String = _season_of_step(k)
	var probs: Dictionary = transition_probs(prev, season)
	if probs.is_empty():
		return "sunny"
	var r := RandomNumberGenerator.new()
	r.seed = _mix(seed_value, k)
	var roll: float = r.randf()
	var last: String = ""
	var ids: Array = probs.keys()
	ids.sort()
	for id in ids:
		last = str(id)
		roll -= float(probs[id])
		if roll <= 0.0:
			return last
	return last

static func weather_at_step(k: int) -> String:
	k = maxi(k, 0)
	if _chain.is_empty() or k < _lo:
		_chain.clear()
		_lo = 0
		_hi = -1
	while _hi < k:
		_hi += 1
		_chain[_hi] = _gen(_hi, str(_chain.get(_hi - 1, "")))
	return str(_chain[k])

static func weather_at(total: int) -> String:
	if forced != "":
		return forced
	return weather_at_step(step_index(total))

static func current() -> String:
	return weather_at(SimEnv.now_min())

static func force(id: String, snow: float = -1.0) -> void:
	forced = id
	forced_snow = snow

static func unforce() -> void:
	forced = ""
	forced_snow = -1.0

# ------------------------------------------------------------------ temperature
static func _day_noise(i: int) -> float:
	if not _noise.has(i):
		var r := RandomNumberGenerator.new()
		r.seed = _mix(seed_value, 1000003 + i)
		_noise[i] = r.randf() * 2.0 - 1.0
	return float(_noise[i])

static func _weather_offset(total: int) -> float:
	var wd: Dictionary = cfg().get("weathers", {})
	if forced != "":
		return float((wd.get(forced, {}) as Dictionary).get("temp_offset", 0.0))
	var step: int = step_minutes()
	var k: int = maxi(total, 0) / step
	var m: float = float(maxi(total, 0) % step)
	var cur: String = weather_at_step(k)
	var prev: String = weather_at_step(k - 1) if k > 0 else cur
	var blend: float = clampf(m / maxf(float(settings().get("blend_minutes", 120)), 1.0), 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	return lerpf(float((wd.get(prev, {}) as Dictionary).get("temp_offset", 0.0)), float((wd.get(cur, {}) as Dictionary).get("temp_offset", 0.0)), blend)

static func temperature(total: int = -1) -> float:
	var t: int = SimEnv.now_min() if total < 0 else maxi(total, 0)
	var day: int = t / 1440 + 1
	var h: float = float(t % 1440) / 60.0
	var pos: float = Seasons.year_pos(day, h)
	var s: Dictionary = settings()
	var di: float = Seasons.diurnal_amp(pos) * cos(TAU * (h - float(s.get("peak_hour", 15.0))) / 24.0)
	var x: float = float(day - 1) + h / 24.0
	var i0: int = int(floor(x))
	var f: float = x - floor(x)
	f = f * f * (3.0 - 2.0 * f)
	var noise: float = lerpf(_day_noise(i0), _day_noise(i0 + 1), f) * float(s.get("daily_noise", 2.0))
	var v: float = Seasons.base_temp(pos) + di + noise + _weather_offset(t)
	if is_nan(v) or is_inf(v):
		v = Seasons.base_temp(pos)
	return clampf(v, float(s.get("min_temp", -30.0)), float(s.get("max_temp", 55.0)))

static func feels_like(total: int = -1) -> float:
	var t: int = SimEnv.now_min() if total < 0 else total
	return temperature(t) - wind(t) * float(settings().get("wind_chill_per_wind", 3.0))

static func temp_string(total: int = -1) -> String:
	return "%d°C" % int(round(temperature(total)))

# ------------------------------------------------------------------ weather properties
static func _prop(key: String, default: float, id: String = "") -> float:
	return float(def(id).get(key, default))

static func precip_kind(id: String = "") -> String:
	return str(def(id).get("kind", ""))

static func is_precipitating(id: String = "") -> bool:
	return precip_kind(id) != ""

static func precip_intensity(id: String = "") -> float:
	return _prop("precip", 0.0, id)

static func fog_amount(id: String = "") -> float:
	return _prop("fog", 0.0, id)

static func cloud_cover(id: String = "") -> float:
	return _prop("cloud", 0.0, id)

static func light_factor(id: String = "") -> float:
	return _prop("light", 1.0, id)

static func wind(total: int = -1) -> float:
	return _prop("wind", 0.0, current() if total < 0 else weather_at(total))

static func severity(id: String = "") -> int:
	return int(def(id).get("severity", 0))

static func sky_color(id: String = "") -> Color:
	return Color(str(def(id).get("sky", "#8ab4e8")))

static func snow_cover() -> float:
	return clampf(forced_snow, 0.0, 1.0) if forced_snow >= 0.0 else _snow

static func wetness() -> float:
	return _wet

## 0 at night .. 1 at midday, with ~1 h twilight at sunrise / sunset (season dependent).
static func daylight(hour: float = -1.0) -> float:
	var h: float = SimEnv.hour_f() if hour < 0.0 else hour
	var pos: float = Seasons.year_pos()
	var sr: float = Seasons.sunrise(pos)
	var ss: float = Seasons.sunset(pos)
	var up: float = clampf((h - (sr - 0.5)) / 1.0, 0.0, 1.0)
	var down: float = clampf(((ss + 0.5) - h) / 1.0, 0.0, 1.0)
	up = up * up * (3.0 - 2.0 * up)
	down = down * down * (3.0 - 2.0 * down)
	return minf(up, down)

static func is_dark() -> bool:
	return daylight() < 0.25

# ------------------------------------------------------------------ forecast
## Next n days (tomorrow first). The model is deterministic so the forecast is always right.
static func forecast(n: int = 2) -> Array:
	var out: Array = []
	var today: int = int(SimEnv.clock().day())
	for i in range(1, n + 1):
		out.append(day_summary(today + i))
	return out

static func day_summary(day: int) -> Dictionary:
	var base_t: int = (day - 1) * 1440
	var steps: Array = []
	var best: String = ""
	var best_sev: int = -1
	var step: int = step_minutes()
	var t: int = base_t
	while t < base_t + 1440:
		var wid: String = weather_at(t)
		steps.append(wid)
		var sev: int = severity(wid)
		if sev > best_sev:
			best_sev = sev
			best = wid
		t += step
	var hi: float = -999.0
	var lo: float = 999.0
	for hh in range(0, 24):
		var tv: float = temperature(base_t + hh * 60)
		hi = maxf(hi, tv)
		lo = minf(lo, tv)
	return {"day": day, "season": Seasons.season_at_day(day), "weather": best, "label": label(best), "icon": icon(best),
		"hi": hi, "lo": lo, "steps": steps}

static func forecast_text(n: int = 2) -> String:
	var lines: Array = []
	for d in forecast(n):
		lines.append("%s: %s, %d / %d°C" % [Seasons.weekday_name(int(d["day"])), str(d["label"]), int(round(float(d["hi"]))), int(round(float(d["lo"])))])
	return "\n".join(lines)

# ------------------------------------------------------------------ gameplay multipliers
static func walk_speed_mult() -> float:
	var m: float = _prop("walk_speed", 1.0)
	return clampf(m * lerpf(1.0, 0.94, snow_cover()), 0.5, 1.0)

static func walk_speed_mult_at(tile: Vector2i) -> float:
	var w = WorldIface.world()
	if w != null and w.has_method("is_outdoor") and not bool(w.is_outdoor(tile)):
		return 1.0
	return walk_speed_mult()

## Garden growth multiplier for the day that just ended: rain makes crops grow faster.
static func crop_growth_mult() -> float:
	return 1.0 + _rain_hours * float((effects().get("garden", {}) as Dictionary).get("rain_growth_mult_per_hour", 0.04))

## Multiplier applied to the household bill (Economy.compute_bill): heating / cooling degree-hours this billing cycle.
static func bill_multiplier() -> float:
	if _bill_hours <= 0.0:
		return 1.0
	var b: Dictionary = effects().get("bills", {})
	var avg: float = (_heat_dh + _cool_dh) / _bill_hours
	return clampf(1.0 + avg * float(b.get("per_degree", 0.012)), 1.0, float(b.get("max_mult", 1.5)))

static func reset_bill_period() -> void:
	_heat_dh = 0.0
	_cool_dh = 0.0
	_bill_hours = 0.0

# ------------------------------------------------------------------ folk helpers
static func is_outside(f) -> bool:
	if f == null or SysUtil.is_away(f):
		return false
	if outdoors_fn.is_valid():
		return bool(outdoors_fn.call(f))
	var w = WorldIface.world()
	if w != null and w.has_method("is_outdoor"):
		return bool(w.is_outdoor(f.tile))
	return bool(f.get_meta("outdoors", false))

static func _has_def(buff_id: String) -> bool:
	return not SimEnv.data().buff_def(buff_id).is_empty()

static func _set_marker(f, buff_id: String, on: bool) -> void:
	if not _has_def(buff_id):
		return
	if on:
		if not f.has_buff(buff_id):
			f.add_buff(buff_id)
	elif f.has_buff(buff_id):
		f.remove_buff(buff_id)

static func _marker_list() -> Array:
	var out: Array = ["wx_snowy"]
	var wd: Dictionary = cfg().get("weathers", {})
	for id in wd:
		for m in (wd[id] as Dictionary).get("markers", []):
			if not out.has(str(m)):
				out.append(str(m))
	return out

static func wanted_markers() -> Array:
	var out: Array = []
	for m in def().get("markers", []):
		out.append(str(m))
	if snow_cover() >= 0.25:
		out.append("wx_snowy")
	return out

static func sync_markers(f) -> void:
	var want: Array = wanted_markers()
	for m in _marker_list():
		_set_marker(f, str(m), want.has(m))
	_marker_sig[int(f.id)] = ",".join(want)

static func on_folk_added(f) -> void:
	if f == null:
		return
	WeatherContent.install()
	sync_markers(f)
	Holidays.sync_folk(f)

# ------------------------------------------------------------------ minute tick
static func on_minute() -> void:
	WeatherContent.install()
	var cur: String = current()
	if _last_weather == "":
		_last_weather = cur
	elif cur != _last_weather:
		_announce_change(_last_weather, cur)
		_last_weather = cur
	var sig: String = ",".join(wanted_markers())
	var e: Dictionary = effects()
	var wd: Dictionary = def(cur)
	var feels: float = feels_like()
	var kind: String = precip_kind(cur)
	var clear_sky: bool = (wd.get("markers", []) as Array).has("wx_clear")
	var dl: float = daylight()
	var air_range: Array = e.get("fresh_air_temp", [10.0, 27.0])
	var severe: bool = (wd.get("markers", []) as Array).has("wx_severe")
	for f in WorldIface.all_folk():
		var fid: int = int(f.id)
		if str(_marker_sig.get(fid, "")) != sig or not _marker_sig.has(fid):
			sync_markers(f)
		if SysUtil.is_away(f):
			continue
		var outside: bool = is_outside(f)
		_set_marker(f, "wx_outside", outside)
		var ex: Dictionary = _exposure.get(fid, {})
		if ex.is_empty():
			ex = {"cold": 0.0, "hot": 0.0, "sun": 0.0, "wet": 0.0, "air": 0.0}
			_exposure[fid] = ex
		if outside:
			var per: Dictionary = wd.get("outdoor_per_min", {})
			for need in per:
				f.add_to_stat(str(need), float(per[need]))
			# cold
			if feels < float(e.get("cold_temp", 5.0)):
				ex["cold"] = float(ex["cold"]) + (2.0 if feels < float(e.get("freezing_temp", -4.0)) else 1.0)
			else:
				ex["cold"] = maxf(float(ex["cold"]) - 1.0, 0.0)
			if float(ex["cold"]) >= float(e.get("cold_exposure_min", 12)):
				_give_timed(f, "cold")
				f.add_to_stat("comfort", -0.1)
			# heat
			if feels > float(e.get("hot_temp", 29.0)):
				ex["hot"] = float(ex["hot"]) + 1.0
			else:
				ex["hot"] = maxf(float(ex["hot"]) - 1.0, 0.0)
			if float(ex["hot"]) >= float(e.get("hot_exposure_min", 15)):
				_give_timed(f, "hot")
			# sun
			if clear_sky and dl > 0.6 and temperature() > 18.0:
				ex["sun"] = float(ex["sun"]) + 1.0
				if float(ex["sun"]) >= float(e.get("sunburn_exposure_min", 120)):
					_give_timed(f, "sunburn")
					ex["sun"] = 0.0
			# wet
			if kind != "":
				ex["wet"] = float(ex["wet"]) + 1.0
				if float(ex["wet"]) >= float(e.get("soak_exposure_min", 8)):
					_give_timed(f, "soaked")
			else:
				ex["wet"] = maxf(float(ex["wet"]) - 0.5, 0.0)
			# fresh air
			if kind == "" and not severe and feels >= float(air_range[0]) and feels <= float(air_range[1]):
				ex["air"] = float(ex["air"]) + 1.0
				if float(ex["air"]) >= float(e.get("fresh_air_exposure_min", 30)):
					_give_timed(f, "fresh_air")
					ex["air"] = 0.0
			else:
				ex["air"] = 0.0
		else:
			for k in ["cold", "hot", "sun", "wet", "air"]:
				ex[k] = maxf(float(ex[k]) - 1.0, 0.0)
			_shorten(f, "soaked", float(e.get("indoor_dry_extra_min", 2.0)))
			_shorten(f, "cold", float(e.get("indoor_warm_extra_min", 2.0)))
			_shorten(f, "hot", float(e.get("indoor_warm_extra_min", 2.0)))

static func _give_timed(f, buff_id: String) -> void:
	if _has_def(buff_id):
		f.add_buff(buff_id)   # re-adding refreshes the duration

static func _shorten(f, buff_id: String, minutes: float) -> void:
	for b in f.buffs:
		if str(b["id"]) == buff_id and float(b["remaining"]) > 0.0:
			b["remaining"] = float(b["remaining"]) - minutes
			if float(b["remaining"]) <= 0.0:
				f.remove_buff(buff_id)
			return

static func _announce_change(from_id: String, to_id: String) -> void:
	var payload: Dictionary = {"from": from_id, "to": to_id, "label": label(to_id), "temp": temperature(), "season": Seasons.current(),
		"day": int(SimEnv.clock().day()), "folk_id": -1}
	SysUtil.game_event("weather_changed", payload)
	var sev: int = severity(to_id)
	if sev >= 5:
		var msgs: Dictionary = {"rain": "It has started to rain.", "thunderstorm": "A thunderstorm is rolling in!", "snow": "Snow is falling.",
			"heatwave": "A heatwave has set in. Stay cool!", "cold_snap": "A cold snap has arrived. Bundle up!"}
		SysUtil.notify(str(msgs.get(to_id, "The weather turns: %s." % label(to_id))), "weather")

# ------------------------------------------------------------------ hourly tick
static func _hour_rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = _mix(seed_value + salt, SimEnv.now_min())
	return r

static func on_hour(_hour: int) -> void:
	WeatherContent.install()
	var e: Dictionary = effects()
	var cur: String = current()
	var temp: float = temperature()
	# bills
	var b: Dictionary = e.get("bills", {})
	_heat_dh += maxf(0.0, float(b.get("heat_below", 16.0)) - temp)
	_cool_dh += maxf(0.0, temp - float(b.get("cool_above", 22.0)))
	_bill_hours += 1.0
	_min_today = minf(_min_today, temp)
	var kind: String = precip_kind(cur)
	# snow cover / wetness
	if kind == "snow" and temp < 2.0:
		_snow = clampf(_snow + float(e.get("snow_per_hour", 0.12)) * precip_intensity(cur) / 0.6, 0.0, 1.0)
	elif temp > float(e.get("snow_melt_temp", 1.0)):
		_snow = clampf(_snow - float(e.get("snow_melt_per_hour", 0.04)) * (1.0 + maxf(temp - 5.0, 0.0) * 0.15), 0.0, 1.0)
	if kind == "rain":
		_wet = clampf(_wet + float(e.get("wet_per_hour", 0.35)), 0.0, 1.0)
		_rain_hours += 1.0
	else:
		_wet = clampf(_wet - float(e.get("dry_per_hour", 0.15)), 0.0, 1.0)
	if kind == "snow":
		_rain_hours += 0.5
	if cur == "heatwave":
		_heat_hours += 1.0
	_hourly_objects(cur, kind, e)
	_puddle_tick(kind, e)
	if cur == "thunderstorm":
		_lightning(e)
	_cozy(kind, e)

static func _objects() -> Array:
	return SysUtil.all_world_objects()

static func _def_of(o) -> Dictionary:
	return SimEnv.data().object_def(str(o.def_id))

static func _hourly_objects(cur: String, kind: String, e: Dictionary) -> void:
	if kind != "rain":
		return
	var g: Dictionary = e.get("garden", {})
	var w = WorldIface.world()
	var can_out: bool = w != null and w.has_method("is_outdoor")
	for o in _objects():
		var d: Dictionary = _def_of(o)
		var tags: Array = d.get("tags", [])
		var key: String = ""
		var amt: float = 0.0
		if str(o.def_id) == "garden_plot":
			key = "water"
			amt = float(g.get("rain_water_per_hour", 0.6))
		elif tags.has("plant") and can_out and bool(w.is_outdoor(o.tile)) and (d.get("state", {}) as Dictionary).has("water"):
			key = "water"
			amt = float(g.get("plant_rain_water_per_hour", 0.8))
		if key != "":
			WorldIface.state_add(o, key, amt)

static func _puddle_tick(kind: String, e: Dictionary) -> void:
	var w = WorldIface.world()
	if w == null or not w.has_method("add_mess") or not w.has_method("is_outdoor"):
		return
	var p: Dictionary = e.get("puddle", {})
	var r: RandomNumberGenerator = _hour_rng(7)
	if kind == "rain":
		var n: int = int(p.get("per_hour", 2))
		for i in n:
			if _puddles.size() >= int(p.get("max", 10)):
				break
			var t := Vector2i(r.randi_range(0, int(w.width) - 1), r.randi_range(0, int(w.height) - 1))
			if bool(w.is_outdoor(t)) and w.is_walkable(t) and float(w.mess.get(t, 0.0)) <= 0.0:
				var a: float = float(p.get("amount", 0.9))
				w.add_mess(t, a)
				_puddles[t] = a
	elif not _puddles.is_empty():
		for t2 in _puddles.keys():
			if r.randf() < float(p.get("dry_chance", 0.5)):
				w.add_mess(t2, -float(_puddles[t2]))
				_puddles.erase(t2)

static func _lightning(e: Dictionary) -> void:
	var l: Dictionary = e.get("lightning", {})
	var r: RandomNumberGenerator = _hour_rng(13)
	if r.randf() > float(l.get("per_hour_chance", 0.1)):
		return
	var cands: Array = []
	for o in _objects():
		var tags: Array = _def_of(o).get("tags", [])
		for t in l.get("break_tags", ["electronics"]):
			if tags.has(t) and not bool(WorldIface.state_get(o, "broken", false)):
				cands.append(o)
				break
	var broke: bool = false
	var oid: int = -1
	if not cands.is_empty():
		var o2 = cands[r.randi_range(0, cands.size() - 1)]
		oid = int(o2.id)
		if r.randf() < float(l.get("break_chance", 0.45)):
			WorldIface.state_set(o2, "broken", true)
			broke = true
			SysUtil.notify("Lightning struck: the %s is broken!" % str(_def_of(o2).get("label", o2.def_id)).to_lower(), "warn")
	SysUtil.game_event("lightning", {"object_id": oid, "broke": broke, "folk_id": -1})

static func _cozy(kind: String, e: Dictionary) -> void:
	if kind == "":
		return
	var r: RandomNumberGenerator = _hour_rng(29)
	if not _has_def("cozy"):
		return
	for f in WorldIface.all_folk():
		if SysUtil.is_away(f) or is_outside(f) or not SysUtil.is_resident(f):
			continue
		if r.randf() < float(e.get("cozy_chance_per_hour", 0.3)):
			f.add_buff("cozy")

# ------------------------------------------------------------------ daily tick
static func on_day(day: int) -> void:
	var e: Dictionary = effects()
	var g: Dictionary = e.get("garden", {})
	var frost: bool = _min_today < float(e.get("frost_temp", 0.0)) and bool(g.get("frost_kills", true))
	var mult: float = crop_growth_mult()
	var killed: int = 0
	for o in _objects():
		if str(o.def_id) != "garden_plot":
			continue
		var spec: Dictionary = ((_def_of(o).get("state", {}) as Dictionary).get("growth", {}) as Dictionary)
		var growth: float = float(WorldIface.state_get(o, "growth", 0.0))
		if _heat_hours >= 4.0:
			WorldIface.state_add(o, "water", -float(g.get("heat_extra_dry", 1.0)))
		if frost:
			if growth > 0.0:
				WorldIface.state_set(o, "growth", 0.0)
				killed += 1
		elif mult > 1.0 and float(WorldIface.state_get(o, "water", 0.0)) >= 2.0:
			WorldIface.state_add(o, "growth", float(spec.get("daily_add", 2.0)) * (mult - 1.0))
	if killed > 0:
		SysUtil.notify("A hard frost killed the crops!", "warn")
		SysUtil.game_event("crops_frozen", {"count": killed, "folk_id": -1})
	_min_today = 99.0
	_rain_hours = 0.0
	_heat_hours = 0.0
	var s: String = Seasons.current()
	if _last_season == "":
		_last_season = s
	elif s != _last_season:
		_last_season = s
		SysUtil.notify("%s has arrived." % Seasons.label(s), "weather")
		SysUtil.game_event("season_changed", {"season": s, "year": Seasons.year(), "day": day, "folk_id": -1})

# ------------------------------------------------------------------ fishing: better in the rain
static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	if ev_name == "caught_fish":
		_caught[int(payload.get("folk_id", -1))] = true

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	var fe: Dictionary = effects().get("fishing", {})
	if not (fe.get("interactions", []) as Array).has(iid):
		return
	var caught: bool = _caught.has(folk_id)
	_caught.erase(folk_id)
	if not success or precip_kind() != "rain":
		return
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	if caught:
		WorldIface.add_coins(int(f.household_id), int(fe.get("rain_bonus_coins", 8)))
	elif SysUtil.chance(float(fe.get("rain_extra_catch_chance", 0.3))):
		WorldIface.add_coins(int(f.household_id), int(fe.get("extra_coins", 14)))
		f.add_buff("fresh_catch")
		SysUtil.game_event("caught_fish", {"folk_id": folk_id, "object_id": -1, "target_id": -1})
		_caught.erase(folk_id)

# ------------------------------------------------------------------ save / load
static func to_dict() -> Dictionary:
	var cur: int = step_index()
	weather_at_step(cur)     # make sure the chain exists up to now; the save carries the last 16 steps up to now
	var tail: Dictionary = {}
	for k in range(maxi(cur - 15, _lo), cur + 1):
		if _chain.has(k):
			tail[str(k)] = _chain[k]
	var pud: Array = []
	for t in _puddles:
		pud.append([t.x, t.y, _puddles[t]])
	return {"seed": seed_value, "chain": tail, "snow": _snow, "wet": _wet, "heat_dh": _heat_dh, "cool_dh": _cool_dh, "bill_hours": _bill_hours,
		"min_today": _min_today, "rain_hours": _rain_hours, "heat_hours": _heat_hours, "last_weather": _last_weather, "last_season": _last_season,
		"puddles": pud, "seasons": Seasons.to_dict(), "holidays": Holidays.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset(int(d.get("seed", int(settings().get("default_seed", 1337)))))
	if d.is_empty():
		return
	Seasons.from_dict(d.get("seasons", {}))
	var ch: Dictionary = d.get("chain", {})
	var keys: Array = []
	for k in ch:
		keys.append(int(str(k)))
	keys.sort()
	if not keys.is_empty():
		for k2 in keys:
			_chain[k2] = str(ch[str(k2)] if ch.has(str(k2)) else ch[k2])
		_lo = int(keys[0])
		_hi = int(keys[keys.size() - 1])
	_snow = float(d.get("snow", 0.0))
	_wet = float(d.get("wet", 0.0))
	_heat_dh = float(d.get("heat_dh", 0.0))
	_cool_dh = float(d.get("cool_dh", 0.0))
	_bill_hours = float(d.get("bill_hours", 0.0))
	_min_today = float(d.get("min_today", 99.0))
	_rain_hours = float(d.get("rain_hours", 0.0))
	_heat_hours = float(d.get("heat_hours", 0.0))
	_last_weather = str(d.get("last_weather", ""))
	_last_season = str(d.get("last_season", ""))
	for p in d.get("puddles", []):
		_puddles[Vector2i(int(p[0]), int(p[1]))] = float(p[2])
	Holidays.from_dict(d.get("holidays", {}))
