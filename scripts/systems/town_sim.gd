class_name TownSim
extends RefCounted
## The cheap TOWN / STATISTICAL tiers of townies who are not in the world (task 17.3, stages 2 and 3).
## Tier behaviour: TOWN = schedule + needs curves refreshed once per hour by a BUCKETED job (a townie is visited at minute id % 60, so 200 townies cost
## 3 or 4 per minute; nothing per minute otherwise). STATISTICAL = nothing hourly at all (their needs/place are computed from the same closed forms only when
## somebody asks, e.g. a promotion); the daily dice of Story / Away / Incidents / CrimeFlow cover both. Active set: the TierSets below, rebuilt by the
## hourly job itself. Caps: one small "town" dictionary per townie record (needs, place, act, minute).
## `where(t, minute)` is a pure function of the townie record and the clock (no randomness, no state): sleep (Circadian ranges by life stage and a per-id
## hash) / shift (CommuteTownies windows) / school / an evening outing to an open venue chosen by a per-(id, day) hash / home. Needs are closed-form curves of the
## time of day (meal sawtooth, hours awake, ...) so a promotion rebuilds the same numbers the hourly job would have stored. PROMOTION (`apply_to_folk`):
## position stays where the crowd spawner puts the person (gate / lot spawn tiles = the start of the route), needs from the curve blended with the stored
## ones; DEMOTION (`on_demoted`) writes needs / place / minute back into the record. Saved with the townie record (Story.to_dict): nothing else to save.

const HOME_ACT := "home"
const SLEEP := "sleep"
const WORK := "work"
const SCHOOL := "school"
const LEISURE := "leisure"
const NO_VENUE := ["home", "townie_home", "hospital", "police", "courthouse", "school", "office"]

static var _sets := TierSets.new()
static var _job: SimJob = null
static var _tracked_n: int = -1
static var _homes: Array = []
static var _homes_n: int = -1
static var _venues: Array = []
static var _venues_n: int = -1
static var hourly_calls: int = 0

static func reset() -> void:
	_sets.clear()
	_tracked_n = -1
	_homes_n = -1
	_venues_n = -1
	hourly_calls = 0
	if _job != null:
		for s in _job.slots:
			(s as Array).clear()
		_job.count = 0

static func cfg() -> Dictionary:
	return (Tiers.cfg().get("town", {}) as Dictionary)

# ------------------------------------------------------------------ scheduler
static func install(sched: SimScheduler, group: String) -> void:
	_job = sched.add_bucketed("TownSim.hourly", "TownSim", group, 60, 95, SimScheduler.LOW, TownSim.hourly,
		"TOWN: schedule + needs curves once per hour, bucketed by id; STATISTICAL: skipped (daily dice only)")
	sched.add("TownSim.sync", "TownSim", group, 1, 96, SimScheduler.NORMAL, TownSim.sync, "", Callable(TownSim, "needs_sync"),
		"keeps the bucketed job's tracked ids equal to the living townies (one size test per minute)")
	_tracked_n = -1

static func needs_sync() -> bool:
	return _job != null and _tracked_n != Story.townies.size() + Story.next_id * 100000

static func sync() -> void:
	if _job == null:
		return
	for tid in Story.townies:
		if bool(Story.townies[tid].get("alive", true)):
			_job.track(int(tid))
		else:
			_job.untrack(int(tid))
			_sets.drop(int(tid))
	_tracked_n = Story.townies.size() + Story.next_id * 100000

# ------------------------------------------------------------------ tier sets of the records
static func tier_of(id: int) -> int:
	return int(_sets.tier_of.get(id, Tiers.STATISTICAL))

static func ids(tier: int) -> Array:
	return (_sets.sets[tier] as Dictionary).keys()

static func count(tier: int) -> int:
	return _sets.count(tier)

# ------------------------------------------------------------------ schedule
static func _frac(id: int, salt: int) -> float:
	return float(absi(((id + 1) * 73856093) ^ ((salt + 1) * 19349663)) % 1000) / 1000.0

static func homes() -> Array:
	var n: int = Neighborhood.lots().size()
	if n != _homes_n:
		_homes_n = n
		_homes = []
		for l in Neighborhood.lots():
			if str(l.get("type", "")) == "townie_home":
				_homes.append(str(l["id"]))
	return _homes

static func home_lot(t: Dictionary) -> String:
	var hs: Array = homes()
	return "" if hs.is_empty() else str(hs[(int(t.get("lot", 1)) - 1) % hs.size()])

