extends RefCounted
## Shared helpers for sim_* tests (no run() method, so the runner skips it).

static func setup(seed_value: int = 12345) -> StubWorld:
	TestFixture.reset()
	SimEnv.use_standalone()
	var w := StubWorld.new()
	WorldIface.stub = w
	WorldIface.coins.clear()
	Autonomy.last_debug.clear()
	Autonomy.rng = RandomNumberGenerator.new()
	Autonomy.rng.seed = seed_value
	Loot.rng = RandomNumberGenerator.new()
	Loot.rng.seed = seed_value + 1
	return w

static func teardown() -> void:
	if WorldIface.stub != null:
		for fk in WorldIface.stub.all_folk():   # break Folk <-> Interaction reference cycles
			fk.current = null
			fk.queue.clear()
	WorldIface.stub = null
	WorldIface.coins.clear()
	Autonomy.rng = null
	Loot.rng = null
	SimEnv.release_standalone()

static func set_time(day: int, hour: int, minute: int = 0) -> void:
	SimEnv.clock().total_minutes = (day - 1) * 1440 + hour * 60 + minute

static func director():
	return load("res://scripts/sim/director.gd").new()

## Furnish an open field. Objects used by the data set.
static func furnish(w: StubWorld, origin: Vector2i = Vector2i(10, 10)) -> Dictionary:
	var o := origin
	var objs: Dictionary = {}
	var layout := {
		"fridge": Vector2i(0, 0), "stove": Vector2i(2, 0), "counter": Vector2i(4, 0), "table": Vector2i(6, 0),
		"chair": Vector2i(8, 0), "bed": Vector2i(0, 4), "toilet": Vector2i(4, 4), "shower": Vector2i(6, 4),
		"bathtub": Vector2i(8, 4), "sink": Vector2i(10, 4), "sofa": Vector2i(0, 8), "tv": Vector2i(4, 8),
		"bookshelf": Vector2i(6, 8), "easel": Vector2i(8, 8), "treadmill": Vector2i(10, 8),
		"computer": Vector2i(12, 8), "plant": Vector2i(12, 0), "lamp": Vector2i(12, 4), "trash_bin": Vector2i(14, 4),
	}
	for k in layout:
		objs[k] = w.add_object(k, o + layout[k])
	return objs

static func expect(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

static func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

## Run director + clock for n minutes.
static func run_minutes(dir, n: int) -> void:
	for i in n:
		SimEnv.clock().advance_minutes(1)
		dir.tick_minute(1)
