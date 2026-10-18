class_name Commute
extends RefCounted
## Real commutes (task 11): a household folk with a shift (or school) leaves home early enough, WALKS the road graph to the
## workplace door (a `go_here` tagged params.commute), goes in (staff and students are exempt from fees / opening hours) and only
## then goes "away" INSIDE that building (Away rabbit hole, or VisibleWork for a few careers). When the shift ends the folk walks home.
## Without a map (stub test worlds, no workplace lot) CareerShifts keeps the old instant rabbit hole.
##
##   Commute.begin(f, kind, ctx)       CareerShifts calls it at leave time; false = no commute possible (use the old path)
##   Commute.on_minute()               arrival / lateness / missed shift / walk home, once per game minute
##   Commute.on_shift_end(f, rec)      the shift (Away record) ended -> walk home
##   Commute.on_shift(fid) / active(fid) / exempt(f, lot)
## trips[fid] = {kind work|school, lot, state out|in|home, due_min, end_min, left_min, arrive_min, career, title, shift, level, shift_end}
## Events: left_for_work / left_for_school (leaving home), arrived_at_work / arrived_at_school, late_for_work / late_for_school,
## missed_shift (any no-show), returned_home. Toasts only for late / missed.

static var trips: Dictionary = {}
static var lates: Dictionary = {}       # fid -> {count (in a row), day}

static func reset() -> void:
	trips.clear()
	lates.clear()

static func on_shift(fid: int) -> bool:
	return str((trips.get(fid, {}) as Dictionary).get("state", "")) == "in"

static func active(fid: int) -> bool:
	return str((trips.get(fid, {}) as Dictionary).get("state", "")) in ["out", "in"]

## Staff / students go through their own workplace without fees or opening hours.
static func exempt(f, lot_id: String) -> bool:
	return f != null and trips.has(int(f.id)) and str(trips[int(f.id)]["lot"]) == lot_id

# ------------------------------------------------------------------ leaving
## Planned lead time in hours before the shift start at which the folk has to set off (route + weather + injury + buffer).
static func lead_hours(f) -> float:
	var lot: String = Workplace.lot_of_folk(f)
	if lot == "":
		return 0.0
	var m: float = Workplace.commute_minutes(f, NeighborhoodLots.entry_tile(lot))
	return 0.0 if m < 0.0 else (m + Workplace.num("buffer_min", 10.0)) / 60.0

static func begin(f, kind: String, ctx: Dictionary) -> bool:
	var lot: String = Workplace.lot_of_folk(f)
	if lot == "":
		return false
	var dest: Vector2i = NeighborhoodLots.entry_tile(lot)
	var plan: float = Workplace.commute_minutes(f, dest)
	if plan < 0.0 or dest.x < 0:
		return false
	var fid: int = int(f.id)
	var now: int = SysUtil.now()
	var t: Dictionary = {"kind": kind, "lot": lot, "state": "out", "due_min": int(ctx["due_min"]), "end_min": int(ctx["end_min"]), "left_min": now,
		"arrive_min": -1, "career": str(ctx.get("career", "")), "title": str(ctx.get("title", "")), "shift": str(ctx.get("shift", "day")),
		"level": int(ctx.get("level", 1)), "shift_end": float(ctx.get("shift_end", 0.0))}
	trips[fid] = t
	f.set_meta(NeighborhoodLots.IN_LOT, NeighborhoodLots.lot_at(f.tile))
	_walk(f, dest)
	var where: String = "work" if kind == "work" else "school"
	SysUtil.game_event("left_for_" + where, {"folk_id": fid, "career": t["career"], "title": t["title"], "shift_end": t["shift_end"], "lot": lot, "plan_min": plan})
	if now + plan + Workplace.traffic_delay(f, dest) > int(t["due_min"]) + Workplace.num("grace_min", 5.0):
		SysUtil.notify("%s is running late for %s." % [f.name, where], "warn")
	return true

## A high-priority walk (it preempts the sofa, not the player's commands), not part of the lot travel bookkeeping.
static func _walk(f, dest: Vector2i) -> bool:
	var ir := Interaction.create_goto(f, dest, false)
	if ir == null:
		return false
	ir.def = ir.def.duplicate(true)
	ir.def["priority"] = "high"
	ir.params["commute"] = true
	ir.params["delay_min"] = Workplace.traffic_delay(f, dest)
	f.enqueue(ir)
	return true

