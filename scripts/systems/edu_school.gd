class_name EduSchool
extends RefCounted
## School life on top of the existing school attendance and grade (CareerShifts / Careers.school), task 14:
##   * HOMEWORK: after a day at school the teacher sets some (event `returned_from_school`); `do_homework` hands it in (+grade, a little xp); not handed
##     in by the next school day costs grade and a note from the teacher. The Homework Club at the library helps (EduServices "tutor").
##   * REPORT CARDS every `term_days`: a grade per subject (the overall grade nudged by the skill behind the subject), an average, a letter and a
##     teacher's comment (the teacher is a real name from PlaceStaff). Honour roll and "needs help" go to the household and the town chronicle.
##   * SCHOOL EVENTS (science fair, sports day, school play, parents' evening) once a year on the first school day on or after their calendar day.
##   * PRESCHOOL for toddlers: a small daily fee on school mornings, a little social and fun, and a head start (grade bonus) when school begins.
##   * GRADUATION when a teen grows up: a diploma with the final grade, and a chronicle line.
## Tier: residents' records only (ACTIVE, daily / event driven); townie children are one statistical line per event (EduTownies).

static func c() -> Dictionary:
	return EduState.cfg()

static func is_student(fid: int) -> bool:
	return Careers.school.has(fid)

static func grade(fid: int) -> float:
	return CareerShifts.grade_of(fid) if is_student(fid) else float(EduState.peek(fid).get("grade_seen", 0.0))

static func letter(g: float) -> String:
	return CareerShifts.grade_letter(g)

# ------------------------------------------------------------------ subjects and report cards
## {subject: 0..100}: the overall grade, nudged by how good the child is at the skill behind each subject.
static func subject_grades(fid: int) -> Dictionary:
	var f = SysUtil.folk(fid)
	var g: float = grade(fid)
	var out: Dictionary = {}
	var subjects: Dictionary = c().get("subjects", {})
	for s in subjects:
		var lvl: int = f.skill_level(str(subjects[s])) if f != null else 2
		out[s] = clampf(g + float(c().get("skill_weight", 4)) * float(lvl - int(c().get("skill_base", 2))), 0.0, 100.0)
	return out

static func report_card(fid: int, day: int) -> Dictionary:
	var f = SysUtil.folk(fid)
	if f == null or not is_student(fid):
		return {}
	var grades: Dictionary = subject_grades(fid)
	var sum := 0.0
	for s in grades:
		sum += float(grades[s])
	var avg: float = sum / maxf(float(grades.size()), 1.0)
	var lt: String = letter(avg)
	var teacher: String = PlaceStaff.who("school", "teacher")
	var pool: Array = LifeDefs.section("comments").get(lt, ["Good luck next term."])
	var comment: String = str(pool[EduState.rng.randi_range(0, pool.size() - 1)])
	var card := {"day": day, "avg": avg, "letter": lt, "comment": comment, "teacher": teacher, "grades": grades}
	var r: Dictionary = EduState.rec(fid)
	r["grade_seen"] = grade(fid)
	(r["reports"] as Array).append(card)
	while (r["reports"] as Array).size() > 8:
		(r["reports"] as Array).pop_front()
	var line: String = "%s's report card: %s on average. %s%s" % [f.name, lt, comment, "" if teacher == "" else " (%s)" % teacher]
	if avg >= float(c().get("honour_avg", 88)):
		LifeNote.say("honour_roll", "%s made the honour roll at Larkfield School." % f.name, [fid], 2, false)
		f.add_buff("cheered_up")
	elif avg < float(c().get("concern_avg", 55)):
		LifeNote.say("school_concern", "%s is struggling at school. The teachers would like a word." % f.name, [fid], 1, false)
	SysUtil.notify(line, "good" if avg >= 70.0 else "info")
	SysUtil.game_event("report_card", {"folk_id": fid, "avg": avg, "letter": lt})
	return card

static func term_of(day: int) -> int:
	return (day - 1) / maxi(int(c().get("term_days", 14)), 1)

