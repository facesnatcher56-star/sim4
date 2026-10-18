extends RefCounted
## Extra careers: data shape (levels, branches, tasks, shift variants, requirements), branch choice at the fork,
## daily tasks, overnight shifts in a real clock run, and promotion cadence for every career.

const K = preload("res://tests/systems_kit.gd")
const CK = preload("res://tests/content_kit.gd")

const NEW_CAREERS := ["musician", "gardener", "handyperson", "scientist", "writer", "barista", "doctor", "athlete", "teacher", "chef"]

func run() -> Array:
	var f: Array = []
	_data(f)
	_requirements(f)
	_branches(f)
	_tasks(f)
	_night_shift(f)
	_cadence(f)
	_legacy_behaviour(f)
	return f

func _data(f: Array) -> void:
	var w := K.setup()
	var c: Dictionary = SimEnv.data().get_table("careers")
	var cs: Dictionary = c["careers"]
	var ints: Dictionary = SimEnv.data().interactions()
	var buffs: Dictionary = SimEnv.data().buffs()
	var skills := CK.known_skills()
	K.expect(f, cs.size() >= 14, "at least 14 careers (4 original + 10 new), found %d" % cs.size())
	var with_night := 0
	for cid in NEW_CAREERS:
		K.expect(f, cs.has(cid), "career %s missing" % cid)
	for cid in cs:
		var cd: Dictionary = cs[cid]
		var lv: Array = cd["levels"]
		K.expect(f, lv.size() == 5, "%s trunk has 5 levels" % cid)
		K.expect(f, skills.has(str(cd["primary_skill"])), "%s primary skill unknown" % cid)
		for s in cd.get("alt_skills", []):
			K.expect(f, skills.has(str(s)), "%s alt skill %s unknown" % [cid, s])
		var prev := 0
		for l in lv:
			K.expect(f, int(l["pay"]) > prev, "%s trunk pay rises" % cid)
			prev = int(l["pay"])
			K.expect(f, float(l["end"]) > float(l["start"]), "%s trunk shift end after start" % cid)
			_req_ok(f, "%s trunk" % cid, l.get("requires", {}), skills)
		for iid in cd.get("hooks", {}):
			K.expect(f, ints.has(iid), "%s hook %s is not an interaction" % [cid, iid])
		K.expect(f, str(cd.get("description", "")) != "" and not (cd.get("tasks", []) as Array).is_empty(), "%s needs flavour text and daily tasks" % cid)
		var task_ids: Dictionary = {}
		for t in cd.get("tasks", []):
			K.expect(f, not task_ids.has(t["id"]), "%s duplicate task id %s" % [cid, t["id"]])
			task_ids[t["id"]] = true
			K.expect(f, int(t.get("count", 1)) >= 1 and float(t.get("bonus", 0)) > 0.0, "%s task %s count/bonus" % [cid, t["id"]])
			for iid2 in t["interactions"]:
				K.expect(f, ints.has(iid2), "%s task %s: unknown interaction %s" % [cid, t["id"], iid2])
		var brs: Dictionary = cd.get("branches", {})
		for bid in brs:
			var br: Dictionary = brs[bid]
			var from_lv: int = int(br["from_level"])
			K.expect(f, from_lv == 3 or from_lv == 4, "%s/%s branches at level 3-4" % [cid, bid])
			K.expect(f, (br["levels"] as Array).size() >= 2 and (br["levels"] as Array).size() + from_lv - 1 <= 10, "%s/%s has 2+ levels, total <= 10" % [cid, bid])
			var prev_pay: int = int(lv[from_lv - 2]["pay"])
			for bl in br["levels"]:
				K.expect(f, int(bl["pay"]) > prev_pay, "%s/%s pay rises from the trunk" % [cid, bid])
				prev_pay = int(bl["pay"])
				_req_ok(f, "%s/%s" % [cid, bid], bl.get("requires", {}), skills)
				K.expect(f, str(bl["title"]) != "", "%s/%s title" % [cid, bid])
		var shifts: Dictionary = cd.get("shifts", {})
		for sid in shifts:
			var sv: Dictionary = shifts[sid]
			K.expect(f, float(sv["pay_mult"]) > 1.0 and float(sv["start"]) != float(sv["end"]), "%s shift %s hours/pay" % [cid, sid])
			if str(sv.get("return_buff", "")) != "":
				K.expect(f, buffs.has(str(sv["return_buff"])), "%s shift %s return_buff unknown" % [cid, sid])
			if float(sv["end"]) <= float(sv["start"]):
				with_night += 1
	for cid2 in NEW_CAREERS:
		K.expect(f, (cs[cid2].get("branches", {}) as Dictionary).size() >= 2, "%s has two branches" % cid2)
		K.expect(f, int(Careers.max_level(cid2)) == 5, "%s trunk max level" % cid2)
	K.expect(f, with_night >= 5, "at least 5 careers offer an overnight shift, found %d" % with_night)
	K.expect(f, Careers.max_level("musician", "solo") == 6 and Careers.max_level("scientist", "inventor") == 6, "branch max_level counts the fork")
	K.teardown()
	_legacy_ids(f)

