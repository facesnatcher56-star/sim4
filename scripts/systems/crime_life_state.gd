class_name CrimeLifeState
extends RefCounted
## Task 21: all state of the criminal life and the security systems in one place (data/crimelife.json, table "crimelife"). Saved INSIDE the
## justice block (systems.justice.life), so no new top-level save key is needed. Own seeded rng (saved) so the underworld story is reproducible
## and does not disturb the justice dice. Players and townies are one thing here: a MEMBER record per person id.
##   members  pid -> {cred, rank, jobs, heists, fenced, since, snitch, heat, caught, straight_until, notoriety, hist{job:n}, skills{sk:n}, townie}
##   contacts owner pid -> [{pid, trust, day, role}]   people the owner can call on (met in bars, in a cell, through a record)
##   cased    "owner|target" -> {amount, day, routes}   how well a target is known (0..1)
##   gear     pid -> {gear id: true};  stash pid -> [{id, name, value, case, day, car}] stolen goods not yet sold
##   heists   id -> heist plan (CrimeLifeHeist);  pending [{kind, due_min, ...}] job resolutions waiting for their time
##   footage  lot key -> [{day, minute, case, clarity, gap}];  ledger culprit -> [{victim, day, kind, loss, case}]  (the moral memory)
##   home_sec household -> {monitored, guard};  biz_sec business id -> {upgrade: level};  alarms household -> {strikes, ignore_until}
##   guards   pid -> {post, shift, fatigue, asleep_until}

const INT_KEYED := ["members", "contacts", "gear", "stash", "heists", "ledger", "home_sec", "biz_sec", "alarms", "guards", "talk", "straight", "notoriety_kept", "offered"]

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var members: Dictionary = {}
static var contacts: Dictionary = {}
static var cased: Dictionary = {}
static var gear: Dictionary = {}
static var stash: Dictionary = {}
static var heists: Dictionary = {}
static var next_heist: int = 1
static var pending: Array = []
static var footage: Dictionary = {}
static var ledger: Dictionary = {}
static var home_sec: Dictionary = {}
static var biz_sec: Dictionary = {}
static var alarms: Dictionary = {}
static var guards: Dictionary = {}
static var straight: Dictionary = {}           # pid -> day until which they are going straight
static var notoriety_kept: Dictionary = {}     # pid -> notoriety earned before they left the path (the legacy keeps it)
static var offered: Dictionary = {}            # pid -> day of the last "shady offer" prompt
static var talk: Dictionary = {}               # pid -> day of the last "ask around" (one a day)
static var counters: Dictionary = {}

static func cfg() -> Dictionary:
	return SysUtil.table("crimelife")

static func sect(name: String) -> Dictionary:
	return cfg().get(name, {})

static func reset() -> void:
	members.clear()
	contacts.clear()
	cased.clear()
	gear.clear()
	stash.clear()
	heists.clear()
	next_heist = 1
	pending.clear()
	footage.clear()
	ledger.clear()
	home_sec.clear()
	biz_sec.clear()
	alarms.clear()
	guards.clear()
	talk.clear()
	straight.clear()
	offered.clear()
	notoriety_kept.clear()
	counters.clear()
	seed_rng(int(sect("general").get("seed", 21021)))

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

static func chance(p: float) -> bool:
	return rng.randf() < p

static func range_i(r: Array) -> int:
	return rng.randi_range(int(r[0]), int(r[1]))

static func pick_index(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return -1
	var roll: float = rng.randf() * total
	for i in weights.size():
		roll -= maxf(float(weights[i]), 0.0)
		if roll <= 0.0:
			return i
	return weights.size() - 1

static func count(kind: String, n: int = 1) -> void:
	counters[kind] = int(counters.get(kind, 0)) + n

static func counter(kind: String) -> int:
	return int(counters.get(kind, 0))

static func queue(ev: Dictionary) -> void:
	pending.append(ev)

# ------------------------------------------------------------------ save
static func _table(k: String) -> Dictionary:
	match k:
		"members": return members
		"contacts": return contacts
		"gear": return gear
		"stash": return stash
		"heists": return heists
		"ledger": return ledger
		"home_sec": return home_sec
		"biz_sec": return biz_sec
		"alarms": return alarms
		"guards": return guards
	if k == "straight":
		return straight
	if k == "offered":
		return offered
	if k == "notoriety_kept":
		return notoriety_kept
	return talk

static func to_dict() -> Dictionary:
	var out: Dictionary = {"rng_seed": rng.seed, "rng_state": str(rng.state), "cased": cased.duplicate(true), "next_heist": next_heist, "pending": pending.duplicate(true),
		"footage": footage.duplicate(true), "counters": counters.duplicate(true), "mem_n": members.size()}
	for k in INT_KEYED:
		out[k] = SysUtil.str_keys(_table(k)).duplicate(true)
	return out

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	rng.seed = int(d.get("rng_seed", rng.seed))
	rng.state = int(str(d.get("rng_state", rng.state)))
	cased = (d.get("cased", {}) as Dictionary).duplicate(true)
	next_heist = int(d.get("next_heist", 1))
	pending = (d.get("pending", []) as Array).duplicate(true)
	for p in pending:
		SysUtil.ints_in(p, ["due_min", "pid", "target_id", "heist"])
	footage = (d.get("footage", {}) as Dictionary).duplicate(true)
	counters = (d.get("counters", {}) as Dictionary).duplicate(true)
	for k in INT_KEYED:
		var dst: Dictionary = _table(k)
		dst.clear()
		dst.merge(SysUtil.int_keys((d.get(k, {}) as Dictionary).duplicate(true)))
	for pid in members:
		SysUtil.ints_in(members[pid], ["jobs", "heists", "fenced", "since", "caught", "straight_until"])
	for hid in heists:
		SysUtil.ints_in(heists[hid], ["id", "leader", "day"])
