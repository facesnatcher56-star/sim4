class_name Seasons
extends RefCounted
## Calendar: 4 seasons x N days (default 7, data/seasons.json, stored in the save), years, weekdays.
## Everything derives from the Clock's day counter plus one saved offset, so it works with --script tests
## (no autoload identifiers). Day 1 of the game = spring day 1, a Monday.
##
## Public API (all static):
##   Seasons.current() -> "spring"|"summer"|"autumn"|"winter"      Seasons.current_label()
##   Seasons.day_of_season() -> 1..length   Seasons.year() -> 1..   Seasons.progress() -> 0..1 (fractional, includes the hour)
##   Seasons.length() / set_length(n)        Seasons.weekday() 0..6, weekday_name(), is_weekend()
##   Seasons.season_at_day(day) / day_of_season_at(day) / year_at(day)      (absolute game day, 1-based)
##   Seasons.base_temp(pos) / diurnal_amp(pos) / daylight_hours(pos)         (smooth seasonal curves, pos = Seasons.year_pos())
##   Seasons.date_string() -> "Mon 3 Spring, Year 1"      Seasons.icon_color()

const IDS := ["spring", "summer", "autumn", "winter"]

static var _len: int = 0                # 0 = use the data default
static var _offset: int = 0             # calendar shift in days (keeps the season when the length changes)

static func cfg() -> Dictionary:
	return SysUtil.table("seasons")

static func reset() -> void:
	_len = 0
	_offset = 0

static func default_length() -> int:
	return int(cfg().get("season_length_days", 7))

static func length() -> int:
	return _len if _len > 0 else maxi(1, default_length())

## Change the season length without jumping to another season / day (the calendar is re-based).
static func set_length(n: int) -> void:
	var lo: int = int(cfg().get("min_length_days", 2))
	var hi: int = int(cfg().get("max_length_days", 30))
	n = clampi(n, lo, hi)
	var d: int = SimEnv.clock().day()
	var s_idx: int = season_index_total(d)
	var dos: int = mini(day_of_season_at(d), n)
	_len = n
	_offset = 0
	_offset = s_idx * n + (dos - 1) - (d - 1)

static func _d0(day: int) -> int:
	return maxi(day - 1 + _offset, 0)

## Total number of seasons elapsed (0 = first season of year 1).
static func season_index_total(day: int) -> int:
	return _d0(day) / length()

static func season_at_day(day: int) -> String:
	return IDS[season_index_total(day) % 4]

static func day_of_season_at(day: int) -> int:
	return _d0(day) % length() + 1

static func year_at(day: int) -> int:
	return season_index_total(day) / 4 + 1

static func today() -> int:
	return int(SimEnv.clock().day())

static func current() -> String:
	return season_at_day(today())

static func index() -> int:
	return IDS.find(current())

static func day_of_season() -> int:
	return day_of_season_at(today())

static func year() -> int:
	return year_at(today())

## Fraction of the current season elapsed, 0..1 (smooth through the day).
static func progress() -> float:
	var frac: float = (float(day_of_season() - 1) + SimEnv.hour_f() / 24.0) / float(length())
	return clampf(frac, 0.0, 1.0)

## Continuous position in the year: 0..4 (season index + progress). Used for smooth seasonal curves.
static func year_pos(day: int = -1, hour: float = -1.0) -> float:
	var d: int = today() if day < 0 else day
	var h: float = SimEnv.hour_f() if hour < 0.0 else hour
	var p: float = (float(_d0(d)) + h / 24.0) / float(length())
	return fposmod(p, 4.0)

static func weekday(day: int = -1) -> int:
	var d: int = today() if day < 0 else day
	return posmod(d - 1, 7)

static func weekday_name(day: int = -1) -> String:
	var names: Array = cfg().get("weekdays", ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
	return str(names[weekday(day) % names.size()])

static func weekday_long(day: int = -1) -> String:
	var names: Array = cfg().get("weekday_long", ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
	return str(names[weekday(day) % names.size()])

static func is_weekend(day: int = -1) -> bool:
	var wd: int = weekday(day)
	for v in cfg().get("weekend_days", [5, 6]):
		if int(v) == wd:
			return true
	return false

static func info(season_id: String) -> Dictionary:
	for s in cfg().get("seasons", []):
		if str(s.get("id", "")) == season_id:
			return s
	return {}

static func label(season_id: String = "") -> String:
	var sid: String = current() if season_id == "" else season_id
	return str(info(sid).get("label", sid.capitalize()))

static func current_label() -> String:
	return label()

static func month_label(season_id: String = "") -> String:
	var sid: String = current() if season_id == "" else season_id
	return str(info(sid).get("month_label", ""))

static func icon_color(season_id: String = "") -> Color:
	var sid: String = current() if season_id == "" else season_id
	return Color(str(info(sid).get("color", "#ffffff")))

static func date_string(day: int = -1) -> String:
	var d: int = today() if day < 0 else day
	return "%s %d %s, Year %d" % [weekday_name(d), day_of_season_at(d), label(season_at_day(d)), year_at(d)]

static func short_date(day: int = -1) -> String:
	var d: int = today() if day < 0 else day
	return "%s %d %s" % [weekday_name(d), day_of_season_at(d), label(season_at_day(d))]

# ------------------------------------------------------------------ smooth seasonal curves
static func _anchor(key: String, pos: float, default: float) -> float:
	var arr: Array = cfg().get("seasons", [])
	if arr.size() < 4:
		return default
	var p: float = fposmod(pos - 0.5, 4.0)     # anchors sit at season centres
	var i0: int = int(floor(p)) % 4
	var f: float = p - floor(p)
	var t: float = f * f * (3.0 - 2.0 * f)
	var a: float = float((arr[i0] as Dictionary).get(key, default))
	var b: float = float((arr[(i0 + 1) % 4] as Dictionary).get(key, default))
	return lerpf(a, b, t)

static func base_temp(pos: float = -1.0) -> float:
	return _anchor("base_temp", year_pos() if pos < 0.0 else pos, 12.0)

static func diurnal_amp(pos: float = -1.0) -> float:
	return _anchor("diurnal_amp", year_pos() if pos < 0.0 else pos, 5.0)

static func sunrise(pos: float = -1.0) -> float:
	return _anchor("sunrise", year_pos() if pos < 0.0 else pos, 6.5)

static func sunset(pos: float = -1.0) -> float:
	return _anchor("sunset", year_pos() if pos < 0.0 else pos, 19.0)

static func daylight_hours(pos: float = -1.0) -> float:
	return sunset(pos) - sunrise(pos)

# ------------------------------------------------------------------ save / load
static func to_dict() -> Dictionary:
	return {"length": length(), "offset": _offset}

static func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		reset()
		return
	_len = int(d.get("length", default_length()))
	_offset = int(d.get("offset", 0))