# ------------------------------------------------------------------ homework
static func on_returned_from_school(fid: int, skipped: bool) -> void:
	if skipped:
		return
	var f = SysUtil.folk(fid)
	if f == null or not Careers.school.has(fid):
		return
	var hw: Dictionary = (EduState.rec(fid) as Dictionary)["hw"]
	var hwc: Dictionary = c().get("homework", {})
	if bool(hw.get("due", false)) and int(hw.get("set_day", -1)) < SysUtil.day():
		hw["missed"] = int(hw.get("missed", 0)) + 1
		hw["due"] = false
		Careers.school[fid]["grade"] = clampf(float(Careers.school[fid]["grade"]) - float(hwc.get("penalty", 2.0)), 0.0, 100.0)
		var t: String = PlaceStaff.who("school", "teacher")
		SysUtil.notify("%s did not hand in the homework%s." % [f.name, "" if t == "" else " and %s noticed" % t], "warn")
	if EduState.rng.randf() < float(hwc.get("set_chance", 0.8)):
		hw["due"] = true
		hw["set_day"] = SysUtil.day()
		SysUtil.notify("%s has homework to do." % f.name, "info")

static func on_homework_done(fid: int) -> void:
	var f = SysUtil.folk(fid)
	var hw: Dictionary = (EduState.rec(fid) as Dictionary)["hw"]
	if f == null or not bool(hw.get("due", false)) or not is_student(fid):
		return
	hw["due"] = false
	var hwc: Dictionary = c().get("homework", {})
	Careers.school[fid]["grade"] = clampf(float(Careers.school[fid]["grade"]) + float(hwc.get("bonus", 1.0)), 0.0, 100.0)
	f.add_skill_xp("logic", float(hwc.get("xp", 6)))
	SysUtil.notify("%s handed in the homework on time." % f.name, "good")

static func homework_due(fid: int) -> bool:
	return bool((EduState.peek(fid).get("hw", {}) as Dictionary).get("due", false))

# ------------------------------------------------------------------ the daily pass
## A new game or a load without the block: this year's events that are already past do not all fire at once.
static func init_year(day: int) -> void:
	var yr: int = Seasons.year_at(day)
	var dy: int = Aging.doy(day)
	for id in LifeDefs.section("events"):
		if int(LifeDefs.get_in("events", id).get("doy", 0)) < dy:
			EduState.fired[str(id)] = yr
	EduState.last_term = term_of(day)

static func on_day(day: int) -> void:
	if EduState.last_term < 0:
		init_year(day)
	if not CareerShifts.is_school_day(day):
		return
	_preschool_day(day)
	_start_bonus()
	if term_of(day) > EduState.last_term:
		EduState.last_term = term_of(day)
		for fid in Careers.school.keys():
			var f = SysUtil.folk(int(fid))
			if f != null and SysUtil.is_resident(f):
				report_card(int(fid), day)
	_events(day)

static func _events(day: int) -> void:
	var yr: int = Seasons.year_at(day)
	var dy: int = Aging.doy(day)
	for id in LifeDefs.section("events"):
		var e: Dictionary = LifeDefs.get_in("events", id)
		if int(EduState.fired.get(str(id), -1)) == yr or dy < int(e.get("doy", 0)):
			continue
		EduState.fired[str(id)] = yr
		_run_event(str(id), e)

static func _run_event(id: String, e: Dictionary) -> void:
	var teacher: String = PlaceStaff.who("school", "teacher")
	LifeNote.news("school", "%s%s" % [str(e.get("join", e.get("label", id))), "" if teacher == "" else " %s is in charge." % teacher])
	for fid in Careers.school.keys():
		var f = SysUtil.folk(int(fid))
		if f == null or not SysUtil.is_resident(f) or not (e.get("stages", []) as Array).has(str(f.age_stage)):
			continue
		if id == "parents_evening":
			_parents_evening(f)
			continue
		var sk: String = str(e.get("skill", ""))
		var score: float = (float(f.skill_level(sk)) * 8.0 if sk != "" else 0.0) + grade(int(fid)) * 0.3 + EduState.rng.randf() * 40.0
		if score >= float(c().get("win_score", 50.0)):
			var txt: String = str(e.get("win", "")).replace("{name}", str(f.name))
			Careers.school[fid]["grade"] = clampf(float(Careers.school[fid]["grade"]) + 2.0, 0.0, 100.0)
			f.add_buff("cheered_up")
			if sk != "":
				f.add_skill_xp(sk, 12.0)
			LifeNote.say("school_event", txt, [int(fid)], 2, true, "good")
		else:
			SysUtil.notify("%s took part in the %s." % [f.name, str(e.get("label", id)).to_lower()], "info")
	EduTownies.school_event(id, e)

