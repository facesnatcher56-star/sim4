class_name Away
extends RefCounted
## "Rabbit-hole" service: a folk leaves the lot for a while (work, school, party...). Implemented as a long,
## non-autonomous `sys_away` interaction so SimDirector keeps ticking needs while they are gone. While away the
## folk carries the `away` buff and meta flag "away" (UI should hide the model: `folk.has_meta("away")`).
## Returning (or being pulled away early) is reported to the caller through `on_finished`.

const IID := "sys_away"
const PENDING_TIMEOUT_MIN := 120

static var pending: Dictionary = {}   # folk_id -> {reason, minutes, data, queued_min}
static var active: Dictionary = {}    # folk_id -> {reason, minutes, data, start_min, until_min}

static func reset() -> void:
	pending.clear()
	active.clear()

static func is_away(folk_id: int) -> bool:
	return active.has(folk_id)

static func info(folk_id: int) -> Dictionary:
	return active.get(folk_id, {})

## Queue the away interaction. Returns false if the folk is invalid/already away/pending.
static func send(f, minutes: float, reason: String, data: Dictionary = {}) -> bool:
	if f == null or active.has(f.id) or pending.has(f.id) or minutes <= 1.0:
		return false
	var ir := Interaction.create(IID, f, -1, false)
	if ir == null:
		return false
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = minutes
	ir.def["label"] = str(data.get("label", "Away (%s)" % reason))
	pending[f.id] = {"reason": reason, "minutes": minutes, "data": data, "queued_min": SysUtil.now()}
	f.enqueue(ir)
	return true

## A VISIBLE shift (task 11): the folk stays on the map doing the job (no sys_away interaction, no hiding, no "away" meta).
## Same record shape as a hidden one so pay / performance work the same; VisibleWork ends it with end_visible().
static func begin_visible(f, minutes: float, reason: String, data: Dictionary, start_min: int = -1) -> bool:
	if f == null or active.has(f.id) or pending.has(f.id) or minutes <= 1.0:
		return false
	var d: Dictionary = data.duplicate(true)
	d["visible"] = true
	active[f.id] = {"reason": reason, "minutes": minutes, "data": d, "start_min": SysUtil.now() if start_min < 0 else start_min,
		"until_min": SysUtil.now() + int(minutes)}
	SysUtil.game_event("left_lot", {"folk_id": f.id, "reason": reason})
	return true

static func is_visible(folk_id: int) -> bool:
	return bool((active.get(folk_id, {}).get("data", {}) as Dictionary).get("visible", false))

## Ends a visible shift: returns the record (like on_finished) or {}.
static func end_visible(folk_id: int, success: bool) -> Dictionary:
	if not is_visible(folk_id):
		return {}
	var rec: Dictionary = active[folk_id]
	active.erase(folk_id)
	rec["completed"] = success
	rec["worked_min"] = SysUtil.now() - int(rec["start_min"])
	SysUtil.game_event("returned_to_lot", {"folk_id": folk_id, "reason": rec["reason"], "completed": success})
	return rec

## interaction_started hook. Returns the info dict when this was a systems away interaction.
static func on_started(folk_id: int, iid: String) -> Dictionary:
	if iid != IID:
		return {}
	var f = SysUtil.folk(folk_id)
	var p: Dictionary = pending.get(folk_id, {"reason": "away", "minutes": 60.0, "data": {}, "queued_min": SysUtil.now()})
	pending.erase(folk_id)
	var rec: Dictionary = {"reason": p["reason"], "minutes": float(p["minutes"]), "data": p["data"],
		"start_min": int(p.get("restored_start", SysUtil.now())), "until_min": SysUtil.now() + int(float(p["minutes"]))}
	active[folk_id] = rec
	if f != null:
		f.set_meta("away", str(rec["reason"]))
		f.add_buff("away")
	SysUtil.game_event("left_lot", {"folk_id": folk_id, "reason": rec["reason"]})
	return rec

