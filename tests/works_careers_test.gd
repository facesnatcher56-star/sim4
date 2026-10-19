extends RefCounted
## Task 31, industrial careers: factory worker -> plant manager, warehouse and logistics, construction, mechanic, power and utility tech.
## Data shape, stage gates, night shifts through a real clock run, strikes (strike pay, no penalty), plant closures, overtime, union dues,
## injury tiers, layoff weights, rained-off sites, the utility crew bonus, townie night shifts, the save round trip and the player command.

const K = preload("res://tests/systems_kit.gd")
const CK = preload("res://tests/content_kit.gd")

const IDS := ["factory_worker", "warehouse_worker", "construction_worker", "mechanic", "utility_tech"]

func run() -> Array:
	var f: Array = []
	_data(f)
	_stage_gates(f)
	_night_shift(f)
	_strike(f)
	_closure(f)
	_overtime_and_union(f)
	_risk(f)
	_weather(f)
	_utility(f)
	_townies(f)
	_save(f)
	_command(f)
	_offers(f)
	return f

func _skilled(w, name: String, skills: Dictionary, traits: Array = [], stage: String = "adult"):
	var a = K.make_folk(w, name, traits, 1, Vector2i(12, 12), stage)
	for s in skills:
		a.add_skill_xp(str(s), Folk.xp_for_level(int(skills[s])) + 1)
	return a

func _data(f: Array) -> void:
	var w := K.setup()
	NeighborhoodContent.install()
	var cs: Dictionary = SimEnv.data().get_table("careers")["careers"]
	var skills := CK.known_skills()
	for cid in IDS:
		K.expect(f, cs.has(cid), "%s is in the career table" % cid)
		var cd: Dictionary = Careers.career_def(cid)
		K.expect(f, str(cd.get("workplace", "")) == "works" and str(cd.get("visible_work", "")) != "", "%s works at the works lot and shows the work" % cid)
		K.expect(f, SimEnv.data().interactions().has(str(cd.get("visible_work", "x"))), "%s: work interaction exists" % cid)
		var kinds: Array = SimEnv.data().interaction_def(str(cd["visible_work"])).get("objects", [])
		for o in kinds:
			K.expect(f, SimEnv.data().objects().has(str(o)), "%s: station object %s exists" % [cid, o])
		var used: Dictionary = {}
		for lv in cd["levels"]:
			for s in (lv.get("requires", {}) as Dictionary).get("skills", {}):
				used[s] = true
		for s2 in used:
			K.expect(f, str(s2) in ["handiness", "fitness", "logic", "charisma"], "%s asks only for existing skills (%s)" % [cid, s2])
		K.expect(f, skills.has(str(cd["primary_skill"])), "%s primary skill known" % cid)
		var night: bool = false
		for sid in cd.get("shifts", {}):
			night = night or float(cd["shifts"][sid]["end"]) <= float(cd["shifts"][sid]["start"])
		K.expect(f, night or cid in ["construction_worker", "mechanic"], "%s has a night or late shift" % cid)
	K.expect(f, Careers.level_def("factory_worker", 1)["title"] == "Line Hand" and Careers.level_def("factory_worker", 3)["title"] == "Line Lead"
		and Careers.level_def("factory_worker", 4)["title"] == "Plant Supervisor" and Careers.level_def("factory_worker", 5)["title"] == "Plant Manager", "factory path: worker, line lead, plant supervisor, plant manager")
	K.expect(f, Careers.level_def("construction_worker", 1)["title"] == "Labourer" and Careers.level_def("construction_worker", 4)["title"] == "Foreman", "construction: labourer to foreman")
	K.expect(f, Careers.level_def("warehouse_worker", 2)["title"] == "Forklift Driver", "warehouse: forklift driver")
	# the lot: template, venue type, map slot
	var lots: Dictionary = (CK.read_json("res://data/lot_templates.json") as Dictionary)["lots"]
	K.expect(f, lots.has("works") and str(lots["works"].get("venue", "")) == "works" and (lots["works"]["objects"] as Array).size() >= 30, "the works lot template exists and is furnished")
	var defs_used: Dictionary = {}
	for o2 in lots["works"]["objects"]:
		defs_used[str(o2["def"])] = true
	for d in ["assembly_line", "pallet_rack", "forklift", "site_materials", "vehicle_lift", "control_panel"]:
		K.expect(f, defs_used.has(d) and SimEnv.data().objects().has(d), "the works lot has a %s" % d)
	var hood: Dictionary = CK.read_json("res://data/neighborhood.json")
	var found := false
	for l in hood["lots"]:
		found = found or (str(l["id"]) == "works" and str(l["type"]) == "works")
	K.expect(f, found, "the works lot is on the neighbourhood list")
	K.expect(f, (CK.read_json("res://data/venues.json")["types"] as Dictionary).has("works"), "the works venue type exists")
	K.teardown()

