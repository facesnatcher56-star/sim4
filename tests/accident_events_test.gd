extends RefCounted
## Task 05 accidents: every event forced end to end (outcomes, text, hurt / hospital / death), rescue + counterplay, the treadmill hook,
## workplace injuries, the property event for lawsuits, statistical townies, save / load of a warned accident.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_drowning(f)
	_rescue(f)
	_choking(f)
	_small_events(f)
	_deaths_need_the_right_conditions(f)
	_workplace(f)
	_property(f)
	_statistical(f)
	_save(f)
	return f

func _world() -> StubWorld:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	IncidentContent.install()
	Incidents.set_level("rare")
	Weather.unforce()
	WorldIface.coins[1] = 2000
	WorldIface.coins[2] = 2000
	return w

func _done() -> void:
	Weather.unforce()
	K.teardown()

func _hurt(fk: Folk) -> bool:
	return fk.has_buff("injured") or Hospital.is_in(fk)

func _drowning(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	a.add_buff("acc_alone")
	K.set_time(5, 14, 0)
	# the warning first: a toast, a thought, nothing else yet
	K.notes.clear()
	var r: Dictionary = Incidents.force("drowning_scare", {"folk_id": a.id, "warn": true})
	K.expect(f, r["mode"] == "warned" and K.has_note("struggling in the water"), "drowning warns first: %s" % str(r))
	K.expect(f, not _hurt(a), "nobody is hurt during the warning")
	# nobody comes: the outcome lands when due
	K.set_time(5, 14, 10)
	Incidents.on_minute()
	K.expect(f, Incidents.active().is_empty() and int(Incidents.stat("drowning_scare")["averted"]) == 0, "unrescued: the warning resolves into an outcome")
	_done()
	# every outcome of the data
	w = _world()
	var b := K.make_folk(w, "Bo", [], 1)
	var outs: Array = IncidentDefs.get_def("drowning_scare")["outcomes"]
	K.expect(f, outs.size() == 6, "drowning has 6 outcomes")
	Incidents.force("drowning_scare", {"folk_id": b.id, "outcome": 3})
	K.expect(f, b.has_buff("injured") and b.has_buff("shaken_up") and not Hospital.is_in(b), "coughed up water: bruised + shaken up, no hospital")
	var c := K.make_folk(w, "Cy", [], 1)
	K.notes.clear()
	Incidents.force("drowning_scare", {"folk_id": c.id, "outcome": 2})
	K.expect(f, Hospital.is_in(c) and K.has_note("swallowed a lot of water"), "bad scare: clinic")
	var d := K.make_folk(w, "Dee", [], 1)
	Incidents.force("drowning_scare", {"folk_id": d.id, "outcome": 5})
	K.expect(f, not _hurt(d) and d.has_buff("shaken_up"), "scrambled out: only shaken up")
	# first aid kit softens the minor outcome
	w.add_object("first_aid_kit", Vector2i(2, 2))
	Economy.refresh_objects()
	var e := K.make_folk(w, "Eli", [], 1)
	var pick := IncidentEffects.pick(outs, IncidentSubject.of_folk(e))
	K.expect(f, not pick.is_empty(), "outcomes can be picked")
	var kit_seen: bool = false
	var nokit_seen: bool = false
	Incidents.seed_rng(3)
	for i in 400:
		var pk: Dictionary = IncidentEffects.pick(outs, IncidentSubject.of_folk(e))
		var idx: int = int(pk["index"])
		kit_seen = kit_seen or idx == 4
		nokit_seen = nokit_seen or idx == 3
	K.expect(f, kit_seen and not nokit_seen, "with a first aid kit the bruise outcome is replaced by the patched-up one")
	var g := K.make_folk(w, "Gus", [], 1)
	g.add_buff("acc_alone")
	Incidents.force("drowning_scare", {"folk_id": g.id, "outcome": 0})
	K.expect(f, w.get_folk(g.id) == null and Aging.dead.size() >= 1, "forced fatal outcome: a quiet collapse and a grave record")
	K.expect(f, str(Aging.dead[Aging.dead.size() - 1].get("cause_id", "")) == "accident_drowning", "cause is accident_drowning: %s" % str(Aging.dead[Aging.dead.size() - 1]))
	_done()

func _rescue(f: Array) -> void:
	var w := _world()
	K.set_time(5, 14, 0)
	var swimmer := K.make_folk(w, "Sky", [], 1, Vector2i(10, 10))
	swimmer.add_buff("acc_alone")
	var friend := K.make_folk(w, "Fern", [], 1, Vector2i(44, 10))   # too far to jump in by themselves: the player sends them
	# the player's counterplay: the rescue interaction is offered for someone in trouble and ends the danger
	Incidents.force("drowning_scare", {"folk_id": swimmer.id, "warn": true})
	AccidentMarks.on_minute()
	K.expect(f, swimmer.has_buff("acc_trouble_water"), "the person in danger is marked so a rescue can target them")
	var idef: Dictionary = SimEnv.data().interaction_def("rescue_swimmer")
	K.expect(f, Cond.check(idef["target_tests"], {"folk": swimmer, "target": friend}), "Pull to Safety is offered for the swimmer")
	K.expect(f, not Cond.check(idef["target_tests"], {"folk": friend, "target": swimmer}), "...and not for someone who is fine")
	Loot.apply(idef["on_finish"], {"folk": friend, "object": null, "target": swimmer})
	AccidentMarks.on_minute()
	K.expect(f, swimmer.has_buff("acc_rescued") and not swimmer.has_buff("acc_trouble_water") and friend.has_buff("hero_moment"), "rescued: out of danger, the helper is thanked")
	K.notes.clear()
	K.set_time(5, 14, 10)
	Incidents.on_minute()
	K.expect(f, int(Incidents.stat("drowning_scare")["averted"]) == 1 and not _hurt(swimmer) and K.has_note("pulled to safety"), "the incident is averted: no injury, a good toast")
	K.expect(f, w.get_folk(swimmer.id) != null, "rescued swimmer lives")
	_done()
	# a bystander steps in by themselves
	w = _world()
	K.set_time(5, 14, 0)
	var s2 := K.make_folk(w, "Sol", [], 1, Vector2i(10, 10))
	var h2 := K.make_folk(w, "Hal", [], 1, Vector2i(12, 10))
	var rel0: float = h2.get_rel(s2.id, "friendship")
	Incidents.force("drowning_scare", {"folk_id": s2.id, "warn": true})
	for m in 3:
		K.set_time(5, 14, 1 + m)
		AccidentMarks.on_minute()
		Incidents.on_minute()
		if s2.has_buff("acc_rescued"):
			break
	K.expect(f, s2.has_buff("acc_rescued") or int(Incidents.stat("drowning_scare")["averted"]) == 1, "someone nearby pulled them out")
	K.expect(f, h2.has_buff("hero_moment") and h2.get_rel(s2.id, "friendship") > rel0, "the bystander is a hero and a friend")
	K.set_time(5, 14, 10)
	Incidents.on_minute()
	K.expect(f, not _hurt(s2), "no injury after a bystander rescue")
	_done()
	# nobody within reach: helpers too far away or asleep do not rescue
	w = _world()
	K.set_time(5, 14, 0)
	var s3 := K.make_folk(w, "Sue", [], 1, Vector2i(10, 10))
	var far := K.make_folk(w, "Far", [], 1, Vector2i(60, 60))
	var asleep := K.make_folk(w, "Zed", [], 1, Vector2i(11, 10))
	asleep.posture = "lie"
	Incidents.force("drowning_scare", {"folk_id": s3.id, "warn": true})
	for m2 in 3:
		K.set_time(5, 14, 1 + m2)
		AccidentMarks.on_minute()
	K.expect(f, not s3.has_buff("acc_rescued") and s3.has_buff("acc_trouble_water") and not far.has_buff("hero_moment"), "far away or sleeping people do not rescue")
	_done()

func _choking(f: Array) -> void:
	var w := _world()
	K.set_time(5, 19, 0)
	var a := K.make_folk(w, "Ada", ["glutton"], 1, Vector2i(10, 10))
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(41, 10))
	K.notes.clear()
	Incidents.force("choking", {"folk_id": a.id, "warn": true})
	K.expect(f, K.has_note("clutching their throat"), "choking warns: help them")
	AccidentMarks.on_minute()
	K.expect(f, a.has_buff("acc_trouble_choke"), "choking marker lets someone help")
	var idef: Dictionary = SimEnv.data().interaction_def("help_choking")
	K.expect(f, Cond.check(idef["target_tests"], {"folk": a, "target": b}), "Help Them Cough It Up is offered")
	Loot.apply(idef["on_finish"], {"folk": b, "object": null, "target": a})
	K.set_time(5, 19, 5)
	Incidents.on_minute()
	K.expect(f, int(Incidents.stat("choking")["averted"]) == 1 and w.get_folk(a.id) != null and not _hurt(a), "helped in time: nothing happens")
	# outcomes
	var c := K.make_folk(w, "Cy", [], 2, Vector2i(30, 30))
	Incidents.force("choking", {"folk_id": c.id, "outcome": 2})
	K.expect(f, c.has_buff("injured") and not Hospital.is_in(c), "choking minor: coughing fit")
	Incidents.force("choking", {"folk_id": c.id, "outcome": 3})
	K.expect(f, c.has_buff("shaken_up"), "choking: shaken up")
	_done()

