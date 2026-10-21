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
static var homemakers: Dictionary = {}  # folk_id -> true: "Stay at home" is a role, not a career (see Homemaker)
static var changed_day: Dictionary = {} # folk_id -> day of the last hire / quit (offers are never taken on their own right after)
static var seeking: Dictionary = {}     # folk_id -> day they started looking for work (JobSeeking)
## UI hook: when true, 'Look for Jobs' only creates the offer and the player answers it (Accept / Decline pop-up, Work dialog). Not saved.
static var confirm_offers: bool = false

static func reset() -> void:
	jobs.clear()
	school.clear()
	offers.clear()
	retired.clear()
	skip_flags.clear()
	shift_log.clear()
	homemakers.clear()
	changed_day.clear()
	seeking.clear()
	SkipRules.reset()
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

## Level definition. `branch` ("" = the generalist trunk) selects a branch track, which replaces the trunk
## from its `from_level` onwards (branch.levels[0] is level from_level).
static func level_def(cid: String, level: int, branch: String = "") -> Dictionary:
	var cd: Dictionary = career_def(cid)
	var br: Dictionary = branch_def(cid, branch)
	if not br.is_empty() and level >= int(br.get("from_level", 4)):
		var bl: Array = br.get("levels", [])
		var idx: int = level - int(br.get("from_level", 4))
		if idx < 0 or idx >= bl.size():
			return {}
		return bl[idx]
	var lv: Array = cd.get("levels", [])
	if level < 1 or level > lv.size():
		return {}
	return lv[level - 1]

static func max_level(cid: String, branch: String = "") -> int:
	var br: Dictionary = branch_def(cid, branch)
	if not br.is_empty():
		return int(br.get("from_level", 4)) - 1 + (br.get("levels", []) as Array).size()
	return (career_def(cid).get("levels", []) as Array).size()

static func branch_def(cid: String, branch: String) -> Dictionary:
	if branch == "":
		return {}
	return (career_def(cid).get("branches", {}) as Dictionary).get(branch, {})

static func branch_ids(cid: String) -> Array:
	return (career_def(cid).get("branches", {}) as Dictionary).keys()

static func branch_of(folk_id: int) -> String:
	return str((jobs.get(folk_id, {}) as Dictionary).get("branch", ""))

## Best of the career's primary skill and its `alt_skills`.
static func skill_for(f, cid: String) -> int:
	var cd: Dictionary = career_def(cid)
	var best: int = f.skill_level(str(cd.get("primary_skill", "")))
	for s in cd.get("alt_skills", []):
		best = maxi(best, f.skill_level(str(s)))
	return best

## Shift variant definition ("" / "day" = the level's own hours).
static func shift_def(cid: String, shift: String) -> Dictionary:
	if shift == "" or shift == "day":
		return {}
	return (career_def(cid).get("shifts", {}) as Dictionary).get(shift, {})

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
	return str(level_def(str(j["career"]), int(j["level"]), str(j.get("branch", ""))).get("title", ""))

# ------------------------------------------------------------------ requirements
## {"ok": bool, "missing": Array[String]}
static func qualify(f, cid: String, level: int, branch: String = "") -> Dictionary:
	var missing: Array = []
	var ld: Dictionary = level_def(cid, level, branch)
	if ld.is_empty():
		return {"ok": false, "missing": ["no such level"]}
	missing.append_array(JusticeCareers.extra_missing(int(f.id), cid))      # a criminal record closes some doors
	missing.append_array(EduGate.extra_missing(int(f.id), cid, level))      # task 14: the better jobs want a degree
	var req: Dictionary = ld.get("requires", {})
	var sk: Dictionary = req.get("skills", {})
	for s in sk:
		if f.skill_level(str(s)) < int(sk[s]):
			missing.append("%s %d" % [s, int(sk[s])])
	if req.has("skills_any"):
		var any_ok: bool = false
		var parts: Array = []
		for s in req["skills_any"]:
			parts.append("%s %d" % [s, int(req["skills_any"][s])])
			if f.skill_level(str(s)) >= int(req["skills_any"][s]):
				any_ok = true
		if not any_ok:
			missing.append("one of: " + " / ".join(parts))
	if req.has("traits_any"):
		var t_ok: bool = false
		for t in req["traits_any"]:
			if f.traits.has(str(t)):
				t_ok = true
		if not t_ok:
			missing.append("trait: " + " or ".join(req["traits_any"]))
	for t2 in req.get("traits_not", []):
		if f.traits.has(str(t2)):
			missing.append("not %s" % str(t2))
	if req.has("friends") and RelationshipBits.count_bit(int(f.id), "friend", true) < int(req["friends"]):
		missing.append(SysUtil.count_text(int(req["friends"]), "friend"))
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
	var cid: String = str(j["career"])
	var ld: Dictionary = level_def(cid, int(j["level"]), str(j.get("branch", "")))
	f.work_start = float(ld.get("start", 9))
	f.work_end = float(ld.get("end", 17))
	var sv: Dictionary = shift_def(cid, str(j.get("shift", "day")))
	if not sv.is_empty() and int(j["level"]) >= int(sv.get("min_level", 1)):
		f.work_start = float(sv.get("start", f.work_start))
		f.work_end = float(sv.get("end", f.work_end))