static func _parents_evening(f) -> void:
	var g: float = grade(int(f.id))
	var word: String = "very good" if g >= 85.0 else ("good" if g >= 70.0 else ("so-so" if g >= 55.0 else "poor"))
	SysUtil.notify("Parents' evening: the teachers say %s is doing %s work (a %s)." % [f.name, word, letter(g)], "info")
	if g >= 85.0:
		for m in SysUtil.residents():
			if int(m.household_id) == int(f.household_id) and str(m.age_stage) in ["adult", "elder"]:
				m.add_buff("cheered_up")

# ------------------------------------------------------------------ preschool
static func enrol_preschool(fid: int, on: bool = true) -> void:
	EduState.rec(fid)["preschool"] = on

static func _preschool_day(_day: int) -> void:
	var pc: Dictionary = c().get("preschool", {})
	if pc.is_empty() or not PlaceStaff.staffed("preschool") or PlaceStaff.closed_today("preschool"):
		return
	for fid in EduState.recs.keys():
		var r: Dictionary = EduState.recs[fid]
		var f = SysUtil.folk(int(fid))
		if not bool(r.get("preschool", false)) or f == null or str(f.age_stage) != "toddler":
			continue
		var cost: int = maxi(int(round(float(pc.get("cost", 14)) * MarketEconomy.price_mult())), 1)
		if not Economy.spend(int(f.household_id), cost, "Preschool"):
			r["preschool"] = false
			SysUtil.notify("%s had to leave preschool: the fees were not paid." % f.name, "warn")
			continue
		r["early"] = float(r.get("early", 0.0)) + float(pc.get("early_per_day", 1.0))
		f.add_to_stat("social", float(pc.get("social", 16)))
		f.add_to_stat("fun", float(pc.get("fun", 8)))

## The head start of a toddler who went to preschool is applied the day after the grade record exists.
static func _start_bonus() -> void:
	var pc: Dictionary = c().get("preschool", {})
	for fid in EduState.recs.keys():
		var r: Dictionary = EduState.recs[fid]
		if not bool(r.get("start_bonus", false)) or not Careers.school.has(int(fid)):
			continue
		r["start_bonus"] = false
		var b: float = minf(float(r.get("early", 0.0)) / float(pc.get("early_div", 4.0)), float(pc.get("max_bonus", 6.0)))
		Careers.school[int(fid)]["grade"] = clampf(float(Careers.school[int(fid)]["grade"]) + b, 0.0, 100.0)
		var f = SysUtil.folk(int(fid))
		if f != null and b >= 1.0:
			SysUtil.notify("%s starts school with a head start from preschool." % f.name, "good")

# ------------------------------------------------------------------ growing up
static func on_aged_up(fid: int, from_stage: String, to_stage: String) -> void:
	var f = SysUtil.folk(fid)
	if f == null:
		return
	if from_stage == "toddler" and to_stage == "child":
		var r: Dictionary = EduState.rec(fid)
		if bool(r.get("preschool", false)) or float(r.get("early", 0.0)) > 0.0:
			r["start_bonus"] = true
		r["preschool"] = false
	elif from_stage == "teen" and to_stage == "adult":
		var r2: Dictionary = EduState.rec(fid)
		var g: float = grade(fid)
		r2["grade_seen"] = g
		r2["diploma"] = letter(g)
		LifeNote.say("graduation", "%s finished school with a %s average." % [f.name, letter(g)], [fid], 2, true, "good")
		f.add_buff("cheered_up")