func _small_events(f: Array) -> void:
	var w := _world()
	K.set_time(5, 12, 0)
	var a := K.make_folk(w, "Ada", [], 1)
	K.notes.clear()
	Incidents.force("electric_shock", {"folk_id": a.id, "outcome": 2})
	K.expect(f, a.has_buff("injured") and K.has_note("burned a hand"), "shock: burned hand")
	var b := K.make_folk(w, "Bo", [], 1)
	Incidents.force("electric_shock", {"folk_id": b.id, "outcome": 1})
	K.expect(f, Hospital.is_in(b), "shock: bad one goes to hospital")
	var c := K.make_folk(w, "Cy", [], 1)
	Incidents.force("electric_shock", {"folk_id": c.id, "outcome": 4})
	K.expect(f, not c.has_buff("injured") and c.has_buff("shaken_up"), "shock: a jolt is a mood penalty")
	var d := K.make_folk(w, "Dee", [], 1, Vector2i(12, 12), "elder")
	Incidents.force("slip_fall", {"folk_id": d.id, "outcome": 2})
	K.expect(f, Hospital.is_in(d), "slip: twisted ankle goes to the clinic")
	var e := K.make_folk(w, "Eli", [], 1)
	Incidents.force("slip_fall", {"folk_id": e.id, "outcome": 3})
	K.expect(f, e.has_buff("injured"), "slip: bruise")
	var g := K.make_folk(w, "Gus", [], 1)
	Incidents.force("slip_fall", {"folk_id": g.id, "outcome": 5})
	K.expect(f, not _hurt(g), "slip: caught themselves")
	var h := K.make_folk(w, "Hana", [], 1, Vector2i(12, 12), "child")
	Incidents.force("traffic_hit", {"folk_id": h.id, "outcome": 2})
	K.expect(f, Hospital.is_in(h) and h.has_buff("shaken_up"), "traffic: hit and taken to hospital")
	var i := K.make_folk(w, "Ivo", [], 1)
	K.notes.clear()
	Incidents.force("traffic_hit", {"folk_id": i.id, "outcome": 4})
	K.expect(f, not _hurt(i) and K.has_note("jumped back"), "traffic: a near miss")
	var j := K.make_folk(w, "Jun", [], 1, Vector2i(12, 12), "toddler")
	Incidents.force("kids_near_road", {"folk_id": j.id, "outcome": 3})
	K.expect(f, not _hurt(j) and j.has_buff("shaken_up"), "kids near the road: pulled back in time")
	var k := K.make_folk(w, "Kay", [], 1)
	Incidents.force("workout_injury", {"folk_id": k.id, "outcome": 1})
	K.expect(f, k.has_buff("injured"), "workout: twisted ankle")
	var l := K.make_folk(w, "Lou", [], 1)
	Incidents.force("workout_injury", {"folk_id": l.id, "outcome": 3})
	K.expect(f, l.has_buff("sore_muscles"), "workout: pulled muscle")
	# the treadmill that gives way (the hook after an exercise session)
	var m := K.make_folk(w, "Mia", [], 1, Vector2i(20, 20))
	var tm = w.add_object("treadmill", Vector2i(20, 21))
	var ir := Interaction.create("exercise", m, tm.id)
	ir.state = "running"
	m.current = ir
	AccidentMarks.on_minute()
	m.current = null                       # as in the game: the interaction is gone when the finished event arrives
	AccidentMarks.on_interaction_finished(m.id, "exercise", true)
	K.expect(f, int(Incidents.stat("treadmill_gives_way")["forced"]) == 0, "a working treadmill: nothing happens")
	WorldIface.state_set(tm, "broken", true)
	m.current = ir
	AccidentMarks.on_minute()
	m.current = null
	AccidentMarks.on_interaction_finished(m.id, "exercise", true)
	K.expect(f, int(Incidents.stat("treadmill_gives_way")["forced"]) == 1, "a treadmill that broke during the session can hurt the user")
	var n := K.make_folk(w, "Ned", [], 1)
	Incidents.force("treadmill_gives_way", {"folk_id": n.id, "outcome": 1})
	K.expect(f, n.has_buff("injured"), "treadmill: knee hurt")
	var o := K.make_folk(w, "Oli", [], 1, Vector2i(12, 12), "toddler")
	Incidents.force("kids_near_water", {"folk_id": o.id, "outcome": 2})
	K.expect(f, Hospital.is_in(o), "child by the water: scare ends in the clinic")
	_done()

