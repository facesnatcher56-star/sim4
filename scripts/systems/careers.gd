class_name Careers
extends RefCounted
## Jobs, shifts, performance, promotions, school and retirement. Data: data/careers.json.
## At shift start a folk with a job is routed off-lot through Away ("left_for_work"), and comes back at shift end
## with pay + performance applied ("returned_from_work"). Interactions done at home (work_computer, paint_canvas,
## exercise, cook_meal ...) feed the performance meter via the career's `hooks`.

static var jobs: Dictionary = {}        # folk_id -> {career, level, performance, days_worked, hired_day, level_since, days_skipped, attempt_day, cap_note_day}
static var school: Dictionary = {}      # folk_id -> {grade, days, skipped, attempt_day}
static var offers: Dictionary = {}      # folk_id -> {career, level, expires_day}
static var retired: Dictionary = {}     # folk_id -> {career, level, pension}
static var skip_flags: Dictionary = {}  # folk_id -> day on which the player chose to skip work
static var shift_log: Array = []        # last shifts {day, folk_id, kind, pay, delta, performance, skipped}
static var auto_accept_offers: bool = false

static func reset() -> void:
	jobs.clear()
	school.clear()
	offers.clear()
	retired.clear()
	skip_flags.clear()
	shift_log.clear()
	auto_accept_offers = false

# ------------------------------------------------------------------ data access
static func cfg() -> Dictionary:
	return SysUtil.table("careers")

static func settings() -> Dictionary:
	return cfg().get("settings", {})

static func career_ids() -> Array:
	return (cfg().get("careers", {}) as Dictionary).keys()

static func career_def(cid: String) -> Dictionary:
	return (cfg().get("careers", {}) as Dictionary).get(cid, {})

static func level_def(cid: String, level: int) -> Dictionary:
	var lv: Array = career_def(cid).get("levels", [])
	if level < 1 or level > lv.size():
		return {}
	return lv[level - 1]

static func max_level(cid: String) -> int:
	return (career_def(cid).get("levels", []) as Array).size()

static func career_of(folk_id: int) -> String:
	return str((jobs.get(folk_id, {}) as Dictionary).get("career", ""))

static func level_of(folk_id: int) -> int:
	return int((jobs.get(folk_id, {}) as Dictionary).get("level", 0))

static func has_job(folk_id: int) -> bool:
	return jobs.has(folk_id)

static func title_of(folk_id: int) -> String:
	if not jobs.has(folk_id):
		return ""
	var j: Dictionary = jobs[folk_id]
	return str(level_def(str(j["career"]), int(j["level"])).get("title", ""))

# ------------------------------------------------------------------ requirements
## {"ok": bool, "missing": Array[String]}
static func qualify(f, cid: String, level: int) -> Dictionary:
	var missing: Array = []
	var ld: Dictionary = level_def(cid, level)
	if ld.is_empty():
		return {"ok": false, "missing": ["no such level"]}
	var req: Dictionary = ld.get("requires", {})
	var sk: Dictionary = req.get("skills", {})
	for s in sk:
		if f.skill_level(str(s)) < int(sk[s]):
			missing.append("%s %d" % [s, int(sk[s])])
	if req.has("friends") and RelationshipService.count_bit(int(f.id), "friend", true) < int(req["friends"]):
		missing.append("%d friends" % int(req["friends"]))
	return {"ok": missing.is_empty(), "missing": missing}

static func trait_bonus(f, cid: String) -> float:
	var total: float = 0.0
	var tb: Dictionary = career_def(cid).get("trait_bonus", {})
	for t in f.traits:
		total += float(tb.get(t, 0.0))
	return total

# ------------------------------------------------------------------ hiring
static func apply_schedule(f) -> void:
	var j: Dictionary = jobs.get(int(f.id), {})
	if j.is_empty():
		f.work_start = -1.0
		f.work_end = -1.0
		return
	var ld: Dictionary = level_def(str(j["career"]), int(j["level"]))
	f.work_start = float(ld.get("start", 9))
	f.work_end = float(ld.get("end", 17))