func _stage_gates(f: Array) -> void:
	var w := K.setup()
	var teen = K.make_folk(w, "Teen", [], 1, Vector2i(12, 12), "teen")
	var kid = K.make_folk(w, "Kid", [], 1, Vector2i(12, 12), "child")
	var adult = K.make_folk(w, "Adult")
	var elder = K.make_folk(w, "Elder", [], 1, Vector2i(12, 12), "elder")
	for cid in IDS:
		K.expect(f, Careers.why_not_work(teen, cid, 1) != "" and Careers.why_not_work(kid, cid, 1) != "", "%s: no teens or children" % cid)
		K.expect(f, not Careers.hire(teen, cid, 1), "%s: a teen cannot be hired" % cid)
		K.expect(f, Careers.why_not_work(adult, cid, 1) == "" and Careers.why_not_work(elder, cid, 1) == "", "%s: adults and elders may" % cid)
	K.expect(f, Careers.hire(adult, "mechanic", 1) and Careers.career_of(int(adult.id)) == "mechanic", "an adult is hired as a garage hand")
	var novice = K.make_folk(w, "Nova")
	K.expect(f, not bool(Careers.qualify(novice, "factory_worker", 3)["ok"]) and bool(Careers.qualify(novice, "factory_worker", 1)["ok"]), "entry level needs nothing, line lead needs skills")
	K.expect(f, not bool(Careers.qualify(novice, "utility_tech", 1)["ok"]), "the grid wants a little handiness first")
	K.teardown()

func _night_shift(f: Array) -> void:
	var w := K.setup()
	var a = _skilled(w, "Nick", {"handiness": 2})
	Careers.hire(a, "factory_worker", 2)
	var fid := int(a.id)
	K.expect(f, a.work_start == 7.0 and a.work_end == 15.0, "day shift 7 to 15")
	K.expect(f, CareerProgress.set_shift(a, "night_line") and a.work_start == 22.0 and a.work_end == 6.0, "the night line is 22:00 to 06:00")
	WorldIface.coins[1] = 0
	var dir = K.director()
	K.set_time(1, 21, 45)
	K.run(dir, 10)
	K.expect(f, not SysUtil.is_away(a), "still home at 21:55")
	K.run(dir, 10)
	K.expect(f, K.count_events("left_for_work") == 1 and SysUtil.is_away(a), "leaves for the night line at 22:00")
	K.run(dir, 10 * 60)
	K.expect(f, not SysUtil.is_away(a) and K.count_events("returned_from_work") == 1, "back after 06:00")
	var r: Dictionary = K.last_event("returned_from_work")
	var base: float = 8.0 * float(Careers.level_def("factory_worker", 2)["pay"]) * CareerProgress.pay_multiplier(CareerProgress.performance_of(fid) - float(r.get("delta", 0.0)))
	K.expect(f, float(r["pay"]) > base * 1.2 and float(r["pay"]) < base * 1.4, "night pay carries the 30 percent premium (%d vs %.0f)" % [int(r["pay"]), base])
	K.expect(f, a.has_buff("post_night_shift"), "night workers come home groggy")
	K.teardown()