func _legacy_ids(f: Array) -> void:
	var legacy: Dictionary = CK.read_json("res://tests/content_legacy_ids.json")
	var w := K.setup()
	for cid in legacy["careers"]:
		K.expect(f, Careers.career_def(str(cid)).get("levels", []).size() == 5, "legacy career %s keeps its 5 levels" % cid)
	K.teardown()

func _req_ok(f: Array, where: String, req: Dictionary, skills: Array) -> void:
	for s in req.get("skills", {}):
		K.expect(f, skills.has(str(s)), "%s requires unknown skill %s" % [where, s])
	for s2 in req.get("skills_any", {}):
		K.expect(f, skills.has(str(s2)), "%s requires unknown skill %s" % [where, s2])
	for t in req.get("traits_any", []) + req.get("traits_not", []):
		K.expect(f, SimEnv.data().traits().has(str(t)), "%s requires unknown trait %s" % [where, t])

func _requirements(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	K.expect(f, not bool(Careers.qualify(a, "doctor", 1)["ok"]), "doctor needs logic 2 to start")
	a.add_skill_xp("logic", Folk.xp_for_level(2) + 1)
	K.expect(f, bool(Careers.qualify(a, "doctor", 1)["ok"]), "logic 2 qualifies as a medical aide")
	var lazy := K.make_folk(w, "Lou", ["lazy"])
	lazy.add_skill_xp("fitness", Folk.xp_for_level(4) + 1)
	K.expect(f, not bool(Careers.qualify(lazy, "athlete", 3)["ok"]) and "not lazy" in Careers.qualify(lazy, "athlete", 3)["missing"], "lazy folk cannot go pro (trait requirement)")
	var fit := K.make_folk(w, "Fit")
	fit.add_skill_xp("fitness", Folk.xp_for_level(4) + 1)
	K.expect(f, bool(Careers.qualify(fit, "athlete", 3)["ok"]), "non-lazy athlete qualifies")
	# skills_any via a temporary requirement
	var cd: Dictionary = Careers.career_def("musician")
	var req: Dictionary = (cd["levels"][1] as Dictionary)["requires"]
	var saved: Dictionary = req.duplicate(true)
	req.clear()
	req["skills_any"] = {"guitar": 2, "piano": 2}
	var m := K.make_folk(w, "Mia")
	K.expect(f, not bool(Careers.qualify(m, "musician", 2)["ok"]), "skills_any: none of the skills")
	m.add_skill_xp("piano", Folk.xp_for_level(2) + 1)
	K.expect(f, bool(Careers.qualify(m, "musician", 2)["ok"]), "skills_any: piano alone is enough")
	req.clear()
	for k in saved:
		req[k] = saved[k]
	# offers never hand out a career whose entry level the folk cannot meet
	var novice := K.make_folk(w, "Nova")
	for i in 30:
		var o: Dictionary = Careers.make_offer(novice)
		K.expect(f, not o.is_empty() and bool(Careers.qualify(novice, str(o["career"]), 1)["ok"]), "offers respect entry requirements (%s)" % str(o.get("career", "")))
		Careers.decline_offer(int(novice.id))
	# alt skills count for performance
	var pm := K.make_folk(w, "Pia")
	pm.add_skill_xp("piano", Folk.xp_for_level(6) + 1)
	K.expect(f, Careers.skill_for(pm, "musician") == 6, "musician skill is the best of guitar/piano")
	K.teardown()

func _skilled(w, name: String, skill_levels: Dictionary, traits: Array = []) -> Folk:
	var f := K.make_folk(w, name, traits)
	for s in skill_levels:
		f.add_skill_xp(str(s), Folk.xp_for_level(int(skill_levels[s])) + 1)
	return f

func _branches(f: Array) -> void:
	var w := K.setup()
	var a := _skilled(w, "Ann", {"guitar": 8, "charisma": 4}, ["showoff"])
	Careers.hire(a, "musician", 3)
	var fid := int(a.id)
	K.expect(f, CareerProgress.set_branch_preference(a, "solo"), "branch preference can be set before the fork")
	CareerProgress.add_performance(fid, 200.0)
	K.expect(f, Careers.level_of(fid) == 4 and Careers.branch_of(fid) == "solo", "promotion into level 4 takes the chosen branch")
	K.expect(f, Careers.title_of(fid) == "Solo Artist", "title follows the branch (%s)" % Careers.title_of(fid))
	K.expect(f, K.count_events("branch_chosen") == 1 and K.has_note("Solo Artist"), "branch choice is announced")
	var info: Dictionary = Careers.info_for(fid)
	K.expect(f, str(info["branch"]) == "solo" and int(info["max_level"]) == 6 and (info["tasks"] as Array).size() >= 1, "info_for exposes branch, max level and tasks")
	K.expect(f, not CareerProgress.set_branch_preference(a, "composer"), "cannot change branch after the fork")
	# next level inside the branch needs its own requirements
	CareerProgress.add_performance(fid, 200.0)
	K.expect(f, Careers.level_of(fid) == 5 and Careers.title_of(fid) == "Arena Act", "branch level 5 reached with guitar 8 (%s)" % Careers.title_of(fid))
	CareerProgress.add_performance(fid, 200.0)
	K.expect(f, Careers.level_of(fid) == 5, "level 6 'Living Legend' needs guitar 9 and charisma 3")
	# auto-pick follows traits when no preference is set
	var b := _skilled(w, "Bea", {"gardening": 8, "painting": 3, "logic": 4}, ["creative"])
	Careers.hire(b, "gardener", 3)
	CareerProgress.add_performance(int(b.id), 200.0)
	K.expect(f, Careers.level_of(int(b.id)) == 4 and Careers.branch_of(int(b.id)) == "landscape", "creative gardener drifts to landscape design, got '%s'" % Careers.branch_of(int(b.id)))
	var c := _skilled(w, "Cal", {"gardening": 6}, [])
	Careers.hire(c, "gardener", 3)
	CareerProgress.add_performance(int(c.id), 200.0)
	K.expect(f, Careers.level_of(int(c.id)) == 4 and Careers.branch_of(int(c.id)) == "", "a folk who only meets the generalist track stays on the trunk")
	# demotion below the fork resets the branch
	CareerProgress.add_performance(fid, -300.0, true)
	CareerProgress.add_performance(fid, -300.0, true)
	K.expect(f, Careers.level_of(fid) <= 4, "demotions walk back down the branch")
	# save/load keeps branch & shift & task state
	var d1: Dictionary = Careers.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	Careers.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1, Careers.to_dict(), "careers", diffs), "careers with branches round-trip: %s" % str(diffs.slice(0, 4)))
	K.teardown()

