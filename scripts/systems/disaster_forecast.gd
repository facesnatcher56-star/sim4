class_name DisasterForecast
extends RefCounted
## Warnings from the weather forecast (task 06) plus the rain / dry streak counters that the flood and wildfire conditions read.
## A "watch" toast appears at most once per config.disasters.forecast.watch_gap_days for each kind, and only when tomorrow's forecast
## really looks dangerous: heavy snow in a hard frost (blizzard), more rain after days of downpour (flood), a hot dry spell
## (wildfire) or a thunderstorm in spring / summer (tornado, hail).

## Hourly: count rain / precipitation hours of the running day.
static func on_hour() -> void:
	var k: String = Weather.precip_kind()
	if k != "":
		DisasterState.precip_hours_today += 1
	if k == "rain":
		DisasterState.rain_hours_today += 1

## Daily (before the counters reset): update the streaks and issue tomorrow's watches.
static func on_day(day: int) -> void:
	var sc: Dictionary = DisasterState.cfg("streaks")
	if DisasterState.rain_hours_today >= int(sc.get("rainy_day_hours", 6)):
		DisasterState.rain_days += 1
	elif DisasterState.precip_hours_today < 3:
		DisasterState.rain_days = 0
	if DisasterState.precip_hours_today <= int(sc.get("dry_day_hours", 0)):
		DisasterState.dry_days += 1
	else:
		DisasterState.dry_days = 0
	DisasterState.rain_hours_today = 0
	DisasterState.precip_hours_today = 0
	for w in watches():
		_watch(day, str(w["kind"]), str(w["text"]))

## [{kind, text}] for tomorrow (also used by tests and the weather UI).
static func watches() -> Array:
	var out: Array = []
	var fc: Array = Weather.forecast(1)
	if fc.is_empty():
		return out
	var t: Dictionary = fc[0]
	var wx: String = str(t["weather"])
	var season: String = str(t["season"])
	var c: Dictionary = DisasterState.cfg("forecast")
	if wx == "snow" and float(t["lo"]) <= float(c.get("blizzard_lo", -4.0)):
		out.append({"kind": "blizzard", "text": "Heavy snow and a hard frost are forecast for tomorrow. A blizzard is possible: stock up, fuel the generator and keep warm."})
	if (wx == "rain" or wx == "thunderstorm") and DisasterState.rain_days >= int(c.get("flood_rain_days", 2)):
		out.append({"kind": "flood", "text": "More heavy rain is forecast after days of downpour. Flooding is possible: sandbags and moving valuables up will help."})
	if wx == "heatwave" and season == "summer" and DisasterState.dry_days >= int(c.get("fire_dry_days", 3)):
		out.append({"kind": "wildfire", "text": "A hot, dry spell is forecast. Wildfire danger is high near the park."})
	if wx == "thunderstorm" and (season == "spring" or season == "summer"):
		out.append({"kind": "storm", "text": "Severe storms are forecast for tomorrow. Tornadoes and hail are possible: check the shutters and know where to take cover."})
	return out

static func _watch(day: int, kind: String, text: String) -> void:
	var gap: int = int(DisasterState.cfg("forecast").get("watch_gap_days", 7))
	if day - int(DisasterState.watch_day.get(kind, -999)) < gap:
		return
	DisasterState.watch_day[kind] = day
	SysUtil.notify(text, "weather")
	ChronicleHook.note("weather_watch", text, [], "", 1, false)