## Who may hold a job: the household's own people (never crew, crowd NPCs, visitors), adults and elders; teens only in the part-time careers
## (settings.teen_careers, level 1). "" = fine, else a reason.
static func why_not_work(f, cid: String = "", level: int = 1) -> String:
	if f == null:
		return "nobody"
	if int(f.household_id) <= 0 or f.has_meta("visitor") or f.has_meta("staff") or f.has_meta("crowd") or f.has_meta("trip_npc"):
		return "not one of the household"
	if homemakers.has(int(f.id)):
		return "stays at home"
	var stage: String = str(f.age_stage)
	if stage in ["adult", "elder"]:
		return ""
	if stage == "teen" and cid != "" and level <= 1 and CareerSpread.teen_careers().has(cid):
		return ""
	return "too young for that job"

static func hire(f, cid: String, level: int = 1) -> bool:
	if f == null or career_def(cid).is_empty() or level_def(cid, level).is_empty():
		return false
	if why_not_work(f, cid, level) != "":
		return false
	if retired.has(int(f.id)):
		return false
	var s: Dictionary = settings()
	jobs[int(f.id)] = {"career": cid, "level": level, "performance": float(s.get("start_performance", 50)),
		"days_worked": 0, "hired_day": SysUtil.day(), "level_since": SysUtil.day(), "days_skipped": 0,
		"attempt_day": -1, "cap_note_day": -1, "branch": "", "branch_pref": "", "shift": "day", "tasks": {"day": -1, "progress": {}, "done": []}}
	offers.erase(int(f.id))
	seeking.erase(int(f.id))
	changed_day[int(f.id)] = SysUtil.day()
	apply_schedule(f)
	SysUtil.game_event("hired", {"folk_id": f.id, "career": cid, "level": level})
	SysUtil.notify("%s is now a %s (%s)!" % [f.name, str(career_def(cid).get("label", cid)), title_of(int(f.id))], "career")
	return true

static func quit_job(f, why: String = "quit") -> void:
	if f == null or not jobs.has(int(f.id)):
		return
	var j: Dictionary = jobs[int(f.id)]
	jobs.erase(int(f.id))
	changed_day[int(f.id)] = SysUtil.day()
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
	if why_not_work(f) != "":
		if str(f.age_stage) != "teen" or why_not_work(f, "x") == "not one of the household":
			return {}
		if cid == "":
			cid = CareerSpread.pick(f, CareerSpread.teen_careers())
			if cid == "":
				return {}
		level = 1
		if why_not_work(f, cid, 1) != "":
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
	var where: String = "A message on your phone" if PhoneOwn.block(int(f.id)) == "" else "A letter came"
	SysUtil.notify("%s: job offer for %s, %s, %d/h." % [where, f.name, str(ld.get("title", cid)), int(ld.get("pay", 0))], "job_offer")
	SysUtil.game_event("job_offer", {"folk_id": f.id, "career": cid, "level": level})
	if auto_accept_offers:
		accept_offer(int(f.id))
	return o

static func accept_offer(folk_id: int) -> bool:
	var o: Dictionary = offers.get(folk_id, {})
	var f = SysUtil.folk(folk_id)
	if o.is_empty() or f == null:
		return false
	if why_not_work(f, str(o["career"]), int(o["level"])) != "":
		offers.erase(folk_id)
		return false
	return hire(f, str(o["career"]), int(o["level"]))

static func decline_offer(folk_id: int) -> void:
	offers.erase(folk_id)

static func _best_career_for(f) -> String:
	return CareerSpread.pick(f, career_ids())