func _strike(f: Array) -> void:
	var w := K.setup()
	var a = _skilled(w, "Sam", {"handiness": 2})
	var b = _skilled(w, "Ben", {"handiness": 2})
	Careers.hire(a, "factory_worker", 1)
	Careers.hire(b, "factory_worker", 1)
	K.expect(f, WorksUnion.join(a)["ok"] and WorksUnion.is_member(int(a.id)) and not bool(WorksUnion.join(a)["ok"]), "a worker joins the union once")
	K.set_time(2, 12)
	K.expect(f, not WorksEvents.schedule_strike("cook", 2) and WorksEvents.schedule_strike("factory_worker", 2, "wages"), "only industrial careers strike")
	K.expect(f, not WorksEvents.schedule_strike("factory_worker", 2), "one strike at a time")
	K.expect(f, not WorksEvents.on_strike("factory_worker") and K.has_note("union has called a strike"), "announced a day ahead, not yet out")
	K.set_time(3, 6, 50)
	K.expect(f, WorksEvents.on_strike("factory_worker") and not WorksEvents.on_strike("mechanic"), "out from tomorrow, and only that trade")
	var dir = K.director()
	WorldIface.coins[1] = 0
	var perf: float = CareerProgress.performance_of(int(a.id))
	K.run(dir, 30)
	K.expect(f, K.count_events("left_for_work") == 0 and not SysUtil.is_away(a) and not SysUtil.is_away(b), "nobody goes in during the strike")
	K.expect(f, K.count_events("works_off_day") == 2 and CareerProgress.performance_of(int(a.id)) == perf and K.count_events("missed_shift") == 0, "a strike day is no penalty and no missed shift")
	var paid: int = WorldIface.coins[1]
	K.expect(f, paid == WorksUnion.strike_pay(15), "the union member gets strike pay, the other nothing (%d)" % paid)
	K.expect(f, K.has_note("picket line") and K.has_note("No work, no wages"), "plain words for both")
	# the strike ends: a raise or nothing, never stuck
	var won := 0
	for i in 30:
		WorksEvents.strikes["factory_worker"] = {"start": 1, "end": 1, "cause": ""}
		WorksEvents.raises.clear()
		K.set_time(5, 6)
		WorksEvents.on_day(5)
		K.expect(f, not WorksEvents.strikes.has("factory_worker"), "an old strike is settled")
		if WorksEvents.wage_mult("factory_worker") > 1.0:
			won += 1
			K.expect(f, WorksEvents.wage_mult("factory_worker") >= 1.03 and WorksEvents.wage_mult("factory_worker") <= 1.081, "the raise is 3 to 8 percent")
	K.expect(f, won >= 10 and won <= 28, "most strikes win something (%d of 30)" % won)
	# the raise reaches the pay cheque
	WorksEvents.raises["factory_worker"] = 0.1
	var p0: int = WorksPay.adjust_pay(b, Careers.jobs[int(b.id)], 100, 8.0, true)
	K.expect(f, p0 == 110, "a 10 percent raise pays 110 for 100 (%d)" % p0)
	K.teardown()

func _closure(f: Array) -> void:
	var w := K.setup()
	Story.generate_townies(10)
	var a = _skilled(w, "Cy", {"handiness": 2})
	Careers.hire(a, "construction_worker", 1)
	var tids: Array = Story.townies.keys()
	var made := 0
	for tid in tids:
		if Story.stage_of(Story.townies[tid]) == "adult" and made < 3:
			Story.townies[tid]["career"] = "construction_worker"
			made += 1
	var before: int = int(WorldIface.coins.get(1, 0))
	var lost: int = WorksEvents.close_works("construction_worker", "test")
	K.expect(f, lost == made + 1 and not Careers.has_job(int(a.id)), "a closure takes everybody's job (%d)" % lost)
	K.expect(f, int(WorldIface.coins.get(1, 0)) - before == 16 * 40 and a.has_buff("laid_off"), "severance is 40 hours of pay")
	var seeking := 0
	for tid2 in tids:
		if bool(Story.townies[tid2].get("seeking", false)) and str(Story.townies[tid2].get("career", "")) == "":
			seeking += 1
	K.expect(f, seeking >= made, "the townies start looking for work (%d)" % seeking)
	K.expect(f, K.has_note("shut down for good") or K.has_note("lost the job"), "the town is told in plain words")
	K.expect(f, WorksEvents.close_works("cook") == 0, "a cook's career has no works to close")
	K.teardown()

