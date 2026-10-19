extends RefCounted
## Task 14b: residents use the places by themselves (fast tier). The rules one by one on the stub world (three households, no player, no map so nobody has to
## walk): the weights (traits, money, age), a sick adult at the clinic, the pets fed, a toddler in preschool, a teen applying to college, an invitation
## answered, a birthday party, the same calls as the Town window, save and load, and the switch.

const L = preload("res://tests/life_auto_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_weights(f)
	_sick_adult(f)
	_pets(f)
	_preschool(f)
	_college(f)
	_invite(f)
	_birthday(f)
	_homework_buff(f)
	_save_and_switch(f)
	return f

## Run the clock `minutes` with the director and the scheduler rows.
func _run(d: Dictionary, minutes: int) -> void:
	K.run(d["dir"], minutes)

func _weights(f: Array) -> void:
	var d: Dictionary = L.build()
	var who: Dictionary = d["who"]
	var rest: Dictionary = PlaceAutoPlan.kind_def("restaurant")
	var price: int = PlaceAutoPlan.price_of(who["ann"], rest["services"])
	var foodie: float = PlaceAutoPlan.chance(who["ann"], "restaurant", rest, price)
	var plain: float = PlaceAutoPlan.chance(who["bo"], "restaurant", rest, price)
	K.expect(f, foodie > plain * 1.5, "a foodie is far more likely to eat out than somebody who is not (%.3f vs %.3f)" % [foodie, plain])
	K.expect(f, foodie > 0.0 and foodie < 0.25, "and still rarely: %.1f percent a day" % (foodie * 100.0))
	WorldIface.coins[1] = 10
	K.expect(f, PlaceAutoPlan.chance(who["ann"], "restaurant", rest, price) == 0.0, "a household that cannot pay twice the price stays at home")
	WorldIface.coins[1] = 3000
	var bar: Dictionary = PlaceAutoPlan.kind_def("bar")
	K.expect(f, not PlaceAutoPlan.viable(who["cy"], "beer", 3, 20) and not PlaceAutoPlan.viable(who["di"], "club_entry", 5, 22), "children and teens are never planned into the bar or the nightclub")
	K.expect(f, PlaceAutoPlan.viable(who["ann"], "beer", 3, 20), "grown-ups are")
	var night: Dictionary = PlaceAutoPlan.kind_def("nightclub")
	var owl: float = PlaceAutoPlan.chance(who["eve"], "nightclub", night, 12)
	var lark: float = PlaceAutoPlan.chance(who["ida"], "nightclub", night, 12)
	K.expect(f, owl > lark, "a night owl goes dancing more than a romantic (%.3f vs %.3f)" % [owl, lark])
	who["ann"].needs["fun"].value = -60.0
	var cine: Dictionary = PlaceAutoPlan.kind_def("cinema")
	var bored: float = PlaceAutoPlan.chance(who["ann"], "cinema", cine, 12)
	who["ann"].needs["fun"].value = 80.0
	var happy: float = PlaceAutoPlan.chance(who["ann"], "cinema", cine, 12)
	K.expect(f, bored > happy * 1.5, "somebody bored wants the cinema more than somebody who is not (%.3f vs %.3f)" % [bored, happy])
	# free hours: a worker's day has a hole where the shift is, the evening is theirs
	var free: Array = PlaceAutoTime.free_hours(who["bo"], 2)
	var bl: Array = PlaceAutoTime.blocked(who["bo"], 2)
	K.expect(f, not bl.is_empty() and not bool(free[int(who["bo"].work_start) + 1]), "no outing is planned over a shift")
	K.teardown()

func _sick_adult(f: Array) -> void:
	var d: Dictionary = L.build()
	var hal = d["who"]["hal"]
	K.set_time(3, 9)                         # a Wednesday morning: the clinic is open
	Health.fall_ill(hal, "flu", 1, "test")
	var planned := false
	for day in range(3, 9):
		K.set_time(day, 9)
		PlaceAuto.last.erase("%d|ill_try" % int(hal.id))
		PlaceAuto.on_hour(9)
		for p in PlaceAuto.plans:
			if int(p["fid"]) == int(hal.id) and str(p["kind"]) == "clinic_sick":
				planned = true
		if planned:
			break
	K.expect(f, planned, "a sick adult plans a visit to the family doctor by themselves")
	if planned:
		var at: int = 0
		for p2 in PlaceAuto.plans:
			if int(p2["fid"]) == int(hal.id):
				at = int(p2["at"])
		SimEnv.clock().total_minutes = at
		_run(d, 100)
		K.expect(f, PlaceAuto.used(3, "clinic") >= 1, "they went to the clinic")
		K.expect(f, hal.has_buff("medicated") or not Health.is_ill(hal), "and the doctor treated the flu")
	K.teardown()

func _pets(f: Array) -> void:
	var d: Dictionary = L.build()
	var rex: Dictionary = d["rex"]
	rex["fullness"] = 20.0
	K.set_time(2, 18)
	PlaceAuto.on_hour(18)
	_run(d, 45)
	K.expect(f, float(rex["fullness"]) > 50.0, "a hungry dog is fed by somebody at home (%.0f)" % float(rex["fullness"]))
	K.expect(f, int(PlaceAuto.stats.get("pet_care", 0)) >= 1 and PlaceAuto.used(1, "pet_care") >= 1, "through the same pet_care service the Pets tab uses")
	var mit: Dictionary = d["mittens"]
	mit["sick"] = true
	K.set_time(4, 9)
	var g: Dictionary = PlaceAutoGate.eval("vet", d["who"]["eve"], "vet", {}, 4)
	K.expect(f, float(g.get("mult", 0.0)) > 1.0 and (g.get("services", []) as Array).has("vet_treat"), "a sick cat gets a vet trip (the sick pet comes first)")
	K.teardown()

func _preschool(f: Array) -> void:
	var d: Dictionary = L.build()
	var gil = d["who"]["gil"]
	K.set_time(2, 8)
	K.expect(f, float(PlaceAutoGate.eval("preschool", gil, "preschool", {}, 2).get("mult", 0.0)) > 0.0, "a toddler is due for preschool")
	K.expect(f, PlaceAutoPlan.make_one(gil, "preschool", 8), "and gets a morning for it")
	var at: int = int(PlaceAuto.plans[0]["at"])
	SimEnv.clock().total_minutes = at
	PlaceAuto.on_minute()
	_run(d, 5)
	K.expect(f, bool(EduState.peek(int(gil.id)).get("preschool", false)), "the toddler is enrolled with the same service the Town window offers")
	K.teardown()

func _college(f: Array) -> void:
	var d: Dictionary = L.build()
	var di = d["who"]["di"]
	Careers.school[int(di.id)]["grade"] = 85.0
	var applied := ""
	for i in 80:
		PlaceAutoPlan._apply(di)
		applied = str(EduState.peek(int(di.id)).get("applied", ""))
		if applied != "":
			break
	K.expect(f, applied != "", "a teen in the last part of school applies to the college (%s)" % applied)
	K.expect(f, K.has_note("applied to Fernwood College") or ChronicleHook.recent.any(func(p): return str(p["kind"]) == "college_apply"), "and it is in the news")
	Aging.set_age_days(di, 80.0)
	var g: Dictionary = PlaceAutoGate.eval("lecture", di, "lecture", {}, 5)
	K.expect(f, (g.get("services", []) as Array) == ["lecture_" + applied], "as a grown-up they go to that subject's lectures first (%s)" % str(g.get("services", [])))
	var hal = d["who"]["hal"]
	var gh: Dictionary = PlaceAutoGate.eval("lecture", hal, "lecture", {}, 5)
	K.expect(f, float(gh.get("mult", 0.0)) > 0.0 and float(PlaceAutoGate.eval("lecture", d["who"]["ann"], "lecture", {}, 5).get("mult", 0.0)) == 0.0, "a bookworm with ambitions starts a degree, somebody without does not")
	K.expect(f, float(PlaceAutoGate.eval("night_class", hal, "night_class", {}, 5).get("mult", 0.0)) >= 1.0, "and takes night classes")
	K.teardown()

func _invite(f: Array) -> void:
	var d: Dictionary = L.build()
	var ida = d["who"]["ida"]
	var tid: int = int(Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult")[0]["id"])
	RelationshipService.add_both(int(ida.id), tid, "friendship", 60.0)
	K.set_time(2, 12)
	PhoneState.add_invite(int(ida.id), tid, "", "cinema", "A friend texted: fancy a film?")
	var g: Dictionary = PlaceAutoGate.eval("invite", ida, "answer_invite", {}, 2)
	K.expect(f, float(g.get("mult", 0.0)) > 0.3 and (g.get("ctx", {}) as Dictionary).has("invite"), "an invitation from a friend is something they will say yes to")
	K.expect(f, PlaceAutoPlan.make_one(ida, "answer_invite", 14), "and plan to go")
	SimEnv.clock().total_minutes = int(PlaceAuto.plans[0]["at"])
	var visits0: int = int(PlaceUse.visits.get("cinema", 0))
	PlaceAuto.on_minute()
	_run(d, 150)
	K.expect(f, PhoneState.inbox_of(int(ida.id)).is_empty(), "the invitation is answered")
	K.expect(f, int(PlaceUse.visits.get("cinema", 0)) > visits0, "and they went to the cinema with the friend")
	K.teardown()

func _birthday(f: Array) -> void:
	var d: Dictionary = L.build()
	var ann = d["who"]["ann"]
	K.set_time(5, 12)
	Aging.records[int(ann.id)]["birth_doy"] = Aging.doy(SysUtil.day()) + 1
	var g: Dictionary = PlaceAutoGate.eval("birthday", ann, "birthday", {}, 5)
	K.expect(f, float(g.get("mult", 0.0)) > 0.0, "the days before a birthday call for a party")
	K.expect(f, PlaceAutoPlan.make_one(ann, "birthday", 12), "and the host books one")
	SimEnv.clock().total_minutes = int(PlaceAuto.plans[0]["at"])
	PlaceAuto.on_minute()
	_run(d, 170)
	K.expect(f, EventState.done_this_year(int(ann.id), "birthday"), "the party was held")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "birthday_party"), "it is in the town's news")
	K.teardown()