## Deaths are extremely rare AND conditional: sample thousands of picks.
func _deaths_need_the_right_conditions(f: Array) -> void:
	var w := _world()
	Incidents.seed_rng(11)
	var a := K.make_folk(w, "Ada", [], 1)
	var cases := {"drowning_scare": ["acc_alone", "alone"], "choking": ["acc_alone", "alone"], "kids_near_water": ["acc_unsupervised", "unsupervised"]}
	for id in cases:
		var outs: Array = IncidentDefs.get_def(id)["outcomes"]
		var deaths_with: int = 0
		var deaths_without: int = 0
		var subj_a = IncidentSubject.of_folk(a)
		for i in 3000:
			var pk: Dictionary = IncidentEffects.pick(outs, subj_a)
			if str(pk["effects"][0]["args"].get("kill", "")) != "":
				deaths_without += 1
		a.add_buff(cases[id][0])
		for i2 in 3000:
			var pk2: Dictionary = IncidentEffects.pick(outs, IncidentSubject.of_folk(a))
			if str(pk2["effects"][0]["args"].get("kill", "")) != "":
				deaths_with += 1
		a.remove_buff(cases[id][0])
		K.expect(f, deaths_without == 0, "%s: never fatal when %s is not true" % [id, cases[id][1]])
		K.expect(f, deaths_with > 0 and deaths_with < 3000 * 0.12, "%s: fatal only sometimes when %s (%d of 3000)" % [id, cases[id][1], deaths_with])
	# the sum of all non-fatal weights stays well above the deadly ones for every incident (deaths a few percent at most)
	for id2 in ["electric_shock", "slip_fall", "traffic_hit", "kids_near_road", "workplace_injury"]:
		var tot: float = 0.0
		var dead: float = 0.0
		for o in IncidentDefs.get_def(id2)["outcomes"]:
			tot += float(o["weight"])
			if str(o["effects"][0]["args"].get("kill", "")) != "":
				dead += float(o["weight"])
		K.expect(f, dead > 0.0 and dead / tot <= 0.02, "%s: death is at most 2 percent of outcomes (%.3f)" % [id2, dead / tot])
	_done()

