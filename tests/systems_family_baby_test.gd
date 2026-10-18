extends RefCounted
## Pregnancy timeline (trimesters), birth with inherited appearance / traits, baby care (adult-only interactions, crib,
## crying, auto care), neglect -> child-services warning -> removal, toddler skills.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_content(f)
	_pregnancy(f)
	_care(f)
	_crying_and_auto_care(f)
	_neglect(f)
	_toddler(f)
	return f

static func _couple(w: StubWorld) -> Array:
	var a := K.make_folk(w, "Ann Rowe", ["creative", "social"])
	var b := K.make_folk(w, "Bo Rowe", ["gamer", "active"], 1, Vector2i(13, 12))
	Aging.set_age_days(a, 60.0)
	Aging.set_age_days(b, 60.0)
	RelationshipService.add_both(a.id, b.id, "romance", 60.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipBits.set_flag(a.id, b.id, "sweetheart", true, false)
	return [a, b]

static func _make_baby(w: StubWorld, parents: Array, nm: String = "Pip Rowe", hid: int = 1) -> Folk:
	var baby := Folk.create(nm)
	baby.household_id = hid
	baby.age_stage = "baby"
	w.add_folk(baby, Vector2i(12, 13))
	Aging.register(baby, 0.0, [parents[0].id, parents[1].id] if parents.size() > 1 else [])
	if parents.size() > 1:
		Family.on_birth(baby, parents[0].id, parents[1].id)
	else:
		BabyCare.on_birth(baby)
	Aging.apply_stage_buff(baby)
	return baby

func _content(f: Array) -> void:
	var w := K.setup()
	var inter: Dictionary = SimEnv.data().interactions()
	for iid in ["feed_baby", "change_diaper", "rock_to_sleep", "play_with_baby", "hold_baby", "have_wedding", "divorce", "adopt_child", "ask_to_move_in", "sleep_crib", "teach_walking", "teach_talking", "teach_potty"]:
		K.expect(f, inter.has(iid), "interaction injected: %s" % iid)
	var crib: Dictionary = SimEnv.data().object_def("crib")
	K.expect(f, not crib.is_empty() and crib["model"] == "res://assets/models/crib.glb" and (crib["interactions"] as Array).has("sleep_crib"), "crib object def injected with the crib model path")
	K.expect(f, SimEnv.data().buffs().has("pregnant_t3") and SimEnv.data().buffs().has("crying"), "family buffs injected")
	var n_before: int = inter.size()
	FamilyContent.install()
	K.expect(f, inter.size() == n_before, "install is idempotent")
	var o = w.add_object("crib", Vector2i(5, 5))
	K.expect(f, o != null, "a crib can be placed in the stub world")
	K.teardown()

func _pregnancy(f: Array) -> void:
	var w := K.setup(31)
	var cfg: Dictionary = SimEnv.data().get_table("aging")
	cfg["pregnancy"]["success_chance"] = 1.0
	var pair: Array = _couple(w)
	var a: Folk = pair[0]
	var b: Folk = pair[1]
	var c := K.make_folk(w, "Cy", ["lazy"], 1, Vector2i(15, 12))
	Aging.set_age_days(c, 60.0)
	RelationshipService.add_both(a.id, c.id, "romance", 60.0)
	K.expect(f, Aging.try_for_baby(a.id, c.id)["reason"] == "not_a_couple", "try for baby needs a sweetheart bond or better")
	K.set_time(1, 8)
	var res: Dictionary = Aging.try_for_baby(a.id, b.id)
	K.expect(f, res["ok"] and a.has_buff("pregnant") and a.has_buff("pregnant_t1"), "pregnancy starts in the first trimester: %s" % str(res))
	K.expect(f, Family.trimester_of(a.id) == 1 and Family.pregnancy_progress(a.id) < 0.01, "progress starts at zero")
	var decay_t1: float = a.decay_mult("bladder")
	K.set_time(2, 20)
	Family.update_pregnancies()
	K.expect(f, Family.trimester_of(a.id) == 2 and a.has_buff("pregnant_t2") and not a.has_buff("pregnant_t1"), "second trimester buff replaces the first")
	a.refresh_mood()
	K.expect(f, a.mood_name == "happy", "second trimester feels good (mood %s)" % a.mood_name)
	K.set_time(3, 20)
	Family.update_pregnancies()
	K.expect(f, Family.trimester_of(a.id) == 3 and a.has_buff("pregnant_t3") and not a.has_buff("pregnant_t2"), "third trimester")
	K.expect(f, a.decay_mult("bladder") > decay_t1 * 1.4, "third trimester needs more bathroom breaks (%.2f vs %.2f)" % [a.decay_mult("bladder"), decay_t1])
	K.expect(f, K.has_note("trimester 3") and K.count_events("trimester") == 3, "trimester transitions are announced (%d events)" % K.count_events("trimester"))
	var folk_before: int = w.all_folk().size()
	K.set_time(4, 0)
	Aging.on_day(4)
	K.expect(f, w.all_folk().size() == folk_before + 1 and not a.has_buff("pregnant") and not a.has_buff("pregnant_t3"), "baby born on the due day, pregnancy buffs cleared")
	var baby: Folk = null
	for fk in w.all_folk():
		if fk.age_stage == "baby":
			baby = fk
	K.expect(f, baby != null and baby.household_id == 1, "baby joins the household")
	if baby != null:
		K.expect(f, Genetics.is_valid(baby.appearance), "baby has an appearance")
		K.expect(f, baby.traits.is_empty(), "no traits at birth")
		K.expect(f, (Aging.records[baby.id]["inherited"] as Array).size() >= 1, "traits are inherited into the pool: %s" % str(Aging.records[baby.id]["inherited"]))
		K.expect(f, FamilyTree.parents_of(baby.id).has(a.id) and FamilyTree.parents_of(baby.id).has(b.id), "family tree knows both parents")
		K.expect(f, a.has_buff("new_parent") and b.has_buff("new_parent"), "new parents get a buff")
		K.expect(f, K.has_note("was born"), "birth notification")
		K.expect(f, (baby.needs["hunger"] as Stat).value > 50.0, "newborn starts content")
		# skin lies between the parents (within mutation)
		var la: Color = Genetics.hex_to_linear(str(a.appearance["skin"]))
		var lb: Color = Genetics.hex_to_linear(str(b.appearance["skin"]))
		var lc: Color = Genetics.hex_to_linear(str(baby.appearance["skin"]))
		var ok: bool = true
		for ch in 3:
			if lc[ch] < minf(la[ch], lb[ch]) - 0.05 or lc[ch] > maxf(la[ch], lb[ch]) + 0.05:
				ok = false
		K.expect(f, ok, "newborn skin between the parents' tones")
	K.teardown()

func _care(f: Array) -> void:
	var w := K.setup(32)
	var pair: Array = _couple(w)
	var a: Folk = pair[0]
	var b: Folk = pair[1]
	var teen := K.make_folk(w, "Teen", [], 1, Vector2i(14, 12), "teen")
	Aging.set_age_days(teen, 30.0)
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(15, 12), "child")
	Aging.set_age_days(kid, 15.0)
	var baby := _make_baby(w, pair)
	var fridge = w.add_object("fridge", Vector2i(12, 16))
	var bed = w.add_object("bed", Vector2i(18, 12))
	var crib = w.add_object("crib", Vector2i(20, 12))
	K.expect(f, baby.has_buff("stage_baby"), "baby marker buff")
	# only adults can care
	for iid in ["feed_baby", "change_diaper", "rock_to_sleep", "play_with_baby", "hold_baby"]:
		for nid in ["bladder", "hunger", "energy", "fun", "social", "hygiene"]:
			(baby.needs[nid] as Stat).set_value(-50.0)
		K.expect(f, Interaction.create(iid, a, baby.id, true).can_run(a), "adult can %s" % iid)
		K.expect(f, not Interaction.create(iid, teen, baby.id, true).can_run(teen), "teen cannot %s" % iid)
		K.expect(f, not Interaction.create(iid, kid, baby.id, true).can_run(kid), "child cannot %s" % iid)
		K.expect(f, not Interaction.create(iid, baby, a.id, true).can_run(baby), "baby cannot %s an adult" % iid)
	# feeding works and needs a hungry baby
	(baby.needs["hunger"] as Stat).set_value(95.0)
	K.expect(f, not Interaction.create("feed_baby", a, baby.id, true).can_run(a), "no feeding a full baby")
	(baby.needs["hunger"] as Stat).set_value(-60.0)
	var ir := Interaction.create("feed_baby", a, baby.id, true)
	K.expect(f, ir.start(), "feed_baby starts")
	ir.tick(30.0)
	K.expect(f, (baby.needs["hunger"] as Stat).value > 20.0, "feeding fills the baby's hunger (%.1f)" % (baby.needs["hunger"] as Stat).value)
	K.expect(f, ir.state == "finished", "feeding finishes")
	(baby.needs["bladder"] as Stat).set_value(-70.0)
	(baby.needs["hygiene"] as Stat).set_value(-40.0)
	var ir2 := Interaction.create("change_diaper", a, baby.id, true)
	ir2.start()
	ir2.tick(10.0)
	K.expect(f, (baby.needs["bladder"] as Stat).value > 40.0 and (baby.needs["hygiene"] as Stat).value > 20.0, "diaper change restores bladder and hygiene")
	(baby.needs["energy"] as Stat).set_value(-70.0)
	var ir3 := Interaction.create("rock_to_sleep", b, baby.id, true)
	ir3.start()
	ir3.tick(40.0)
	K.expect(f, (baby.needs["energy"] as Stat).value > 40.0, "rocking restores energy (%.1f)" % (baby.needs["energy"] as Stat).value)
	(baby.needs["fun"] as Stat).set_value(-50.0)
	(baby.needs["social"] as Stat).set_value(-50.0)
	var ir4 := Interaction.create("play_with_baby", a, baby.id, true)
	ir4.start()
	ir4.tick(30.0)
	var ir5 := Interaction.create("hold_baby", a, baby.id, true)
	ir5.start()
	ir5.tick(30.0)
	K.expect(f, (baby.needs["fun"] as Stat).value > 10.0 and (baby.needs["social"] as Stat).value > 10.0, "play and cuddles restore fun and social")
	K.expect(f, RelationshipService.value(baby.id, a.id, "friendship") > 40.0, "caring builds the bond")
	# babies cannot look after themselves
	(baby.needs["hunger"] as Stat).set_value(-50.0)
	K.expect(f, not Interaction.create("grab_snack", baby, fridge.id, true).can_run(baby), "baby cannot raid the fridge")
	(baby.needs["energy"] as Stat).set_value(-50.0)
	K.expect(f, not Interaction.create("sleep_bed", baby, bed.id, true).can_run(baby), "baby cannot sleep in a bed")
	K.expect(f, Interaction.create("sleep_crib", baby, crib.id, true).can_run(baby), "baby can sleep in a crib")
	K.expect(f, not Interaction.create("sleep_crib", a, crib.id, true).can_run(a), "adults cannot sleep in a crib")
	var dir = K.director()
	baby.tile = Vector2i(20, 13)
	K.run(dir, 120)
	K.expect(f, baby.history_counts.get("sleep_crib", 0) >= 1 or (baby.needs["energy"] as Stat).value > -50.0 or baby.current != null, "an exhausted baby heads for the crib (history %s)" % str(baby.history))
	# babies have no accidents (they need diapers)
	var em: Array = SimEnv.data().interaction_def("have_accident")["emergency"]
	K.expect(f, Cond.check(em, {"folk": baby, "object": null, "target": null}) == false, "babies do not use the emergency accident routine")
	K.teardown()