func _tasks(f: Array) -> void:
	var w := K.setup()
	var g := _skilled(w, "Gus", {"gardening": 2})
	Careers.hire(g, "gardener", 1)
	var fid := int(g.id)
	K.set_time(3, 12)
	var tasks: Array = CareerProgress.tasks_for(fid)
	K.expect(f, tasks.size() == 1 and not bool(tasks[0]["done"]), "level 1 gardener sees the tend-the-beds task only (%d)" % tasks.size())
	var p0: float = CareerProgress.performance_of(fid)
	CareerProgress.on_interaction(fid, "water_garden", true)
	K.expect(f, K.count_events("daily_task_done") == 1, "daily_task_done fires")
	var gain: float = CareerProgress.performance_of(fid) - p0
	K.expect(f, gain >= 2.0 + 5.0 - 0.01, "task bonus stacks on the hook gain (%.1f)" % gain)
	var p1: float = CareerProgress.performance_of(fid)
	CareerProgress.on_interaction(fid, "water_garden", true)
	K.expect(f, K.count_events("daily_task_done") == 1 and CareerProgress.performance_of(fid) - p1 < 3.0, "a task pays only once per day")
	K.expect(f, g.has_buff("on_a_roll"), "finishing a task gives On a Roll")
	K.set_time(4, 12)
	CareerProgress.on_interaction(fid, "water_garden", true)
	K.expect(f, K.count_events("daily_task_done") == 2, "tasks reset the next day")
	# min_level gating and multi-count tasks
	var cs := _skilled(w, "Cass", {"cooking": 2}, [])
	Careers.hire(cs, "barista", 2)
	K.expect(f, (CareerProgress.tasks_for(int(cs.id)) as Array).size() == 2, "barista level 2 unlocks the conversation task")
	CareerProgress.on_interaction(int(cs.id), "chat", true)
	K.expect(f, not bool(CareerProgress.tasks_for(int(cs.id))[1]["done"]) and int(CareerProgress.tasks_for(int(cs.id))[1]["progress"]) == 1, "multi-count task keeps progress")
	CareerProgress.on_interaction(int(cs.id), "tell_joke", true)
	K.expect(f, bool(CareerProgress.tasks_for(int(cs.id))[1]["done"]), "second conversation completes it")
	K.teardown()

