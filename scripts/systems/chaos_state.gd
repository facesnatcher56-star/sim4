class_name ChaosState
extends RefCounted
## Household chaos (task 07): the saved state of home trouble. Lives inside the incidents save block (Incidents.to_dict()["chaos"]).
##   leaks   household id -> {obj, kind "pipe"|"overflow", since, hours}      water running right now
##   pests   household id -> {level 0..1, day, free_until}                    roaches in the house (level grows while it is messy)
##   jobs    [{hid, kind "plumber"|"exterminator"|"handy", due}]               tradespeople on their way
##   stats   counters for the long-run tests and the F9 panel
## Numbers are data: config.chaos in data/incidents/07_chaos.json.

static var leaks: Dictionary = {}
static var pests: Dictionary = {}
static var jobs: Array = []
static var stats: Dictionary = {}

static func reset() -> void:
	leaks.clear()
	pests.clear()
	jobs.clear()
	stats.clear()

static func cfg(key: String = "") -> Dictionary:
	var d: Dictionary = IncidentDefs.cfg("chaos", {})
	return d if key == "" else d.get(key, {})

static func count(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n

static func pest_level(hid: int) -> float:
	return float((pests.get(str(hid), {}) as Dictionary).get("level", 0.0))

static func pest_rec(hid: int) -> Dictionary:
	if not pests.has(str(hid)):
		pests[str(hid)] = {"level": 0.0, "day": SysUtil.day(), "free_until": -1}
	return pests[str(hid)]

static func leak_of(hid: int) -> Dictionary:
	return leaks.get(str(hid), {})

static func job_pending(hid: int, kind: String) -> bool:
	for j in jobs:
		if int(j["hid"]) == hid and str(j["kind"]) == kind:
			return true
	return false

static func to_dict() -> Dictionary:
	return {"leaks": leaks.duplicate(true), "pests": pests.duplicate(true), "jobs": jobs.duplicate(true), "stats": stats.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in (d.get("leaks", {}) as Dictionary):
		var r: Dictionary = (d["leaks"][k] as Dictionary).duplicate(true)
		SysUtil.ints_in(r, ["obj", "since", "hours"])
		leaks[str(k)] = r
	for k2 in (d.get("pests", {}) as Dictionary):
		var p: Dictionary = (d["pests"][k2] as Dictionary).duplicate(true)
		SysUtil.ints_in(p, ["day", "free_until"])
		p["level"] = float(p.get("level", 0.0))
		pests[str(k2)] = p
	for j in d.get("jobs", []):
		var q: Dictionary = (j as Dictionary).duplicate(true)
		SysUtil.ints_in(q, ["hid", "due"])
		jobs.append(q)
	stats = (d.get("stats", {}) as Dictionary).duplicate(true)
