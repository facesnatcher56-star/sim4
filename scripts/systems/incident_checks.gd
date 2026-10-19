class_name IncidentChecks
extends RefCounted
## The hourly / daily dice. For every incident of the given `check` frequency, every candidate subject whose conditions hold gets one
## roll with chance = 1 - exp(-effective_rate / checks_per_year). Candidates per scope (all deterministic: sorted by id):
##   folk   - every Folk on the map (household + visitors) -> FULL; every far townie record -> STATISTICAL
##   townie - far townies (STATISTICAL) and visitor Folk (FULL)
##   lot    - each household (FULL) and each townie lot (STATISTICAL)
##   town   - ONE roll for the town (conditions / non per_lot risks on the weather and season); a hit then rolls EVERY lot separately:
##            chance min(1, lot_hit x per_lot risk factor), outcome chosen per lot with that lot's own conditions.
## Subjects in hospital are skipped. Exposure (subject-years that passed the conditions) is counted for the statistical tests.

## The candidate lists are built ONCE per run (not once per incident def) and rebuilt only after a hit changed the world (task 17.3). Same lists, same
## order, same dice => the same outcomes as building them per def.
static var _cache: Dictionary = {}
static var _stale := true

static func _list(kind: String) -> Array:
	if _stale:
		_cache.clear()
		IncidentSubject.clear_cache()
		_stale = false
	if not _cache.has(kind):
		var tl := PerfProf.start()
		match kind:
			"folk":
				_cache[kind] = folk_subjects(true)
			"townie":
				_cache[kind] = townie_subjects()
			_:
				_cache[kind] = lot_subjects()
		PerfProf.stop("incidents/build " + kind, tl)
	return _cache[kind]

## Slice mode (IncidentSlices): the caches live for one slice.
static func begin_slice() -> void:
	IncidentSubject.refresh_on_map()          # who stands on the map changes between slices; owners / members only change on a hit (_dirty) or a new pass
	IncidentSubject.caching = true

static func end_slice() -> void:
	IncidentSubject.caching = false

static func _dirty() -> void:
	_stale = true
	IncidentSubject.clear_cache()

static func run(check: String) -> void:
	IncidentDefs.ensure()
	_stale = true
	IncidentSubject.caching = true
	_run_defs(check)
	IncidentSubject.caching = false
	IncidentSubject.clear_cache()

static func _run_defs(check: String) -> void:
	for id in IncidentDefs.ids():
		var def: Dictionary = IncidentDefs.defs[id]
		if str(def["check"]) != check:
			continue
		var tdef := PerfProf.start()
		match str(def["scope"]):
			"folk":
				for s in _list("folk"):
					_roll(id, def, s)
			"townie":
				for s2 in _list("townie"):
					_roll(id, def, s2)
			"lot":
				for s3 in _list("lot"):
					_roll(id, def, s3)
			"town":
				_town(id, def)
		PerfProf.stop("incidents/scope " + str(def["scope"]), tdef)
		PerfProf.stop("incdef/" + str(id), tdef)

static func _roll(id: String, def: Dictionary, s) -> void:
	if not IncidentCond.check(def.get("conditions", []), s):
		return
	var check: String = str(def["check"])
	var c: Dictionary = Incidents._counter(id)
	c["checks"] = int(c["checks"]) + 1
	c["exposure"] = float(c["exposure"]) + 1.0 / IncidentRisk.checks_per_year(check)
	var p: float = IncidentRisk.rate_to_chance(IncidentRisk.effective_rate(def, s, true, true) * StoryPacing.incident_mult(id, s), check)
	if p > 0.0 and Incidents.rng.randf() < p:
		_dirty()
		IncidentFlow.start(id, s)
		_dirty()

static func _town(id: String, def: Dictionary) -> void:
	var dummy = IncidentSubject.of_town_lot(0)
	if not IncidentCond.check(def.get("conditions", []), dummy):
		return
	var check: String = str(def["check"])
	var c: Dictionary = Incidents._counter(id)
	c["checks"] = int(c["checks"]) + 1
	c["exposure"] = float(c["exposure"]) + 1.0 / IncidentRisk.checks_per_year(check)
	var p: float = IncidentRisk.rate_to_chance(IncidentRisk.effective_rate(def, dummy), check)
	if p <= 0.0 or Incidents.rng.randf() >= p:
		return
	_dirty()
	for ls in lot_subjects():
		var hit: float = minf(float(def.get("lot_hit", 1.0)) * IncidentRisk.risk_factor(def, ls, "lot"), 1.0)
		if hit > 0.0 and Incidents.rng.randf() < hit:
			IncidentFlow.resolve(id, ls, not ls.is_full(), false)
			_dirty()

# ------------------------------------------------------------------ candidates
static func folk_subjects(with_townies: bool) -> Array:
	var out: Array = []
	var folk: Array = WorldIface.all_folk().duplicate()
	folk.sort_custom(func(a, b): return a.id < b.id)
	for f in folk:
		if not Hospital.is_in(f):
			out.append(IncidentSubject.of_folk(f))
	if with_townies:
		out.append_array(townie_subjects(true))
	return out

## Far townies (statistical). With `only_far` false the visitor Folk are included as FULL subjects.
static func townie_subjects(only_far: bool = false) -> Array:
	var out: Array = []
	var ids: Array = Story.townies.keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = Story.townies[tid]
		if not bool(t["alive"]) or bool(t.get("in_hospital", false)) or IncidentSubject.on_map(int(tid)):
			continue
		out.append(IncidentSubject.of_townie(int(tid)))
	if not only_far:
		var folk: Array = WorldIface.all_folk().duplicate()
		folk.sort_custom(func(a, b): return a.id < b.id)
		for f in folk:
			if f.has_meta("townie_id") and not Hospital.is_in(f):
				out.append(IncidentSubject.of_folk(f))
	return out

static func lot_subjects() -> Array:
	var out: Array = []
	for hid in Economy.household_ids():
		out.append(IncidentSubject.of_household(int(hid)))
	var lots: Array = []
	for tid in Story.townies:
		var t: Dictionary = Story.townies[tid]
		var n: int = int(t.get("lot", 0))
		if bool(t["alive"]) and n > 0 and not lots.has(n):
			lots.append(n)
	lots.sort()
	for n2 in lots:
		var s = IncidentSubject.of_town_lot(int(n2))
		if not s.members().is_empty():
			out.append(s)
	return out