static func venues() -> Array:
	var n: int = Neighborhood.lots().size()
	if n != _venues_n:
		_venues_n = n
		_venues = []
		for l in Neighborhood.lots():
			if not NO_VENUE.has(str(l.get("type", ""))):
				_venues.append(str(l["id"]))
	return _venues

## [bed, wake] hours of the townie (Circadian ranges by life stage, a per-id position inside them).
static func sleep_window(t: Dictionary) -> Array:
	var c: Dictionary = Circadian.cfg()
	var stages: Dictionary = c.get("stages", {})
	var st: Dictionary = stages.get(Story.stage_of(t), stages.get("adult", {}))
	if st.is_empty():
		return [22.5, 7.0]
	var id: int = int(t["id"])
	var bed_r: Array = st.get("bed", [22.0, 23.5])
	var len_r: Array = st.get("sleep_h", [7.0, 8.5])
	var bed: float = lerpf(float(bed_r[0]), float(bed_r[1]), _frac(id, 1))
	var wake: float = bed + lerpf(float(len_r[0]), float(len_r[1]), _frac(id, 2))
	return [fposmod(bed, 24.0), fposmod(wake, 24.0)]

static func _in_window(h: float, lo: float, hi: float) -> bool:
	if lo < hi:
		return h >= lo and h < hi
	return h >= lo or h < hi

## {"lot": lot id ("" = unknown / street), "act": sleep | work | school | leisure | home} of a townie at an absolute game minute.
static func where(t: Dictionary, minute: int) -> Dictionary:
	var id: int = int(t["id"])
	var h: float = float(minute % 1440) / 60.0
	var home: String = home_lot(t)
	if CommuteTownies.on_shift(t, minute):
		return {"lot": Workplace.lot_for_townie(t), "act": WORK}
	var sw: Array = sleep_window(t)
	if _in_window(h, float(sw[0]), float(sw[1])):
		return {"lot": home, "act": SLEEP}
	var stage: String = Story.stage_of(t)
	var sc: Dictionary = Careers.cfg().get("school", {})
	var day: int = minute / 1440 + 1
	if stage in (sc.get("stages", ["child", "teen"]) as Array) and SysUtil.has_int(sc.get("days", [0, 1, 2, 3, 4]), SysUtil.weekday(day)) \
			and h >= float(sc.get("start", 9.0)) and h < float(sc.get("end", 15.0)):
		var sl: String = "school" if not Neighborhood.lot("school").is_empty() else home
		return {"lot": sl, "act": SCHOOL}
	var c: Dictionary = cfg()
	var vs: Array = venues()
	if not vs.is_empty() and stage not in ["baby", "toddler"] and _frac(id, day * 7 + 3) < float(c.get("leisure_chance", 0.35)):
		var from_h: float = float(c.get("leisure_from", 17.0)) + _frac(id, day * 7 + 4) * 2.0
		var to_h: float = from_h + 1.5 + _frac(id, day * 7 + 5) * 1.5
		if h >= from_h and h < minf(to_h, float(c.get("leisure_to", 21.5))):
			var lot: String = str(vs[int(_frac(id, day * 7 + 6) * 1000.0) % vs.size()])
			if Venues.is_open(lot, minute):
				return {"lot": lot, "act": LEISURE}
	return {"lot": home, "act": HOME_ACT}

static func lot_at(t: Dictionary, minute: int) -> String:
	return str(where(t, minute)["lot"])

# ------------------------------------------------------------------ needs as curves
## Needs of a townie at an absolute minute as closed forms of the clock (hours since a meal, hours awake, ...); same ranges as the needs table.
static func needs_at(t: Dictionary, minute: int) -> Dictionary:
	var id: int = int(t["id"])
	var h: float = float(minute % 1440) / 60.0
	var sw: Array = sleep_window(t)
	var asleep: bool = _in_window(h, float(sw[0]), float(sw[1]))
	var since_wake: float = fposmod(h - float(sw[1]), 24.0)
	var since_meal: float = 24.0
	for m in [7.5, 12.5, 19.0]:
		since_meal = minf(since_meal, fposmod(h - (float(m) + _frac(id, 11) * 0.8), 24.0))
	var noise: float = float(cfg().get("need_noise", 6.0))
	var raw: Dictionary = {
		"hunger": 62.0 - 9.0 * since_meal,
		"energy": (22.0 + 6.0 * fposmod(h - float(sw[0]), 24.0)) if asleep else (78.0 - 5.0 * since_wake),
		"bladder": 66.0 - 15.0 * fposmod(h + _frac(id, 12) * 4.0, 4.0),
		"hygiene": 72.0 - 2.4 * since_wake,
		"social": 38.0 + 22.0 * sin(TAU * (h - 14.0) / 24.0),
		"fun": 40.0 + 15.0 * sin(TAU * (h - 16.0) / 24.0),
		"comfort": 52.0}
	var out: Dictionary = {}
	var defs: Dictionary = SimEnv.data().needs()
	var k := 0
	for n in defs:
		k += 1
		var d: Dictionary = defs[n]
		var v: float = float(raw.get(str(n), 45.0)) + (_frac(id, 20 + k) - 0.5) * 2.0 * noise
		out[str(n)] = clampf(v, float(d.get("min", -100)), float(d.get("max", 100)))
	return out

