extends RefCounted
## Calendar: season progression, year counter, weekdays, configurable season length, smooth seasonal curves.

const W = preload("res://tests/weather_kit.gd")

func run() -> Array:
	var f: Array = []
	_progression(f)
	_length(f)
	_weekdays(f)
	_curves(f)
	return f

func _progression(f: Array) -> void:
	W.setup()
	SimEnv.clock().reset()
	W.expect(f, Seasons.current() == "spring" and Seasons.day_of_season() == 1 and Seasons.year() == 1, "day 1 must be spring day 1 of year 1")
	W.expect(f, Seasons.length() == 7, "default season length is 7, got %d" % Seasons.length())
	var expect_seq := ["spring", "summer", "autumn", "winter", "spring"]
	for i in 5:
		var day: int = 1 + i * 7
		SimEnv.clock().total_minutes = W.at(day, 12)
		W.expect(f, Seasons.current() == expect_seq[i], "day %d should be %s, got %s" % [day, expect_seq[i], Seasons.current()])
		W.expect(f, Seasons.day_of_season() == 1, "first day of a season has day_of_season 1")
	SimEnv.clock().total_minutes = W.at(28, 12)
	W.expect(f, Seasons.current() == "winter" and Seasons.day_of_season() == 7 and Seasons.year() == 1, "day 28 = winter day 7 year 1")
	SimEnv.clock().total_minutes = W.at(29, 0)
	W.expect(f, Seasons.year() == 2, "day 29 starts year 2")
	W.expect(f, Seasons.year_at(57) == 3 and Seasons.season_at_day(57) == "spring", "day 57 = year 3 spring")
	# progress is monotonic within a season and within 0..1
	var last: float = -1.0
	for d in range(1, 8):
		for h in [0, 6, 12, 18]:
			SimEnv.clock().total_minutes = W.at(d, h)
			var p: float = Seasons.progress()
			W.expect(f, p >= 0.0 and p <= 1.0, "progress out of range: %f" % p)
			W.expect(f, p > last, "progress must increase (%f after %f)" % [p, last])
			last = p
	W.expect(f, Seasons.date_string(1).begins_with("Mon 1 Spring"), "date string: " + Seasons.date_string(1))
	# the clock's day_passed drives season change events through the manager
	SimEnv.clock().total_minutes = W.at(7, 23, 58)
	W.run_min(5)
	W.expect(f, Seasons.current() == "summer", "clock advance crosses into summer")
	W.teardown()

func _length(f: Array) -> void:
	W.setup()
	SimEnv.clock().total_minutes = W.at(9, 8)     # summer day 2
	Seasons.set_length(10)
	W.expect(f, Seasons.current() == "summer" and Seasons.day_of_season() == 2, "set_length keeps the current season and day: %s %d" % [Seasons.current(), Seasons.day_of_season()])
	SimEnv.clock().total_minutes = W.at(17, 8)    # 8 days later: summer day 10
	W.expect(f, Seasons.current() == "summer" and Seasons.day_of_season() == 10, "10-day summer, day 10: %s %d" % [Seasons.current(), Seasons.day_of_season()])
	SimEnv.clock().total_minutes = W.at(18, 8)
	W.expect(f, Seasons.current() == "autumn" and Seasons.day_of_season() == 1, "autumn follows a 10-day summer")
	Seasons.set_length(3)
	W.expect(f, Seasons.length() == 3 and Seasons.day_of_season() == 1 and Seasons.current() == "autumn", "shrinking keeps season, clamps day")
	Seasons.set_length(500)
	W.expect(f, Seasons.length() == 30, "length is clamped to the configured max")
	var d: Dictionary = Seasons.to_dict()
	Seasons.reset()
	W.expect(f, Seasons.length() == 7, "reset restores the data default")
	Seasons.from_dict(JSON.parse_string(JSON.stringify(d)))
	W.expect(f, Seasons.length() == 30 and Seasons.current() == "autumn", "season length + offset survive a JSON round trip")
	W.teardown()

func _weekdays(f: Array) -> void:
	W.setup()
	W.expect(f, Seasons.weekday_name(1) == "Mon" and Seasons.weekday_name(7) == "Sun" and Seasons.weekday_name(8) == "Mon", "weekday cycle")
	W.expect(f, not Seasons.is_weekend(5) and Seasons.is_weekend(6) and Seasons.is_weekend(7), "weekend = days 6 and 7")
	W.teardown()

func _curves(f: Array) -> void:
	W.setup()
	var b_sp: float = Seasons.base_temp(0.5)
	var b_su: float = Seasons.base_temp(1.5)
	var b_au: float = Seasons.base_temp(2.5)
	var b_wi: float = Seasons.base_temp(3.5)
	W.expect(f, b_su > b_sp and b_sp > b_wi and b_au > b_wi, "base temps: summer warmest, winter coldest (%f %f %f %f)" % [b_sp, b_su, b_au, b_wi])
	W.expect(f, absf(Seasons.base_temp(3.999) - Seasons.base_temp(0.0)) < 0.5, "curve is continuous across the year boundary")
	W.expect(f, Seasons.daylight_hours(1.5) > Seasons.daylight_hours(3.5) + 4.0, "summer days are longer than winter days")
	W.teardown()
