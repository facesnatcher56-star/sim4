class_name JobApps
extends RefCounted
## Task 61B: applying for a job takes time (data/job_apps.json). Apply sends an application (EduJobs.check: the same gates as before); the answer
## comes a day or two later by phone, or by letter the next morning without a working phone; asking again in person at the workplace gets it on
## the spot. Some ask for an interview at the workplace at a set time (CalendarBook): the pawn sets off on its own like a commute, and on arrival it
## is one SkillCheck (act "interview": charisma) plus the job's skill, hygiene, mood, the record and the others who applied. Small jobs asked about
## in person give a trial shift instead. An offer hires with a start day (Careers.jobs[fid].start_day, the job's next work day): "You start
## Monday, 9:00, at Moss & Mug Cafe." A no is one plain line, never a list or odds.
##   JobApps.send(fid, cid, in_person, who)   JobApps.pending(fid)   JobApps.ask_in_person(f, lot) -> bool   JobApps.on_minute()

static var apps: Array = []          # [{id, fid, cid, level, lot, state sent|interview|done, answer_min, applicants, letter, iv_min}]
static var _seq: int = 1

static func reset() -> void:
	apps = []
	_seq = 1

static func cfg() -> Dictionary:
	return SysUtil.table("job_apps")

static func busy() -> bool:
	return not apps.is_empty()

static func _line(k: String, vars: Dictionary) -> String:
	var lines: Array = (cfg().get("lines", {}) as Dictionary).get(k, [""])
	var t: String = str(lines[SysUtil.rng.randi_range(0, lines.size() - 1)])
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

static func place(cid: String) -> String:
	var lot: String = Workplace.lot_for(cid)
	return Neighborhood.label_of(lot) if lot != "" else str(Careers.career_def(cid).get("label", cid))

## "Monday, 9:00" (or "tomorrow, 9:00" / "today, 14:00").
static func when(day: int, hour: float) -> String:
	var d: String = "today" if day == SysUtil.day() else ("tomorrow" if day == SysUtil.day() + 1 else Seasons.weekday_long(day))
	return "%s, %d:%02d" % [d, int(hour), int(round(fmod(hour, 1.0) * 60.0))]

static func pending(fid: int) -> Array:
	return apps.filter(func(a): return int(a["fid"]) == fid and str(a["state"]) != "done")

static func _has(fid: int, cid: String) -> bool:
	return pending(fid).any(func(a): return str(a["cid"]) == cid)

# ------------------------------------------------------------------ sending
static func send(fid: int, cid: String, in_person: bool = false, who: String = "") -> Dictionary:
	var chk: Dictionary = EduJobs.check(fid, cid)
	if not bool(chk.get("ok", false)):
		return chk
	if _has(fid, cid):
		return {"ok": false, "reason": "You have already applied there."}
	var c: Dictionary = cfg()
	var lv: int = int(chk["level"])
	var nm: String = who if who != "" else "They"
	if in_person and (c.get("small_jobs", []) as Array).has(cid) and lv <= 1:
		var sd: Dictionary = _offer(fid, cid, lv)
		if sd.is_empty():
			return {"ok": false, "reason": "They could not take you on."}
		SysUtil.notify(_line("trial", {"who": nm, "when": when(int(sd["day"]), float(sd["hour"]))}), "career")
		return {"ok": true, "reason": ""}
	var ad: Array = c.get("answer_days", [1, 2])
	var ah: Array = c.get("answer_hours", [10, 17])
	var day: int = SysUtil.day() + SysUtil.rng.randi_range(int(ad[0]), int(ad[1]))
	var ap: Array = c.get("applicants", [0, 4])
	apps.append({"id": _seq, "fid": fid, "cid": cid, "level": lv, "lot": Workplace.lot_for(cid), "state": "sent",
		"answer_min": _abs(day, float(SysUtil.rng.randi_range(int(ah[0]), int(ah[1]) - 1)) + SysUtil.rng.randf()), "applicants": SysUtil.rng.randi_range(int(ap[0]), int(ap[1])),
		"iv_min": -1})
	_seq += 1
	if in_person:
		SysUtil.notify(_line("sent_in_person", {"who": nm}), "story")
	else:
		SysUtil.notify(_line("sent", {"place": place(cid)}), "career")
	return {"ok": true, "reason": ""}