func _overtime_and_union(f: Array) -> void:
	var w := K.setup()
	var a = _skilled(w, "Ola", {"handiness": 2})
	Careers.hire(a, "warehouse_worker", 1)
	var j: Dictionary = Careers.jobs[int(a.id)]
	var e0: float = a.get_stat_value("energy")
	K.expect(f, WorksPay.adjust_pay(a, j, 112, 8.0, true) == 112, "overtime is off by default")
	j["overtime"] = true
	var extra := 0
	var n := 400
	for i in n:
		var p: int = WorksPay.adjust_pay(a, j, 112, 8.0, true)
		if p > 112:
			extra += 1
			K.expect(f, p == 112 + int(round(112.0 / 8.0 * 2.0 * 1.5)), "two hours at time and a half (%d)" % p)
		(a.needs["energy"] as Stat).set_value(80.0)
	var rate: float = float(extra) / float(n)
	K.expect(f, rate > 0.18 and rate < 0.32, "a busy day asks for overtime about a quarter of the time (%.2f)" % rate)
	K.expect(f, a.has_buff("overtime_worn"), "staying late wears you out")
	var tired = _skilled(w, "Tia", {"handiness": 2})
	Careers.hire(tired, "warehouse_worker", 1)
	Careers.jobs[int(tired.id)]["overtime"] = true
	tired.add_to_stat("energy", -100.0)
	var worn := 0
	for i2 in 100:
		if WorksPay.adjust_pay(tired, Careers.jobs[int(tired.id)], 112, 8.0, true) > 112:
			worn += 1
	K.expect(f, worn == 0, "nobody is asked to stay late when exhausted")
	K.expect(f, WorksPay.adjust_pay(a, j, 112, 4.0, false) == 112, "a shift left early gets no overtime")
	# union dues
	j["overtime"] = false
	WorksUnion.join(a)
	K.expect(f, WorksPay.adjust_pay(a, j, 100, 8.0, true) == 98, "union dues are 2 percent")
	WorksUnion.leave(a)
	K.expect(f, WorksPay.adjust_pay(a, j, 100, 8.0, true) == 100 and not WorksUnion.is_member(int(a.id)), "leaving stops them")
	var cook = _skilled(w, "Cook", {"cooking": 2})
	Careers.hire(cook, "cook", 1)
	K.expect(f, WorksPay.adjust_pay(cook, Careers.jobs[int(cook.id)], 100, 8.0, true) == 100 and not bool(WorksUnion.join(cook)["ok"]), "other careers are untouched")
	K.teardown()