static func walking(f) -> bool:
	if f.current != null and f.current.def_id == "go_here" and f.current.params.has("commute"):
		return true
	for q in f.queue:
		if (q as Interaction).def_id == "go_here" and (q as Interaction).params.has("commute"):
			return true
	return false

static func _stop_walk(f) -> void:
	if f.current != null and f.current.def_id == "go_here" and f.current.params.has("commute"):
		f.current.cancel("arrived")
	for q in f.queue.duplicate():
		if (q as Interaction).def_id == "go_here" and (q as Interaction).params.has("commute"):
			f.queue.erase(q)

# ------------------------------------------------------------------ per minute
static func on_minute() -> void:
	if trips.is_empty():
		return
	var now: int = SysUtil.now()
	for fid in trips.keys():
		var f = SysUtil.folk(int(fid))
		if f == null:
			trips.erase(fid)
			continue
		var t: Dictionary = trips[fid]
		match str(t["state"]):
			"out":
				_step_out(f, t, now)
			"in":
				if Away.is_visible(int(fid)):
					VisibleWork.step(f, t, now)
				elif not Away.active.has(int(fid)) and not Away.pending.has(int(fid)):
					_start_home(f, t)                 # the record is gone (recalled / lost on load): just go home
			"home":
				_step_home(f, t, now)

static func _step_out(f, t: Dictionary, now: int) -> void:
	var dest: Vector2i = NeighborhoodLots.entry_tile(str(t["lot"]))
	var at_door: bool = f.tile == dest or (maxi(absi(f.tile.x - dest.x), absi(f.tile.y - dest.y)) <= 1 and not walking(f))
	if at_door:
		_arrive(f, t, now)
		return
	if CareerShifts.player_busy(f):
		miss(f, t, "chose to skip %s on the way" % ("work" if str(t["kind"]) == "work" else "school"))
		return
	if now > int(t["due_min"]) + int(Workplace.num("miss_after_min", 90.0)) or now >= int(t["end_min"]) - 20:
		miss(f, t, "never made it to %s" % ("work" if str(t["kind"]) == "work" else "school"))
		return
	if not walking(f):
		_walk(f, dest)                                # the walk was lost (interrupted, loaded): high priority, so it preempts the errand

static func _arrive(f, t: Dictionary, now: int) -> void:
	_stop_walk(f)
	var fid: int = int(f.id)
	var lot: String = str(t["lot"])
	var work: bool = str(t["kind"]) == "work"
	var left_min: int = int(t["end_min"]) - now
	if left_min <= 5:
		miss(f, t, "arrived after the shift was over")
		return
	var late: int = maxi(0, now - int(t["due_min"]))
	var inside: bool = work and Workplace.visible_job(str(t["career"])) != ""
	var spot: Vector2i = VisibleWork.post_tile(f, lot, str(t["career"])) if inside else Workplace.desk_tile(lot, f)
	f.tile = spot
	if "level" in f:
		f.level = 0                       # multi-floor hook: Workplace.entry_tile(career).level will put office jobs on their floor
	NeighborhoodLots.mark_inside(f, lot)
	Neighborhood.refresh_view(fid)
	t["state"] = "in"
	t["arrive_min"] = now
	var data: Dictionary = {"commute": true, "lot": lot, "kind": str(t["kind"])}
	if work:
		data.merge({"shift": t["shift"], "career": t["career"], "level": t["level"], "title": t["title"], "label": "At work: " + str(t["title"]), "shift_end": t["shift_end"]})
	else:
		data["label"] = "At school"
	var start_min: int = maxi(now, int(t["due_min"]))
	var ok: bool = false
	if inside:
		f.idle_until_min = now + 5          # no autonomy errands between arriving and the first job
		ok = Away.begin_visible(f, float(left_min), "work", data, start_min)
	else:
		ok = Away.send(f, float(left_min), str(t["kind"]), data)
		if ok:
			(Away.pending[fid] as Dictionary)["restored_start"] = start_min
	if not ok:
		_start_home(f, t)
		return
	SysUtil.game_event("arrived_at_" + ("work" if work else "school"), {"folk_id": fid, "career": t["career"], "lot": lot, "late_min": late})
	_late(f, t, late)
	Workplace.greet_coworkers(f, lot)

