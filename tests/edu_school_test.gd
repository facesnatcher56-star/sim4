extends RefCounted
## Task 14 education, part 1: homework, report cards, school events, preschool, graduation.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_homework(f)
	_report_cards(f)
	_events(f)
	_preschool(f)
	_graduation(f)
	return f

## Ann (adult) and Kit (child, enrolled in school), coins 500, townies, the life areas on.
func _world() -> Array:
	var w := K.setup()
	K.make_folk(w, "Ann")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid, 25.6)
	WorldIface.coins[1] = 500
	Story.generate_townies(12)
	K.set_time(1, 6)
	Careers.on_day(1)
	LifeTick.new_game()
	LifeDefs.ensure()
	LifeDefs.config["education"]["homework"]["set_chance"] = 1.0
	return [w, kid]

func _homework(f: Array) -> void:
	var kid: Folk = _world()[1]
	var id: int = int(kid.id)
	var g0: float = CareerShifts.grade_of(id)
	K.set_time(1, 15)
	LifeTick.on_game_event("returned_from_school", {"folk_id": id, "skipped": false})
	K.expect(f, EduSchool.homework_due(id) and K.has_note("homework"), "after school the teacher sets homework")
	LifeTick.on_interaction_finished(id, "do_homework", true)
	K.expect(f, not EduSchool.homework_due(id) and CareerShifts.grade_of(id) > g0, "handing it in raises the grade (%.1f -> %.1f)" % [g0, CareerShifts.grade_of(id)])
	# not handed in: the next school day costs grade and the teacher notices
	K.set_time(2, 15)
	LifeTick.on_game_event("returned_from_school", {"folk_id": id, "skipped": false})
	var g1: float = CareerShifts.grade_of(id)
	K.set_time(3, 15)
	LifeTick.on_game_event("returned_from_school", {"folk_id": id, "skipped": false})
	K.expect(f, CareerShifts.grade_of(id) < g1 and K.has_note("did not hand in"), "missing homework costs grade (%.1f -> %.1f)" % [g1, CareerShifts.grade_of(id)])
	K.expect(f, int(EduState.rec(id)["hw"]["missed"]) == 1, "and is counted")
	# a skipped day sets nothing
	EduState.rec(id)["hw"]["due"] = false
	LifeTick.on_game_event("returned_from_school", {"folk_id": id, "skipped": true})
	K.expect(f, not EduSchool.homework_due(id), "a skipped school day sets no homework")
	K.teardown()

func _report_cards(f: Array) -> void:
	var kid: Folk = _world()[1]
	var id: int = int(kid.id)
	kid.skills["painting"] = {"xp": 0.0, "level": 6}
	kid.skills["fitness"] = {"xp": 0.0, "level": 0}
	Careers.school[id]["grade"] = 80.0
	var sg: Dictionary = EduSchool.subject_grades(id)
	K.expect(f, float(sg["Art"]) > float(sg["Sport"]) + 20.0, "a gifted painter has better art than sport (%d vs %d)" % [sg["Art"], sg["Sport"]])
	K.set_time(15, 8)                              # the second term starts on a Monday
	LifeTick.on_day(15)
	var reps: Array = EduState.rec(id)["reports"]
	K.expect(f, reps.size() == 1 and str(reps[0]["letter"]) in ["A", "B", "C", "D", "F"] and str(reps[0]["comment"]) != "", "a report card with a letter and a comment arrives each term")
	K.expect(f, str(reps[0]["teacher"]) == PlaceStaff.who("school", "teacher") and K.has_note("report card"), "it names the teacher and reaches the household")
	LifeTick.on_day(16)
	K.expect(f, (EduState.rec(id)["reports"] as Array).size() == 1, "only one per term")
	# honour roll and concern go to the town chronicle
	Careers.school[id]["grade"] = 100.0
	kid.skills["painting"] = {"xp": 0.0, "level": 8}
	kid.skills["fitness"] = {"xp": 0.0, "level": 8}
	kid.skills["logic"] = {"xp": 0.0, "level": 8}
	kid.skills["writing"] = {"xp": 0.0, "level": 8}
	K.set_time(29, 8)
	LifeTick.on_day(29)
	var kinds: Array = ChronicleHook.recent.map(func(p): return str(p["kind"]))
	K.expect(f, kinds.has("honour_roll"), "top marks make the honour roll")
	Careers.school[id]["grade"] = 20.0
	for s in ["painting", "fitness", "logic", "writing"]:
		kid.skills[s] = {"xp": 0.0, "level": 0}
	K.set_time(43, 8)
	LifeTick.on_day(43)
	kinds = ChronicleHook.recent.map(func(p): return str(p["kind"]))
	K.expect(f, kinds.has("school_concern"), "very low marks tell the household the teachers want a word")
	K.teardown()

