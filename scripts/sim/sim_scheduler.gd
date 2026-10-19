class_name SimScheduler
extends RefCounted
## The one place where simulation work is scheduled (task 17.2). NO system connects to Clock.minute_passed / hour_passed / day_passed any
## more: it registers a job here (the data table is sim_registry.gd) and the scheduler is the only Clock listener (one per Clock, `of(clock)`).
##
## Work comes in three shapes:
##  * PLAIN periodic job: `add(...)`, cadence 1 / 5 / 15 minutes, 60 (hourly) or 1440 (daily); runs in the layer of its cadence in
##    (order, seq) order. A Clock minute runs the minute layer, then (on the hour) the hour layer, then (at midnight) the day layer, exactly
##    like the old signal order. `active` is an emptiness gate: when it returns false the job costs one call and nothing else.
##  * BUCKETED periodic job: `add_bucketed(...)` + `track(id)` / `untrack(id)`: every tracked id is visited once per `cadence` minutes, spread by
##    `id % cadence`, so 200 townies at cadence 60 run about 3-4 per minute, never all at the top of the hour. Nothing tracked = zero cost.
##  * TIMED wake-up: `at(minute, owner, fn, args)`: fires once at an absolute game minute, ordered by (minute, seq). Not saved: a system that
##    owns timed work re-registers it after a load from its own saved state.
##
## Priorities: CRITICAL (household-critical, never deferred), NORMAL (never deferred), LOW (deferred to a later tick when the frame budget is
## spent). `budget_usec` = 0 means unlimited (tests, headless; deterministic). The game sets it (main.gd) so a heavy frame postpones LOW work.
## A postponed job runs at the start of a later tick (at the latest after MAX_DEFER_TICKS) and is counted in stats().
## Stats are free when `profile` is off (counts only); ms per job need `profile = true` (perf tools) or a budget.

const CRITICAL := 0
const NORMAL := 1
const LOW := 2
const MINUTE := 1
const HOUR := 60
const DAY := 1440
const META := "sim_scheduler"
const MAX_DEFER_TICKS := 12

var clock = null
var profile: bool = false
var budget_usec: int = 0
var now_fn: Callable = Callable()          # tests inject a fake microsecond timer
var frame_fn: Callable = Callable()        # ... and a fake frame counter
var ticks: int = 0
var deferred_total: int = 0
var timed_fired: int = 0
var layer_usec: Array = [0, 0, 0]          # profile only: usec spent per layer (minute / hour / day)
var layer_calls: Array = [0, 0, 0]
var max_deferred_pending: int = 0

var _layers: Array = [[], [], []]
var _all: Array = []
var _seq: int = 0
var _disabled: Dictionary = {}
var _timed := SimTimed.new()
var _deferred: Array = []                  # [job, arg, age]
var _frame: int = -1
var _spent: int = 0
var _ticking: bool = false
var _dirty: bool = false                   # layers need re-sorting / pruning

## The scheduler of a Clock (created and attached on first use).
static func of(clk = null) -> SimScheduler:
	if clk == null:
		clk = SimEnv.clock()
	if clk.has_meta(META):
		return clk.get_meta(META)
	var s := SimScheduler.new()
	s.clock = clk
	clk.minute_passed.connect(s._on_minute)
	clk.hour_passed.connect(s._on_hour)
	clk.day_passed.connect(s._on_day)
	clk.set_meta(META, s)
	return s

# ------------------------------------------------------------------ registration
func _new_job(name: String, owner: String, group: String, cadence: int, order: int, prio: int, fn: Callable, arg_kind: String, layer: int) -> SimJob:
	var j := SimJob.new()
	j.name = name
	j.owner = owner
	j.group = group
	j.cadence = maxi(cadence, 1)
	j.order = order
	j.prio = prio
	j.fn = fn
	j.arg_kind = arg_kind
	_seq += 1
	j.seq = _seq
	_all.append(j)
	(_layers[layer] as Array).append(j)
	_dirty = true
	return j