func _crying_and_auto_care(f: Array) -> void:
	var w := K.setup(33)
	var pair: Array = _couple(w)
	var a: Folk = pair[0]
	var b: Folk = pair[1]
	var baby := _make_baby(w, pair)
	var dir = K.director()
	dir.autonomy_enabled = false
	# nothing to do for a content baby
	BabyCare.evaluate(10.0)
	K.expect(f, not baby.has_buff("crying") and a.queue.is_empty() and b.queue.is_empty(), "content baby: no crying, no care queued")
	(baby.needs["hunger"] as Stat).set_value(-60.0)
	BabyCare.evaluate(10.0)
	K.expect(f, baby.has_buff("crying") and BabyCare.is_crying(baby.id), "hungry baby cries")
	K.expect(f, a.has_buff("baby_crying") and b.has_buff("baby_crying"), "crying stresses the household adults")
	a.refresh_mood()
	K.expect(f, a.mood_name == "tense", "the crying makes parents tense (mood %s)" % a.mood_name)
	var queued: int = 0
	for p in [a, b]:
		for q in p.queue:
			if (q as Interaction).def_id == "feed_baby":
				queued += 1
	K.expect(f, queued == 1, "exactly one parent was sent to feed the baby (%d)" % queued)
	K.run(dir, 25)
	K.expect(f, (baby.needs["hunger"] as Stat).value > 20.0, "baby got fed (%.1f)" % (baby.needs["hunger"] as Stat).value)
	BabyCare.evaluate(10.0)
	K.expect(f, not baby.has_buff("crying"), "crying stops once the need is met")
	K.expect(f, BabyCare.neglect_minutes(baby.id) == 0.0, "no neglect when cared for")
	# via the clock hook: on_minute every 10 minutes
	(baby.needs["bladder"] as Stat).set_value(-60.0)
	K.set_time(1, 12, 0)
	BabyCare.on_minute()
	K.expect(f, baby.has_buff("crying"), "on_minute evaluates on the 10 minute mark")
	# a parent in the middle of a non-interruptible task is skipped; an away parent too
	K.teardown()