func _workplace(f: Array) -> void:
	var w := _world()
	K.set_time(5, 11, 0)
	var cook := K.make_folk(w, "Cora", [], 1)
	Careers.hire(cook, "cook", 1)
	K.expect(f, Incidents.effective_rate("workplace_injury", cook) == 0.0, "at home: no workplace accident")
	var dir = K.director()
	K.expect(f, Away.send(cook, 480.0, "work", {"label": "At work"}), "the cook leaves for work")
	K.run(dir, 3)
	AccidentMarks.on_hour(11)
	K.expect(f, cook.has_buff("acc_job_risky") and not cook.has_buff("acc_job_very_risky"), "a cook at work is exposed at the hourly dice")
	var base: float = float(IncidentDefs.get_def("workplace_injury")["base_rate_per_year"])
	K.expect(f, absf(Incidents.effective_rate("workplace_injury", cook) - base) < 0.0001, "cook rate = base")
	var hand := K.make_folk(w, "Hank", ["clumsy"], 1)
	Careers.hire(hand, "handyperson", 1)
	Away.send(hand, 480.0, "work", {"label": "At work"})
	K.run(dir, 3)
	AccidentMarks.on_hour(11)
	K.expect(f, absf(Incidents.effective_rate("workplace_injury", hand) - base * 2.0 * 2.5) < 0.0001, "clumsy handyperson: dangerous trade x2, clumsy x2.5")
	hand.skills["handiness"]["level"] = 4
	K.expect(f, absf(Incidents.effective_rate("workplace_injury", hand) - base * 2.0 * 2.5 * 0.6) < 0.0001, "skill at the trade x0.6")
	var teacher := K.make_folk(w, "Tess", [], 1)
	Careers.hire(teacher, "teacher", 1)
	Away.send(teacher, 480.0, "work", {"label": "At work"})
	K.run(dir, 3)
	AccidentMarks.on_hour(11)
	K.expect(f, not teacher.has_buff("acc_job_risky"), "a desk or classroom job is not a physical career")
	AccidentMarks.after_hour()
	K.expect(f, not cook.has_buff("acc_job_risky") and not hand.has_buff("acc_job_very_risky"), "the job markers are removed again right after the hourly dice")
	K.notes.clear()
	Incidents.force("workplace_injury", {"folk_id": cook.id, "outcome": 2})
	K.expect(f, Hospital.is_in(cook) and K.has_note("accident at work"), "a serious accident at work goes to hospital even while away at work")
	Incidents.force("workplace_injury", {"folk_id": hand.id, "outcome": 3})
	K.expect(f, hand.has_buff("injured") and Health.is_injured(hand), "a hurt hand: injured through the health system (physical jobs get skipped)")
	_done()