func _night_shift(f: Array) -> void:
	var w := K.setup()
	var dr := _skilled(w, "Doc", {"logic": 6, "charisma": 3})
	Careers.hire(dr, "doctor", 2)
	var fid := int(dr.id)
	var nobody := K.make_folk(w, "Nobody")
	K.expect(f, not CareerProgress.set_shift(nobody, "er_night"), "folk without a job cannot take a shift")
	K.expect(f, CareerProgress.set_shift(dr, "er_night") and dr.work_start == 20.0 and dr.work_end == 6.0, "ER night shift sets overnight hours (%.0f-%.0f)" % [dr.work_start, dr.work_end])
	K.expect(f, not CareerProgress.set_shift(dr, "nonexistent"), "unknown shift refused")
	WorldIface.coins[1] = 0
	var dir = K.director()
	K.set_time(1, 19, 45)        # Monday evening
	K.run(dir, 10)
	K.expect(f, not SysUtil.is_away(dr), "still home at 19:55")
	K.run(dir, 10)
	K.expect(f, K.count_events("left_for_work") == 1 and SysUtil.is_away(dr), "leaves for the night shift at 20:00")
	var ev: Dictionary = K.last_event("left_for_work")
	K.expect(f, float(ev.get("shift_end", -1.0)) == 6.0, "shift_end reports 06:00")
	K.run(dir, 5 * 60)
	K.expect(f, SysUtil.is_away(dr) and SysUtil.hour_f() >= 1.0 and SysUtil.hour_f() < 2.0, "still at work after midnight (hour %.1f)" % SysUtil.hour_f())
	K.run(dir, 5 * 60)
	K.expect(f, not SysUtil.is_away(dr) and K.count_events("returned_from_work") == 1, "back home after 06:00")
	var r: Dictionary = K.last_event("returned_from_work")
	var pay: int = int(r.get("pay", 0))
	var base_pay: float = 10.0 * float(Careers.level_def("doctor", 2)["pay"]) * CareerProgress.pay_multiplier(CareerProgress.performance_of(fid) - float(r.get("delta", 0.0)))
	K.expect(f, float(pay) > base_pay * 1.2 and float(pay) < base_pay * 1.5, "night pay carries the 1.35x premium (%d vs %.0f base)" % [pay, base_pay])
	K.expect(f, dr.has_buff("post_night_shift"), "night workers come home groggy")
	K.expect(f, not bool(r.get("skipped", true)), "a full overnight shift is not 'skipped'")
	# no second departure that same night
	K.run(dir, 60)
	K.expect(f, K.count_events("left_for_work") == 1, "one shift per working day")
	# day variant unaffected
	K.expect(f, CareerProgress.set_shift(dr, "day") and dr.work_start == 8.0 and dr.work_end == 16.0, "switching back restores the day hours")
	K.expect(f, CareerShifts.in_shift_window(23.0, 22.0, 6.0) and not CareerShifts.in_shift_window(3.0, 22.0, 6.0) and CareerShifts.in_shift_window(10.0, 9.0, 17.0) and not CareerShifts.in_shift_window(17.5, 9.0, 17.0), "in_shift_window handles day and overnight windows")
	K.teardown()

