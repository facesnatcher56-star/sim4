class_name PerfProf
extends RefCounted
## Opt-in micro profiler for tests/perf_probe.gd: `PerfProf.on = true`, then `var t := PerfProf.start()` ... `PerfProf.stop("label", t)`.
## Costs one boolean test when off. Totals are label -> [usec, calls].

static var on: bool = false
static var totals: Dictionary = {}

static func start() -> int:
	return Time.get_ticks_usec() if on else 0

static func stop(label: String, t0: int) -> void:
	if not on:
		return
	var rec: Array = totals.get(label, [0, 0])
	rec[0] += Time.get_ticks_usec() - t0
	rec[1] += 1
	totals[label] = rec
