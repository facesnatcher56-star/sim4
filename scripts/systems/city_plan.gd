class_name CityPlan
extends RefCounted
## Town planning and growth (task 12.6). Zoning says how new land is used: residential, commercial or civic (the mayor shifts it). When the town is nearly full
## (townies vs the population cap), the planners start a project in a zone chosen by the zoning shares, if the town can pay: first scaffolding goes up, then
## workers build for days, then it opens. What a finished project does: flats raise the population cap (so more people can move in: StoryGrowth), shops raise the
## town's revenue, a community centre adds to the parks and schools budgets.
##   CityPlan.extra_capacity() -> extra people the town can hold     CityPlan.revenue_bonus()     CityPlan.funding_bonus(dept)
## The map itself does not grow yet: the finished project is a record (and a chronicle line), not a building on a new block (every slot of the street grid is taken).
## Tier behaviour: world-level list of at most `max_projects` projects; workers are a number. Cadence: daily.

static var projects: Array = []          # {id, zone, kind, state: planned|scaffold|building, start, scaffold_end, ready, workers}
static var built: Dictionary = {}        # kind -> number finished
static var zoning: Dictionary = {}       # kind -> share
static var seq: int = 1
static var last_check: int = 0

static func reset() -> void:
	projects = []
	built = {}
	zoning = (cfg().get("zoning", {}) as Dictionary).duplicate()
	seq = 1
	last_check = 0

static func cfg() -> Dictionary:
	return CityState.cfg().get("plan", {})

static func kind_def(kind: String) -> Dictionary:
	return (cfg().get("kinds", {}) as Dictionary).get(kind, {})

# ------------------------------------------------------------------ what it does
static func extra_capacity() -> int:
	return int(built.get("residential", 0)) * int(kind_def("residential").get("capacity", 4))

static func revenue_bonus() -> float:
	return float(built.get("commercial", 0)) * float(kind_def("commercial").get("revenue", 18.0))

static func funding_bonus(dept: String) -> float:
	return float(built.get("civic", 0)) * float((kind_def("civic").get("funding_bonus", {}) as Dictionary).get(dept, 0.0))

static func shift_zoning(kind: String) -> void:
	if not zoning.has(kind):
		return
	var step: float = float(cfg().get("zoning_step", 0.1))
	var lo: float = float(cfg().get("zoning_min", 0.05))
	var others: Array = zoning.keys().filter(func(k): return k != kind)
	var take: float = 0.0
	for k in others:
		var give: float = maxf(minf(step / float(others.size()), float(zoning[k]) - lo), 0.0)
		zoning[k] = float(zoning[k]) - give
		take += give
	zoning[kind] = float(zoning[kind]) + take

static func pick_kind() -> String:
	var keys: Array = zoning.keys()
	keys.sort()
	var total: float = 0.0
	for k in keys:
		total += float(zoning[k])
	var r: float = CityState.rng.randf() * total
	for k2 in keys:
		r -= float(zoning[k2])
		if r <= 0.0:
			return str(k2)
	return str(keys[keys.size() - 1])

# ------------------------------------------------------------------ the days
static func population_fill() -> float:
	var cap: int = int(Story.cfg().get("max_population", 24)) + extra_capacity()
	return float(StoryGrowth.population()) / float(maxi(cap, 1))

static func on_day(day: int) -> void:
	if zoning.is_empty():
		zoning = (cfg().get("zoning", {}) as Dictionary).duplicate()
	_progress(day)
	if day - last_check >= int(cfg().get("check_days", 7)):
		last_check = day
		_consider(day)

static func _consider(_day: int) -> void:
	if projects.size() >= int(cfg().get("max_projects", 2)) or population_fill() < float(cfg().get("fill_trigger", 0.9)):
		return
	var kind: String = pick_kind()
	var d: Dictionary = kind_def(kind)
	if d.is_empty():
		return
	if CityGov.treasury < float(d.get("cost", 400)):
		if CityState.zone_of_household(Players.primary_household()) != "" and CityState.chance(0.2):
			CityGov.note("plan", str(cfg().get("texts", {}).get("waiting", "")).replace("{what}", str(d.get("label", kind))))
		return
	CityGov.treasury -= float(d.get("cost", 400))
	CityGov.recompute()
	var zones: Array = CityState.zone_ids()
	var zone: String = str(zones[CityState.rng.randi_range(0, zones.size() - 1)])
	var now: int = SysUtil.day()
	var sc: int = CityState.range_i(d.get("scaffold_days", [2, 4]))
	var bd: int = CityState.range_i(d.get("build_days", [8, 14]))
	var p: Dictionary = {"id": seq, "zone": zone, "kind": kind, "state": "scaffold", "start": now, "scaffold_end": now + sc, "ready": now + sc + bd, "workers": 0}
	seq += 1
	projects.append(p)
	var t: String = str(cfg().get("texts", {}).get("scaffold", "")).replace("{zone}", CityState.zone_label(zone)).replace("{what}", str(d.get("label", kind)))
	CityGov.note("plan", t)
	if CityState.zone_of_household(Players.primary_household()) == zone:
		SysUtil.notify(t, "info")
	SysUtil.game_event("project_started", {"zone": zone, "kind": kind, "folk_id": -1})

static func _progress(day: int) -> void:
	for p in projects.duplicate():
		var d: Dictionary = kind_def(str(p["kind"]))
		if str(p["state"]) == "scaffold" and day >= int(p["scaffold_end"]):
			p["state"] = "building"
			var w: Array = d.get("workers", [4, 8])
			p["workers"] = CityState.range_i(w)
		if str(p["state"]) == "building" and day >= int(p["ready"]):
			projects.erase(p)
			built[str(p["kind"])] = int(built.get(str(p["kind"]), 0)) + 1
			var t: String = str(cfg().get("texts", {}).get("done", "")).replace("{zone}", CityState.zone_label(str(p["zone"]))).replace("{what}", str(d.get("label", p["kind"])))
			t = t.substr(0, 1).to_upper() + t.substr(1)
			CityGov.note("plan", t)
			ChronicleHook.note("town", t, [], "", 2, true)
			if CityState.zone_of_household(Players.primary_household()) == str(p["zone"]):
				SysUtil.notify(t, "good")
			CityGov.recompute()
			SysUtil.game_event("project_done", {"zone": str(p["zone"]), "kind": str(p["kind"]), "folk_id": -1})

## For the planners' readout and the tests: "scaffolding", "workers are building" ...
static func describe(p: Dictionary) -> String:
	var d: Dictionary = kind_def(str(p["kind"]))
	var what: String = str(d.get("label", p["kind"]))
	if str(p["state"]) == "scaffold":
		return "Scaffolding is up for %s on %s." % [what, CityState.zone_label(str(p["zone"]))]
	return "%d workers are building %s on %s. Ready around day %d." % [int(p["workers"]), what, CityState.zone_label(str(p["zone"])), int(p["ready"])]

static func to_dict() -> Dictionary:
	return {"projects": projects.duplicate(true), "built": built.duplicate(), "zoning": zoning.duplicate(), "seq": seq, "last": last_check}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	projects = (d.get("projects", []) as Array).duplicate(true)
	for p in projects:
		SysUtil.ints_in(p, ["id", "start", "scaffold_end", "ready", "workers"])
	built = {}
	for k in (d.get("built", {}) as Dictionary):
		built[str(k)] = int(d["built"][k])
	zoning = (d.get("zoning", zoning) as Dictionary).duplicate()
	seq = int(d.get("seq", 1))
	last_check = int(d.get("last", 0))
