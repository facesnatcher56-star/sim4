extends RefCounted
## Task 05 accidents: data validity, calibration table, risk multipliers + counterplay, the Traffic hook and the exposure markers
## (what a person is doing becomes a hidden acc_* buff the hourly dice read).

const K = preload("res://tests/systems_kit.gd")
const IDS := ["drowning_scare", "kids_near_water", "choking", "electric_shock", "slip_fall", "traffic_hit", "kids_near_road", "workout_injury", "treadmill_gives_way",
	"workplace_injury"]

func run() -> Array:
	var f: Array = []
	_data(f)
	_calibration(f)
	_traffic(f)
	_risks(f)
	_markers(f)
	_townie_markers(f)
	return f

func _near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _world() -> StubWorld:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	IncidentContent.install()
	Incidents.set_level("rare")
	Weather.unforce()
	Traffic.provider = Callable()
	Traffic.test_floors.clear()
	Weather.outdoors_fn = Callable()
	return w

func _done() -> void:
	Traffic.provider = Callable()
	Traffic.test_floors.clear()
	Weather.outdoors_fn = Callable()
	Weather._wet = 0.0
	Weather.unforce()
	K.teardown()

func _data(f: Array) -> void:
	_world()
	for id in IDS:
		var d: Dictionary = IncidentDefs.get_def(id)
		K.expect(f, not d.is_empty(), "%s is defined" % id)
		K.expect(f, IncidentDefs.validate_def(id, d).is_empty(), "%s validates: %s" % [id, str(IncidentDefs.validate_def(id, d))])
	for id2 in ["drowning_scare", "kids_near_water", "choking", "electric_shock", "slip_fall", "traffic_hit", "workout_injury", "workplace_injury"]:
		K.expect(f, not (IncidentDefs.get_def(id2).get("prevent", []) as Array).is_empty(), "%s has prevention the player can do" % id2)
	for id3 in ["drowning_scare", "kids_near_water", "choking"]:
		K.expect(f, int(IncidentDefs.get_def(id3)["warning"]["lead_min"]) > 0 and not (IncidentDefs.get_def(id3)["defuse"] as Array).is_empty(), "%s warns and can be defused by a rescue" % id3)
	for cause in ["accident_drowning", "accident_choking", "accident_electric", "accident_traffic", "accident_fall", "accident_work"]:
		K.expect(f, DeathCauses.has_cause(cause), "death cause %s exists" % cause)
	var sp: Dictionary = IncidentDefs.handler_specs.get("accident_outcome", {})
	K.expect(f, not sp.is_empty() and (load(str(sp["script"])) as Script).has_method(str(sp["method"])), "the accident_outcome handler is declared and exists")
	# content installed: buffs, interactions, objects
	var data = SimEnv.data()
	K.expect(f, not data.buff_def("shaken_up").is_empty() and not data.buff_def("acc_water").is_empty() and bool(data.buff_def("acc_water").get("hidden", false)), "marker + mood buffs installed")
	K.expect(f, not data.interaction_def("rescue_swimmer").is_empty() and not data.interaction_def("help_choking").is_empty(), "rescue interactions installed")
	K.expect(f, not data.object_def("life_ring").is_empty() and not data.object_def("slip_mat").is_empty() and not data.object_def("first_aid_kit").is_empty(), "safety objects installed")
	# every accident outcome is non-graphic: no outcome text names gore
	for id4 in IDS:
		var d4: Dictionary = IncidentDefs.get_def(id4)
		for o in d4.get("outcomes", []):
			var txt: String = str(o.get("text", "")).to_lower()
			for bad in ["blood", "gore", "corpse", "mangled", "crushed"]:
				K.expect(f, txt.find(bad) < 0, "%s text is non-graphic" % id4)
	_done()

## base_rate_per_year x checks_per_year / 672 must equal the documented per-person-year target.
func _calibration(f: Array) -> void:
	_world()
	var targets: Dictionary = (IncidentDefs.cfg("accidents", {}) as Dictionary).get("targets", {})
	K.expect(f, targets.size() >= 9, "calibration table present (%d)" % targets.size())
	for id in targets:
		var t: Dictionary = targets[id]
		var base: float = float(IncidentDefs.get_def(id)["base_rate_per_year"])
		var got: float = base * float(t["checks_per_year"]) / 672.0
		K.expect(f, absf(got / float(t["per_person_year"]) - 1.0) <= 0.08, "%s: base %.2f gives %.3f per person-year, target %.3f" % [id, base, got, float(t["per_person_year"])])
	_done()

