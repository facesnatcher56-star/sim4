extends RefCounted
## Save / load of the family layer: a pregnancy mid-way, a baby with an inherited appearance and a neglect meter, the tree
## (parents, adoptive, spouses, exes, engagements), moved-out people and orphans; plus old saves without the new blocks.

const K = preload("res://tests/systems_kit.gd")
const SLOT := 95

func run() -> Array:
	var f: Array = []
	_roundtrip(f)
	_old_save(f)
	return f

func _roundtrip(f: Array) -> void:
	var w := K.setup(51)
	var cfg: Dictionary = SimEnv.data().get_table("aging")
	cfg["pregnancy"]["success_chance"] = 1.0
	var mum := K.make_folk(w, "Mia Rowe", ["creative", "social"])
	var dad := K.make_folk(w, "Dan Rowe", ["gamer"], 1, Vector2i(13, 12))
	var other := K.make_folk(w, "Eli Park", ["lazy"], 1, Vector2i(14, 12))
	var fiancee := K.make_folk(w, "Fay Park", [], 1, Vector2i(15, 12))
	for p in [mum, dad, other, fiancee]:
		Aging.set_age_days(p, 94.0)
	RelationshipService.add_both(mum.id, dad.id, "romance", 80.0)
	RelationshipService.add_both(mum.id, dad.id, "friendship", 80.0)
	RelationshipBits.set_flag(mum.id, dad.id, "partner", true, false)
	FamilyMarriage.propose_marriage(mum.id, dad.id)
	FamilyMarriage.marry(mum.id, dad.id)
	# a baby born earlier, with the neglect meter running
	var baby := Folk.create("Pip Rowe")
	baby.household_id = 1
	baby.age_stage = "baby"
	w.add_folk(baby, Vector2i(12, 14))
	Aging.register(baby, 1.0, [mum.id, dad.id])
	Family.on_birth(baby, mum.id, dad.id)
	Aging.apply_stage_buff(baby)
	baby.appearance = Genetics.inherit(mum, dad)["appearance"]
	BabyCare.state[baby.id]["neglect"] = 137.0
	BabyCare.state[baby.id]["warned"] = true
	# someone else's engagement, an ex, an orphan, a moved-out person
	RelationshipService.add_both(other.id, fiancee.id, "romance", 80.0)
	RelationshipService.add_both(other.id, fiancee.id, "friendship", 80.0)
	RelationshipBits.set_flag(other.id, fiancee.id, "partner", true, false)
	FamilyMarriage.propose_marriage(other.id, fiancee.id)
	Family.exes[other.id] = [4242]
	Family.note_person(4242, "Old Flame")
	Story.generate_townies(6)
	var orphans: Array = FamilyHousehold.spawn_orphans(2)
	var leaver := K.make_folk(w, "Lee Gone", [], 1, Vector2i(16, 12))
	FamilyHousehold.move_out(leaver.id, 0.0)
	# the second pregnancy, half way through
	K.set_time(1, 8)
	var fresh := K.make_folk(w, "Gwen Rowe", ["neat"], 1, Vector2i(17, 12))
	Aging.set_age_days(fresh, 94.0)
	RelationshipService.add_both(fresh.id, dad.id, "romance", 60.0)
	RelationshipBits.set_flag(fresh.id, dad.id, "sweetheart", true, false)
	K.expect(f, Aging.try_for_baby(fresh.id, dad.id)["ok"], "precondition: a pregnancy begins")
	K.set_time(2, 20)
	Family.update_pregnancies()
	K.expect(f, Family.trimester_of(fresh.id) == 2 and fresh.has_buff("pregnant_t2"), "precondition: second trimester")
	var snap_before: Dictionary = SaveLoad.snapshot("family")
	var raw_saved: bool = SaveLoad.save(SLOT, "Family household")
	K.expect(f, raw_saved, "family state saves: %s" % SaveLoad.last_error)
	var raw: Dictionary = SaveLoad.read(SLOT)
	K.expect(f, raw["systems"].has("family") and raw["systems"].has("babycare"), "family + babycare blocks in the file")
	# wreck
	var skin: String = str(baby.appearance["skin"])
	var hair: int = int(baby.appearance["hair_style"])
	var due: int = int(Aging.pregnancies[fresh.id]["due_day"])
	Family.reset()
	BabyCare.reset()
	Aging.reset()
	RelationshipService.reset()
	Story.reset()
	for fk in w.all_folk().duplicate():
		fk.current = null
		fk.queue.clear()
		SysUtil.world_remove_folk(fk.id)
	K.expect(f, SaveLoad.load(SLOT), "load succeeds: %s" % SaveLoad.last_error)
	var snap_after: Dictionary = SaveLoad.snapshot("family")
	var diffs: Array = []
	K.expect(f, K.deep_eq(snap_before, snap_after, "save", diffs), "state after load equals the saved state: %s" % str(diffs.slice(0, 8)))
	# specifics
	var b2 = w.get_folk(baby.id)
	K.expect(f, b2 != null and b2.age_stage == "baby" and str(b2.appearance["skin"]) == skin and int(b2.appearance["hair_style"]) == hair, "baby keeps its appearance")
	K.expect(f, b2 != null and Genetics.is_valid(b2.appearance) and b2.appearance["hair_style"] is int, "appearance types restored")
	K.expect(f, absf(BabyCare.neglect_minutes(baby.id) - 137.0) < 0.001 and bool(BabyCare.state[baby.id]["warned"]), "neglect meter restored")
	K.expect(f, FamilyTree.parents_of(baby.id) == [mum.id, dad.id] and FamilyTree.spouse_of(mum.id) == dad.id, "tree + marriage restored")
	K.expect(f, FamilyMarriage.is_engaged(other.id, fiancee.id) and FamilyTree.fiance_of(other.id) == fiancee.id, "engagement restored")
	K.expect(f, (Family.exes[other.id] as Array) == [4242] and Family.name_of(4242) == "Old Flame", "exes + people restored")
	K.expect(f, FamilyTree.relation_id(baby.id, mum.id) == "parent", "relation ids work after loading")
	K.expect(f, FamilyHousehold.adoptable().size() == orphans.size(), "orphans restored (%d)" % FamilyHousehold.adoptable().size())
	K.expect(f, Story.townies.has(leaver.id) and Genetics.is_valid(Story.townies[leaver.id]["appearance"]), "moved-out person is a townie with an appearance")
	K.expect(f, Aging.pregnancies.has(fresh.id) and Family.trimester_of(fresh.id) == 2 and Family.pregnancy_progress(fresh.id) > 0.4, "pregnancy mid-way restored (progress %.2f)" % Family.pregnancy_progress(fresh.id))
	var fresh2 = w.get_folk(fresh.id)
	K.expect(f, fresh2 != null and fresh2.has_buff("pregnant") and fresh2.has_buff("pregnant_t2"), "pregnancy buffs restored")
	# the restored game carries on: third trimester, birth, wedding, baby care
	K.set_time(3, 20)
	Family.update_pregnancies()
	K.expect(f, Family.trimester_of(fresh.id) == 3 and fresh2.has_buff("pregnant_t3"), "restored pregnancy moves on to the third trimester")
	var count: int = w.all_folk().size()
	K.set_time(due, 0)
	Aging.on_day(due)
	K.expect(f, w.all_folk().size() == count + 1, "restored pregnancy ends in a birth")
	K.expect(f, FamilyMarriage.marry(other.id, fiancee.id), "restored engagement leads to a wedding")
	BabyCare.evaluate(10.0)
	K.expect(f, BabyCare.neglect_minutes(baby.id) >= 137.0 or w.get_folk(baby.id) != null, "baby care keeps evaluating")
	SaveLoad.delete_slot(SLOT)
	K.teardown()

func _old_save(f: Array) -> void:
	var w := K.setup(52)
	var a := K.make_folk(w, "Ann")
	var snap: Dictionary = SaveLoad.snapshot("old")
	(snap["systems"] as Dictionary).erase("family")
	(snap["systems"] as Dictionary).erase("babycare")
	var folk_list: Array = snap["folk"]
	for fd in folk_list:
		(fd as Dictionary).erase("appearance")
	K.expect(f, SaveLoad.restore(snap), "a save without the family blocks and appearances still loads")
	var back = w.get_folk(a.id)
	K.expect(f, back != null and back.appearance.is_empty(), "old folk have an empty appearance...")
	Genetics.ensure_all()
	K.expect(f, Genetics.is_valid(back.appearance), "...which Genetics.ensure_all() fills in")
	K.expect(f, Family.people.is_empty() and BabyCare.state.is_empty(), "family state starts empty")
	K.teardown()
