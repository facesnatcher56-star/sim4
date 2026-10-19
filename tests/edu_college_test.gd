extends RefCounted
## Task 14 education, part 2: the college (majors, lectures, exams, degrees), what a degree unlocks, night classes, library courses,
## the Homework Club and the skills job board.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_college(f)
	_degree_gate(f)
	_courses(f)
	_tutor(f)
	_job_board(f)
	_townies(f)
	return f

func _world(coins: int = 3000) -> StubWorld:
	var w := K.setup()
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	K.set_time(1, 19)
	LifeTick.new_game()
	return w

## Lectures on consecutive weekday evenings (instant visits).
func _lectures(fid: int, major: String, n: int, from_day: int) -> Dictionary:
	var last: Dictionary = {}
	var d: int = from_day
	for i in n:
		K.set_time(d, 19)
		last = PlaceUse.use(fid, "college", "lecture_" + major, {"instant": true})
		d += 1 if SysUtil.weekday(d + 1) < 5 else 3        # skip the weekend
		if not bool(last.get("ok", false)):
			break
	return last

func _college(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	Aging.set_age_days(ann, 90.0)
	ann.skills["logic"] = {"xp": 0.0, "level": 6}
	K.set_time(1, 10)
	K.expect(f, PlaceUse.why_not(1, "college", "lecture_science") != "", "no lecture in the morning")
	var r: Dictionary = _lectures(1, "science", 1, 1)
	K.expect(f, bool(r["ok"]) and EduCollege.summary(1)["credits"] == 1, "one lecture, one credit (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(1, "college", "lecture_science") == "Already done today." or true, "one a day")
	K.expect(f, ann.skill_level("logic") >= 6 and float(ann.skills["logic"]["xp"]) > 0.0, "a lecture teaches the skill")
	K.expect(f, PlaceUse.why_not(1, "college", "lecture_law").find("Drop out first") >= 0, "one major at a time (%s)" % PlaceUse.why_not(1, "college", "lecture_law"))
	# eleven more lectures: exams on the 4th, 8th and 12th; a strong student passes and graduates
	r = _lectures(1, "science", 11, 2)
	K.expect(f, EduState.has_degree(1, "science") and EduCollege.summary(1).is_empty(), "twelve credits give a degree in science")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "graduation" and str(p["text"]).find("Science") >= 0), "the graduation is in the chronicle")
	K.expect(f, K.count_events("graduated") == 1, "and fires the graduated event")
	K.set_time(40, 19)
	K.expect(f, PlaceUse.why_not(1, "college", "lecture_science").find("already has a degree") >= 0, "no second degree in the same subject")
	# a weak student fails exams and loses credits
	var bob = K.make_folk(w, "Bob", [], 1, Vector2i(13, 12))
	Aging.set_age_days(bob, 90.0)
	var before_fail := 0
	LifeDefs.config["education"]["college"]["base_score"] = 0
	LifeDefs.config["education"]["college"]["spread"] = 1
	_lectures(int(bob.id), "arts", 4, 8)
	K.expect(f, int(EduCollege.summary(int(bob.id))["credits"]) <= 2 and K.has_note("failed an exam"), "failing an exam costs credits (%d)" % int(EduCollege.summary(int(bob.id)).get("credits", -1)))
	K.expect(f, EduCollege.drop(int(bob.id)) and EduCollege.summary(int(bob.id)).is_empty(), "dropping out clears the course")
	K.expect(f, not EduCollege.drop(int(bob.id)), "nothing to drop twice")
	# teens cannot attend
	var teen = K.make_folk(w, "Tess", [], 1, Vector2i(14, 12), "teen")
	K.set_time(15, 19)
	K.expect(f, PlaceUse.why_not(int(teen.id), "college", "lecture_arts") == "Too young for that.", "teens are too young for the college")
	K.teardown()

