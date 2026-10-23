class_name EduCollege
extends RefCounted
## The college (task 14): Fernwood College is a place in the school lot with evening and weekend lectures. A student picks one MAJOR, goes to
## lectures (one a day, a few coins each, a skill grows with every one), sits an exam every few lectures (a score from the skills behind the major,
## how rested they are and a little luck; a failed exam costs credits) and gets a DEGREE after `credits_needed` credits. A degree opens the better
## jobs of its careers (EduGate), adds a wage bonus, and goes to the chronicle. Townies study too (EduTownies, statistical).
## Tier: resident students: event driven (a lecture). Townies: one daily line each. Data: data/life/10_education.json (majors, config.education.college).

static func cc() -> Dictionary:
	return EduState.cfg().get("college", {})

static func major_def(major: String) -> Dictionary:
	return LifeDefs.get_in("majors", major)

static func major_label(major: String) -> String:
	return str(major_def(major).get("label", major.capitalize()))

static func letter_of_score(score: float) -> String:
	return CareerShifts.grade_letter(score)

## Plain-word reason this person cannot go to a lecture in `major` ("" = fine).
static func why_not(f, major: String) -> String:
	if major_def(major).is_empty():
		return "That subject is not taught here."
	var r: Dictionary = EduState.peek(int(f.id))
	if (r.get("degrees", []) as Array).has(major):
		return "%s already has a degree in %s." % [f.name, major_label(major)]
	var col: Dictionary = r.get("college", {})
	if not col.is_empty() and str(col.get("major", "")) != major and int(col.get("credits", 0)) > 0:
		return "%s is studying %s. Drop out first to change subject." % [f.name, major_label(str(col["major"]))]
	return ""

static func student(fid: int) -> Dictionary:
	return (EduState.peek(fid).get("college", {}) as Dictionary)

static func lecture(f, major: String) -> Dictionary:
	var fid: int = int(f.id)
	var r: Dictionary = EduState.rec(fid)
	var col: Dictionary = r["college"]
	if col.is_empty() or str(col.get("major", "")) != major:
		var start: int = int(cc().get("diploma_credits", 2)) if str(r.get("diploma", "")) in ["A", "B"] else 0
		start = maxi(start, int(round(Creation.add(fid, "college_credit") * float(cc().get("credits_needed", 12)))))          # task 62: the year a dropout did counts
		col = {"major": major, "credits": start, "lectures": 0, "scores": []}
		r["college"] = col
	col["credits"] = int(col["credits"]) + 1
	col["lectures"] = int(col["lectures"]) + 1
	var skills: Array = major_def(major).get("skills", [])
	if not skills.is_empty():
		f.add_skill_xp(str(skills[0]), 25.0)
	f.add_to_stat("fun", -6.0)
	var text := "%s learned something new in %s." % [f.name, major_label(major)]
	var done_exam: Dictionary = {}
	if int(col["lectures"]) % maxi(int(cc().get("exam_every", 4)), 1) == 0:
		done_exam = exam(f, major)
		text = str(done_exam["text"])
	if int(col["credits"]) >= int(cc().get("credits_needed", 12)):
		return graduate(f, major)
	return {"text": text, "credits": int(col["credits"]), "exam": done_exam}

## Score of an exam: base + skill levels + rest + luck (+ tutoring). Pass = credits stay, fail = credits are lost.
static func exam(f, major: String) -> Dictionary:
	var c: Dictionary = cc()
	var col: Dictionary = EduState.rec(int(f.id))["college"]
	var best := 0
	for s in major_def(major).get("skills", []):
		best = maxi(best, f.skill_level(str(s)))
	var rest: float = 4.0 if f.get_stat_value("energy") > 0.0 else -4.0
	var score: float = float(c.get("base_score", 38)) + float(c.get("skill_weight", 6)) * float(best) + rest + EduState.rng.randf() * float(c.get("spread", 26)) + float(col.get("tutor", 0.0))
	col["tutor"] = 0.0
	score = clampf(score, 0.0, 100.0)
	(col["scores"] as Array).append(score)
	var pass_ok: bool = score >= float(c.get("pass_score", 55))
	var text: String
	if pass_ok:
		text = "%s passed an exam in %s with a %s." % [f.name, major_label(major), letter_of_score(score)]
	else:
		col["credits"] = maxi(int(col["credits"]) - int(c.get("fail_credits", 2)), 0)
		text = "%s failed an exam in %s. Two lectures are lost, but there is always the next one." % [f.name, major_label(major)]
		f.add_to_stat("fun", -10.0)
	SysUtil.game_event("college_exam", {"folk_id": int(f.id), "major": major, "score": score, "passed": pass_ok})
	return {"score": score, "passed": pass_ok, "text": text}