static func _hm(m: int) -> String:
	return "%d:%02d" % [floori((m % 1440) / 60.0), m % 60]

static func _abs(day: int, hour: float) -> int:
	return (day - 1) * 1440 + int(round(hour * 60.0))

# ------------------------------------------------------------------ the clock
static func on_minute() -> void:
	var now: int = SysUtil.now()
	for a in apps.duplicate():
		match str(a["state"]):
			"sent":
				if now >= int(a["answer_min"]):
					_answer(a, false)
			"interview", "in_scene":
				_interview_tick(a, now)
	apps = apps.filter(func(a): return str(a["state"]) != "done")

## The answer reaches the pawn: by phone, else by letter at letter_hour (the next morning when that hour has passed); in_person = asked at the counter.
static func _answer(a: Dictionary, in_person: bool) -> void:
	var fid: int = int(a["fid"])
	var f = SysUtil.folk(fid)
	if f == null or Careers.why_not_work(f, str(a["cid"]), int(a["level"])) != "":
		a["state"] = "done"
		return
	var by_letter: bool = not in_person and PhoneOwn.block(fid) != ""
	if by_letter and not bool(a.get("letter", false)):
		a["letter"] = true
		var lh: float = float(cfg().get("letter_hour", 9))
		var d: int = SysUtil.day() if SysUtil.hour_f() < lh else SysUtil.day() + 1
		a["answer_min"] = maxi(_abs(d, lh), SysUtil.now())
		return
	var cid: String = str(a["cid"])
	var pre: String = ("" if in_person else str((cfg().get("lines", {}) as Dictionary).get("letter" if by_letter else "phone", ""))) + place(cid) + ": "
	var iv: Dictionary = cfg().get("interview", {})
	if int(a["level"]) >= int(iv.get("from_level", 2)) or SysUtil.rng.randf() < float(iv.get("chance", 0.5)):
		var ih: Array = iv.get("hours", [10, 15])
		var day: int = SysUtil.day() + int(iv.get("days_ahead", 1))
		var hour: float = float(SysUtil.rng.randi_range(int(ih[0]), int(ih[1])))
		a["state"] = "interview"
		a["iv_min"] = _abs(day, hour)
		CalendarBook.add(fid, day, hour, str(a["lot"]), "Interview at %s" % place(cid), "interview", int(a["id"]))
		SysUtil.notify(pre + _line("interview", {"when": when(day, hour)}), "career")
		return
	_decide(a, false, pre)