func _traffic(f: Array) -> void:
	_world()
	var cross := Vector2i(5, 5)
	var road := Vector2i(6, 5)
	Traffic.test_floors[cross] = "crosswalk"
	Traffic.test_floors[road] = "asphalt"
	K.expect(f, Traffic.risk_at(Vector2i(1, 1), 23.0) == 0.0, "off the road there is no traffic risk")
	var night: float = Traffic.risk_at(cross, 23.0)
	var day: float = Traffic.risk_at(cross, 12.0)
	var dusk: float = Traffic.risk_at(cross, 19.0)
	K.expect(f, night > dusk and dusk > day and day > 0.0, "night %.2f > dusk %.2f > day %.2f" % [night, dusk, day])
	K.expect(f, Traffic.risk_at(road, 12.0) > Traffic.risk_at(cross, 12.0), "jaywalking beats the crosswalk")
	Traffic.provider = func(_tile, _hour): return 0.07
	K.expect(f, _near(Traffic.risk_at(cross, 23.0), 0.07), "phase 5 can plug real cars in with Traffic.provider")
	K.expect(f, Traffic.risk_at(Vector2i(1, 1), 23.0) == 0.0, "the provider is only asked on road tiles")
	_done()

func _risks(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	a.add_buff("acc_water")
	var base: float = float(IncidentDefs.get_def("drowning_scare")["base_rate_per_year"])
	var r0: float = Incidents.effective_rate("drowning_scare", a)
	K.expect(f, _near(r0, base * 1.6, 0.0001), "drowning: low fitness x1.6 (%.3f)" % r0)
	a.skills["fitness"]["level"] = 4
	K.expect(f, _near(Incidents.effective_rate("drowning_scare", a), base * 0.5, 0.0001), "drowning: strong swimmer x0.5")
	a.add_to_stat("energy", -200.0)
	K.expect(f, _near(Incidents.effective_rate("drowning_scare", a), base * 0.5 * 3.0, 0.0001), "drowning: worn out x3")
	a.add_buff("acc_alone")
	K.expect(f, _near(Incidents.effective_rate("drowning_scare", a), base * 0.5 * 3.0 * 2.0, 0.0001), "drowning: alone x2")
	w.add_object("life_ring", Vector2i(3, 3))
	Economy.refresh_objects()
	K.expect(f, _near(Incidents.effective_rate("drowning_scare", a), base * 0.5 * 3.0 * 2.0 * 0.35, 0.0001), "drowning: life ring x0.35")
	a.remove_buff("acc_water")
	K.expect(f, Incidents.effective_rate("drowning_scare", a) == 0.0, "no deep water, no drowning")
	# electric shock: wet floor and handiness
	var b := K.make_folk(w, "Bo", [], 2)
	b.add_buff("acc_repair_electric")
	var sb: float = float(IncidentDefs.get_def("electric_shock")["base_rate_per_year"])
	K.expect(f, _near(Incidents.effective_rate("electric_shock", b), sb * 3.0, 0.0001), "shock: low handiness x3")
	b.add_buff("acc_slippery")
	K.expect(f, _near(Incidents.effective_rate("electric_shock", b), sb * 9.0, 0.0001), "shock: wet floor x3 more")
	b.skills["handiness"]["level"] = 4
	K.expect(f, _near(Incidents.effective_rate("electric_shock", b), sb * 3.0 * 0.3, 0.0001), "shock: skilled with tools x0.3 (wet floor still x3)")
	# choking
	var c := K.make_folk(w, "Cy", ["glutton"], 3)
	c.add_buff("acc_eating")
	var cb: float = float(IncidentDefs.get_def("choking")["base_rate_per_year"])
	K.expect(f, _near(Incidents.effective_rate("choking", c), cb * 3.0, 0.0001), "choking: glutton x3")
	c.add_to_stat("hunger", -200.0)
	K.expect(f, _near(Incidents.effective_rate("choking", c), cb * 3.0 * 1.8 * 1.7, 0.0001), "choking: starving and gulping")
	# slip: elder on ice with a mat
	var e := K.make_folk(w, "Edda", [], 4, Vector2i(12, 12), "elder")
	e.add_buff("acc_slippery")
	var sf: float = float(IncidentDefs.get_def("slip_fall")["base_rate_per_year"])
	K.expect(f, _near(Incidents.effective_rate("slip_fall", e), sf * 3.0, 0.0001), "slip: elder x3")
	e.add_buff("acc_icy")
	K.expect(f, _near(Incidents.effective_rate("slip_fall", e), sf * 6.0, 0.0001), "slip: ice x2")
	# traffic: toddler on a crosswalk
	var t := K.make_folk(w, "Tot", [], 5, Vector2i(14, 14), "toddler")
	t.add_buff("acc_on_road")
	var tb: float = float(IncidentDefs.get_def("traffic_hit")["base_rate_per_year"])
	K.expect(f, _near(Incidents.effective_rate("traffic_hit", t), tb * 4.0, 0.0001), "traffic: toddler x4")
	t.add_buff("acc_crosswalk")
	K.expect(f, _near(Incidents.effective_rate("traffic_hit", t), tb * 4.0 * 0.4, 0.0001), "traffic: crosswalk x0.4")
	# kids unsupervised: both markers needed, adults never
	var kid := K.make_folk(w, "Kit", [], 6, Vector2i(15, 15), "child")
	kid.add_buff("acc_near_water")
	K.expect(f, Incidents.effective_rate("kids_near_water", kid) == 0.0, "a child near water but supervised is safe")
	kid.add_buff("acc_unsupervised")
	K.expect(f, Incidents.effective_rate("kids_near_water", kid) > 0.0, "an unsupervised child near water is at risk")
	var adult := K.make_folk(w, "Ann", [], 7)
	adult.add_buff("acc_near_water")
	adult.add_buff("acc_unsupervised")
	K.expect(f, Incidents.effective_rate("kids_near_water", adult) == 0.0, "adults are not 'unsupervised children'")
	# surprises off = never
	Incidents.set_level("off")
	K.expect(f, Incidents.effective_rate("choking", c) == 0.0, "Surprises off silences accidents")
	_done()

func _interaction(w: StubWorld, folk: Folk, iid: String, obj_def: String, tile: Vector2i) -> void:
	var o = w.add_object(obj_def, tile)
	var ir := Interaction.create(iid, folk, o.id)
	ir.state = "running"
	folk.current = ir

func _markers(f: Array) -> void:
	var w: StubWorld = _world()
	K.set_time(5, 22, 0)
	var a := K.make_folk(w, "Ada", [], 1, Vector2i(10, 10))
	_interaction(w, a, "fish_pond", "fishing_spot", Vector2i(10, 11))
	AccidentMarks.on_minute()
	K.expect(f, a.has_buff("acc_water"), "fishing sets the water marker")
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(11, 10))
	_interaction(w, b, "eat_meal_good", "table", Vector2i(11, 11))
	var c := K.make_folk(w, "Cy", [], 1, Vector2i(12, 10))
	_interaction(w, c, "exercise", "treadmill", Vector2i(12, 11))
	var d := K.make_folk(w, "Dee", [], 1, Vector2i(13, 10))
	_interaction(w, d, "repair_object", "tv", Vector2i(13, 11))
	var e := K.make_folk(w, "Eli", [], 1, Vector2i(14, 10))
	_interaction(w, e, "repair_object", "plant", Vector2i(14, 11))
	AccidentMarks.on_minute()
	K.expect(f, b.has_buff("acc_eating") and not b.has_buff("acc_water"), "eating sets the eating marker only")
	K.expect(f, c.has_buff("acc_exercise"), "the treadmill sets the exercise marker")
	K.expect(f, d.has_buff("acc_repair_electric"), "repairing a tv sets the electric-repair marker")
	K.expect(f, not e.has_buff("acc_repair_electric"), "repairing something not electric does not")
	# walking to the pond is not fishing
	var g := K.make_folk(w, "Gus", [], 1, Vector2i(20, 20))
	_interaction(w, g, "fish_pond", "fishing_spot", Vector2i(20, 21))
	g.current.state = "walking"
	AccidentMarks.on_minute()
	K.expect(f, not g.has_buff("acc_water"), "only a RUNNING interaction counts")
	# road: night always, day sometimes (deterministic thinning)
	var r := K.make_folk(w, "Rae", [], 1, Vector2i(30, 30))
	Traffic.test_floors[Vector2i(30, 30)] = "crosswalk"
	AccidentMarks.on_minute()
	K.expect(f, r.has_buff("acc_on_road") and r.has_buff("acc_crosswalk") and r.has_buff("acc_near_road"), "a crosswalk at night: on road + crosswalk markers")
	Traffic.test_floors[Vector2i(30, 30)] = "asphalt"
	r.remove_buff("acc_crosswalk")
	r.remove_buff("acc_on_road")
	AccidentMarks.on_minute()
	K.expect(f, r.has_buff("acc_on_road") and not r.has_buff("acc_crosswalk"), "jaywalking: no crosswalk marker")
	Traffic.provider = func(_t, _h): return 0.0
	r.remove_buff("acc_on_road")
	AccidentMarks.on_minute()
	K.expect(f, not r.has_buff("acc_on_road") and r.has_buff("acc_near_road"), "no cars (provider 0): not exposed, still beside the road")
	Traffic.provider = Callable()
	# slippery / icy only outdoors
	var s := K.make_folk(w, "Sam", [], 1, Vector2i(40, 40))
	Weather.force("snow", 0.8)
	Weather.outdoors_fn = func(fk): return fk.tile.x >= 40
	AccidentMarks.on_minute()
	K.expect(f, s.has_buff("acc_slippery") and s.has_buff("acc_icy"), "snow outside: slippery + icy")
	K.expect(f, not a.has_buff("acc_slippery"), "indoors on a dry floor: fine")
	Weather.unforce()
	s.remove_buff("acc_slippery")
	s.remove_buff("acc_icy")
	Weather._wet = 0.9
	AccidentMarks.on_minute()
	K.expect(f, s.has_buff("acc_slippery") and not s.has_buff("acc_icy"), "wet ground outside: slippery, not icy")
	_done()
	w = _world()
	# company: alone vs not, unsupervised children (stub world: everybody is 'near', so a fresh world)
	var kid := K.make_folk(w, "Kit", [], 9, Vector2i(60, 60), "child")
	AccidentMarks.on_minute()
	K.expect(f, kid.has_buff("acc_alone") and kid.has_buff("acc_unsupervised"), "a child with nobody around is alone + unsupervised")
	var mum := K.make_folk(w, "Mum", [], 9, Vector2i(61, 60))
	AccidentMarks.on_minute()
	K.expect(f, not kid.has_buff("acc_alone") and not kid.has_buff("acc_unsupervised"), "a grown-up nearby: neither")
	mum.posture = "lie"
	AccidentMarks.on_minute()
	K.expect(f, kid.has_buff("acc_unsupervised"), "a sleeping grown-up does not supervise")
	# next to water (child), within 4 tiles
	var pond = w.add_object("fishing_spot", Vector2i(62, 60))
	AccidentMarks.on_minute()
	K.expect(f, kid.has_buff("acc_near_water"), "a child beside the pond is marked (%s)" % str(pond.tile))
	_done()