## Plain periodic job. `arg_kind`: "" fn(), otherwise fn(value) with the minute total (layer 0), the hour or the day number.
## `active`: optional emptiness gate (Callable -> bool). `note`: tier behaviour / active set / caps for describe().
func add(name: String, owner: String, group: String, cadence: int, order: int, prio: int, fn: Callable, arg_kind: String = "", active: Callable = Callable(), note: String = "") -> SimJob:
	var layer := 0 if cadence < HOUR else (1 if cadence < DAY else 2)
	var j := _new_job(name, owner, group, cadence, order, prio, fn, arg_kind, layer)
	j.active = active
	j.note = note
	if not _ticking:
		_settle()
	return j

## Bucketed periodic job: fn(id, elapsed_minutes) for each tracked id once per `cadence` minutes (id % cadence picks the minute).
## Bucketed jobs are checked every minute whatever their cadence, so they live in the minute layer.
func add_bucketed(name: String, owner: String, group: String, cadence: int, order: int, prio: int, fn: Callable, note: String = "") -> SimJob:
	var j := _new_job(name, owner, group, cadence, order, prio, fn, "", 0)
	j.make_buckets()
	j.note = note
	if not _ticking:
		_settle()
	return j

## One-shot wake-up at an absolute game minute (fires on the first tick at or after it). Returns an id for cancel().
func at(minute: int, owner: String, fn: Callable, args: Array = [], name: String = "") -> int:
	return _timed.add(minute, owner, name if name != "" else owner, fn, args)

func cancel(timed_id: int) -> bool:
	return _timed.cancel(timed_id)

func timed_pending() -> int:
	return _timed.size()

func job(name: String, group: String = "") -> SimJob:
	for j in _all:
		if j.name == name and (group == "" or j.group == group) and not j.removed:
			return j
	return null

func remove_group(group: String) -> void:
	for j in _all:
		if j.group == group:
			j.removed = true
			j.enabled = false
	_disabled.erase(group)
	_dirty = true
	if not _ticking:
		_settle()

func set_group_enabled(group: String, on: bool) -> void:
	if on:
		_disabled.erase(group)
	else:
		_disabled[group] = true

func has_group(group: String) -> bool:
	for j in _all:
		if j.group == group and not j.removed:
			return true
	return false

func _settle() -> void:
	if not _dirty:
		return
	_dirty = false
	for j in _all.duplicate():
		if j.removed:
			_all.erase(j)
			for l in _layers:
				(l as Array).erase(j)
	_deferred = _deferred.filter(func(e): return not (e[0] as SimJob).removed)
	for l in _layers:
		(l as Array).sort_custom(func(a, b): return a.order < b.order or (a.order == b.order and a.seq < b.seq))

# ------------------------------------------------------------------ clock
func _on_minute(total: int) -> void:
	_run_layer(0, total)

func _on_hour(hour: int) -> void:
	_run_layer(1, hour)

func _on_day(day: int) -> void:
	_run_layer(2, day)

func _now() -> int:
	return int(now_fn.call()) if now_fn.is_valid() else Time.get_ticks_usec()

func _frame_id() -> int:
	return int(frame_fn.call()) if frame_fn.is_valid() else Engine.get_process_frames()

func over_budget() -> bool:
	return budget_usec > 0 and _spent >= budget_usec

func _run_layer(layer: int, arg: int) -> void:
	_ticking = true
	var measure := profile or budget_usec > 0
	var t_layer := _now() if profile else 0
	if layer == 0:
		ticks += 1
	if budget_usec > 0:
		var f := _frame_id()
		if f != _frame:
			_frame = f
			_spent = 0
	var total: int = arg if layer == 0 else (int(clock.total_minutes) if clock != null else 0)
	if layer == 0 and _timed.size() > 0:
		_fire_timed(total)
	if not _deferred.is_empty():
		_drain_deferred()
	for j in _layers[layer]:
		if j.removed or not j.enabled or _disabled.has(j.group):
			continue
		if j.slots.is_empty():
			if j.cadence > 1 and layer == 0 and (total - j.phase) % j.cadence != 0:
				continue
			if j.active.is_valid() and not j.active.call():
				j.idle_skips += 1
				continue
		elif j.count == 0:
			continue
		if j.prio == LOW and over_budget():
			_defer(j, arg if j.slots.is_empty() else total)
			continue
		_run(j, arg, total, measure)
	_ticking = false
	if _dirty:
		_settle()
	if profile:
		layer_usec[layer] += _now() - t_layer
		layer_calls[layer] += 1