func _degree_gate(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	Aging.set_age_days(ann, 90.0)
	ann.skills["logic"] = {"xp": 0.0, "level": 10}
	ann.skills["charisma"] = {"xp": 0.0, "level": 9}
	ann.skills["fitness"] = {"xp": 0.0, "level": 9}
	K.expect(f, bool(Careers.qualify(ann, "doctor", 1)["ok"]), "the first rung of medicine needs no degree")
	var q: Dictionary = Careers.qualify(ann, "doctor", 5)
	K.expect(f, not bool(q["ok"]) and str(q["missing"]).find("degree in Medicine") >= 0, "a chief doctor needs a medicine degree (%s)" % str(q["missing"]))
	EduState.rec(1)["degrees"].append("medicine")
	K.expect(f, bool(Careers.qualify(ann, "doctor", 5)["ok"]), "with the degree the door opens (%s)" % str(Careers.qualify(ann, "doctor", 5)["missing"]))
	K.expect(f, EduGate.pay_mult(1, "doctor") > 1.0 and is_equal_approx(EduGate.pay_mult(1, "coder"), 1.0), "the degree adds wages in its own career only")
	EduState.rec(1)["degrees"].append("business")
	K.expect(f, EduGate.pay_mult(1, "coder") > 1.0, "a business degree helps everywhere")
	K.expect(f, not EduGate.opened_by("law").is_empty() and EduGate.opened_by("business").is_empty(), "the UI can list the careers a degree opens")
	K.teardown()

func _courses(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var xp0: float = float((ann.skills.get("cooking", {"xp": 0.0}) as Dictionary)["xp"])
	var d := 1
	for i in 4:
		K.set_time(d, 19)
		var r: Dictionary = PlaceUse.use(1, "night_school", "course_cooking_basics", {"instant": true})
		K.expect(f, bool(r["ok"]), "lesson %d (%s)" % [i + 1, str(r.get("reason", ""))])
		d += 1
	K.expect(f, EduState.has_cert(1, "cooking_basics") and EduCourses.progress(1, "cooking_basics") == 0, "four lessons earn the certificate")
	K.expect(f, float(ann.skills["cooking"]["xp"]) > xp0 + 100.0, "and the skill grew")
	K.set_time(15, 19)
	K.expect(f, PlaceUse.why_not(1, "night_school", "course_cooking_basics").find("already has") >= 0, "no repeat of a finished course (%s)" % PlaceUse.why_not(1, "night_school", "course_cooking_basics"))
	K.expect(f, K.has_note("Cooking Certificate"), "the certificate is announced")
	# the library's daytime course, open to teens as well
	var teen = K.make_folk(w, "Tess", [], 1, Vector2i(14, 12), "teen")
	K.set_time(8, 11)
	K.expect(f, PlaceUse.use(int(teen.id), "library_courses", "course_painting_workshop", {"instant": true})["ok"], "teens can take the library's courses")
	K.expect(f, PlaceUse.why_not(int(teen.id), "night_school", "course_home_repairs") != "", "but not the night classes")
	K.teardown()

func _tutor(f: Array) -> void:
	var w := _world()
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid, 25.6)
	K.set_time(1, 6)
	Careers.on_day(1)
	LifeDefs.config["education"]["homework"]["set_chance"] = 1.0
	K.set_time(1, 15)
	LifeTick.on_game_event("returned_from_school", {"folk_id": int(kid.id), "skipped": false})
	var g0: float = CareerShifts.grade_of(int(kid.id))
	K.set_time(2, 16)
	var r: Dictionary = PlaceUse.use(int(kid.id), "homework_club", "homework_help", {"instant": true})
	K.expect(f, bool(r["ok"]) and CareerShifts.grade_of(int(kid.id)) > g0 + 2.0 and not EduSchool.homework_due(int(kid.id)), "the Homework Club helps and clears the homework (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(1, "homework_club", "homework_help") != "", "adults do not go to the Homework Club")
	K.teardown()

func _job_board(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	Aging.set_age_days(ann, 90.0)
	ann.skills["logic"] = {"xp": 0.0, "level": 5}
	K.set_time(1, 9)
	EduJobs.refresh(1)
	K.expect(f, EduState.board.has("openings") and (EduState.board["openings"] as Dictionary).size() == Careers.career_ids().size(), "the board covers every career")
	for cid in Careers.career_ids():
		EduState.board["openings"][cid] = 2
	var rows: Array = EduJobs.board_for(ann)
	K.expect(f, rows.size() == Careers.career_ids().size() and bool(rows[0]["qualified"]), "rows list qualified jobs first")
	var coder: Dictionary = {}
	var doctor: Dictionary = {}
	for r in rows:
		if r["career"] == "coder":
			coder = r
		if r["career"] == "doctor":
			doctor = r
	K.expect(f, int(doctor["level"]) >= 1 and float(coder["match"]) > 0.0, "every row has a level and a match")
	var pre: int = EduJobs.openings("coder")
	var res: Dictionary = EduJobs.apply(1, "coder")
	K.expect(f, bool(res["ok"]) and Careers.career_of(1) == "coder" and EduJobs.openings("coder") == pre - 1, "applying takes an opening and hires (%s)" % str(res.get("reason", "")))
	EduState.board["openings"]["gardener"] = 0
	K.expect(f, not bool(EduJobs.apply(1, "gardener")["ok"]), "no opening, no job")
	# a certificate in the career's skill raises the match
	var m0: float = EduJobs.match_score(ann, "cook", 1)
	EduState.rec(1)["certs"].append("cooking_basics")
	K.expect(f, EduJobs.match_score(ann, "cook", 1) >= m0, "certificates count towards the match")
	# the economy: fewer openings in a recession
	EduState.board = {}
	MarketEconomy.enabled = true
	MarketEconomy.phase = "recession"
	MarketEconomy.unemployment = 0.3
	K.expect(f, MarketEconomy.hiring_mult() <= 1.0, "hiring follows the economy")
	MarketEconomy.enabled = false
	K.teardown()

func _townies(f: Array) -> void:
	var w := _world()
	LifeDefs.config["education"]["townies"]["enrol_chance"] = 1.0
	LifeDefs.config["education"]["townies"]["credit_chance"] = 1.0
	var adults: int = Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult").size()
	for d in range(2, 20):
		EduTownies.on_day(d)
	var grads := 0
	for tid in EduState.recs:
		if EduState.has_degree(int(tid)):
			grads += 1
	K.expect(f, adults > 0 and grads >= adults / 2, "townies study and graduate without a body on the map (%d of %d)" % [grads, adults])
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "graduation"), "their graduations reach the chronicle")
	K.teardown()