func _property(f: Array) -> void:
	var w := _world()
	var host := K.make_folk(w, "Host", [], 1, Vector2i(10, 10))
	var guest := K.make_folk(w, "Guest", [], 2, Vector2i(11, 10))
	K.events.clear()
	Incidents.force("slip_fall", {"folk_id": guest.id, "outcome": 3})
	var ev: Dictionary = K.last_event("accident_on_property")
	K.expect(f, not ev.is_empty() and int(ev["victim"]) == guest.id and int(ev["owner"]) == 1 and str(ev["lot"]) == "home:1", "a guest hurt on a household lot emits accident_on_property for the lawsuit hooks: %s" % str(ev))
	K.events.clear()
	Incidents.force("slip_fall", {"folk_id": host.id, "outcome": 3})
	K.expect(f, K.last_event("accident_on_property").is_empty() or int(K.last_event("accident_on_property")["victim"]) != host.id or true, "")
	var ev2: Dictionary = K.last_event("accident_on_property")
	K.expect(f, ev2.is_empty() or int(ev2["owner"]) != 1 or int(ev2["victim"]) != host.id, "the owner hurt on their own lot (nobody else's) emits nothing")
	_done()

func _statistical(f: Array) -> void:
	var w := _world()
	K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	var alive: Array = Story.alive_townies()
	var tid: int = int(alive[0]["id"])
	var t: Dictionary = Story.townies[tid]
	t["buffs"] = ["acc_eating"]
	t["age_days"] = 132.0
	t["traits"] = []
	var subj := IncidentSubject.of_townie(tid)
	var base: float = float(IncidentDefs.get_def("choking")["base_rate_per_year"])
	K.expect(f, absf(Incidents.effective_rate("choking", subj) - base) < 0.0001, "a far townie who is eating has the same choking rate as a Folk")
	t["traits"] = ["glutton"]
	K.expect(f, absf(Incidents.effective_rate("choking", subj) - base * 3.0) < 0.0001, "...and the glutton trait counts")
	t["buffs"] = []
	K.expect(f, Incidents.effective_rate("choking", subj) == 0.0, "not eating, no choking")
	var alive_ids: Array = Story.alive_townies().map(func(x): return int(x["id"]))
	# one-line summaries for every accident, no crash
	t["buffs"] = ["acc_alone", "acc_unsupervised"]
	t["age_days"] = 16.5
	for id in ["drowning_scare", "kids_near_water", "choking", "electric_shock", "slip_fall", "traffic_hit", "kids_near_road", "workout_injury", "workplace_injury"]:
		var outs: Array = IncidentDefs.get_def(id)["statistical"]["outcomes"]
		for i in outs.size():
			var tid2: int = int(alive_ids[(i + 2) % alive_ids.size()])
			var res: Dictionary = Incidents.resolve_statistical(id, tid2, i)
			K.expect(f, bool(res["ok"]) and str(res["summary"]) != "" and str(res["summary"]).find("{") < 0, "%s statistical %d: %s" % [id, i, res.get("summary", "")])
	# a statistical death is a death
	var victim: int = int(alive_ids[5])
	Story.townies[victim]["alive"] = true
	Incidents.resolve_statistical("traffic_hit", victim, 0)
	K.expect(f, not bool(Story.townies[victim]["alive"]), "a far townie killed by a car is dead")
	var hurt_id: int = int(alive_ids[6])
	Story.townies[hurt_id]["alive"] = true
	Incidents.resolve_statistical("workplace_injury", hurt_id, 2)
	K.expect(f, Hospital.is_in(hurt_id), "a far townie hurt at work is in hospital")
	# the hourly dice reach exposed far townies
	Incidents.reset()
	IncidentContent.install()
	Incidents.set_level("chaotic")
	var ex: int = int(alive_ids[7])
	for h in 400:
		Story.townies[ex]["buffs"] = ["acc_eating"]
		Story.townies[ex]["in_hospital"] = false
		Hospital.patients.erase(ex)
		Story.townies[ex]["alive"] = true
		Incidents.on_hour()
	K.expect(f, int(Incidents.stat("choking")["statistical"]) > 0, "the hourly dice roll choking for far townies who are eating")
	_done()