# ------------------------------------------------------------------ lateness / missing
static func _late(f, t: Dictionary, late: int) -> void:
	var fid: int = int(f.id)
	var work: bool = str(t["kind"]) == "work"
	if late <= int(Workplace.num("grace_min", 5.0)):
		lates.erase(fid)
		return
	var lc: Dictionary = cfg_late()
	var pen: float = minf(float(lc.get("perf_max", 10)), ceil(float(late) / 10.0) * float(lc.get("perf_per_10_min", 1.5)))
	var rec: Dictionary = lates.get(fid, {"count": 0, "day": SysUtil.day()})
	rec["count"] = int(rec["count"]) + 1
	rec["day"] = SysUtil.day()
	lates[fid] = rec
	if work:
		CareerProgress.add_performance(fid, -pen, true)
		SysUtil.notify("%s was %d min late for work (-%d performance)." % [f.name, late, int(round(pen))], "warn")
	else:
		var st: Dictionary = Careers.school.get(fid, {})
		if not st.is_empty():
			st["grade"] = clampf(float(st["grade"]) - float(lc.get("grade_loss", 1.5)), 0.0, 100.0)
		SysUtil.notify("%s was %d min late for school." % [f.name, late], "warn")
	SysUtil.game_event("late_for_" + ("work" if work else "school"), {"folk_id": fid, "minutes": late, "penalty": pen, "streak": int(rec["count"])})
	if late >= int(lc.get("chronicle_min", 45)) or int(rec["count"]) == 3:
		var again: String = " again" if int(rec["count"]) >= 3 else ""
		ChronicleHook.note("late_for_work", "%s was late for %s%s." % [f.name, "work" if work else "school", again], [fid], "home:%d" % int(f.household_id), 1, false)

static func cfg_late() -> Dictionary:
	return Workplace.cfg().get("late", {})

## The folk did not make it (chose to skip, got stuck, came after the shift): penalty, events, walk home.
static func miss(f, t: Dictionary, why: String) -> void:
	_stop_walk(f)
	CareerShifts.missed(f, str(t["kind"]), why)
	_start_home(f, t)

# ------------------------------------------------------------------ coming home
## The shift (hidden Away or visible) ended.
static func on_shift_end(f, rec: Dictionary) -> void:
	var fid: int = int(f.id)
	if not bool((rec.get("data", {}) as Dictionary).get("commute", false)) or not trips.has(fid):
		return
	_start_home(f, trips[fid])

static func finish_visible(f, success: bool) -> void:
	var rec: Dictionary = Away.end_visible(int(f.id), success)
	if rec.is_empty():
		return
	for q in f.queue.duplicate():
		if (q as Interaction).params.has("visible_job"):
			f.queue.erase(q)
	if f.current != null and f.current.params.has("visible_job"):
		f.current.cancel("shift_over")
	CareerShifts.on_returned(f, rec)

static func _start_home(f, t: Dictionary) -> void:
	t["state"] = "home"
	t["left_min"] = SysUtil.now()
	var home: Vector2i = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	if NeighborhoodLots.lot_at(f.tile) == Neighborhood.HOME or home.x < 0:
		_home(f, t)
	else:
		_walk(f, home)

static func _step_home(f, t: Dictionary, now: int) -> void:
	if Away.active.has(int(f.id)) or Away.pending.has(int(f.id)):
		return
	var home: Vector2i = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	if NeighborhoodLots.lot_at(f.tile) == Neighborhood.HOME or f.tile == home:
		_home(f, t)
	elif now - int(t["left_min"]) > int(Workplace.num("home_timeout_min", 240.0)):
		trips.erase(int(f.id))                         # gave up (autonomy / stranded_home takes over)
	elif not walking(f) and (f.current == null or f.current.effective_priority() < 2) and f.queue.is_empty():
		_walk(f, home)

static func _home(f, t: Dictionary) -> void:
	_stop_walk(f)
	trips.erase(int(f.id))
	SysUtil.game_event("returned_home", {"folk_id": int(f.id), "reason": str(t["kind"])})

# ------------------------------------------------------------------ save / load
static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for k in trips:
		out[str(k)] = (trips[k] as Dictionary).duplicate(true)
	var l: Dictionary = {}
	for k2 in lates:
		l[str(k2)] = (lates[k2] as Dictionary).duplicate(true)
	return {"trips": out, "lates": l}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in d.get("trips", {}):
		var t: Dictionary = (d["trips"][k] as Dictionary).duplicate(true)
		for key in ["due_min", "end_min", "left_min", "arrive_min", "level"]:
			t[key] = int(t.get(key, 0))
		t["shift_end"] = float(t.get("shift_end", 0.0))
		trips[int(str(k))] = t
	for k2 in d.get("lates", {}):
		var r: Dictionary = d["lates"][k2]
		lates[int(str(k2))] = {"count": int(r.get("count", 0)), "day": int(r.get("day", 0))}
