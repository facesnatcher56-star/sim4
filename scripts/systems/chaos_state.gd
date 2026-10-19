class_name ChaosState
extends RefCounted
## Household chaos (task 07): the saved state of home trouble. Lives inside the incidents save block (Incidents.to_dict()["chaos"]).
##   leaks   household id -> {obj, kind "pipe"|"overflow", since, hours}      water running right now
##   pests   household id -> {level 0..1, day, free_until}                    roaches in the house (level grows while it is messy)
##   jobs    [{hid, kind "plumber"|"exterminator"|"handy", due}]               tradespeople on their way
##   stats   counters for the long-run tests and the F9 panel
##   gas     household id -> {obj, since, alarm, out {folk id: true}, called}   a gas leak that has not been stopped yet (task 07b)
##   unhappy folk id -> days in a row a teen has been miserable (feeds the runaway teen)
##   theft   household id -> {taken, since, reported, fix_day}                  identity theft that has not been sorted out
##   neglect child id -> days in a row a child's needs were unmet with no adult acting (feeds child services)
##   gone    folk id -> {since, back}                                          teens who ran away and have not come home yet
## Numbers are data: config.chaos in data/incidents/07_chaos.json.

static var leaks: Dictionary = {}
static var pests: Dictionary = {}
static var jobs: Array = []
static var stats: Dictionary = {}
static var gas: Dictionary = {}
static var unhappy: Dictionary = {}
static var theft: Dictionary = {}
static var neglect: Dictionary = {}
static var gone: Dictionary = {}

static func reset() -> void:
	leaks.clear()
	pests.clear()
	jobs.clear()
	stats.clear()
	gas.clear()
	unhappy.clear()
	theft.clear()
	neglect.clear()
	gone.clear()
	Health.register_neglect_hook(Callable(ChaosNeglect, "on_neglect"))      # survives Health.reset; registering twice is ignored

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
	return {"leaks": leaks.duplicate(true), "pests": pests.duplicate(true), "jobs": jobs.duplicate(true), "stats": stats.duplicate(true),
		"gas": SysUtil.str_keys(gas).duplicate(true), "unhappy": SysUtil.str_keys(unhappy), "theft": SysUtil.str_keys(theft).duplicate(true),
		"neglect": SysUtil.str_keys(neglect), "gone": SysUtil.str_keys(gone).duplicate(true)}

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
	for k3 in (d.get("gas", {}) as Dictionary):
		var g: Dictionary = (d["gas"][k3] as Dictionary).duplicate(true)
		SysUtil.ints_in(g, ["obj", "since"])
		g["out"] = SysUtil.int_keys(g.get("out", {}) as Dictionary)
		gas[int(k3)] = g
	for k4 in (d.get("unhappy", {}) as Dictionary):
		unhappy[int(k4)] = int(d["unhappy"][k4])
	for k5 in (d.get("theft", {}) as Dictionary):
		var th: Dictionary = (d["theft"][k5] as Dictionary).duplicate(true)
		SysUtil.ints_in(th, ["taken", "since", "fix_day", "victim"])
		theft[int(k5)] = th
	for k6 in (d.get("neglect", {}) as Dictionary):
		neglect[int(k6)] = int(d["neglect"][k6])
	for k7 in (d.get("gone", {}) as Dictionary):
		var gn: Dictionary = (d["gone"][k7] as Dictionary).duplicate(true)
		SysUtil.ints_in(gn, ["since", "back"])
		gone[int(k7)] = gn
