extends RefCounted
## Helpers for crime_* / justice_* tests (no run(): the runner skips it).

const K = preload("res://tests/systems_kit.gd")

## Stub world, the player household 1 (Ada, 1000 coins), `n` townies, fresh crime state.
static func town(n: int = 10) -> StubWorld:
	var w: StubWorld = K.setup()
	Incidents.reset()
	Incidents.set_level("rare")
	CrimeFlow.reset()
	CrimeFlow.install()
	K.make_folk(w, "Ada", [], 1)
	WorldIface.coins[1] = 1000
	Story.generate_townies(n)
	Economy.refresh_objects()
	return w

static func ids() -> Array:
	var out: Array = Story.townies.keys()
	out.sort()
	return out

## Adult townies only (the first generated townie is a teen and the second an elder).
static func adults() -> Array:
	return ids().filter(func(t): return Story.stage_of(Story.townies[t]) == "adult")

static func quiet_witnesses() -> void:
	var m: Dictionary = JusticeState.sect("murder")
	m["witness_public"] = 0.0
	m["witness_home"] = 0.0
	m["witness_alone"] = 0.0

## Advance `hours` game hours from the current clock, calling the crime hourly tick each hour.
static func hours(n: int) -> void:
	for i in n:
		SimEnv.clock().total_minutes += 60
		CrimeFlow.on_hour()

static func minutes(n: int) -> void:
	for i in n:
		SimEnv.clock().total_minutes += 1
		CrimeFlow.on_minute()

## Run `days` days of the crime daily tick (and the hourly tick between).
static func days(n: int, hourly: bool = true) -> void:
	for d in n:
		if hourly:
			hours(24)
		else:
			SimEnv.clock().total_minutes += 1440
		CrimeFlow.on_day(SysUtil.day())

static func set_family(a: int, b: int) -> void:
	RelationshipService.add_both(a, b, "friendship", 70.0)
	RelationshipBits.set_flag(a, b, "family", true, false)

## Make `a` hate `b`: tension, grudge history, negative friendship.
static func feud(a: int, b: int, power: float = 90.0) -> void:
	RelationshipRomance.add_tension(a, b, power)
	RelationshipRomance.add_tension(b, a, power * 0.5)
	RelationshipService.set_value(a, b, "friendship", -70.0)
	for i in 4:
		RelationshipService.add_history(a, b, "insult", -1.0, b)
