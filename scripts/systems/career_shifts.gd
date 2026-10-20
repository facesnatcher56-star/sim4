class_name CareerShifts
extends RefCounted
## Attendance: work days, shifts, school days and the away hooks.

# ------------------------------------------------------------------ attendance
static func is_work_day(cid: String, day: int, shift: String = "day") -> bool:
	var sv: Dictionary = Careers.shift_def(cid, shift)
	if sv.has("days"):
		return SysUtil.has_int(sv["days"], SysUtil.weekday(day))
	return SysUtil.has_int(Careers.career_def(cid).get("days", []), SysUtil.weekday(day))

## Is hour `h` inside the window in which a shift may START? Overnight shifts (end <= start) start any time from `start`.
static func in_shift_window(h: float, start: float, end: float) -> bool:
	if end > start:
		return h >= start and h < end
	return h >= start

static func is_school_day(day: int) -> bool:
	return SysUtil.has_int(Careers.cfg().get("school", {}).get("days", []), SysUtil.weekday(day))

static func skip_work_today(folk_id: int) -> void:
	Careers.skip_flags[folk_id] = SysUtil.day()

static func is_critical(f) -> bool:
	return _critical(f)

static func player_busy(f) -> bool:
	return _player_busy(f)

static func _critical(f) -> bool:
	var lim: float = float(Careers.settings().get("critical_need", -65))
	for n in ["hunger", "energy", "bladder"]:
		if f.get_stat_value(n) < lim:
			return true
	return false

static func _player_busy(f) -> bool:
	if f.current != null and f.current.player:
		return true
	for q in f.queue:
		if (q as Interaction).player:
			return true
	return false

static func on_minute() -> void:
	Commute.on_minute()
	var day: int = SysUtil.day()
	var h: float = SysUtil.hour_f()
	for fid0 in Careers.jobs.keys() + Careers.school.keys():      # the active set: people with a job or a school place (never every folk in the world)
		var fid: int = int(fid0)
		var f = WorldIface.get_folk(fid)
		if f == null or SysUtil.is_away(f) or Away.pending.has(fid) or Commute.active(fid) or Away.is_away(fid) or Vacation.on_trip(fid):
			continue
		if Careers.jobs.has(fid):
			var j: Dictionary = Careers.jobs[fid]
			if int(j["attempt_day"]) != day and is_work_day(str(j["career"]), day, str(j.get("shift", "day"))) \
					and in_shift_window(h + _lead(f, h, f.work_start, f.work_end), f.work_start, f.work_end):
				j["attempt_day"] = day
				if _hired_after_start(f, j, h, day):
					SysUtil.notify("%s starts at the %s tomorrow." % [f.name, str(Careers.career_def(str(j["career"])).get("label", "new job")).to_lower()], "career")
					continue
				_start_shift(f, j, h)
		elif Careers.school.has(fid):
			var sc: Dictionary = Careers.cfg().get("school", {})
			var st: Dictionary = Careers.school[fid]
			var s0: float = float(sc.get("start", 9))
			if int(st["attempt_day"]) != day and is_school_day(day) and h + _lead(f, h, s0, float(sc.get("end", 15))) >= s0 and h < float(sc.get("end", 15)):
				st["attempt_day"] = day
				_start_school(f, st, h, sc)

## First day on the job: hired after the day shift has already begun, so the first shift is tomorrow's (no late walk, no penalty).
static func _hired_after_start(f, j: Dictionary, h: float, day: int) -> bool:
	if int(j.get("hired_day", -1)) != day or int(j.get("days_worked", 0)) != 0 or f.work_end <= f.work_start or h < f.work_start - 6.0:
		return false
	return h + Commute.lead_hours(f) > f.work_start + Workplace.num("grace_min", 5.0) / 60.0

## Hours before the start at which a folk has to leave home so that the walk to the workplace gets there on time (0 without a map).
static func _lead(f, h: float, start: float, end: float) -> float:
	if not in_shift_window(h + 4.0, start, end):
		return 0.0                    # nowhere near the start yet: skip the route question
	return Commute.lead_hours(f)

## Absolute game minute of today's `hour`.
static func _abs_min(hour: float) -> int:
	return (SysUtil.day() - 1) * 1440 + int(round(hour * 60.0))

