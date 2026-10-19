class_name CrimeUnderState
extends RefCounted
## Task 23: all state of the underworld lines, gangs and the good side in one place (data/crimeunder.json, table "crimeunder"). Saved INSIDE the
## criminal-life block (systems.justice.life.under) so no new top-level save key is needed. Own seeded rng (saved).
## Tier behaviour: nothing here runs per minute. Daily passes loop SMALL tracked sets only (open contracts, addicts, dealers, gangs, rackets,
## cops with a bribe), never the world; far townies play the same dice statistically (CrimeUnder*.person_day / on_day). Timed player work
## (research, a sale, a rehab stay) reuses CrimeLifeState.pending and Away.
##   lines    pid -> {line: {standing, since, acts}}     hit / deal / racket standing (rank derived from data)
##   contracts id -> {id, client, target, fee, posted, deadline, cond{quiet,alone}, state, hitman, research, mistakes, seen, case, outsider}
##   addicts  pid -> {sub, level, frail, since, last_dose, rehab_until, clean_days, relapses, debt, dealer}
##   dealers  pid -> {stock{sub:n}, corner, customers[pid], tips, sales, stung, stash_hidden, last_sale_day}
##   corners  id -> {owner, hold, day}
##   gangs    id -> {id, name, boss, members[{pid, standing, loyal, rank}], territory[], war{with, until, since}, strength, day}
##   rackets  id -> {id, kind, owner, target, principal, owed, due, state, missed, ...}
##   cops     pid -> {taken, corruption, protecting[], ia{since, state}, suspended_until, refused}
##   rep      pid -> {hero, honour, guilt, deeds}
##   redeem   pid -> {start, progress, mentor, resisted, falls}
##   undercover pid -> {gang, trust, evidence, day}   informant pid -> {gang, day, exposed}   protected pid -> day until
##   taint    pid -> dirty-money score;  front pid -> business id used to launder;  laundered pid -> {week, amount}

const INT_KEYED := ["lines", "contracts", "addicts", "dealers", "gangs", "rackets", "cops", "rep", "redeem", "undercover", "informant", "protected", "taint", "front", "laundered", "offered_gang", "dens"]

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var lines: Dictionary = {}
static var contracts: Dictionary = {}
static var next_contract: int = 1
static var addicts: Dictionary = {}
static var dealers: Dictionary = {}
static var corners: Dictionary = {}
static var gangs: Dictionary = {}
static var next_gang: int = 1
static var rackets: Dictionary = {}
static var next_racket: int = 1
static var cops: Dictionary = {}
static var rep: Dictionary = {}
static var redeem: Dictionary = {}
static var undercover: Dictionary = {}
static var informant: Dictionary = {}
static var protected: Dictionary = {}
static var taint: Dictionary = {}
static var front: Dictionary = {}
static var laundered: Dictionary = {}
static var offered_gang: Dictionary = {}
static var dens: Dictionary = {}
static var last_bust_day: int = -999
static var counters: Dictionary = {}

static func cfg() -> Dictionary:
	return SysUtil.table("crimeunder")

static func sect(name: String) -> Dictionary:
	return cfg().get(name, {})

static func reset() -> void:
	for k in INT_KEYED:
		_table(k).clear()
	corners.clear()
	next_contract = 1
	next_gang = 1
	next_racket = 1
	last_bust_day = -999
	counters.clear()
	seed_rng(int(sect("general").get("seed", 23023)))

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

static func chance(p: float) -> bool:
	return rng.randf() < p

static func range_i(r: Array) -> int:
	return rng.randi_range(int(r[0]), int(r[1]))

static func range_f(r: Array) -> float:
	return rng.randf_range(float(r[0]), float(r[1]))

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

static func _table(k: String) -> Dictionary:
	match k:
		"lines": return lines
		"contracts": return contracts
		"addicts": return addicts
		"dealers": return dealers
		"gangs": return gangs
		"rackets": return rackets
		"cops": return cops
		"rep": return rep
		"redeem": return redeem
		"undercover": return undercover
		"informant": return informant
		"protected": return protected
		"taint": return taint
		"front": return front
		"laundered": return laundered
		"dens": return dens
	return offered_gang

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	var out: Dictionary = {"rng_seed": rng.seed, "rng_state": str(rng.state), "next_contract": next_contract, "next_gang": next_gang, "next_racket": next_racket,
		"corners": corners.duplicate(true), "counters": counters.duplicate(true), "last_bust_day": last_bust_day}
	for k in INT_KEYED:
		out[k] = SysUtil.str_keys(_table(k)).duplicate(true)
	return out

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	rng.seed = int(d.get("rng_seed", rng.seed))
	rng.state = int(str(d.get("rng_state", rng.state)))
	next_contract = int(d.get("next_contract", 1))
	next_gang = int(d.get("next_gang", 1))
	next_racket = int(d.get("next_racket", 1))
	last_bust_day = int(d.get("last_bust_day", -999))
	corners = (d.get("corners", {}) as Dictionary).duplicate(true)
	for cid in corners:
		corners[cid]["owner"] = int(corners[cid].get("owner", -1))
	counters = (d.get("counters", {}) as Dictionary).duplicate(true)
	for k in INT_KEYED:
		var dst: Dictionary = _table(k)
		dst.clear()
		dst.merge(SysUtil.int_keys((d.get(k, {}) as Dictionary).duplicate(true)))
	_fix_ints()

## JSON turns every number into a float: put the ids back.
static func _fix_ints() -> void:
	for id in contracts:
		SysUtil.ints_in(contracts[id], ["id", "client", "target", "posted", "deadline", "hitman", "case", "mistakes", "due_day"])
	for pid in dealers:
		dealers[pid]["customers"] = SysUtil.to_ints(dealers[pid].get("customers", []))
		SysUtil.ints_in(dealers[pid], ["tips", "sales", "stung", "last_sale_day"])
	for pid in addicts:
		SysUtil.ints_in(addicts[pid], ["since", "last_dose", "rehab_until", "clean_days", "relapses", "dealer"])
	for gid in gangs:
		var g: Dictionary = gangs[gid]
		SysUtil.ints_in(g, ["id", "boss", "day"])
		for m in g.get("members", []):
			SysUtil.ints_in(m, ["pid"])
		if (g.get("war", {}) as Dictionary).size() > 0:
			SysUtil.ints_in(g["war"], ["with", "until", "since"])
	for rid in rackets:
		SysUtil.ints_in(rackets[rid], ["id", "owner", "target", "principal", "owed", "due", "missed", "biz", "visits"])
	for pid in cops:
		cops[pid]["protecting"] = SysUtil.to_ints(cops[pid].get("protecting", []))
		SysUtil.ints_in(cops[pid], ["taken", "suspended_until", "refused"])
	for pid in redeem:
		SysUtil.ints_in(redeem[pid], ["start", "mentor", "resisted", "falls", "last_tempt"])
	for pid in undercover:
		SysUtil.ints_in(undercover[pid], ["gang", "day"])
	for pid in informant:
		SysUtil.ints_in(informant[pid], ["gang", "day"])
	for pid in protected:
		protected[pid] = int(protected[pid])
	for pid in front:
		front[pid] = int(front[pid])
	for pid in dens:
		SysUtil.ints_in(dens[pid], ["n"])
	for pid in offered_gang:
		offered_gang[pid] = int(offered_gang[pid])