## The pawn sets off for the interview like a commute (lead time), waits there until the stated time, then sits down with the staff for a short
## scene (task 63) and hears the answer at the end of it; an hour before, the alarm wakes a sleeping pawn (or a nudge). Missed after late_min.
static func _interview_tick(a: Dictionary, now: int) -> void:
	var f = SysUtil.folk(int(a["fid"]))
	if f == null:
		a["state"] = "done"
		return
	var iv: Dictionary = cfg().get("interview", {})
	var lot: String = str(a["lot"])
	var t0: int = int(a["iv_min"])
	if str(a["state"]) == "in_scene":
		if now >= int(a["end_min"]):
			_decide(a, true, "")
		return
	var late: int = int(iv.get("late_min", 45))
	var here: bool = lot != "" and NeighborhoodLots.lot_at(f.tile) == lot
	if here and now >= t0:
		CalendarBook.remove_ref("interview", int(a["id"]))
		_scene(f, a, now)
		return
	if here and not bool(a.get("early", false)):
		a["early"] = true
		SysUtil.notify("You're early. They'll see you at %s." % _hm(t0), "story")
	if now > t0 + late:
		CalendarBook.remove_ref("interview", int(a["id"]))
		a["state"] = "done"
		SysUtil.notify(_line("missed", {"place": place(str(a["cid"]))}), "warn")
		return
	if not bool(a.get("nudged", false)) and not here and now >= t0 - int(iv.get("nudge_min", 60)):
		a["nudged"] = true
		var t: String = _hm(t0)
		if CrimePlace.is_asleep(f):
			f.cancel_current("woken for the interview")
			SysUtil.notify("Your alarm goes off: the interview at %s is at %s." % [place(str(a["cid"])), t], "career")
		else:
			SysUtil.notify("Interview at %s at %s. Time to get going." % [place(str(a["cid"])), t], "career")
	if not bool(a.get("set_off", false)) and lot != "" and not SysUtil.is_away(f) and not Commute.active(int(f.id)):
		var dest: Vector2i = NeighborhoodLots.entry_tile(lot)
		var m: float = Workplace.trip_minutes(f, dest)
		if m >= 0.0 and now >= t0 - int(m * Workplace.num("lead_mult", 1.15) + Workplace.num("buffer_min", 10.0)):
			a["set_off"] = true
			if CrimePlace.is_asleep(f):
				f.cancel_current("woken for the interview")
			var ir := Interaction.create_goto(f, dest, false)
			if ir != null:
				ir.def = ir.def.duplicate(true)
				ir.def["priority"] = "high"          # like a commute: the pawn sets off on its own (Pawn.allows), the Calendar and the line said when
				ir.params["interview"] = true
				f.enqueue(ir)

## The interview itself: the pawn sits with the staff member on shift (or the manager) for `minutes`; the answer comes when it ends.
static func _scene(f, a: Dictionary, now: int) -> void:
	var mins: int = int((cfg().get("interview", {}) as Dictionary).get("minutes", 18))
	a["state"] = "in_scene"
	a["end_min"] = now + mins
	var staff: Array = Crowd.staff_folk(str(a["lot"]))
	var who: String = str(staff[0].name).get_slice(" (", 0) if not staff.is_empty() else "The manager"
	SysUtil.notify("%s sits down with you for the interview." % who, "career")
	var ir: Interaction = Interaction.create("wait_here", f, -1, false)
	if ir != null:
		ir.def = ir.def.duplicate(true)
		ir.def["label"] = "Interview"
		ir.def["duration_min"] = mins
		ir.def["posture"] = "sit"
		ir.def["priority"] = "high"
		ir.def["thought"] = "Trying to make a good impression."
		f.clear_queue()
		f.enqueue(ir)

## Yes or no. Interview: SkillCheck act "interview" (charisma) plus the rest; without one, a base share plus the rest.
static func _decide(a: Dictionary, interviewed: bool, pre: String) -> void:
	var fid: int = int(a["fid"])
	var cid: String = str(a["cid"])
	a["state"] = "done"
	var p: float = chance(fid, cid, int(a["applicants"]), interviewed, int(a["level"]))
	var barred: bool = str(a["lot"]) != "" and str((Creation.picks.get(fid, {}) as Dictionary).get("barred_lot", "")) == str(a["lot"])          # task 62: the old manager's word
	if JusticeRecords.bans(fid, cid) or barred or SysUtil.rng.randf() >= p:
		if interviewed:
			SkillCheck.train(fid, "charisma", 4.0, false)
			_walk_home(fid)
		SysUtil.notify((pre if pre != "" else place(cid) + ": ") + _line("no", {}), "story")
		return
	if interviewed:
		SkillCheck.train(fid, "charisma", 6.0, true)
	if interviewed:
		_walk_home(fid)
	var head: String = pre if pre != "" else place(cid) + ": "
	if Careers.has_job(fid) and Pawn.is_pawn_id(fid):          # playtest 65: never swap the job without asking
		var old: String = Careers.title_of(fid)
		var lv: int = int(a["level"])
		JusticePlayer.ask(fid, "A job offer", "%sThe job is yours if you want it. Take it, and leave your job as %s?" % [head, old],
			[{"id": "take", "label": "Take it"}, {"id": "stay", "label": "Stay as %s" % old}], func(ch): _take(fid, cid, lv, head, str(ch)), "stay")
		return
	_take(fid, cid, int(a["level"]), head, "take")