func _risk(f: Array) -> void:
	var w := K.setup()
	K.expect(f, Works.injury_tier("construction_worker") == 3 and Works.injury_tier("factory_worker") == 2 and Works.injury_tier("utility_tech") == 2, "heavy work is the most dangerous")
	K.expect(f, Works.injury_tier("warehouse_worker") == 1 and Works.injury_tier("mechanic") == 1 and Works.injury_tier("coder") == 0, "a desk job is not")
	K.expect(f, Works.injury_tier("handyperson") == 2 and Works.injury_tier("cook") == 1, "the older careers keep their tier")
	var raw: String = CK.read_text("res://data/incidents/05_accidents.json")
	K.expect(f, raw.contains("acc_job_hazard") and raw.contains("Hazardous site"), "the hazard doubles into the hourly dice")
	K.expect(f, Works.layoff_mult("construction_worker") > Works.layoff_mult("factory_worker") and Works.layoff_mult("factory_worker") > 1.0 and Works.layoff_mult("utility_tech") < 1.0 and Works.layoff_mult("cook") == 1.0, "layoff weights: construction, then the plant; the grid is steady")
	K.expect(f, CK.read_text("res://data/incidents/07b_chaos_more.json").contains("Heavy industry feels a slump first"), "the layoff incident weighs heavy industry")
	# injuries feed the strike dice
	WorksEvents.hurt.clear()
	var c0: float = WorksEvents.strike_chance("factory_worker")
	for i in 4:
		WorksEvents.note_injury("factory_worker")
	K.expect(f, WorksEvents.strike_chance("factory_worker") > c0 * 2.5, "a run of injuries makes a strike likelier")
	WorksEvents.note_injury("cook")
	K.expect(f, not WorksEvents.hurt.has("cook"), "only industrial injuries count")
	K.expect(f, WorksEvents.closure_chance("construction_worker") > WorksEvents.closure_chance("utility_tech"), "closure dice follow the layoff weight")
	K.teardown()

func _weather(f: Array) -> void:
	var w := K.setup()
	var c = _skilled(w, "Cal", {"handiness": 1})
	Careers.hire(c, "construction_worker", 1)
	var fa = _skilled(w, "Fay", {"handiness": 1})
	Careers.hire(fa, "factory_worker", 1)
	Weather.force("sunny")
	K.expect(f, not WorksPay.off_day(c, Careers.jobs[int(c.id)]), "the site works in sunshine")
	Weather.force("thunderstorm")
	K.expect(f, WorksPay.off_day(c, Careers.jobs[int(c.id)]) and K.has_note("too wet and stormy"), "a thunderstorm sends the site home")
	K.expect(f, not WorksPay.off_day(fa, Careers.jobs[int(fa.id)]), "the factory is indoors")
	Weather.force("snow", 0.8)
	K.expect(f, WorksPay.off_day(c, Careers.jobs[int(c.id)]), "snow stops the site too")
	Weather.force("rain")
	K.expect(f, not WorksPay.off_day(c, Careers.jobs[int(c.id)]), "light rain does not")
	Weather.unforce()
	K.teardown()

func _utility(f: Array) -> void:
	var w := K.setup()
	Story.generate_townies(12)
	K.expect(f, WorksUtility.crew_mult() == 1.0 and WorksUtility.techs() == 0, "no techs, ordinary crews")
	var a = _skilled(w, "Uma", {"handiness": 2})
	Careers.hire(a, "utility_tech", 1)
	var m1: float = WorksUtility.crew_mult()
	K.expect(f, m1 > 1.0 and m1 < 1.1, "one tech makes the crews a little quicker (%.2f)" % m1)
	var made := 0
	for tid in Story.townies:
		if Story.stage_of(Story.townies[tid]) == "adult" and made < 8:
			Story.townies[tid]["career"] = "utility_tech"
			made += 1
	K.expect(f, WorksUtility.crew_mult() <= 1.3001 and WorksUtility.crew_mult() > m1, "more techs help, up to a cap (%.2f)" % WorksUtility.crew_mult())
	WorksEvents.schedule_strike("utility_tech", 2)
	K.set_time(SysUtil.day() + 1, 12)
	K.expect(f, WorksUtility.crew_mult() == 1.0, "a strike by the grid workers stops the bonus")
	var baseline: float = 10.0 / CityBudget.repair_speed("utilities")
	K.expect(f, baseline > 0.0, "repair hours still follow the utilities budget")
	K.teardown()