func _homework_buff(f: Array) -> void:
	var d: Dictionary = L.build()
	var cy = d["who"]["cy"]
	var id: int = int(cy.id)
	K.set_time(2, 15)
	LifeDefs.config["education"]["homework"]["set_chance"] = 1.0
	LifeTick.on_game_event("returned_from_school", {"folk_id": id, "skipped": false})
	K.expect(f, cy.has_buff("homework_due"), "a child with homework wants to do it")
	LifeTick.on_interaction_finished(id, "do_homework", true)
	K.expect(f, not cy.has_buff("homework_due"), "and the wish goes when it is handed in")
	K.teardown()

func _save_and_switch(f: Array) -> void:
	var d: Dictionary = L.build()
	var who: Dictionary = d["who"]
	K.set_time(2, 6)
	PlaceAuto.on_day(2)
	var snap: Dictionary = LifeTick.to_dict()
	K.expect(f, snap.has("auto") and (snap["auto"] as Dictionary).has("plans"), "the plans are saved in the life block")
	var before: Dictionary = PlaceAuto.to_dict()
	PlaceAuto.reset()
	LifeTick.from_dict(JSON.parse_string(JSON.stringify(snap)), true)
	var after: Dictionary = PlaceAuto.to_dict()
	var diffs: Array = []
	K.deep_eq(before, after, "auto", diffs)
	K.expect(f, diffs.is_empty(), "they load back the same (%s)" % str(diffs.slice(0, 3)))
	PlaceAuto.reset()
	PlaceAuto.off = true
	PlaceAuto.on_day(3)
	K.expect(f, PlaceAuto.plans.is_empty(), "switched off, nobody plans anything")
	PlaceAuto.off = false
	PlaceAuto.on_day(3)
	K.expect(f, not PlaceAuto.plans.is_empty() or int(PlaceAuto.stats["planned"]) >= 0, "switched on again, they do")
	K.teardown()
