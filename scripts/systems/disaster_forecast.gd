class_name DisasterForecast
extends RefCounted
## Warnings from the weather forecast (task 06) plus the rain / dry streak counters that the flood and wildfire conditions read.
## A "watch" toast appears at most once per config.disasters.forecast.watch_gap_days for each kind, and only when tomorrow's chance of
## the incident is real (data/forecast.json min_chance), with likelihood wording ("a slight chance of...").

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

## [{kind, text, chance}] for tomorrow (also used by tests and the weather UI): only dangers with a real chance, worded by how likely
## they are (DisasterOdds, derived from the incidents' own rates).
static func watches() -> Array:
	var fc: Array = Weather.forecast(1)
	if fc.is_empty():
		return []
	return DisasterOdds.watches_for(str(fc[0]["weather"]), str(fc[0]["season"]))

static func _watch(day: int, kind: String, text: String) -> void:
	var gap: int = int(DisasterState.cfg("forecast").get("watch_gap_days", 7))
	if day - int(DisasterState.watch_day.get(kind, -999)) < gap:
		return
	DisasterState.watch_day[kind] = day
	SysUtil.notify(text, "weather")
	ChronicleHook.note("weather_watch", text, [], "", 1, false)