## The computer's "Look for Jobs" interaction fires game_event job_search.
static func on_job_search(folk_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null or jobs.has(folk_id) or (why_not_work(f) != "" and str(f.age_stage) != "teen"):
		return
	seeking[folk_id] = SysUtil.day()
	if not offers.has(folk_id):
		make_offer(f)
	if not confirm_offers:
		accept_offer(folk_id)

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
	ContentRules.on_day(day)
	Homemaker.on_day()
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
		if jobs.has(fid):
			CareerSpread.maybe_switch(f)                  # a young adult may change careers (friction: back to level 1)
			continue
		# offers
		if not jobs.has(fid) and not offers.has(fid) and not homemakers.has(fid) and JobSeeking.cooled_down(f) and stage == min_stage and Aging.stage_index(stage) >= Aging.stage_index(min_stage):
			if SysUtil.chance(float(s.get("offer_chance_per_day", 0.3)) * StoryPacing.mult("job", int(f.household_id))):
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
		var br_id: String = str(j.get("branch", ""))
		var ld: Dictionary = level_def(cid, int(j["level"]), br_id)
		var nxt: Dictionary = level_def(cid, int(j["level"]) + 1, br_id)
		var req_text: Array = []
		if f != null and not nxt.is_empty():
			req_text = qualify(f, cid, int(j["level"]) + 1, br_id)["missing"]
		return {"employed": true, "career": cid, "career_label": career_def(cid).get("label", cid), "title": ld.get("title", ""),
			"level": j["level"], "max_level": max_level(cid, br_id), "branch": br_id,
			"branch_label": str(branch_def(cid, br_id).get("label", "")), "blurb": str(career_def(cid).get("description", "")),
			"flavor": str(ld.get("flavor", "")), "shift": str(j.get("shift", "day")), "shifts": (career_def(cid).get("shifts", {}) as Dictionary).keys(),
			"tasks": CareerProgress.tasks_for(folk_id), "performance": j["performance"], "pay_hour": ld.get("pay", 0),
			"start": ld.get("start", 0), "end": ld.get("end", 0), "days_worked": j["days_worked"], "days_skipped": j["days_skipped"],
			"next_title": nxt.get("title", ""), "next_missing": req_text, "away": Away.is_away(folk_id)}
	if school.has(folk_id):
		return {"employed": false, "student": true, "grade": school[folk_id]["grade"], "letter": CareerShifts.grade_letter(float(school[folk_id]["grade"]))}
	if retired.has(folk_id):
		return {"employed": false, "retired": true, "pension": retired[folk_id]["pension"]}
	return {"employed": false, "offer": offers.get(folk_id, {})}

static func to_dict() -> Dictionary:
	return {"jobs": SysUtil.str_keys(jobs).duplicate(true), "school": SysUtil.str_keys(school).duplicate(true),
		"offers": SysUtil.str_keys(offers).duplicate(true), "retired": SysUtil.str_keys(retired).duplicate(true),
		"skip_flags": SysUtil.str_keys(skip_flags), "shift_log": shift_log.duplicate(true), "auto_accept": auto_accept_offers,
		"homemakers": SysUtil.str_keys(homemakers), "changed_day": SysUtil.str_keys(changed_day), "seeking": SysUtil.str_keys(seeking),
		"skip_rules": SkipRules.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	jobs = SysUtil.int_keys((d.get("jobs", {}) as Dictionary).duplicate(true))
	school = SysUtil.int_keys((d.get("school", {}) as Dictionary).duplicate(true))
	offers = SysUtil.int_keys((d.get("offers", {}) as Dictionary).duplicate(true))
	retired = SysUtil.int_keys((d.get("retired", {}) as Dictionary).duplicate(true))
	skip_flags = SysUtil.int_keys(d.get("skip_flags", {}))
	shift_log = (d.get("shift_log", []) as Array).duplicate(true)
	auto_accept_offers = bool(d.get("auto_accept", false))
	homemakers = SysUtil.int_keys(d.get("homemakers", {}))
	changed_day = SysUtil.int_keys(d.get("changed_day", {}))
	seeking = SysUtil.int_keys(d.get("seeking", {}))
	SkipRules.from_dict(d.get("skip_rules", {}))
	for fid in jobs:
		var f = SysUtil.folk(int(fid))
		if f != null:
			apply_schedule(f)

# ---- thin delegates (called from UI / views)
static func skip_work_today(folk_id: int) -> void:
	CareerShifts.skip_work_today(folk_id)