## interaction_finished hook. Returns {} for unrelated interactions, else the info dict plus "completed".
static func on_finished(folk_id: int, iid: String, success: bool) -> Dictionary:
	if iid != IID:
		return {}
	var rec: Dictionary = active.get(folk_id, {})
	active.erase(folk_id)
	pending.erase(folk_id)
	var f = SysUtil.folk(folk_id)
	if f != null:
		if f.has_meta("away"):
			f.remove_meta("away")
		f.remove_buff("away")
	if rec.is_empty():
		return {}
	rec["completed"] = success
	rec["worked_min"] = SysUtil.now() - int(rec["start_min"])
	SysUtil.game_event("returned_to_lot", {"folk_id": folk_id, "reason": rec["reason"], "completed": success})
	return rec

## Drop stale queued requests (the folk never got to start them).
## Places that look after the people they hold (34 logic: a cell or a ward serves meals and has a toilet and a wash): at each meal time
## hunger is brought up to `hunger_to` (never down), and the toilet and wash keep bladder and hygiene from hitting the floor.
## The slow per-minute drift of sys_away (content_sys.json) still applies in between. Trips, work and school are not looked after.
const CARE_REASONS := ["custody", "jail", "prison", "court", "hospital"]
const CARE_MEALS_MIN := [480, 780, 1140]        # 08:00, 13:00, 19:00
const CARE_FLOOR := {"hunger": 40.0, "bladder": 20.0, "hygiene": 0.0}

static func _care() -> void:
	if not (SysUtil.now() % 1440 in CARE_MEALS_MIN):
		return
	for fid in active:
		if not str((active[fid] as Dictionary).get("reason", "")) in CARE_REASONS:
			continue
		var f = SysUtil.folk(int(fid))
		if f == null:
			continue
		for nid in CARE_FLOOR:
			var v: float = float(f.get_stat_value(nid))
			if v < float(CARE_FLOOR[nid]):
				f.add_to_stat(nid, float(CARE_FLOOR[nid]) - v)

static func on_minute() -> void:
	_care()
	PlaceHold.on_minute()
	var stale: Array = []
	for fid in pending:
		if SysUtil.now() - int(pending[fid]["queued_min"]) > PENDING_TIMEOUT_MIN:
			stale.append(fid)
	for fid in stale:
		var f = SysUtil.folk(int(fid))
		if f != null:
			for q in f.queue.duplicate():
				if (q as Interaction).def_id == IID:
					f.queue.erase(q)
		pending.erase(fid)

## Pull a folk back early (counts as an unfinished, cancelled interaction).
static func recall(folk_id: int, reason: String = "recalled") -> bool:
	var f = SysUtil.folk(folk_id)
	if f == null or not active.has(folk_id):
		return false
	if is_visible(folk_id):
		if PlaceHold.holding(folk_id):
			PlaceHold.end(f)
			return true
		Commute.finish_visible(f, false)
		return true
	if f.current != null and f.current.def_id == IID:
		f.current.cancel(reason)
		return true
	return false

static func to_dict() -> Dictionary:
	var a: Dictionary = {}
	for k in active:
		a[str(k)] = (active[k] as Dictionary).duplicate(true)
	return {"active": a}

## Restore after a load: folk that were away are re-sent for the remaining time.
static func from_dict(d: Dictionary) -> void:
	reset()
	var a: Dictionary = d.get("active", {})
	for k in a:
		var rec: Dictionary = a[k]
		var f = SysUtil.folk(int(str(k)))
		if f == null:
			continue
		if bool((rec.get("data", {}) as Dictionary).get("visible", false)):      # a visible shift just continues on the map
			var vr: Dictionary = (rec as Dictionary).duplicate(true)
			vr["start_min"] = int(vr.get("start_min", 0))
			vr["until_min"] = int(vr.get("until_min", 0))
			active[f.id] = vr
			continue
		var left: float = float(int(rec.get("until_min", 0)) - SysUtil.now())
		if left < 2.0:
			left = 2.0
		f.remove_buff("away")
		if send(f, left, str(rec.get("reason", "away")), (rec.get("data", {}) as Dictionary)):
			pending[f.id]["restored_start"] = int(rec.get("start_min", SysUtil.now()))
			# look away right now; the interaction itself resumes on the next director tick
			var restored: Dictionary = (rec as Dictionary).duplicate(true)
			for key in ["minutes", "start_min", "until_min"]:
				restored[key] = float(restored.get(key, 0.0)) if key == "minutes" else int(restored.get(key, 0))
			active[f.id] = restored
			f.set_meta("away", str(rec.get("reason", "away")))
			f.add_buff("away")