static func hire(f, cid: String, level: int = 1) -> bool:
	if f == null or career_def(cid).is_empty() or level_def(cid, level).is_empty():
		return false
	if retired.has(int(f.id)):
		return false
	var s: Dictionary = settings()
	jobs[int(f.id)] = {"career": cid, "level": level, "performance": float(s.get("start_performance", 50)),
		"days_worked": 0, "hired_day": SysUtil.day(), "level_since": SysUtil.day(), "days_skipped": 0,
		"attempt_day": -1, "cap_note_day": -1}
	offers.erase(int(f.id))
	apply_schedule(f)
	SysUtil.game_event("hired", {"folk_id": f.id, "career": cid, "level": level})
	SysUtil.notify("%s is now a %s (%s)!" % [f.name, str(career_def(cid).get("label", cid)), title_of(int(f.id))], "career")
	return true

static func quit_job(f, why: String = "quit") -> void:
	if f == null or not jobs.has(int(f.id)):
		return
	var j: Dictionary = jobs[int(f.id)]
	jobs.erase(int(f.id))
	apply_schedule(f)
	SysUtil.game_event("left_job", {"folk_id": f.id, "career": j["career"], "reason": why})

static func fire(f) -> void:
	if f == null or not jobs.has(int(f.id)):
		return
	var j: Dictionary = jobs[int(f.id)]
	SysUtil.notify("%s was fired from the %s job!" % [f.name, str(career_def(str(j["career"])).get("label", ""))], "bad")
	quit_job(f, "fired")
	SysUtil.game_event("fired", {"folk_id": f.id})

# ------------------------------------------------------------------ job offers
static func pending_offer(folk_id: int) -> Dictionary:
	return offers.get(folk_id, {})

static func make_offer(f, cid: String = "", level: int = 0) -> Dictionary:
	if f == null or jobs.has(int(f.id)) or retired.has(int(f.id)):
		return {}
	if cid == "":
		cid = _best_career_for(f)
	if cid == "":
		return {}
	if level <= 0:
		level = 1
		for lv in range(mini(2, max_level(cid)), 0, -1):
			if bool(qualify(f, cid, lv)["ok"]):
				level = lv
				break
	var o: Dictionary = {"career": cid, "level": level, "expires_day": SysUtil.day() + int(settings().get("offer_expire_days", 3))}
	offers[int(f.id)] = o
	var ld: Dictionary = level_def(cid, level)
	SysUtil.notify("%s got a job offer: %s (%s), %d coins/hour. Use a computer's 'Look for Jobs' to accept." % [
		f.name, str(ld.get("title", cid)), str(career_def(cid).get("label", cid)), int(ld.get("pay", 0))], "job_offer")
	SysUtil.game_event("job_offer", {"folk_id": f.id, "career": cid, "level": level})
	if auto_accept_offers:
		accept_offer(int(f.id))
	return o

static func accept_offer(folk_id: int) -> bool:
	var o: Dictionary = offers.get(folk_id, {})
	var f = SysUtil.folk(folk_id)
	if o.is_empty() or f == null:
		return false
	return hire(f, str(o["career"]), int(o["level"]))

static func decline_offer(folk_id: int) -> void:
	offers.erase(folk_id)

static func _best_career_for(f) -> String:
	var ids: Array = career_ids()
	var weights: Array = []
	for cid in ids:
		var w: float = 1.0 + float(f.skill_level(str(career_def(str(cid)).get("primary_skill", "")))) * 1.5 + trait_bonus(f, str(cid))
		weights.append(maxf(w, 0.2))
	var pick = SysUtil.pick_weighted(ids, weights)
	return str(pick) if pick != null else ""

