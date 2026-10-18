extends RefCounted
## Aging: stages from data, birthdays, age-up (+gating), trait slots, lifespan setting, pregnancy / birth with
## trait inheritance, death with grief, inheritance and legacy summary.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_stages(f)
	_gating(f)
	_growth(f)
	_lifespan(f)
	_baby(f)
	_death(f)
	_roundtrip(f)
	return f

func _stages(f: Array) -> void:
	K.setup()
	K.expect(f, Aging.stage_ids() == ["baby", "toddler", "child", "teen", "adult", "elder"], "six life stages from data: %s" % str(Aging.stage_ids()))
	K.expect(f, Aging.stage_for_days(0.0) == "baby" and Aging.stage_for_days(5.0) == "toddler" and Aging.stage_for_days(20.0) == "child", "stage thresholds")
	K.expect(f, Aging.stage_for_days(30.0) == "teen" and Aging.stage_for_days(60.0) == "adult" and Aging.stage_for_days(150.0) == "elder", "stage thresholds (older)")
	K.expect(f, Aging.trait_slots("baby") == 0 and Aging.trait_slots("child") == 2 and Aging.trait_slots("adult") == 4, "trait slots per stage")
	K.expect(f, Aging.stage_index("teen") == 3, "stage index")
	K.teardown()

func _gating(f: Array) -> void:
	var w := K.setup()
	var comp = w.add_object("computer", Vector2i(10, 10))
	var adult := K.make_folk(w, "Ann", [], 1, Vector2i(10, 11), "adult")
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(10, 12), "child")
	var baby := K.make_folk(w, "Bub", [], 1, Vector2i(10, 13), "baby")
	Aging.set_age_days(kid, 15.0)
	Aging.set_age_days(baby, 1.0)
	K.expect(f, kid.age_stage == "child" and kid.has_buff("stage_child") and not kid.has_buff("stage_adult"), "stage buff marker follows the stage")
	var work_adult := Interaction.create("work_computer", adult, comp.id, true)
	var work_kid := Interaction.create("work_computer", kid, comp.id, true)
	var play_kid := Interaction.create("play_computer", kid, comp.id, true)
	K.expect(f, work_adult.can_run(adult), "adults can work")
	K.expect(f, not work_kid.can_run(kid), "children cannot do 'work' interactions")
	K.expect(f, play_kid.can_run(kid), "children can play on the computer")
	K.expect(f, not Interaction.create("play_computer", baby, comp.id, true).can_run(baby), "babies cannot use the computer")
	K.expect(f, not Interaction.create("flirt", kid, adult.id, true).can_run(kid), "children cannot flirt")
	adult.add_rel(kid.id, "friendship", 30.0)
	K.expect(f, not Interaction.create("flirt", adult, kid.id, true).can_run(adult), "nobody can flirt with a child")
	# the systems-level condition extension
	K.expect(f, SysCond.check([{"age_stage_is": "child"}], kid) and not SysCond.check([{"age_stage_is": "child"}], adult), "age_stage_is condition")
	K.expect(f, SysCond.check([{"age_stage_is": ["teen", "adult"]}], adult), "age_stage_is accepts lists")
	K.expect(f, SysCond.check([{"not": {"age_stage_is": "baby"}}], adult), "not wrapper works with extension keys")
	K.teardown()