static func _start_shift(f, j: Dictionary, h: float) -> void:
	var fid: int = int(f.id)
	var s: Dictionary = Careers.settings()
	var title: String = Careers.title_of(fid)
	if PregnancyLeave.on_leave(fid):          # maternity / paternity leave or bed rest: the job is kept, nothing is recorded
		return
	if WorksPay.off_day(f, j):                 # task 31: a strike or a rained-off site: no work today, no penalty
		return
	if int(Careers.skip_flags.get(fid, -1)) == SysUtil.day():
		_record_skip(f, j, float(s.get("skip_penalty", 15)), "chose to skip work")
		return
	if _player_busy(f) and SkipRules.chooses_to_skip(f, "work"):
		_record_skip(f, j, float(s.get("skip_penalty", 15)), "was busy with something else and skipped work")
		return
	if _critical(f):
		_record_skip(f, j, float(s.get("sick_penalty", 8)), "was too run down and called in sick")
		return
	var unwell: String = Health.work_block(f, str(j["career"]))
	if unwell != "":
		_record_skip(f, j, float(s.get("sick_penalty", 8)) * 0.5, unwell)
		return
	var end_h: float = f.work_end
	if end_h <= f.work_start:
		end_h += 24.0
	var minutes: float = (end_h - h) * 60.0
	var due: int = _abs_min(f.work_start)
	if Commute.begin(f, "work", {"due_min": due, "end_min": due + int(round((end_h - f.work_start) * 60.0)), "career": j["career"], "title": title,
			"shift": str(j.get("shift", "day")), "level": j["level"], "shift_end": f.work_end}):
		SysUtil.game_event("work_dispatched", {"folk_id": fid, "commute": true})
		return
	var data: Dictionary = {"kind": "work", "shift": str(j.get("shift", "day")), "career": j["career"], "level": j["level"], "title": title,
		"label": "At work: " + title, "shift_end": f.work_end}
	if Away.send(f, minutes, "work", data):
		SysUtil.game_event("work_dispatched", {"folk_id": fid})

## Did not turn up (commute abandoned): same bookkeeping as a skip, plus the `missed_shift` event the missing-person score reads.
static func missed(f, kind: String, why: String) -> void:
	var fid: int = int(f.id)
	if kind == "school":
		var sc: Dictionary = Careers.cfg().get("school", {})
		var st: Dictionary = Careers.school.get(fid, {})
		if not st.is_empty():
			st["skipped"] = int(st["skipped"]) + 1
			st["grade"] = clampf(float(st["grade"]) - float(sc.get("skip_penalty", 12)), 0.0, 100.0)
		SysUtil.notify("%s %s." % [f.name, why], "warn")
		SysUtil.game_event("missed_shift", {"folk_id": fid, "kind": "school", "why": why})
		return
	if Careers.jobs.has(fid):
		_record_skip(f, Careers.jobs[fid], float(Careers.settings().get("skip_penalty", 15)), why)

static func _record_skip(f, j: Dictionary, penalty: float, why: String) -> void:
	j["days_skipped"] = int(j["days_skipped"]) + 1
	SysUtil.notify("%s %s (-%d performance)." % [f.name, why, int(penalty)], "warn")
	Careers.shift_log.append({"day": SysUtil.day(), "folk_id": int(f.id), "kind": "work", "pay": 0, "delta": -penalty,
		"performance": float(j["performance"]) - penalty, "skipped": true})
	_trim_log()
	CareerProgress.add_performance(int(f.id), -penalty, true)
	SysUtil.game_event("skipped_work", {"folk_id": f.id, "penalty": penalty})
	SysUtil.game_event("missed_shift", {"folk_id": f.id, "kind": "work", "why": why})

static func _trim_log() -> void:
	while Careers.shift_log.size() > 60:
		Careers.shift_log.pop_front()

## Away started for work / school -> emit the specific event.
static func on_left(f, rec: Dictionary) -> void:
	var fid: int = int(f.id)
	match str(rec["reason"]):
		"work":
			if bool(rec["data"].get("commute", false)):
				return                  # a real commute already announced the departure (Commute.begin) and the arrival
			SysUtil.game_event("left_for_work", {"folk_id": fid, "career": rec["data"].get("career", ""), "title": rec["data"].get("title", ""),
				"shift_end": rec["data"].get("shift_end", 0.0)})
		"school":
			if not bool(rec["data"].get("commute", false)):
				SysUtil.game_event("left_for_school", {"folk_id": fid})