func _neglect(f: Array) -> void:
	var w := K.setup(34)
	var pair: Array = _couple(w)
	var a: Folk = pair[0]
	var b: Folk = pair[1]
	var baby := _make_baby(w, pair)
	# the parents are away: nobody can help
	a.set_meta("away", "work")
	b.set_meta("away", "work")
	var bid: int = baby.id
	(baby.needs["hunger"] as Stat).set_value(-95.0)
	var minutes: int = 0
	var warned_at: int = -1
	var removed_at: int = -1
	while minutes < 20 * 60 and w.get_folk(bid) != null:
		(baby.needs["hunger"] as Stat).set_value(-95.0)
		BabyCare.evaluate(10.0)
		minutes += 10
		if warned_at < 0 and K.has_note("Child services has noticed"):
			warned_at = minutes
		if w.get_folk(bid) == null:
			removed_at = minutes
	K.expect(f, warned_at > 0 and warned_at <= 6 * 60 + 10, "child-services warning after about 6 hours of severe neglect (at %d min)" % warned_at)
	K.expect(f, removed_at > 0 and removed_at >= 11 * 60 and removed_at <= 12 * 60 + 10, "baby is taken away after about 12 hours (at %d min)" % removed_at)
	K.expect(f, w.get_folk(bid) == null and K.has_note("taken") and K.count_events("child_removed") == 1, "removal notified, baby no longer on the lot")
	K.expect(f, Story.townies.has(bid) and bool(Story.townies[bid]["orphan"]), "the baby becomes an adoptable orphan townie")
	K.expect(f, FamilyHousehold.adoptable().size() == 1 and BabyCare.removed.size() == 1, "listed as adoptable, removal logged")
	K.expect(f, a.has_buff("grieving") and b.has_buff("grieving"), "parents grieve")
	K.expect(f, FamilyTree.parents_of(bid).size() == 2, "family links survive the removal")
	# adopting the baby back
	a.remove_meta("away")
	b.remove_meta("away")
	var res: Dictionary = FamilyHousehold.adopt(bid, a.id, b.id)
	K.expect(f, res["ok"] and w.get_folk(bid) != null and w.get_folk(bid).age_stage == "baby", "the parents can adopt the baby back: %s" % str(res))
	K.teardown()

	# recovery: neglect shrinks while the baby is fine
	var w2 := K.setup(35)
	var pair2: Array = _couple(w2)
	var baby2 := _make_baby(w2, pair2)
	pair2[0].set_meta("away", "work")
	pair2[1].set_meta("away", "work")
	(baby2.needs["hunger"] as Stat).set_value(-90.0)
	for i in 12:
		BabyCare.evaluate(10.0)
	var peak: float = BabyCare.neglect_minutes(baby2.id)
	K.expect(f, peak >= 119.0, "neglect accumulates (%.0f min)" % peak)
	(baby2.needs["hunger"] as Stat).set_value(60.0)
	for i2 in 6:
		BabyCare.evaluate(10.0)
	K.expect(f, BabyCare.neglect_minutes(baby2.id) < peak - 100.0, "neglect recovers faster than it builds (%.0f)" % BabyCare.neglect_minutes(baby2.id))
	K.teardown()