func _growth(f: Array) -> void:
	var w := K.setup()
	var t := K.make_folk(w, "Teen", ["social"], 1, Vector2i(12, 12), "teen")
	Aging.set_age_days(t, 42.5)    # adult at 44
	var birthdays: int = 0
	var ups: int = 0
	for d in range(2, 8):
		K.set_time(d, 0)
		Aging.on_day(d)
	birthdays = K.count_events("birthday")
	ups = K.count_events("aged_up")
	K.expect(f, t.age_stage == "adult" and t.has_buff("stage_adult"), "teen grew into an adult, stage=%s" % t.age_stage)
	K.expect(f, ups == 1 and K.last_event("aged_up")["to"] == "adult", "aged_up event")
	K.expect(f, birthdays >= 1 and K.has_note("birthday"), "birthday events and notifications (%d)" % birthdays)
	K.expect(f, t.traits.size() == 2, "growing up reveals a new trait (slots 3->4), traits=%s" % str(t.traits))
	K.expect(f, Aging.age_years(t.id) == int(floor(Aging.age_days(t.id) / 4.0)), "age in years from days_per_year")
	# ageing a child past 28 days makes a teen and drops them out of school
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid, 27.5)
	Careers.on_day(1)
	K.expect(f, Careers.school.has(kid.id), "child in school")
	K.set_time(9, 0)
	Aging.on_day(9)
	K.expect(f, kid.age_stage == "teen" and Careers.school.has(kid.id), "teens still go to school")
	Aging.set_age_days(kid, 43.5)
	K.set_time(10, 0)
	Aging.on_day(10)
	K.expect(f, kid.age_stage == "adult" and not Careers.school.has(kid.id), "adults leave school")
	K.expect(f, Aging.can_add_trait(kid) == (kid.traits.size() < 4), "can_add_trait reflects slots")
	K.teardown()

