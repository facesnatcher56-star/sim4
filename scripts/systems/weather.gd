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

## Fresh game: seeded from the game's world seed (Neighborhood.world_seed, saved), else random when a window exists, else the fixed default seed (tests).
static func new_game() -> void:
	reset()
	if Neighborhood.world_seed > 0:
		seed_value = _mix(int(settings().get("default_seed", 1337)), Neighborhood.world_seed)      # each game's world seed gives its own weather
	elif DisplayServer.get_name() != "headless":
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

## Is the tile of that floor open to the sky (rain, snow and wind reach it)? Only the top roof of a building is rained on; floors below
## it are indoors. Worlds without rooms (stubs): everything is outdoors.
static func is_outdoor(tile: Vector2i, level: int = 0) -> bool:
	var w = WorldIface.world()
	if w != null and w.has_method("is_outdoor"):
		return bool(w.is_outdoor(tile, level))
	return true

static func walk_speed_mult_at(tile: Vector2i, level: int = 0) -> float:
	if not is_outdoor(tile, level):
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