func _townies(f: Array) -> void:
	var w := K.setup()
	var night := 0
	for id in 100:
		var t := {"id": id, "career": "factory_worker", "level": 1}
		var s: Dictionary = WorksPay.townie_shift(t)
		if not s.is_empty():
			night += 1
			K.expect(f, float(s["start"]) == 22.0 and float(s["end"]) == 6.0, "townie night line is 22 to 6")
	K.expect(f, night == 25, "a quarter of the industrial townies work nights (%d of 100)" % night)
	K.expect(f, WorksPay.townie_shift({"id": 5, "career": "cook", "level": 1}).is_empty(), "other careers keep day hours")
	K.expect(f, WorksPay.townie_shift({"id": 0, "career": "mechanic", "level": 1}).is_empty(), "a trade without a night shift stays on days")
	var members := 0
	for id2 in 100:
		if WorksUnion.townie_member({"id": id2, "career": "mechanic"}):
			members += 1
	K.expect(f, members == 35, "a third of the industrial townies are in the union (%d)" % members)
	K.teardown()

func _save(f: Array) -> void:
	var w := K.setup()
	var a = _skilled(w, "Sue", {"handiness": 2})
	Careers.hire(a, "factory_worker", 1)
	WorksUnion.join(a)
	K.set_time(4, 10)
	WorksEvents.schedule_strike("mechanic", 3, "wages")
	WorksEvents.raises["factory_worker"] = 0.05
	WorksEvents.note_injury("construction_worker")
	var d1: Dictionary = CityState.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	CityState.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1["works"], CityState.to_dict()["works"], "works", diffs), "works state round-trips through JSON: %s" % str(diffs.slice(0, 3)))
	K.expect(f, WorksEvents.strikes.has("mechanic") and WorksUnion.is_member(int(a.id)) and WorksEvents.wage_mult("factory_worker") == 1.05, "strike, union and raise survive a load")
	K.teardown()

func _command(f: Array) -> void:
	var w := K.setup()
	var a = _skilled(w, "Ned", {"handiness": 2})
	Careers.hire(a, "mechanic", 1)
	var pid: int = Players.local_id
	var env := {"player_id": pid, "folk_id": int(a.id), "action": "works", "args": {"action": "join_union"}}
	var mine: bool = Players.owns(pid, int(a.household_id))
	if mine:
		K.expect(f, bool(WorksCmd.run(env)["ok"]) and WorksUnion.is_member(int(a.id)), "join the union by command")
		env["args"] = {"action": "overtime", "on": true}
		K.expect(f, bool(WorksCmd.run(env)["ok"]) and bool(Careers.jobs[int(a.id)]["overtime"]), "ask for overtime by command")
		env["args"] = {"action": "status"}
		var lines: Array = WorksCmd.run(env)["lines"]
		K.expect(f, lines.size() >= 2 and str(lines[0]).begins_with("Union: member"), "status says it in words")
		env["args"] = {"action": "leave_union"}
		K.expect(f, bool(WorksCmd.run(env)["ok"]) and not WorksUnion.is_member(int(a.id)), "leave by command")
	var stranger := {"player_id": 99, "folk_id": int(a.id), "action": "works", "args": {"action": "join_union"}}
	K.expect(f, not bool(WorksCmd.run(stranger)["ok"]), "another player cannot act for your folk")
	K.expect(f, CommandActions.has_action("works"), "the command layer knows the works action")
	K.teardown()

func _offers(f: Array) -> void:
	var w := K.setup()
	var seen: Dictionary = {}
	for i in 120:
		var n = K.make_folk(w, "Job%d" % i)
		var o: Dictionary = Careers.make_offer(n)
		if not o.is_empty():
			seen[str(o["career"])] = true
		Careers.decline_offer(int(n.id))
	var works := 0
	for cid in IDS:
		if seen.has(cid):
			works += 1
	K.expect(f, works >= 2, "the job market offers industrial jobs (%d of 5 seen in 120 offers)" % works)
	K.expect(f, Story.cfg().get("careers", []).has("factory_worker") and Story.cfg().get("careers", []).has("utility_tech"), "townies take industrial jobs too")
	K.teardown()