func _townie_markers(f: Array) -> void:
	_world()
	Story.generate_townies()
	K.set_time(5, 12, 0)
	var tid: int = int(Story.alive_townies()[0]["id"])
	var t: Dictionary = Story.townies[tid]
	t["buffs"] = ["keep_me", "acc_stale"]
	t["career"] = "handyperson"
	for h in 24:
		AccidentMarks.on_hour(h)
	K.expect(f, (t["buffs"] as Array).has("keep_me") and not (t["buffs"] as Array).has("acc_stale"), "old markers are replaced, other buffs kept")
	AccidentMarks.on_hour(10)
	K.expect(f, (t["buffs"] as Array).has("acc_job_risky") and (t["buffs"] as Array).has("acc_job_very_risky"), "a handyperson at work is exposed to workplace accidents")
	AccidentMarks.on_hour(22)
	K.expect(f, not (t["buffs"] as Array).has("acc_job_risky"), "...but not at night")
	# deterministic: same day + hour = same markers
	var a1: Array = []
	var a2: Array = []
	for h2 in 24:
		AccidentMarks.on_hour(h2)
		a1.append(str(Story.townies[tid]["buffs"]))
	for h3 in 24:
		AccidentMarks.on_hour(h3)
		a2.append(str(Story.townies[tid]["buffs"]))
	K.expect(f, a1 == a2, "townie exposure is deterministic")
	# markers do appear over a day for the whole town
	var seen: Dictionary = {}
	for h4 in 24:
		AccidentMarks.on_hour(h4)
		for id in Story.townies:
			for b in Story.townies[id]["buffs"]:
				if str(b).begins_with("acc_"):
					seen[str(b)] = true
	K.expect(f, seen.has("acc_eating") and seen.has("acc_on_road"), "the town eats and crosses roads (%s)" % str(seen.keys()))
	_done()
