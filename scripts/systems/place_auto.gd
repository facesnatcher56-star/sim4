class_name PlaceAuto
extends RefCounted
## Residents use the places by themselves (task 14b): "the world runs with or without the player". A resident nobody plays (and the player's own folk
## while they are on autonomy) plans a few outings a day, weighted by traits, needs, money, time of day and relationships (PlaceAutoPlan, PlaceAutoGate,
## data/life/95_auto.json), walks there and uses the service with the SAME calls the Town window makes (LifeCommand: go, use, phone_invite, phone_respond,
## college_apply, home), then goes home (PlaceAutoTrip). Illness and the pets are checked every hour (PlaceAutoNow), townies far away are one dice a day
## (PlaceAutoTownies). Someone the player is steering (a player order in the queue) is never pulled away.
## State: plans of today, trips in progress, when each kind was last done, a tally of uses per household and place. Own seeded rng. Saved in the `life`
## block (`auto`). Tier: residents ACTIVE, one dice per kind per person per day (a handful of kinds pass), nothing per minute unless a trip is on.

const SEED := 140141

static var plans: Array = []              # [{fid, kind, at, expires, ctx}]: outings decided but not started
static var trips: Dictionary = {}         # fid -> {kind, place, state, t0, ctx, services}: outings in progress
static var last: Dictionary = {}          # "fid|kind" -> day it last happened
static var claims: Dictionary = {}        # "hid|claim" -> day one member of the household took the job (the vet trip, the wedding)
static var tally: Dictionary = {}         # "hid|place" -> uses by the household (auto trips and home care)
static var stats: Dictionary = {}         # counters: planned, started, done, dropped, kinds {kind: n}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var off: bool = false              # tests switch the whole thing off to compare (not saved)

static func reset() -> void:
	plans.clear()
	trips.clear()
	last.clear()
	claims.clear()
	tally.clear()
	stats = {"planned": 0, "started": 0, "done": 0, "dropped": 0, "kinds": {}, "drops": {}, "who": {}}
	rng = RandomNumberGenerator.new()
	rng.seed = SEED
	off = false
	PlaceAutoPlan.reset()

static func cfg() -> Dictionary:
	return LifeDefs.cfg("auto")

static func on() -> bool:
	return not off and bool(cfg().get("enabled", true))

static func kinds() -> Dictionary:
	return cfg().get("kinds", {})

## Scheduler gate for the minute row: only while there is something to start or to follow.
static func busy() -> bool:
	return not plans.is_empty() or not trips.is_empty()

static func count(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1

## A named counter inside stats[sub] (kinds started, drop reasons).
static func tick(sub: String, name: String) -> void:
	var m: Dictionary = stats[sub]
	m[name] = int(m.get(name, 0)) + 1

# ------------------------------------------------------------------ clock entries
static func on_day(day: int) -> void:
	if not on():
		return
	plans = plans.filter(func(p): return int(p["expires"]) > SysUtil.now())
	var ids: Array = []
	for f in SysUtil.residents():
		ids.append(int(f.id))
	ids.sort()
	for fid in ids:
		var f2 = SysUtil.folk(fid)
		if f2 != null and not Pawn.is_pawn(f2):          # the pawn goes out only when the player sends them
			PlaceAutoPlan.make(f2, day)
	PlaceAutoTownies.on_day(day)

static func on_hour(hour: int) -> void:
	if not on():
		return
	PlaceAutoNow.on_hour(hour)

static func on_minute() -> void:
	if on():
		PlaceAutoTrip.on_minute()

## How many times this household used this place by itself or on a trip (for the tests and the Town window).
static func used(hid: int, place: String) -> int:
	return int(tally.get("%d|%s" % [hid, place], 0))

static func kinds_used(hid: int) -> Array:
	var out: Array = []
	var pre := "%d|" % hid
	for k in tally:
		if str(k).begins_with(pre):
			out.append(str(k).substr(pre.length()))
	out.sort()
	return out

static func note_use(fid: int, place: String) -> void:
	var f = SysUtil.folk(fid)
	if f == null:
		return
	var k := "%d|%s" % [int(f.household_id), place]
	tally[k] = int(tally.get(k, 0)) + 1

static func was_done(fid: int, kind: String) -> int:
	return int(last.get("%d|%s" % [fid, kind], -999))

static func mark(fid: int, kind: String) -> void:
	last["%d|%s" % [fid, kind]] = SysUtil.day()

## The household has nobody a player controls (no toasts for what they do; the chronicle still hears it).
static func quiet_for(f) -> bool:
	return f != null and Players.player_of(int(f.household_id)) < 0 and not Players.table.is_empty()

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"plans": plans.duplicate(true), "trips": SysUtil.str_keys(trips).duplicate(true), "last": last.duplicate(), "claims": claims.duplicate(), "tally": tally.duplicate(),
		"stats": stats.duplicate(true), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	plans = (d.get("plans", []) as Array).duplicate(true)
	for p in plans:
		for k in ["fid", "at", "expires"]:
			p[k] = int(p[k])
	trips = SysUtil.int_keys((d.get("trips", {}) as Dictionary).duplicate(true))
	for fid in trips:
		for k2 in ["t0", "wait_until"]:
			trips[fid][k2] = int(trips[fid].get(k2, 0))
	for k3 in (d.get("last", {}) as Dictionary):
		last[str(k3)] = int(d["last"][k3])
	for k7 in (d.get("claims", {}) as Dictionary):
		claims[str(k7)] = int(d["claims"][k7])
	for k4 in (d.get("tally", {}) as Dictionary):
		tally[str(k4)] = int(d["tally"][k4])
	var s: Dictionary = d.get("stats", {})
	if not s.is_empty():
		for k5 in ["planned", "started", "done", "dropped"]:
			stats[k5] = int(s.get(k5, 0))
		for sub in ["kinds", "drops", "who"]:
			stats[sub] = {}
			for k6 in (s.get(sub, {}) as Dictionary):
				stats[sub][str(k6)] = int(s[sub][k6])
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