static func _take(fid: int, cid: String, level: int, head: String, ch: String) -> void:
	if ch != "take":
		SysUtil.notify(head + "You turn it down and stay where you are.", "career")
		return
	var sd: Dictionary = _offer(fid, cid, level)
	if not sd.is_empty():
		SysUtil.notify(head + _line("offer", {"when": "%s, at %s" % [when(int(sd["day"]), float(sd["hour"])), place(cid)]}), "career")

## After an interview the pawn walks home again, like after a shift (nobody waits around in the building until it closes).
static func _walk_home(fid: int) -> void:
	var f = SysUtil.folk(fid)
	if f == null or SoloHome.homeless:
		return
	var ir := Interaction.create_goto(f, NeighborhoodLots.entry_tile(Neighborhood.HOME), false)
	if ir != null:
		ir.def = ir.def.duplicate(true)
		ir.def["priority"] = "high"
		f.enqueue(ir)
		SysUtil.notify("%s heads home." % str(f.name).get_slice(" ", 0), "travel")          # playtest 65: never leave without saying why

## The share of a yes (never shown).
static func chance(fid: int, cid: String, applicants: int, interviewed: bool, level: int = 1) -> float:
	var w: Dictionary = cfg().get("weights", {})
	var f = SysUtil.folk(fid)
	var b: float = float(w.get("job_skill", 0.04)) * float(Careers.skill_for(f, cid)) if f != null else 0.0
	if f != null:
		b += float(w.get("hygiene", 0.12)) * clampf(f.get_stat_value("hygiene") / 100.0, -1.0, 1.0)
		b += float(w.get("mood", 0.08)) * clampf(float(Emotions.valence(str(f.mood_name))) * minf(float(f.mood_intensity), 3.0) / 3.0, -1.0, 1.0)
	if not JusticeRecords.convictions(fid).is_empty():
		b += float(w.get("record", -0.22))
	b += float(w.get("hiring_bonus", 0.05)) * Creation.hiring(fid, Creation.job_kind(cid))
	b += float(w.get("per_applicant", -0.05)) * float(applicants)
	if interviewed:
		if level <= 1:
			b += float(w.get("entry_ease", 0.0))          # task 63: an entry-level job with an average applicant is about an even chance
		return SkillCheck.chance(fid, "interview", {"bonus": b})
	return clampf(0.5 + float(w.get("no_interview_base", 0.35)) + b, 0.05, 0.95)

## Hire with a start: the job's next work day after today at its start hour. {day, hour} or {} when the hire failed.
static func _offer(fid: int, cid: String, level: int) -> Dictionary:
	var f = SysUtil.folk(fid)
	if f == null:
		return {}
	if Careers.has_job(fid):
		Careers.quit_job(f, "took another job")
	if not Careers.hire(f, cid, level, true):
		return {}
	var j: Dictionary = Careers.jobs[fid]
	var day: int = SysUtil.day() + 1
	for i in 8:
		if CareerShifts.works_on(fid, day):          # the first shift of a part-time first job too
			break
		day += 1
	j["start_day"] = day
	EduState.board["openings"][cid] = maxi(EduJobs.openings(cid) - 1, 0)
	return {"day": day, "hour": f.work_start}

# ------------------------------------------------------------------ asking in person
## Asked at the counter of the workplace with an application waiting: the answer comes now. True when there was one.
static func ask_in_person(f, lot: String) -> bool:
	for a in pending(int(f.id)):
		if str(a["lot"]) == lot and str(a["state"]) == "sent":
			_answer(a, true)
			apps = apps.filter(func(x): return str(x["state"]) != "done")
			return true
	return false

static func to_dict() -> Dictionary:
	return {"apps": apps.duplicate(true), "seq": _seq}

static func from_dict(d: Dictionary) -> void:
	reset()
	apps = (d.get("apps", []) as Array).duplicate(true)
	_seq = int(d.get("seq", 1))
