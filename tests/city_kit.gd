extends RefCounted
## Shared helpers for city_* tests (task 12; no run() method, so the runner skips it).

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

## Stub world + systems + incident content, one furnished home (Ada + Bo, household 1), the city dice OFF (scripted events only).
static func setup() -> StubWorld:
	var w := D.setup()
	CityState.reset()
	CityBudget.reset()
	UtilityEvents.dice_on = false
	UtilityContent.ensure()
	return w

static func home(w: StubWorld) -> Dictionary:
	var h: Dictionary = D.home(w)
	UtilityHomes.forget_cache()
	return h

static func zone() -> String:
	return CityState.zone_of_household(1)

static func run_hours(n: int) -> void:
	SimEnv.clock().advance_minutes(n * 60)
