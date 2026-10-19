class_name PlaceMember
extends RefCounted
## Passes and memberships of places (task 14): a gym pass, a cinema card, a pool season ticket. A pass service (`pass: {days}`) is bought once and
## makes every service of that place that lists `pass_discount` cheaper (0.0 = free .. 1.0 = no discount) until it runs out.
## Tier: event driven + one daily expiry sweep over a handful of entries. Saved in the `life` block.

static var passes: Dictionary = {}       # folk id -> {place id: last valid day}

static func reset() -> void:
	passes.clear()

static func has_pass(fid: int, pid: String) -> bool:
	return int((passes.get(fid, {}) as Dictionary).get(pid, -1)) >= SysUtil.day()

static func days_left(fid: int, pid: String) -> int:
	return maxi(int((passes.get(fid, {}) as Dictionary).get(pid, -1)) - SysUtil.day() + 1, 0)

static func grant(fid: int, pid: String, days: int) -> void:
	if not passes.has(fid):
		passes[fid] = {}
	var cur: int = maxi(int(passes[fid].get(pid, -1)), SysUtil.day() - 1)
	passes[fid][pid] = cur + days

## Does any pass this person holds belong to a place inside this lot (the gym pass waives the gym's entry fee)?
static func covers_lot(fid: int, lot_id: String) -> bool:
	for pid in (passes.get(fid, {}) as Dictionary):
		if Places.lot_of(str(pid)) == lot_id and has_pass(fid, str(pid)):
			return true
	return false

## Price factor of a service for this person at this place.
static func discount(fid: int, pid: String, svc: Dictionary) -> float:
	if fid >= 0 and svc.has("pass_discount") and has_pass(fid, pid):
		return clampf(float(svc["pass_discount"]), 0.0, 1.0)
	return 1.0

static func on_day(day: int) -> void:
	for fid in passes.keys():
		for pid in (passes[fid] as Dictionary).keys():
			if int(passes[fid][pid]) < day - 2:
				passes[fid].erase(pid)
		if (passes[fid] as Dictionary).is_empty():
			passes.erase(fid)

static func to_dict() -> Dictionary:
	return {"passes": SysUtil.str_keys(passes).duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	passes = SysUtil.int_keys((d.get("passes", {}) as Dictionary).duplicate(true))
	for fid in passes:
		for pid in passes[fid]:
			passes[fid][pid] = int(passes[fid][pid])