func _toddler(f: Array) -> void:
	var w := K.setup(36)
	var pair: Array = _couple(w)
	var a: Folk = pair[0]
	var baby := _make_baby(w, pair)
	Aging.set_age_days(baby, 5.0)         # toddler (from day 4)
	K.expect(f, baby.age_stage == "toddler", "toddler stage")
	# the daily routine grows the three skills a little
	for d in range(2, 5):
		K.set_time(d, 0)
		Family.on_day(d)
	var lv: Dictionary = Family.toddler_skill_levels(baby.id)
	K.expect(f, lv.has("walking") and lv.has("talking") and lv.has("potty"), "toddler has walking / talking / potty skills")
	var xp_before: float = float(baby.skills["walking"]["xp"])
	K.expect(f, xp_before > 0.0, "skills grow daily (%.0f xp)" % xp_before)
	# adults teach: lesson interaction -> event -> skill xp for the toddler
	var ir := Interaction.create("teach_walking", a, baby.id, true)
	K.expect(f, ir.can_run(a), "adults can teach a toddler to walk")
	ir.start()
	ir.tick(30.0)
	K.expect(f, float(baby.skills["walking"]["xp"]) >= xp_before + 39.0, "the lesson gave walking xp (%.0f)" % float(baby.skills["walking"]["xp"]))
	K.expect(f, not Interaction.create("teach_walking", a, pair[1].id, true).can_run(a), "only toddlers can be taught")
	# toddlers can be played with and held, but not fed like babies
	K.expect(f, Interaction.create("play_with_baby", a, baby.id, true).can_run(a), "play with a toddler")
	(baby.needs["hunger"] as Stat).set_value(-50.0)
	K.expect(f, not Interaction.create("feed_baby", a, baby.id, true).can_run(a), "feed_baby is for babies only")
	# growing into a child with all skills >= 1 makes the parents proud
	for s in ["walking", "talking", "potty"]:
		baby.add_skill_xp(s, 150.0)
	Aging.set_age_days(baby, 11.9)
	K.set_time(10, 0)
	Aging.on_day(10)
	K.expect(f, baby.age_stage == "child", "grows into a child (%s)" % baby.age_stage)
	K.expect(f, a.has_buff("proud_parent") and K.has_note("proud parents"), "proud parents once the skills are learned")
	K.expect(f, not BabyCare.state.has(baby.id), "baby care state is dropped when no longer a baby")
	K.teardown()