## Every new career: with the needed skills, promotion happens on a predictable schedule (a few shifts per level).
func _cadence(f: Array) -> void:
	for cid in NEW_CAREERS + ["cook", "coder", "painter", "fitness_coach"]:
		var w := K.setup(1000 + cid.length())
		var cd: Dictionary = Careers.career_def(cid)
		var a := K.make_folk(w, "Pro")
		for s in [str(cd["primary_skill"])] + (cd.get("alt_skills", []) as Array) + ["charisma", "logic", "cooking", "handiness", "gardening", "painting", "fitness", "writing"]:
			a.add_skill_xp(s, Folk.xp_for_level(10) + 1)
		var fid := int(a.id)
		Careers.hire(a, cid, 1)
		var shifts := 0
		var last_level := 1
		var level_shifts: Array = []
		var day := 1
		var guard := 0
		while Careers.level_of(fid) < 5 and guard < 120:
			guard += 1
			day += 1
			K.set_time(day, 12)
			# first task of the day done at home, then a full shift
			var tasks: Array = CareerProgress.tasks_for(fid)
			if not tasks.is_empty():
				var t0: Dictionary = (Careers.career_def(cid)["tasks"] as Array)[0]
				for n in int(t0["count"]):
					CareerProgress.on_interaction(fid, str((t0["interactions"] as Array)[0]), true)
			CareerShifts.on_returned(a, {"reason": "work", "completed": true, "worked_min": 480.0, "data": {}})
			shifts += 1
			if Careers.level_of(fid) != last_level:
				level_shifts.append(shifts)
				shifts = 0
				last_level = Careers.level_of(fid)
		K.expect(f, Careers.level_of(fid) >= 4, "%s reaches level 4 (stuck at %d after %d shifts)" % [cid, Careers.level_of(fid), guard])
		for n in level_shifts:
			K.expect(f, int(n) >= 3 and int(n) <= 14, "%s promotion cadence %s shifts per level is out of 3..14" % [cid, str(level_shifts)])
		K.teardown()
	# one real clock run: day shift pay and promotion bookkeeping through the director
	var w2 := K.setup(4242)
	var h := _skilled(w2, "Hank", {"handiness": 4})
	Careers.hire(h, "handyperson", 1)
	var dir = K.director()
	K.set_time(1, 7, 50)
	K.run(dir, 10 + 8 * 60 + 30)
	K.expect(f, K.count_events("left_for_work") == 1 and K.count_events("returned_from_work") == 1, "handyperson works a real 8:00-15:00 shift")
	K.expect(f, int(Careers.info_for(int(h.id))["days_worked"]) == 1, "day counted")
	K.teardown()

func _legacy_behaviour(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Old", [], 1, Vector2i(12, 12), "elder")
	Aging.set_age_days(a, 150.0)
	Careers.hire(a, "chef", 3)
	Careers.on_day(5)
	K.expect(f, Careers.retired.has(int(a.id)) and not Careers.has_job(int(a.id)), "elders still retire from the new careers")
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(12, 12), "child")
	Aging.set_age_days(kid, 15.0)
	Careers.on_day(5)
	K.expect(f, Careers.school.has(int(kid.id)), "school enrolment still works")
	var g0: float = CareerShifts.grade_of(int(kid.id))
	CareerProgress.on_interaction(int(kid.id), "do_homework", true)
	K.expect(f, CareerShifts.grade_of(int(kid.id)) > g0, "homework raises the grade")
	K.teardown()
