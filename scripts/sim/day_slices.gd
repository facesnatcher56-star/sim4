class_name DaySlices
extends RefCounted
## Daily passes over many items (relationship pairs, grudges ...) spread over the 24 hours of the day instead of one midnight lump (task 17.3).
## A system registers its pass at midnight with `begin(name, items, fn)`; the hour row calls `on_hour()`, which runs slice k (items with index % 24 == k) of every
## pass, so each item is still visited exactly once per day with the same function. Without a scheduler (tests calling the on_day functions directly) the
## owners run their full loops as before: `enabled()` tells them. A pass still unfinished when the next one begins is flushed first.
## Tier behaviour: items are the TOWN / STATISTICAL records and the ACTIVE ones alike (pure data passes); the cost per hour is total / 24.

const SLICES := 24

static var _job: SimJob = null
static var _sched_id: int = 0
static var _passes: Dictionary = {}       # name -> {"items": Array, "fn": Callable, "k": int}
static var stats: Dictionary = {"begun": 0, "slices": 0, "items": 0}

static func install(sched: SimScheduler, group: String) -> void:
	_sched_id = sched.get_instance_id()
	_job = sched.add("DaySlices", "DaySlices", group, 60, 205, SimScheduler.NORMAL, DaySlices.on_hour, "", Callable(DaySlices, "active"),
		"runs 1/24 of every registered daily pass each hour (relationship decay, grudges, ...); idle = one call")

static func enabled() -> bool:
	return _job != null and not _job.removed and _job.enabled and SimScheduler.of(SimEnv.clock()).get_instance_id() == _sched_id

static func active() -> bool:
	return not _passes.is_empty()

static func reset() -> void:
	_passes.clear()

static func begin(pass_name: String, items: Array, fn: Callable) -> void:
	if _passes.has(pass_name):
		_flush(pass_name)
	_passes[pass_name] = {"items": items, "fn": fn, "k": 0}
	stats["begun"] = int(stats["begun"]) + 1

static func _flush(pass_name: String) -> void:
	while _passes.has(pass_name):
		_slice(pass_name)

static func on_hour() -> void:
	for n in _passes.keys():
		_slice(n)

static func _slice(pass_name: String) -> void:
	var p: Dictionary = _passes[pass_name]
	var k: int = int(p["k"])
	var items: Array = p["items"]
	var fn: Callable = p["fn"]
	var i: int = k
	while i < items.size():
		if fn.is_valid():
			fn.call(items[i])
			stats["items"] = int(stats["items"]) + 1
		i += SLICES
	stats["slices"] = int(stats["slices"]) + 1
	p["k"] = k + 1
	if k + 1 >= SLICES:
		_passes.erase(pass_name)
