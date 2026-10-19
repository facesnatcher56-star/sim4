extends RefCounted
## Shared helpers for chaos_* tests (no run() method, so the runner skips it).

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

## Fresh stub world with the incident content, one household (Ada + Bo) with a furnished home and a mailbox.
static func setup() -> Dictionary:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	Incidents.set_level("rare")
	IncidentContent.install()
	Weather.force("sunny")
	var ada := K.make_folk(w, "Ada Voss", [], 1, Vector2i(12, 12))
	var bo := K.make_folk(w, "Bo Voss", [], 1, Vector2i(13, 12))
	var objs: Dictionary = Kit.furnish(w)
	objs["mailbox"] = w.add_object("mailbox", Vector2i(30, 30))
	WorldIface.coins[1] = 3000
	Economy.refresh_objects()
	return {"w": w, "ada": ada, "bo": bo, "objs": objs}

static func ev(name: String, folk, obj_id: int = -1) -> void:
	SimEnv.emit("game_event", name, {"folk_id": folk.id, "object_id": obj_id, "target_id": -1})

## Advance the clock; the SystemsManager of the test world runs the minute / hour / day hooks (Incidents -> ChaosClock) by itself.
static func minutes(n: int) -> void:
	for i in n:
		SimEnv.clock().advance_minutes(1)

## Whole hours without the full simulation (cheap): the clock jumps an hour, then the minute and hour chaos hooks run once.
static func hours(n: int) -> void:
	for i in n:
		var m: int = SysUtil.now() + 60
		K.set_time(m / 1440 + 1, (m % 1440) / 60, m % 60)
		ChaosClock.on_minute()
		ChaosClock.on_hour()

## Whole days without the full simulation (cheap): the clock is set to the next morning and the daily chaos hook runs once.
static func days(n: int) -> void:
	for i in n:
		K.set_time(SysUtil.day() + 1, 6)
		ChaosClock.on_day()