func _lifespan(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var b := K.make_folk(w, "Bo")
	Aging.set_age_days(a, 50.0)
	Aging.set_age_days(b, 50.0)
	K.expect(f, Aging.age_rate() == 1.0, "normal lifespan rate 1.0")
	Aging.on_day(2)
	K.expect(f, absf(Aging.age_days(a.id) - 51.0) < 0.001, "normal: one day older")
	Aging.set_lifespan("short")
	Aging.on_day(3)
	K.expect(f, absf(Aging.age_days(a.id) - 52.6) < 0.001, "short lifespan ages 1.6x faster")
	Aging.set_lifespan("epic")
	Aging.on_day(4)
	K.expect(f, absf(Aging.age_days(a.id) - 52.9) < 0.001, "epic lifespan ages 0.3x")
	K.teardown()

func _baby(f: Array) -> void:
	var w := K.setup()
	var cfg: Dictionary = SimEnv.data().get_table("aging")
	cfg["pregnancy"]["success_chance"] = 1.0
	cfg["pregnancy"]["inherit_chance"] = 1.0
	var a := K.make_folk(w, "Ann Rowe", ["creative", "social"])
	var b := K.make_folk(w, "Bo Rowe", ["gamer", "active"])
	Aging.set_age_days(a, 60.0)
	Aging.set_age_days(b, 60.0)
	var res: Dictionary = Aging.try_for_baby(a.id, b.id)
	K.expect(f, not res["ok"] and res["reason"] == "not_romantic_enough", "needs romance first: %s" % str(res))
	RelationshipService.add_both(a.id, b.id, "romance", 60.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	res = Aging.try_for_baby(a.id, b.id)
	K.expect(f, res["ok"] and a.has_buff("pregnant"), "pregnancy begins: %s" % str(res))
	K.expect(f, not Aging.try_for_baby(a.id, b.id)["ok"], "no double pregnancy")
	var folk_before: int = w.all_folk().size()
	for d in range(2, 6):
		K.set_time(d, 0)
		Aging.on_day(d)
	K.expect(f, w.all_folk().size() == folk_before + 1, "a baby was born")
	K.expect(f, K.count_events("baby_born") == 1 and not a.has_buff("pregnant"), "baby_born event, pregnancy over")
	var baby: Folk = null
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			baby = fk
	K.expect(f, baby != null and baby.household_id == 1 and baby.name.ends_with("Rowe"), "baby joins the household with the family name")
	if baby != null:
		K.expect(f, baby.traits.is_empty(), "babies start with no traits")
		K.expect(f, RelationshipService.bit_for(baby.id, a.id) == "family" and RelationshipService.bit_for(a.id, baby.id) == "family", "family bits")
		K.expect(f, Aging.children_of(a.id).has(baby.id), "parent knows the child")
		var inh: Array = Aging.records[baby.id]["inherited"]
		K.expect(f, inh.size() == 2, "traits inherited from the parents: %s" % str(inh))
		# toddler stage unlocks the first (inherited) trait
		Aging.set_age_days(baby, 11.5)
		K.set_time(8, 0)
		Aging.on_day(8)
		K.expect(f, baby.age_stage == "child" or baby.age_stage == "toddler", "baby grows")
		K.expect(f, baby.traits.size() >= 1 and inh.has(baby.traits[0]), "first trait comes from the inherited pool: %s" % str(baby.traits))
		var comp = w.add_object("computer", Vector2i(3, 3))
		baby.tile = Vector2i(3, 4)
		K.expect(f, not Interaction.create("work_computer", baby, comp.id, true).can_run(baby), "children do not work")
	# try_for_baby interaction available to adult couples only
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(5, 5), "child")
	Aging.set_age_days(kid, 15.0)
	K.expect(f, not Interaction.create("try_for_baby", kid, a.id, true).can_run(kid), "children cannot try for a baby")
	K.teardown()

func _death(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Old Ann", ["social"], 1)
	var b := K.make_folk(w, "Bo", [], 1)
	var c := K.make_folk(w, "Cy", [], 2)
	var d := K.make_folk(w, "Di", [], 3)
	Aging.set_age_days(a, 160.0)
	WorldIface.coins[1] = 1000
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipService.set_flag(a.id, b.id, "family")
	RelationshipService.add_both(a.id, c.id, "friendship", 80.0)
	RelationshipService.add_both(a.id, d.id, "friendship", 10.0)
	Careers.hire(a, "painter", 2)
	a.add_skill_xp("painting", Folk.xp_for_level(4))
	var legacy: Dictionary = Aging.kill(a.id, "old age")
	K.expect(f, w.get_folk(a.id) == null, "the deceased leaves the world")
	K.expect(f, b.has_buff("grieving") and c.has_buff("grieving") and not d.has_buff("grieving"), "relatives and close friends grieve, strangers do not")
	K.expect(f, K.count_events("died") == 1 and K.has_note("passed away"), "death announced")
	K.expect(f, legacy.has("summary") and str(legacy["summary"]).find("Old Ann") >= 0 and legacy["best_skill"] == "painting", "legacy summary: %s" % str(legacy.get("summary", "")))
	K.expect(f, Aging.dead.size() == 1 and not Careers.has_job(a.id), "legacy recorded, job cleared")
	K.expect(f, WorldIface.get_coins(1) == 1000, "household with survivors keeps its funds")
	# sole survivor-less household: coins go to the closest heir
	var e := K.make_folk(w, "Eve", [], 5)
	var g := K.make_folk(w, "Gus", [], 6)
	WorldIface.coins[5] = 700
	RelationshipService.add_both(e.id, g.id, "friendship", 60.0)
	RelationshipService.set_flag(e.id, g.id, "family")
	var chair = w.add_object("chair", Vector2i(2, 2))
	Economy.owner[chair.id] = 5
	var lg: Dictionary = Aging.kill(e.id)
	K.expect(f, int(lg["inheritance"].get("coins", 0)) == 700 and WorldIface.get_coins(6) == 700 and WorldIface.get_coins(5) == 0, "heir inherits the coins: %s" % str(lg["inheritance"]))
	K.expect(f, int(Economy.owner.get(chair.id, -1)) == 6, "heir inherits the objects")
	# natural death roll: past the max age is certain
	var h := K.make_folk(w, "Hal", [], 7)
	Aging.set_age_days(h, 231.0)
	Aging.on_day(50)
	K.expect(f, w.get_folk(h.id) == null, "death is certain past max age")
	K.teardown()

func _roundtrip(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	Aging.set_age_days(a, 70.0)
	Aging.pregnancies[a.id] = {"father": 99, "due_day": 5, "started": 2}
	Aging.cooldowns[a.id] = 9
	Aging.set_lifespan("long")
	var d1: Dictionary = Aging.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	Aging.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1, Aging.to_dict(), "aging", diffs), "aging roundtrip: %s" % str(diffs.slice(0, 5)))
	K.expect(f, Aging.lifespan() == "long", "lifespan setting persists")
	K.teardown()