## Away finished (completed shift or interrupted).
static func on_returned(f, rec: Dictionary) -> void:
	var fid: int = int(f.id)
	var completed: bool = bool(rec.get("completed", false))
	Commute.on_shift_end(f, rec)                 # walk home from the workplace (no-op for an old-style rabbit hole)
	match str(rec["reason"]):
		"work":
			if not Careers.jobs.has(fid):
				return
			var j: Dictionary = Careers.jobs[fid]
			var cid: String = str(j["career"])
			var ld: Dictionary = Careers.level_def(cid, int(j["level"]), str(j.get("branch", "")))
			var s: Dictionary = Careers.settings()
			var perf: float = float(j["performance"])
			var hours: float = float(rec["worked_min"]) / 60.0
			var sv: Dictionary = Careers.shift_def(cid, str(j.get("shift", "day")))
			var smult: float = float(sv.get("pay_mult", 1.0)) if (not sv.is_empty() and int(j["level"]) >= int(sv.get("min_level", 1))) else 1.0
			var pay: int = int(round(hours * float(ld.get("pay", 0)) * CareerProgress.pay_multiplier(perf) * smult * MarketEconomy.wage_mult() * EduGate.pay_mult(fid, cid) * SoloRules.wage_mult(f)))
			var delta: float
			if completed:
				delta = CareerProgress.shift_gain(f, cid, int(j["level"]))
				j["days_worked"] = int(j["days_worked"]) + 1
			else:
				pay = int(pay * 0.5)
				delta = -float(s.get("skip_penalty", 15))
				j["days_skipped"] = int(j["days_skipped"]) + 1
			pay = WorksPay.adjust_pay(f, j, pay, hours, completed)      # task 31: wage rises, overtime, union dues of the industrial careers
			Economy.deposit(int(f.household_id), pay, "wages: %s" % Careers.title_of(fid))
			if smult != 1.0 and completed and str(sv.get("return_buff", "")) != "":
				f.add_buff(str(sv["return_buff"]))
			CareerProgress.add_performance(fid, delta, true)
			var perf_now: float = CareerProgress.performance_of(fid) if Careers.jobs.has(fid) else 0.0
			Careers.shift_log.append({"day": SysUtil.day(), "folk_id": fid, "kind": "work", "pay": pay, "delta": delta,
				"performance": perf_now, "skipped": not completed})
			_trim_log()
			SysUtil.notify("%s earned %d coins at work%s." % [f.name, pay, "" if completed else " (left early!)"], "career")
			SysUtil.game_event("returned_from_work", {"folk_id": fid, "pay": pay, "performance": perf_now, "delta": delta,
				"skipped": not completed, "career": cid})
		"school":
			if not Careers.school.has(fid):
				return
			var st: Dictionary = Careers.school[fid]
			var sc: Dictionary = Careers.cfg().get("school", {})
			var gd: float
			if completed:
				gd = (float(sc.get("base_gain", 1)) + float(Careers.settings().get("mood_gain", {}).get(str(f.mood_name), 0.0)) * float(sc.get("mood_scale", 0.8))) * (0.85 + 0.15 * CityBudget.funding("schools"))      # task 12: school budget
				st["days"] = int(st["days"]) + 1
				SkillInterest.school_day(f)
			else:
				gd = -float(sc.get("skip_penalty", 12))
				st["skipped"] = int(st["skipped"]) + 1
			st["grade"] = clampf(float(st["grade"]) + gd, 0.0, 100.0)
			SysUtil.game_event("returned_from_school", {"folk_id": fid, "grade": st["grade"], "letter": grade_letter(float(st["grade"])), "skipped": not completed})

static func grade_letter(g: float) -> String:
	for pair in Careers.cfg().get("school", {}).get("grades", []):
		if g >= float(pair[0]):
			return str(pair[1])
	return "F"

static func grade_of(folk_id: int) -> float:
	return float((Careers.school.get(folk_id, {}) as Dictionary).get("grade", 0.0))

static func _start_school(f, st: Dictionary, h: float, sc: Dictionary) -> void:
	if _player_busy(f) and SkipRules.chooses_to_skip(f, "school"):
		st["skipped"] = int(st["skipped"]) + 1
		st["grade"] = clampf(float(st["grade"]) - float(sc.get("skip_penalty", 12)), 0.0, 100.0)
		SysUtil.notify("%s skipped school (-%d grade)." % [f.name, int(sc.get("skip_penalty", 12))], "warn")
		SysUtil.game_event("missed_shift", {"folk_id": f.id, "kind": "school", "why": "chose to skip school"})
		return
	if Commute.begin(f, "school", {"due_min": _abs_min(float(sc.get("start", 9))), "end_min": _abs_min(float(sc.get("end", 15)))}):
		return
	var minutes: float = (float(sc.get("end", 15)) - h) * 60.0
	Away.send(f, minutes, "school", {"label": "At school"})