func _events(f: Array) -> void:
	var kid: Folk = _world()[1]
	var id: int = int(kid.id)
	kid.skills["logic"] = {"xp": 0.0, "level": 10}
	kid.skills["fitness"] = {"xp": 0.0, "level": 10}
	Careers.school[id]["grade"] = 100.0
	K.set_time(7, 8)                               # calendar day 6 is a Sunday: the fair waits for Monday
	LifeTick.on_day(7)
	K.expect(f, not EduState.fired.has("science_fair"), "no school event on a weekend")
	K.set_time(8, 8)
	LifeTick.on_day(8)
	K.expect(f, int(EduState.fired.get("science_fair", -1)) == 1, "the science fair runs on the next school day")
	var kinds: Array = ChronicleHook.recent.map(func(p): return str(p["kind"]))
	K.expect(f, kinds.has("school_event") and K.has_note("science fair"), "a clever child wins a prize and it is in the chronicle")
	var n: int = ChronicleHook.recent.size()
	LifeTick.on_day(9)
	var news: int = ChronicleHook.recent.filter(func(p): return str(p["text"]).find("science fair is today") >= 0).size()
	K.expect(f, news == 1, "it does not run twice in a year (%d)" % news)
	K.set_time(25, 8)
	LifeTick.on_day(25)
	K.expect(f, K.has_note("Parents' evening"), "parents' evening tells the household how the child is doing")
	K.set_time(36, 8)                              # the next year, a Monday
	EduState.fired["science_fair"] = 1
	LifeTick.on_day(36)
	K.expect(f, int(EduState.fired.get("science_fair", -1)) == 2, "and it comes round again next year")
	K.teardown()

func _preschool(f: Array) -> void:
	var w: StubWorld = _world()[0]
	var tia := K.make_folk(w, "Tia", [], 1, Vector2i(15, 12), "toddler")
	Aging.set_age_days(tia, 10.0)
	K.set_time(1, 10)
	var r: Dictionary = PlaceUse.use(int(tia.id), "preschool", "preschool_enrol", {"instant": true})
	K.expect(f, bool(r["ok"]) and bool(EduState.rec(int(tia.id))["preschool"]), "a toddler can be enrolled (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(int(tia.id), "preschool", "preschool_enrol") != "", "not twice")
	var coins: int = Economy.balance(1)
	var soc: float = tia.get_stat_value("social")
	for d in range(1, 11):
		if CareerShifts.is_school_day(d):
			K.set_time(d, 8)
			LifeTick.on_day(d)
	K.expect(f, Economy.balance(1) < coins and float(EduState.rec(int(tia.id))["early"]) >= 7.0, "school mornings cost a small fee and build early learning (%.0f)" % float(EduState.rec(int(tia.id))["early"]))
	# starting school: a head start
	Aging.set_age_days(tia, 25.6)
	LifeTick.on_game_event("aged_up", {"folk_id": int(tia.id), "from": "toddler", "to": "child"})
	var g0: float = CareerShifts.grade_of(int(tia.id))
	K.set_time(15, 8)
	LifeTick.on_day(15)
	K.expect(f, CareerShifts.grade_of(int(tia.id)) > g0 and K.has_note("head start"), "preschool gives a head start at school (%.1f -> %.1f)" % [g0, CareerShifts.grade_of(int(tia.id))])
	# unpaid fees end it
	var tom := K.make_folk(w, "Tom", [], 1, Vector2i(16, 12), "toddler")
	Aging.set_age_days(tom, 10.0)
	EduSchool.enrol_preschool(int(tom.id), true)
	WorldIface.coins[1] = 0
	K.set_time(16, 8)
	LifeTick.on_day(16)
	K.expect(f, not bool(EduState.rec(int(tom.id))["preschool"]) and K.has_note("fees"), "unpaid fees end preschool")
	K.teardown()

func _graduation(f: Array) -> void:
	var kid: Folk = _world()[1]
	var id: int = int(kid.id)
	Careers.school[id]["grade"] = 93.0
	LifeTick.on_game_event("aged_up", {"folk_id": id, "from": "teen", "to": "adult"})
	K.expect(f, EduState.rec(id)["diploma"] == "A" and K.has_note("finished school"), "a teen grows up with a diploma (%s)" % str(EduState.rec(id)["diploma"]))
	var kinds: Array = ChronicleHook.recent.map(func(p): return str(p["kind"]))
	K.expect(f, kinds.has("graduation"), "graduation is in the chronicle")
	K.teardown()