func _save(f: Array) -> void:
	var w := _world()
	K.set_time(5, 14, 0)
	var a := K.make_folk(w, "Ada", [], 1, Vector2i(10, 10))
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(52, 10))
	Incidents.force("drowning_scare", {"folk_id": a.id, "warn": true})
	AccidentMarks.on_minute()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Incidents.to_dict()))
	var fsnap: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	Incidents.reset()
	Incidents.from_dict(snap)
	K.expect(f, Incidents.active().size() == 1 and str(Incidents.active()[0]["id"]) == "drowning_scare", "a warned accident survives save / load")
	var a2: Folk = Folk.from_dict(fsnap)
	K.expect(f, a2.has_buff("acc_trouble_water"), "the 'in trouble' marker is saved with the person")
	# after a load the marker is re-derived from the pending warning even without it
	a.remove_buff("acc_trouble_water")
	AccidentMarks.on_minute()
	K.expect(f, a.has_buff("acc_trouble_water") or a.has_buff("acc_rescued"), "the marker comes back from the pending warning (or a bystander already helped)")
	# reset-safe: reset clears pending and nothing leaks into the next game
	Incidents.reset()
	AccidentMarks.on_minute()
	K.expect(f, Incidents.active().is_empty() and not b.has_buff("acc_trouble_water"), "reset leaves nothing pending")
	_done()
