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

static func outdoors(f, on: bool = true) -> void:
	f.set_meta("outdoors", on)

static func expect(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