## The computer's "Look for Jobs" interaction fires game_event job_search.
static func on_job_search(folk_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null or jobs.has(folk_id):
		return
	if not offers.has(folk_id):
		make_offer(f)
	accept_offer(folk_id)

# ------------------------------------------------------------------ performance
static func performance_of(folk_id: int) -> float:
	return float((jobs.get(folk_id, {}) as Dictionary).get("performance", 0.0))

static func pay_multiplier(perf: float) -> float:
	var s: Dictionary = settings()
	return float(s.get("pay_perf_floor", 0.8)) + float(s.get("pay_perf_span", 0.4)) * clampf(perf / 100.0, 0.0, 1.0)

## Performance change for one finished shift, from mood, buffs, skill and traits.
static func shift_gain(f, cid: String, level: int) -> float:
	var s: Dictionary = settings()
	var gain: float = float(s.get("base_gain", 3))
	var mg: Dictionary = s.get("mood_gain", {})
	gain += float(mg.get(str(f.mood_name), 0.0)) * float(maxi(int(f.mood_intensity), 1)) / 2.0
	var bg: Dictionary = s.get("buff_gain", {})
	for b in f.buffs:
		gain += float(bg.get(str(b["id"]), 0.0))
	var skill: int = f.skill_level(str(career_def(cid).get("primary_skill", "")))
	var cap: float = float(s.get("skill_gain_cap", 3))
	gain += clampf(float(skill - (level * 2 - 2)), -cap, cap)
	gain += trait_bonus(f, cid)
	return gain

static func add_performance(folk_id: int, delta: float, allow_demote: bool = false) -> void:
	if not jobs.has(folk_id):
		return
	var j: Dictionary = jobs[folk_id]
	var s: Dictionary = settings()
	j["performance"] = clampf(float(j["performance"]) + delta, 0.0, 100.0)
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	if float(j["performance"]) >= float(s.get("promote_at", 100)):
		_try_promote(f)
	elif allow_demote and float(j["performance"]) <= float(s.get("demote_at", 0)):
		_demote(f)

static func _try_promote(f) -> void:
	var j: Dictionary = jobs[int(f.id)]
	var cid: String = str(j["career"])
	var nxt: int = int(j["level"]) + 1
	if nxt > max_level(cid):
		return
	var q: Dictionary = qualify(f, cid, nxt)
	if not bool(q["ok"]):
		if int(j.get("cap_note_day", -1)) != SysUtil.day():
			j["cap_note_day"] = SysUtil.day()
			SysUtil.notify("%s is ready for a promotion but needs: %s" % [f.name, ", ".join(q["missing"])], "career")
		return
	var old_pay: int = int(level_def(cid, int(j["level"])).get("pay", 0))
	j["level"] = nxt
	j["level_since"] = SysUtil.day()
	j["performance"] = float(settings().get("after_promotion_performance", 40))
	apply_schedule(f)
	var ld: Dictionary = level_def(cid, nxt)
	var bonus: int = int(ld.get("pay", old_pay)) * 8
	Economy.deposit(int(f.household_id), bonus, "promotion bonus")
	SysUtil.notify("Promotion! %s is now a %s (%d coins/hour). Bonus: %d coins." % [f.name, str(ld.get("title", "")), int(ld.get("pay", 0)), bonus], "career")
	SysUtil.game_event("promoted", {"folk_id": f.id, "career": cid, "level": nxt, "title": ld.get("title", "")})

static func _demote(f) -> void:
	var j: Dictionary = jobs[int(f.id)]
	var cid: String = str(j["career"])
	if int(j["level"]) <= 1:
		fire(f)
		return
	j["level"] = int(j["level"]) - 1
	j["level_since"] = SysUtil.day()
	j["performance"] = float(settings().get("after_demotion_performance", 35))
	apply_schedule(f)
	SysUtil.notify("Demoted! %s is now a %s." % [f.name, title_of(int(f.id))], "bad")
	SysUtil.game_event("demoted", {"folk_id": f.id, "career": cid, "level": j["level"]})

## Called after a folk finishes any interaction: work-ish interactions at home move the meter.
static func on_interaction(folk_id: int, iid: String, success: bool) -> void:
	if not success:
		return
	if jobs.has(folk_id):
		var hooks: Dictionary = career_def(str(jobs[folk_id]["career"])).get("hooks", {})
		if hooks.has(iid):
			add_performance(folk_id, float(hooks[iid]))
	if school.has(folk_id):
		var sh: Dictionary = cfg().get("school", {}).get("hooks", {})
		if sh.has(iid):
			school[folk_id]["grade"] = clampf(float(school[folk_id]["grade"]) + float(sh[iid]), 0.0, 100.0)

# ------------------------------------------------------------------ attendance
static func _has_int(arr: Array, v: int) -> bool:
	for x in arr:
		if int(x) == v:
			return true
	return false

static func is_work_day(cid: String, day: int) -> bool:
	return _has_int(career_def(cid).get("days", []), SysUtil.weekday(day))

static func is_school_day(day: int) -> bool:
	return _has_int(cfg().get("school", {}).get("days", []), SysUtil.weekday(day))

static func skip_work_today(folk_id: int) -> void:
	skip_flags[folk_id] = SysUtil.day()

static func _critical(f) -> bool:
	var lim: float = float(settings().get("critical_need", -65))
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
	var day: int = SysUtil.day()
	var h: float = SysUtil.hour_f()
	for f in WorldIface.all_folk():
		var fid: int = int(f.id)
		if SysUtil.is_away(f) or Away.pending.has(fid):
			continue
		if jobs.has(fid):
			var j: Dictionary = jobs[fid]
			if int(j["attempt_day"]) != day and is_work_day(str(j["career"]), day) and h >= f.work_start and h < f.work_end:
				j["attempt_day"] = day
				_start_shift(f, j, h)
		elif school.has(fid):
			var sc: Dictionary = cfg().get("school", {})
			var st: Dictionary = school[fid]
			if int(st["attempt_day"]) != day and is_school_day(day) and h >= float(sc.get("start", 9)) and h < float(sc.get("end", 15)):
				st["attempt_day"] = day
				_start_school(f, st, h, sc)

static func _start_shift(f, j: Dictionary, h: float) -> void:
	var fid: int = int(f.id)
	var s: Dictionary = settings()
	var title: String = title_of(fid)
	if int(skip_flags.get(fid, -1)) == SysUtil.day():
		_record_skip(f, j, float(s.get("skip_penalty", 15)), "chose to skip work")
		return
	if _player_busy(f):
		_record_skip(f, j, float(s.get("skip_penalty", 15)), "was busy with something else and skipped work")
		return
	if _critical(f):
		_record_skip(f, j, float(s.get("sick_penalty", 8)), "was too run down and called in sick")
		return
	var minutes: float = (f.work_end - h) * 60.0
	var data: Dictionary = {"kind": "work", "career": j["career"], "level": j["level"], "title": title,
		"label": "At work: " + title, "shift_end": f.work_end}
	if Away.send(f, minutes, "work", data):
		SysUtil.game_event("work_dispatched", {"folk_id": fid})

static func _record_skip(f, j: Dictionary, penalty: float, why: String) -> void:
	j["days_skipped"] = int(j["days_skipped"]) + 1
	SysUtil.notify("%s %s (-%d performance)." % [f.name, why, int(penalty)], "warn")
	shift_log.append({"day": SysUtil.day(), "folk_id": int(f.id), "kind": "work", "pay": 0, "delta": -penalty,
		"performance": float(j["performance"]) - penalty, "skipped": true})
	_trim_log()
	add_performance(int(f.id), -penalty, true)
	SysUtil.game_event("skipped_work", {"folk_id": f.id, "penalty": penalty})

static func _trim_log() -> void:
	while shift_log.size() > 60:
		shift_log.pop_front()

## Away started for work / school -> emit the specific event.
static func on_left(f, rec: Dictionary) -> void:
	var fid: int = int(f.id)
	match str(rec["reason"]):
		"work":
			SysUtil.game_event("left_for_work", {"folk_id": fid, "career": rec["data"].get("career", ""), "title": rec["data"].get("title", ""),
				"shift_end": rec["data"].get("shift_end", 0.0)})
		"school":
			SysUtil.game_event("left_for_school", {"folk_id": fid})

## Away finished (completed shift or interrupted).
static func on_returned(f, rec: Dictionary) -> void:
	var fid: int = int(f.id)
	var completed: bool = bool(rec.get("completed", false))
	match str(rec["reason"]):
		"work":
			if not jobs.has(fid):
				return
			var j: Dictionary = jobs[fid]
			var cid: String = str(j["career"])
			var ld: Dictionary = level_def(cid, int(j["level"]))
			var s: Dictionary = settings()
			var perf: float = float(j["performance"])
			var hours: float = float(rec["worked_min"]) / 60.0
			var pay: int = int(round(hours * float(ld.get("pay", 0)) * pay_multiplier(perf)))
			var delta: float
			if completed:
				delta = shift_gain(f, cid, int(j["level"]))
				j["days_worked"] = int(j["days_worked"]) + 1
			else:
				pay = int(pay * 0.5)
				delta = -float(s.get("skip_penalty", 15))
				j["days_skipped"] = int(j["days_skipped"]) + 1
			Economy.deposit(int(f.household_id), pay, "wages: %s" % title_of(fid))
			add_performance(fid, delta, true)
			var perf_now: float = performance_of(fid) if jobs.has(fid) else 0.0
			shift_log.append({"day": SysUtil.day(), "folk_id": fid, "kind": "work", "pay": pay, "delta": delta,
				"performance": perf_now, "skipped": not completed})
			_trim_log()
			SysUtil.notify("%s earned %d coins at work%s." % [f.name, pay, "" if completed else " (left early!)"], "career")
			SysUtil.game_event("returned_from_work", {"folk_id": fid, "pay": pay, "performance": perf_now, "delta": delta,
				"skipped": not completed, "career": cid})
		"school":
			if not school.has(fid):
				return
			var st: Dictionary = school[fid]
			var sc: Dictionary = cfg().get("school", {})
			var gd: float
			if completed:
				gd = float(sc.get("base_gain", 1)) + float(settings().get("mood_gain", {}).get(str(f.mood_name), 0.0)) * float(sc.get("mood_scale", 0.8))
				st["days"] = int(st["days"]) + 1
			else:
				gd = -float(sc.get("skip_penalty", 12))
				st["skipped"] = int(st["skipped"]) + 1
			st["grade"] = clampf(float(st["grade"]) + gd, 0.0, 100.0)
			SysUtil.game_event("returned_from_school", {"folk_id": fid, "grade": st["grade"], "letter": grade_letter(float(st["grade"])), "skipped": not completed})

static func grade_letter(g: float) -> String:
	for pair in cfg().get("school", {}).get("grades", []):
		if g >= float(pair[0]):
			return str(pair[1])
	return "F"

static func grade_of(folk_id: int) -> float:
	return float((school.get(folk_id, {}) as Dictionary).get("grade", 0.0))

static func _start_school(f, st: Dictionary, h: float, sc: Dictionary) -> void:
	if _player_busy(f):
		st["skipped"] = int(st["skipped"]) + 1
		st["grade"] = clampf(float(st["grade"]) - float(sc.get("skip_penalty", 12)), 0.0, 100.0)
		SysUtil.notify("%s skipped school (-%d grade)." % [f.name, int(sc.get("skip_penalty", 12))], "warn")
		return
	var minutes: float = (float(sc.get("end", 15)) - h) * 60.0
	Away.send(f, minutes, "school", {"label": "At school"})

# ------------------------------------------------------------------ daily upkeep
## School enrolment follows the age stage (children and teens attend).
static func enroll_school() -> void:
	var sc: Dictionary = cfg().get("school", {})
	for f in SysUtil.residents():
		var fid: int = int(f.id)
		if (sc.get("stages", []) as Array).has(str(f.age_stage)):
			if not school.has(fid):
				school[fid] = {"grade": float(sc.get("grade_start", 70)), "days": 0, "skipped": 0, "attempt_day": -1}
		elif school.has(fid):
			school.erase(fid)

static func on_day(day: int) -> void:
	enroll_school()
	# expire offers
	for fid in offers.keys():
		if day > int(offers[fid]["expires_day"]):
			offers.erase(fid)
	var s: Dictionary = settings()
	var min_stage: String = str(s.get("offer_min_stage", "adult"))
	for f in SysUtil.residents():
		var fid: int = int(f.id)
		var stage: String = str(f.age_stage)
		# retirement and pensions
		if retired.has(fid):
			var pen: int = int(retired[fid]["pension"])
			Economy.deposit(int(f.household_id), pen, "pension")
			continue
		if stage == str(cfg().get("retirement", {}).get("stage", "elder")):
			if jobs.has(fid):
				_retire(f)
				continue
		# offers
		if not jobs.has(fid) and not offers.has(fid) and stage == min_stage and Aging.stage_index(stage) >= Aging.stage_index(min_stage):
			if SysUtil.chance(float(s.get("offer_chance_per_day", 0.3))):
				make_offer(f)

static func _retire(f) -> void:
	var fid: int = int(f.id)
	var j: Dictionary = jobs[fid]
	var r: Dictionary = cfg().get("retirement", {})
	var pension: int = int(j["level"]) * int(r.get("pension_per_level", 14)) + 10
	retired[fid] = {"career": j["career"], "level": j["level"], "pension": pension}
	quit_job(f, "retired")
	SysUtil.notify("%s has retired and now receives a pension of %d coins per day." % [f.name, pension], "career")
	SysUtil.game_event("retired", {"folk_id": fid, "pension": pension})

## Aging calls this when a folk changes life stage.
static func on_stage_changed(f, _old: String, new_stage: String) -> void:
	var fid: int = int(f.id)
	var sc: Dictionary = cfg().get("school", {})
	if (sc.get("stages", []) as Array).has(new_stage):
		if not school.has(fid):
			school[fid] = {"grade": float(sc.get("grade_start", 70)), "days": 0, "skipped": 0, "attempt_day": -1}
	else:
		school.erase(fid)
	if new_stage == str(cfg().get("retirement", {}).get("stage", "elder")) and jobs.has(fid):
		_retire(f)

static func forget(folk_id: int) -> void:
	jobs.erase(folk_id)
	school.erase(folk_id)
	offers.erase(folk_id)
	retired.erase(folk_id)

# ------------------------------------------------------------------ UI helpers
static func info_for(folk_id: int) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	if jobs.has(folk_id):
		var j: Dictionary = jobs[folk_id]
		var cid: String = str(j["career"])
		var ld: Dictionary = level_def(cid, int(j["level"]))
		var nxt: Dictionary = level_def(cid, int(j["level"]) + 1)
		var req_text: Array = []
		if f != null and not nxt.is_empty():
			req_text = qualify(f, cid, int(j["level"]) + 1)["missing"]
		return {"employed": true, "career": cid, "career_label": career_def(cid).get("label", cid), "title": ld.get("title", ""),
			"level": j["level"], "max_level": max_level(cid), "performance": j["performance"], "pay_hour": ld.get("pay", 0),
			"start": ld.get("start", 0), "end": ld.get("end", 0), "days_worked": j["days_worked"], "days_skipped": j["days_skipped"],
			"next_title": nxt.get("title", ""), "next_missing": req_text, "away": Away.is_away(folk_id)}
	if school.has(folk_id):
		return {"employed": false, "student": true, "grade": school[folk_id]["grade"], "letter": grade_letter(float(school[folk_id]["grade"]))}
	if retired.has(folk_id):
		return {"employed": false, "retired": true, "pension": retired[folk_id]["pension"]}
	return {"employed": false, "offer": offers.get(folk_id, {})}

static func to_dict() -> Dictionary:
	return {"jobs": SysUtil.str_keys(jobs).duplicate(true), "school": SysUtil.str_keys(school).duplicate(true),
		"offers": SysUtil.str_keys(offers).duplicate(true), "retired": SysUtil.str_keys(retired).duplicate(true),
		"skip_flags": SysUtil.str_keys(skip_flags), "shift_log": shift_log.duplicate(true), "auto_accept": auto_accept_offers}

static func from_dict(d: Dictionary) -> void:
	reset()
	jobs = SysUtil.int_keys((d.get("jobs", {}) as Dictionary).duplicate(true))
	school = SysUtil.int_keys((d.get("school", {}) as Dictionary).duplicate(true))
	offers = SysUtil.int_keys((d.get("offers", {}) as Dictionary).duplicate(true))
	retired = SysUtil.int_keys((d.get("retired", {}) as Dictionary).duplicate(true))
	skip_flags = SysUtil.int_keys(d.get("skip_flags", {}))
	shift_log = (d.get("shift_log", []) as Array).duplicate(true)
	auto_accept_offers = bool(d.get("auto_accept", false))
	for fid in jobs:
		var f = SysUtil.folk(int(fid))
		if f != null:
			apply_schedule(f)
