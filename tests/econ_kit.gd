extends RefCounted
## Shared helpers for the econ_* tests (no run(), so the runner skips it).

const K = preload("res://tests/systems_kit.gd")

## Stub world, one adult household (id 1, 5000 coins), 12 townies, the economy switched on.
static func setup(coins: int = 5000) -> StubWorld:
	var w: StubWorld = K.setup()
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	MarketTick.new_game()
	return w

## Jump to day `d` (8:00) and run the economy's daily tick.
static func day(d: int) -> void:
	K.set_time(d, 8)
	MarketTick.on_day(d)

static func days(from_day: int, to_day: int) -> void:
	for d in range(from_day, to_day + 1):
		day(d)

static func teardown() -> void:
	K.teardown()
