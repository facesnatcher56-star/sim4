class_name CommuteTownies
extends RefCounted
## Townies commute too (task 11). A townie with a career is "at work" at the career's workplace lot for the hours of the shift on
## work days (a small per-townie offset spreads the arrivals). Statistically that is all there is - `lot_now(tid)` answers where a
## far townie is - and when a resident is near the lot (Crowd wakes it) the townies on shift are shown: they appear at the lot's
## street gate shortly before the shift, walk in, stay (as the coworker crowd, needs held up) and walk out when the shift ends.
## Called from Crowd._update_lot / Crowd._pick_townie. NPCs carry the meta `coworker`.

static func _def(t: Dictionary) -> Dictionary:
	var cid: String = str(t.get("career", ""))
	if cid == "":
		return {}
	return Careers.level_def(cid, int(t.get("level", 1)), str(t.get("branch", "")))

## {start, end} absolute game minutes of today's shift of this townie (arrival offset included), or {} when not a work day.
static func window(t: Dictionary, now: int) -> Dictionary:
	var cid: String = str(t.get("career", ""))
	if cid == "" or Workplace.lot_for_townie(t) == "":
		return {}
	var day: int = now / 1440 + 1
	var ld: Dictionary = _def(t)
	var sh: float = float(ld.get("start", 9))
	var eh: float = float(ld.get("end", 17))
	if not CareerShifts.is_work_day(cid, day):
		return {}
	var tc: Dictionary = Workplace.cfg().get("townie", {})
	var off: int = (int(t["id"]) * 7) % maxi(int(tc.get("spread_min", 15)), 1)
	var s: int = (day - 1) * 1440 + int(sh * 60.0) - int(tc.get("arrive_early_min", 20)) + off
	var e: int = (day - 1) * 1440 + int(eh * 60.0) + (0 if eh > sh else 1440)
	return {"start": s, "end": e}

static func on_shift(t: Dictionary, now: int) -> bool:
	var w: Dictionary = window(t, now)
	return not w.is_empty() and now >= int(w["start"]) and now < int(w["end"])

## Where townie `tid` is for work purposes right now: the workplace lot id, "" when not on shift.
static func lot_now(tid: int, now: int = -1) -> String:
	var t: Dictionary = Story.townies.get(tid, {})
	if t.is_empty() or not bool(t.get("alive", true)):
		return ""
	var n: int = SysUtil.now() if now < 0 else now
	return Workplace.lot_for_townie(t) if on_shift(t, n) else ""

## True when the townie is at work at some other lot than `lot_id` (so it cannot be a customer there).
static func busy_elsewhere(t: Dictionary, lot_id: String, now: int) -> bool:
	var w: String = Workplace.lot_for_townie(t)
	return w != "" and w != lot_id and on_shift(t, now)

static func present(lot_id: String) -> Array:
	var out: Array = []
	for f in Crowd.crowd_folk(lot_id):
		if f.has_meta("coworker"):
			out.append(f)
	return out

## Bring the townies on shift at `lot_id` into view (at most a few per update, all at once when the lot wakes up).
static func update(lot_id: String, now: int, instant: bool) -> void:
	for f in present(lot_id):
		for n in f.needs:
			(f.needs[n] as Stat).set_value(40.0)
	var vtype: String = Venues.type_of_lot(lot_id)
	var made: int = 0
	for t in Story.free_townies():
		if Workplace.lot_for_townie(t) != lot_id or not on_shift(t, now):
			continue
		var tid: int = int(t["id"])
		var there = SysUtil.folk(tid)
		if there != null:
			if there.has_meta("crowd") and not there.has_meta("coworker"):
				Crowd.start_leaving(there)          # was out and about as a customer elsewhere: time to go to work
			continue
		if Story.stage_of(t) in ["baby", "toddler", "child"]:
			continue
		var f = Crowd.spawn_npc(t, lot_id, vtype, int(window(t, now)["end"]) - now, not instant)
		f.set_meta("coworker", true)
		for n2 in f.needs:
			(f.needs[n2] as Stat).set_value(40.0)
		made += 1
		if not instant and made >= 2:
			break
