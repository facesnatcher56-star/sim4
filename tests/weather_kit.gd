extends RefCounted
## Shared helpers for weather_* tests (no run() method, so the runner skips it).

const K = preload("res://tests/systems_kit.gd")

static func setup(seed_value: int = 777) -> StubWorld:
	var w: StubWorld = K.setup(4242, true)
	Weather.reset(seed_value)
	WeatherContent.install()
	return w

static func teardown() -> void:
	Weather.unforce()
	Weather.outdoors_fn = Callable()
	K.teardown()

## Absolute minute counter for (day, hour).
static func at(day: int, hour: int = 0, minute: int = 0) -> int:
	return (day - 1) * 1440 + hour * 60 + minute

static func run_min(n: int) -> void:
	SimEnv.clock().advance_minutes(n)

## Like run_min, but only the hour and day signals fire (no per-minute systems): for tests whose subject lives in the hourly / daily
## hooks (weather steps, bills, crops, snow), 10x cheaper than minute by minute.
static func run_coarse(n: int) -> void:
	var c = SimEnv.clock()
	for i in n:
		var old_day: int = c.day()
		c.total_minutes += 1
		if c.minute() == 0:
			c.hour_passed.emit(c.hour())
		if c.day() != old_day:
			c.day_passed.emit(c.day())

static func outdoors(f, on: bool = true) -> void:
	f.set_meta("outdoors", on)

static func expect(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)