extends RefCounted
## Shared helpers for the fire_* tests (no run() method, so the runner skips it): a stub world with a small furnished house, a director and
## a minute loop that drives the clock (SystemsManager -> Fire.on_minute) and the folk (director).

const K = preload("res://tests/systems_kit.gd")

static var dir = null

static func setup() -> StubWorld:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	Incidents.set_level("rare")
	Fire.reset()
	Weather.force("sunny")
	K.set_time(3, 12)
	dir = K.director()
	dir.autonomy_enabled = false
	return w

static func teardown() -> void:
	Weather.unforce()
	K.teardown()

## A kitchen corner (stove, counter, fridge), a living corner and a bedroom. Returns name -> object.
static func house(w: StubWorld, extra: Array = []) -> Dictionary:
	var o: Dictionary = {}
	o["stove"] = w.add_object("stove", Vector2i(12, 12))
	o["counter"] = w.add_object("counter", Vector2i(13, 12))
	o["fridge"] = w.add_object("fridge", Vector2i(14, 12))
	o["tv"] = w.add_object("tv", Vector2i(16, 12))
	o["sofa"] = w.add_object("sofa", Vector2i(17, 12))
	o["bed"] = w.add_object("bed", Vector2i(12, 18))
	o["crib"] = w.add_object("crib", Vector2i(13, 18))
	for e in extra:
		o[str(e[0])] = w.add_object(str(e[0]), e[1])
	Economy.refresh_objects()
	return o

static func run(n: int) -> void:
	K.run(dir, n)

static func burning(lot: String = "home") -> bool:
	return not Fire.fires_in(lot).is_empty()

## Minutes until the blaze of `lot` is over (or `cap`). Returns minutes used.
static func run_until_out(cap: int = 120, lot: String = "home") -> int:
	var n: int = 0
	while n < cap and (Fire.blazes.has(lot) or not Fire.crew.is_empty()):
		run(1)
		n += 1
	return n