func _fire_timed(now: int) -> void:
	for e in _timed.pop_due(now):
		var fn: Callable = e[3]
		if fn.is_valid():
			timed_fired += 1
			fn.callv(e[4])

func _defer(j: SimJob, arg: int) -> void:
	j.deferred += 1
	deferred_total += 1
	if j.slots.is_empty():
		for e in _deferred:
			if e[0] == j:
				j.coalesced += 1
				e[1] = arg
				return
	_deferred.append([j, arg, 0])
	max_deferred_pending = maxi(max_deferred_pending, _deferred.size())

func _drain_deferred() -> void:
	var keep: Array = []
	var measure := profile or budget_usec > 0
	for e in _deferred:
		e[2] += 1
		var j: SimJob = e[0]
		if j.removed:
			continue
		if int(e[2]) > MAX_DEFER_TICKS or not over_budget():
			_run(j, int(e[1]), int(e[1]), measure)
		else:
			keep.append(e)
	_deferred = keep

func _run(j: SimJob, arg: int, total: int, measure: bool) -> void:
	if not j.fn.is_valid():           # the owner was freed without unregistering: drop the job
		j.removed = true
		j.enabled = false
		_dirty = true
		return
	var t0 := _now() if measure else 0
	if j.slots.is_empty():
		if j.arg_kind == "":
			j.fn.call()
		else:
			j.fn.call(arg)
	else:
		var ids: Array = j.slots[posmod(total, j.cadence)]
		j.last_batch = ids.size()
		if not ids.is_empty():
			j.max_batch = maxi(j.max_batch, ids.size())
			j.items += ids.size()
			for id in ids.duplicate():
				j.fn.call(id, j.cadence)
	j.calls += 1
	if measure:
		var dt := _now() - t0
		j.usec += dt
		_spent += dt

# ------------------------------------------------------------------ stats / documentation
func reset_stats() -> void:
	ticks = 0
	deferred_total = 0
	timed_fired = 0
	max_deferred_pending = 0
	layer_usec = [0, 0, 0]
	layer_calls = [0, 0, 0]
	for j in _all:
		j.calls = 0
		j.usec = 0
		j.deferred = 0
		j.coalesced = 0
		j.idle_skips = 0
		j.max_batch = 0
		j.items = 0

## {jobs, ticks, deferred_total, deferred_pending, timed_pending, timed_fired, by_owner: {owner: {jobs, calls, usec, deferred}}, rows: [per job]}.
func stats() -> Dictionary:
	var by_owner: Dictionary = {}
	var rows: Array = []
	for j in _all:
		if j.removed:
			continue
		var o: Dictionary = by_owner.get(j.owner, {"jobs": 0, "calls": 0, "usec": 0, "deferred": 0})
		o["jobs"] += 1
		o["calls"] += j.calls
		o["usec"] += j.usec
		o["deferred"] += j.deferred
		by_owner[j.owner] = o
		rows.append({"name": j.name, "owner": j.owner, "group": j.group, "cadence": j.cadence, "prio": j.prio, "calls": j.calls, "usec": j.usec,
			"deferred": j.deferred, "idle_skips": j.idle_skips, "max_batch": j.max_batch, "tracked": j.count, "bucketed": j.is_bucketed()})
	return {"jobs": rows.size(), "ticks": ticks, "deferred_total": deferred_total, "deferred_pending": _deferred.size(), "timed_pending": _timed.size(),
		"timed_fired": timed_fired, "by_owner": by_owner, "rows": rows, "layer_usec": layer_usec.duplicate()}

## The registry as a markdown table (docs/PERFORMANCE.md lists it): one line per job in running order.
func describe() -> String:
	var lines: PackedStringArray = PackedStringArray(["| layer | order | job | system | cadence | priority | tier behaviour / active set / caps |", "|---|---|---|---|---|---|---|"])
	var names := ["minute", "hour", "day"]
	for l in 3:
		for j in _layers[l]:
			if j.removed:
				continue
			lines.append("| %s | %d | %s | %s | %s%s | %s | %s |" % [names[l], j.order, j.name, j.owner, j.cadence_label(), " (bucketed)" if j.is_bucketed() else "",
				["CRITICAL", "NORMAL", "LOW"][j.prio], j.note])
	return "\n".join(lines)
