class_name WeatherFolk
extends RefCounted
## Per-folk weather effects: markers, exposure and the minute tick.

# ------------------------------------------------------------------ folk helpers
static func is_outside(f) -> bool:
	if f == null or SysUtil.is_away(f):
		return false
	if Weather.outdoors_fn.is_valid():
		return bool(Weather.outdoors_fn.call(f))
	var w = WorldIface.world()
	if w != null and w.has_method("is_outdoor"):
		return bool(w.is_outdoor(f.tile, int(f.level)))      # floors: only the top roof is rained on
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
	var wd: Dictionary = Weather.cfg().get("weathers", {})
	for id in wd:
		for m in (wd[id] as Dictionary).get("markers", []):
			if not out.has(str(m)):
				out.append(str(m))
	return out

static func wanted_markers() -> Array:
	var out: Array = []
	for m in Weather.def().get("markers", []):
		out.append(str(m))
	if Weather.snow_cover() >= 0.25:
		out.append("wx_snowy")
	return out

static func sync_markers(f) -> void:
	var want: Array = wanted_markers()
	for m in _marker_list():
		_set_marker(f, str(m), want.has(m))
	Weather._marker_sig[int(f.id)] = ",".join(want)

static func on_folk_added(f) -> void:
	if f == null:
		return
	WeatherContent.install()
	sync_markers(f)
	Holidays.sync_folk(f)

# ------------------------------------------------------------------ minute tick
const STRANGER_PERIOD := 5

static func on_minute() -> void:
	WeatherContent.install()
	var cur: String = Weather.current()
	if Weather._last_weather == "":
		Weather._last_weather = cur
	elif cur != Weather._last_weather:
		_announce_change(Weather._last_weather, cur)
		Weather._last_weather = cur
	var sig: String = ",".join(wanted_markers())
	var e: Dictionary = Weather.effects()
	var wd: Dictionary = Weather.def(cur)
	var feels: float = Weather.feels_like()
	var kind: String = Weather.precip_kind(cur)
	var clear_sky: bool = (wd.get("markers", []) as Array).has("wx_clear")
	var dl: float = Weather.daylight()
	var air_range: Array = e.get("fresh_air_temp", [10.0, 27.0])
	var severe: bool = (wd.get("markers", []) as Array).has("wx_severe")
	var now: int = SysUtil.now()
	for f in WorldIface.all_folk():
		var fid: int = int(f.id)
		if str(Weather._marker_sig.get(fid, "")) != sig or not Weather._marker_sig.has(fid):
			sync_markers(f)
		if SysUtil.is_away(f):
			continue
		var k := 1.0           # minutes of exposure this pass covers: strangers (crowd, townies, visitors) are done once per STRANGER_PERIOD minutes
		if int(f.household_id) <= 0 and f.has_meta("visitor"):
			if (now + fid) % STRANGER_PERIOD != 0:
				continue
			k = float(STRANGER_PERIOD)
		var outside: bool = is_outside(f)
		_set_marker(f, "wx_outside", outside)
		var ex: Dictionary = Weather._exposure.get(fid, {})
		if ex.is_empty():
			ex = {"cold": 0.0, "hot": 0.0, "sun": 0.0, "wet": 0.0, "air": 0.0}
			Weather._exposure[fid] = ex
		if outside:
			var per: Dictionary = wd.get("outdoor_per_min", {})
			for need in per:
				f.add_to_stat(str(need), float(per[need]) * k)
			# cold
			if feels < float(e.get("cold_temp", 5.0)):
				ex["cold"] = float(ex["cold"]) + (2.0 if feels < float(e.get("freezing_temp", -4.0)) else 1.0) * k
			else:
				ex["cold"] = maxf(float(ex["cold"]) - k, 0.0)
			if float(ex["cold"]) >= float(e.get("cold_exposure_min", 12)):
				_give_timed(f, "cold")
				f.add_to_stat("comfort", -0.1)
			# heat
			if feels > float(e.get("hot_temp", 29.0)):
				ex["hot"] = float(ex["hot"]) + k
			else:
				ex["hot"] = maxf(float(ex["hot"]) - k, 0.0)
			if float(ex["hot"]) >= float(e.get("hot_exposure_min", 15)):
				_give_timed(f, "hot")
			# sun
			if clear_sky and dl > 0.6 and Weather.temperature() > 18.0:
				ex["sun"] = float(ex["sun"]) + k
				if float(ex["sun"]) >= float(e.get("sunburn_exposure_min", 120)):
					_give_timed(f, "sunburn")
					ex["sun"] = 0.0
			# wet
			if kind != "":
				ex["wet"] = float(ex["wet"]) + k
				if float(ex["wet"]) >= float(e.get("soak_exposure_min", 8)):
					_give_timed(f, "soaked")
			else:
				ex["wet"] = maxf(float(ex["wet"]) - 0.5 * k, 0.0)
			# fresh air
			if kind == "" and not severe and feels >= float(air_range[0]) and feels <= float(air_range[1]):
				ex["air"] = float(ex["air"]) + k
				if float(ex["air"]) >= float(e.get("fresh_air_exposure_min", 30)):
					_give_timed(f, "fresh_air")
					ex["air"] = 0.0
			else:
				ex["air"] = 0.0
		else:
			for ek in ["cold", "hot", "sun", "wet", "air"]:
				ex[ek] = maxf(float(ex[ek]) - k, 0.0)
			_shorten(f, "soaked", float(e.get("indoor_dry_extra_min", 2.0)) * k)
			_shorten(f, "cold", float(e.get("indoor_warm_extra_min", 2.0)) * k)
			_shorten(f, "hot", float(e.get("indoor_warm_extra_min", 2.0)) * k)

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
	var payload: Dictionary = {"from": from_id, "to": to_id, "label": Weather.label(to_id), "temp": Weather.temperature(), "season": Seasons.current(),
		"day": int(SimEnv.clock().day()), "folk_id": -1}
	SysUtil.game_event("weather_changed", payload)
	var sev: int = Weather.severity(to_id)
	if sev >= 5:
		var msgs: Dictionary = {"rain": "It has started to rain.", "thunderstorm": "A thunderstorm is rolling in!", "snow": "Snow is falling.",
			"heatwave": "A heatwave has set in. Stay cool!", "cold_snap": "A cold snap has arrived. Bundle up!"}
		SysUtil.notify(str(msgs.get(to_id, "The weather turns: %s." % Weather.label(to_id))), "weather")
