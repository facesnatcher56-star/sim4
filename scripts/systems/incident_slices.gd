class_name IncidentSlices
extends RefCounted
## The hourly and daily incident dice spread over the clock (task 17.3), so no frame pays for every subject at once.
## An hourly pass (IncidentChecks.run("hour") used to roll ~200 subjects x 15 incident defs inside the hour tick: 100-800 ms) is cut into 60 slices, one per game
## minute: slice k rolls the subjects with index % 60 == k (the same candidate lists, the same chance per subject per hour, the same data), so the
## expected number of rolls and events per hour is unchanged; only WHEN inside the hour a subject is rolled moves. The daily pass is cut into 96 slices, one every
## 15 minutes. The town-wide roll ("town" scope) is slice 0. A subject that stopped being valid between the start of the pass and its slice (left the world,
## died, went to hospital) is skipped.
## Tier behaviour: ACTIVE / NEAR folk are FULL subjects, TOWN / STATISTICAL townies are the STATISTICAL subjects of the same lists. Active set: the lists built at the
## start of the pass (bounded by the folk in the world + living townies + lots). Cadence: minute row "Incidents.slice" (gated: idle = one call).

static var _job: SimJob = null
static var _sched_id: int = 0
static var _passes: Dictionary = {}       # check -> pass (an hourly and a daily pass can run side by side)
static var stats: Dictionary = {"passes": 0, "slices": 0, "rolls": 0, "skipped": 0, "max_slice_usec": 0}

static func install(sched: SimScheduler, group: String) -> void:
	_sched_id = sched.get_instance_id()
	_job = sched.add("Incidents.slice", "Incidents", group, 1, 271, SimScheduler.NORMAL, IncidentSlices.run_slice, "", Callable(IncidentSlices, "active"),
		"hourly / daily dice in 60 / 96 slices of the subject lists (FULL near, STATISTICAL far); no midnight or top-of-hour lump")

static func enabled() -> bool:
	return _job != null and not _job.removed and _job.enabled and SimScheduler.of(SimEnv.clock()).get_instance_id() == _sched_id

static func active() -> bool:
	return not _passes.is_empty()

static func reset() -> void:
	_passes.clear()

## Start a pass: the hour / day tick calls this instead of IncidentChecks.run. A pass still running (a slow clock) is finished first.
static func begin(check: String) -> void:
	IncidentDefs.ensure()
	while _passes.has(check):
		_do_slice(check)
	IncidentSubject.clear_cache()
	_passes[check] = {"check": check, "i": 0, "n": 60 if check == "hour" else 96, "step": 1 if check == "hour" else 15, "next": SimEnv.now_min(), "lists": {}}
	stats["passes"] = int(stats["passes"]) + 1

static func run_slice() -> void:
	var now: int = SimEnv.now_min()
	for check in _passes.keys():
		if now < int((_passes[check] as Dictionary)["next"]):
			continue
		var t0 := Time.get_ticks_usec()
		_do_slice(check)
		stats["max_slice_usec"] = maxi(int(stats["max_slice_usec"]), Time.get_ticks_usec() - t0)

static func _lists(ps: Dictionary) -> Dictionary:
	var ls: Dictionary = ps["lists"]
	if ls.is_empty():
		ls["folk"] = IncidentChecks.folk_subjects(true)
		ls["townie"] = IncidentChecks.townie_subjects()
		ls["lot"] = IncidentChecks.lot_subjects()
	return ls

static func _valid(s) -> bool:
	match str(s.kind):
		"folk":
			return WorldIface.get_folk(int(s.id)) == s.folk and not Hospital.is_in(s.folk)
		"townie":
			var t: Dictionary = Story.townies.get(int(s.id), {})
			return not t.is_empty() and bool(t["alive"]) and not bool(t.get("in_hospital", false)) and not IncidentSubject.on_map(int(s.id))
	return true

static func _do_slice(check: String) -> void:
	var ps: Dictionary = _passes[check]
	var k: int = int(ps["i"])
	var n: int = int(ps["n"])
	var lists: Dictionary = _lists(ps)
	IncidentChecks.begin_slice()
	if check == "hour":
		AccidentMarks.slice_markers(true)
	for id in IncidentDefs.ids():
		var def: Dictionary = IncidentDefs.defs[id]
		if str(def["check"]) != check:
			continue
		var scope: String = str(def["scope"])
		var tdef := PerfProf.start()
		if scope == "town":
			if k == 0:
				IncidentChecks._town(id, def)
			PerfProf.stop("incdef/" + str(id), tdef)
			continue
		var arr: Array = lists["folk" if scope == "folk" else ("townie" if scope == "townie" else "lot")]
		var i: int = k
		while i < arr.size():
			var s = arr[i]
			i += n
			if _valid(s):
				stats["rolls"] = int(stats["rolls"]) + 1
				IncidentChecks._roll(id, def, s)
			else:
				stats["skipped"] = int(stats["skipped"]) + 1
		PerfProf.stop("incdef/" + str(id), tdef)
	if check == "hour":
		AccidentMarks.slice_markers(false)
	IncidentChecks.end_slice()
	stats["slices"] = int(stats["slices"]) + 1
	ps["i"] = k + 1
	ps["next"] = SimEnv.now_min() + int(ps["step"])
	if k + 1 >= n:
		_passes.erase(check)