static func graduate(f, major: String) -> Dictionary:
	var fid: int = int(f.id)
	var r: Dictionary = EduState.rec(fid)
	var scores: Array = (r["college"] as Dictionary).get("scores", [])
	var avg := 0.0
	for s in scores:
		avg += float(s)
	avg = avg / float(maxi(scores.size(), 1)) if not scores.is_empty() else 60.0
	r["college"] = {}
	if not (r["degrees"] as Array).has(major):
		(r["degrees"] as Array).append(major)
	var careers: Array = major_def(major).get("careers", [])
	var names: Array = careers.map(func(cid): return str(Careers.career_def(str(cid)).get("label", cid)))
	var text := "%s graduated from Fernwood College with a degree in %s (%s)." % [f.name, major_label(major), letter_of_score(avg)]
	LifeNote.say("graduation", text, [fid], 2, true, "good")
	if not names.is_empty():
		SysUtil.notify("A degree in %s opens better jobs: %s." % [major_label(major), ", ".join(names)], "career")
	f.add_buff("cheered_up")
	SysUtil.game_event("graduated", {"folk_id": fid, "major": major, "avg": avg})
	return {"text": text, "degree": major}

## Apply to the college for a major (a teen looking ahead, or a grown-up): kept on the education record. A later lecture of this major is what the person
## goes to first (PlaceAutoGate), and a diploma of A or B gives a head start in credits. Returns {ok, reason}.
static func apply(fid: int, major: String) -> Dictionary:
	var f = SysUtil.folk(fid)
	if f == null:
		return {"ok": false, "reason": "Nobody is applying."}
	if major_def(major).is_empty():
		return {"ok": false, "reason": "That subject is not taught here."}
	if not str(f.age_stage) in ["teen", "adult", "elder"]:
		return {"ok": false, "reason": "%s is too young to apply." % f.name}
	var r: Dictionary = EduState.rec(fid)
	if EduState.has_degree(fid, major):
		return {"ok": false, "reason": "%s already has a degree in %s." % [f.name, major_label(major)]}
	if str(r.get("applied", "")) == major:
		return {"ok": false, "reason": "%s has already applied for %s." % [f.name, major_label(major)]}
	r["applied"] = major
	LifeNote.say("college_apply", "%s applied to Fernwood College to study %s." % [f.name, major_label(major)], [fid], 1, false)
	SysUtil.game_event("college_applied", {"folk_id": fid, "major": major})
	return {"ok": true, "reason": ""}

## Give up the course: the credits are lost (the degrees already earned stay).
static func drop(fid: int) -> bool:
	var r: Dictionary = EduState.peek(fid)
	if r.is_empty() or (r.get("college", {}) as Dictionary).is_empty():
		return false
	r["college"] = {}
	return true

## Student summary for the UI: {major, label, credits, needed, avg_letter} or {}.
static func summary(fid: int) -> Dictionary:
	var col: Dictionary = student(fid)
	if col.is_empty():
		return {}
	var scores: Array = col.get("scores", [])
	var avg := 0.0
	for s in scores:
		avg += float(s)
	return {"major": col["major"], "label": major_label(str(col["major"])), "credits": int(col["credits"]), "needed": int(cc().get("credits_needed", 12)),
		"letter": "-" if scores.is_empty() else letter_of_score(avg / float(scores.size()))}