# ------------------------------------------------------------------ hourly job (TOWN tier)
static func hourly(id: int, _elapsed: int = 60) -> void:
	hourly_calls += 1
	var t: Dictionary = Story.townies.get(id, {})
	if t.is_empty() or not bool(t.get("alive", true)):
		if _job != null:
			_job.untrack(id)
		_sets.drop(id)
		return
	if WorldIface.get_folk(id) != null:
		_sets.drop(id)
		return                      # in the world: Tiers owns this person now
	var now: int = SimEnv.now_min()
	var w: Dictionary = where(t, now)
	var tier: int = _tier_for(id, str(w["lot"]))
	_sets.put(id, tier, null)
	if tier == Tiers.TOWN:
		var rec: Dictionary = t.get("town", {})
		rec["place"] = w["lot"]
		rec["act"] = w["act"]
		rec["min"] = now
		rec["needs"] = needs_at(t, now)
		t["town"] = rec

## TOWN when the townie knows a controlled folk or is (by schedule) within town_radius of an anchor, else STATISTICAL.
static func _tier_for(id: int, lot: String) -> int:
	if Tiers.anchors.is_empty():
		return Tiers.STATISTICAL
	for cid in Tiers.controlled_ids:
		if RelationshipService.knows(int(cid), id):
			return Tiers.TOWN
	if lot == "":
		return Tiers.STATISTICAL
	var rc := NeighborhoodLots.rect_of(lot)
	var radius: int = int(Tiers.cfg().get("town_radius", 96))
	for a in Tiers.anchors:
		if InterestArea.rect_dist(a["tile"], rc) <= radius:
			return Tiers.TOWN
	return Tiers.STATISTICAL

# ------------------------------------------------------------------ promotion / demotion
## Needs of a townie being brought into the world: the curve now, blended with what the record stored when they left the world / were last updated.
static func needs_for_promotion(t: Dictionary, now: int) -> Dictionary:
	var cur: Dictionary = needs_at(t, now)
	var rec: Dictionary = t.get("town", {})
	var stored: Dictionary = rec.get("needs", {})
	if stored.is_empty():
		return cur
	var relax: float = float(cfg().get("relax_hours", 6.0)) * 60.0
	var w: float = clampf(float(now - int(rec.get("min", now))) / maxf(relax, 1.0), 0.0, 1.0)
	if w >= 1.0:
		return cur
	var then: Dictionary = needs_at(t, int(rec.get("min", now)))
	var out: Dictionary = {}
	for n in cur:
		var drift: float = float(stored.get(n, cur[n])) + (float(cur[n]) - float(then.get(n, cur[n])))
		out[n] = lerpf(drift, float(cur[n]), w)
	return out

## PROMOTION: give a freshly created Folk the plausible state of the townie record (needs from the curves; clamped to the needs table).
static func apply_to_folk(f, t: Dictionary, now: int) -> void:
	var ns: Dictionary = needs_for_promotion(t, now)
	for n in f.needs:
		if ns.has(n):
			(f.needs[n] as Stat).set_value(float(ns[n]))
	var rec: Dictionary = t.get("town", {})
	rec["promoted"] = now
	t["town"] = rec
	_sets.drop(int(t["id"]))

## DEMOTION: the Folk leaves the world; keep what matters in the record.
static func on_demoted(f) -> void:
	var t: Dictionary = Story.townies.get(int(f.id), {})
	if t.is_empty():
		return
	var now: int = SimEnv.now_min()
	var rec: Dictionary = t.get("town", {})
	var ns: Dictionary = {}
	for n in f.needs:
		ns[n] = snappedf((f.needs[n] as Stat).value, 0.1)
	rec["needs"] = ns
	rec["place"] = NeighborhoodLots.lot_at(f.tile)
	rec["act"] = "left"
	rec["min"] = now
	t["town"] = rec
