class_name HealthLife
extends RefCounted
## Everyday health of a person (task 14), on top of the incident-based Health (illness, injury, collapse): four slow METERS and a record of
## long-term conditions, for residents AND townies (statistical: one daily line per person).
##   fitness 0..100   rises with exercise, gym classes and sport, falls a little every day
##   diet    0..100   rises with good meals, falls with snacks and fast food, drifts back to the middle
##   dental  0..100   falls every day (less with clean habits), brushing helps, the dentist restores it; below 35 it hurts (toothache)
##   strain  0..100   work stress: grows with every shift (more when tired), eases on days off and holidays; at 85 the person is burnt out
## Fitness, diet and teeth make the HEALTH SCORE: it scales the chance of colds, flu and heart trouble (HealthRisk) and moves the window of old-age
## death (age_shift, up to 14 game days either way, hooked into Aging._check_deaths and the townie death roll), so a fit person lives longer.
## Data: data/life/20_health.json (config.health_life, conditions, places). Tier: residents ACTIVE daily, townies STATISTICAL daily, no per-minute work.
## Saved in the `life` block (`health`). Own seeded rng.

const SEED := 140061

static var recs: Dictionary = {}          # person id -> record
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var counts: Dictionary = {}        # event counters for tests and the report: onsets, flares, burnouts ...

static func reset() -> void:
	recs.clear()
	counts.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

static func cfg() -> Dictionary:
	return LifeDefs.cfg("health_life")

static func count(key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1

## A stable per-person spread (no rng draw, so the order people are first looked at never matters).
static func _spread(id: int, salt: int, width: float) -> float:
	return (float(posmod(id * 7919 + salt * 104729, 1000)) / 999.0 - 0.5) * 2.0 * width

static func rec(id: int) -> Dictionary:
	if not recs.has(id):
		var st: Dictionary = cfg().get("start", {})
		recs[id] = {"fitness": clampf(float(st.get("fitness", 40)) + _spread(id, 1, 15.0), 5.0, 95.0), "diet": clampf(float(st.get("diet", 50)) + _spread(id, 2, 12.0), 5.0, 95.0),
			"dental": clampf(float(st.get("dental", 80)) + _spread(id, 3, 10.0), 10.0, 100.0), "strain": 0.0, "conds": {}, "checkup_day": -1, "shot_until": -1,
			"sessions": 0, "last_work_day": -1}
	return recs[id]

static func peek(id: int) -> Dictionary:
	return recs.get(id, {})

static func meter(id: int, name: String) -> float:
	return float(rec(id).get(name, 0.0))

static func add_meter(id: int, name: String, delta: float) -> void:
	var r: Dictionary = rec(id)
	if not r.has(name):
		return
	var d: float = delta
	if name == "fitness" and delta > 0.0 and EduState.stage_of(id) == "elder":
		d *= float(cfg().get("fitness", {}).get("elder_gain", 0.7))
	r[name] = clampf(float(r[name]) + d, 0.0, 100.0)

## 0..100 from fitness, diet and teeth.
static func score(id: int) -> float:
	var w: Dictionary = cfg().get("score", {})
	var r: Dictionary = rec(id)
	return clampf(float(r["fitness"]) * float(w.get("fitness", 0.45)) + float(r["diet"]) * float(w.get("diet", 0.45)) + float(r["dental"]) * float(w.get("dental", 0.1)), 0.0, 100.0)

## "In good shape" for a meter value (the first row of the label table whose limit the value reaches).
static func label(name: String, value: float) -> String:
	for row in (cfg().get("labels", {}) as Dictionary).get(name, []):
		if value >= float(row[0]):
			return str(row[1])
	return ""

## Game days the old-age window is moved by health: +14 for the best habits (they are "younger" and die later), -14 for the worst. Aging subtracts it from the age.
static func age_shift(id: int) -> float:
	if not recs.has(id):
		return 0.0
	return (score(id) - 50.0) / 50.0 * float(cfg().get("death", {}).get("shift_days", 14))

## Multiplier of the old-age death chance from long-term conditions (unmanaged 1.18 each, managed 1.04).
static func death_mult(id: int) -> float:
	if not recs.has(id):
		return 1.0
	var d: Dictionary = cfg().get("death", {})
	var m := 1.0
	for cid in (recs[id]["conds"] as Dictionary):
		m *= float(d.get("condition_managed", 1.04)) if HealthCond.managed(id, str(cid)) else float(d.get("condition_unmanaged", 1.18))
	return m

## A finished interaction changes a meter (data: interaction_effects).
static func on_interaction(id: int, iid: String) -> void:
	var fx: Dictionary = (cfg().get("interaction_effects", {}) as Dictionary).get(iid, {})
	for m in fx:
		add_meter(id, str(m), float(fx[m]))

static func forget(id: int) -> void:
	recs.erase(id)

static func to_dict() -> Dictionary:
	return {"recs": SysUtil.str_keys(recs).duplicate(true), "counts": counts.duplicate(), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	recs = SysUtil.int_keys((d.get("recs", {}) as Dictionary).duplicate(true))
	for id in recs:
		var r: Dictionary = recs[id]
		for k in ["checkup_day", "shot_until", "sessions", "last_work_day"]:
			r[k] = int(r.get(k, -1))
		var cs: Dictionary = {}
		for cid in (r.get("conds", {}) as Dictionary):
			var c: Dictionary = r["conds"][cid]
			cs[str(cid)] = {"since": int(c.get("since", 0)), "diag": bool(c.get("diag", false)), "doses": int(c.get("doses", 0)), "flares": int(c.get("flares", 0)), "told": bool(c.get("told", false))}
		r["conds"] = cs
	for k in (d.get("counts", {}) as Dictionary):
		counts[str(k)] = int(d["counts"][k])
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
