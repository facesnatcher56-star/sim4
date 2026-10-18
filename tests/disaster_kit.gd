extends RefCounted
## Shared helpers for disaster_* tests (no run() method, so the runner skips it).

const K = preload("res://tests/systems_kit.gd")

## Fresh stub world with the incident content, one household (Ada + Bo) with a furnished home and a few outdoor things.
static func setup() -> StubWorld:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	Incidents.set_level("rare")
	IncidentContent.install()
	DisasterContent.ensure()
	Weather.force("sunny")
	return w

static func home(w: StubWorld) -> Dictionary:
	var ada := K.make_folk(w, "Ada Voss", [], 1, Vector2i(12, 12))
	var bo := K.make_folk(w, "Bo Voss", [], 1, Vector2i(13, 12))
	var objs: Dictionary = Kit.furnish(w)
	for id in ["garden_plot", "mailbox", "grill"]:
		objs[id] = w.add_object(id, Vector2i(30, 30 + objs.size()))
	WorldIface.coins[1] = 3000
	Economy.refresh_objects()
	return {"ada": ada, "bo": bo, "objs": objs}

const Kit = preload("res://tests/sim_testkit.gd")

static func cfg_set(kind: String, key: String, value: Variant) -> void:
	((IncidentDefs.config["disasters"]["damage"] as Dictionary)[kind] as Dictionary)[key] = value

## Force a town incident for the home lot only.
static func force_home(id: String, outcome: int = -1) -> Dictionary:
	return Incidents.force(id, {"lot": "home:1", "outcome": outcome})

static func run_minutes(n: int) -> void:
	for i in n:
		SimEnv.clock().advance_minutes(1)
		DisasterClock.on_minute()

static func run_hours(n: int) -> void:
	for i in n:
		for m in 60:
			SimEnv.clock().advance_minutes(1)
			DisasterClock.on_minute()
		DisasterClock.on_hour(0)

static func count_objects(w: StubWorld, def_id: String) -> int:
	var n: int = 0
	for o in w.objects.values():
		if str(o.def_id) == def_id:
			n += 1
	return n
