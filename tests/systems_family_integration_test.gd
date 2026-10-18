extends RefCounted
## 20 game days on the stub world with the real clock / director / SystemsManager: a couple (short lifespan setting) tries
## for a baby, the pregnancy runs through its trimesters, the baby is born, cared for by its parents (auto care + crib),
## and grows into a toddler (and further) without child services getting involved.

const K = preload("res://tests/systems_kit.gd")
const DAYS := 20

func run() -> Array:
	var f: Array = []
	var w := K.setup(3030, true)
	var kit = load("res://tests/sim_testkit.gd")
	var objs: Dictionary = kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	w.add_object("bed", Vector2i(14, 14))
	w.add_object("toilet", Vector2i(16, 14))
	w.add_object("sofa", Vector2i(16, 18))
	w.add_object("shower", Vector2i(18, 14))
	w.add_object("crib", Vector2i(20, 18))
	var cfg: Dictionary = SimEnv.data().get_table("aging")
	cfg["pregnancy"]["success_chance"] = 1.0
	var story_cfg: Dictionary = SimEnv.data().get_table("story")      # keep the lot quiet: no visitors, parties or burglars
	story_cfg["visits"]["daily_chance"] = 0.0
	story_cfg["invites"]["daily_chance"] = 0.0
	story_cfg["burglar"]["chance"] = 0.0
	var ann := Folk.create("Ann Reed", ["neat", "social"])
	var bo := Folk.create("Bo Reed", ["creative", "active"])
	for p in [ann, bo]:
		(p as Folk).household_id = 1
	w.add_folk(ann, Vector2i(12, 12))
	w.add_folk(bo, Vector2i(13, 12))
	K.mgr.new_game([1], "short")
	Aging.set_age_days(ann, 60.0)
	Aging.set_age_days(bo, 60.0)
	RelationshipService.add_both(ann.id, bo.id, "romance", 80.0)
	RelationshipService.add_both(ann.id, bo.id, "friendship", 80.0)
	RelationshipService.set_flag(ann.id, bo.id, "partner", true, false)
	var dir = K.director()
	Autonomy.debug_enabled = false      # skip the per-decision debug breakdown (speed)
	var seen: Dictionary = {"stages": [], "max_neglect": 0.0, "tri": [], "baby_id": -1, "birth_day": -1, "min_hunger": 999.0, "cries": 0}
	var tried: bool = false
	var total: int = DAYS * 1440
	var t0: int = Time.get_ticks_msec()
	var step: int = 3          # the director integrates in 3 minute steps to keep the run quick
	for minute in range(step, total + 1, step):
		if minute % 1440 == 1440 - step:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10
		if minute >= 120 and not tried:
			tried = dir.command(ann.id, "try_for_baby", bo.id)
		SimEnv.clock().advance_minutes(step)
		dir.tick_minute(step)
		if minute % 21 == 0:
			var baby = null
			if int(seen["baby_id"]) >= 0:
				baby = w.get_folk(int(seen["baby_id"]))
			else:
				for fk in w.all_folk():
					if str(fk.name).begins_with("Pip") or (Family.parents_of(fk.id).has(ann.id)):
						baby = fk
						seen["baby_id"] = fk.id
						seen["birth_day"] = SysUtil.day()
			if baby != null:
				var st: String = str(baby.age_stage)
				if not (seen["stages"] as Array).has(st):
					(seen["stages"] as Array).append(st)
				seen["max_neglect"] = maxf(float(seen["max_neglect"]), BabyCare.neglect_minutes(baby.id))
				seen["min_hunger"] = minf(float(seen["min_hunger"]), (baby.needs["hunger"] as Stat).value)
				if BabyCare.is_crying(baby.id):
					seen["cries"] += 1
			var tri: int = Family.trimester_of(ann.id)
			if tri > 0 and not (seen["tri"] as Array).has(tri):
				(seen["tri"] as Array).append(tri)
	var ms: int = Time.get_ticks_msec() - t0
	var baby_id: int = int(seen["baby_id"])
	var baby2 = w.get_folk(baby_id) if baby_id >= 0 else null
	print("\n  ===== family integration: %d game days, short lifespan, %d ms real time =====" % [DAYS, ms])
	print("  pregnancy trimesters seen: %s; baby born day %d; stages seen: %s" % [str(seen["tri"]), int(seen["birth_day"]), str(seen["stages"])])
	print("  baby care: max neglect %.0f min, lowest hunger %.0f, %d crying samples, final stage %s" % [float(seen["max_neglect"]), float(seen["min_hunger"]), int(seen["cries"]), str(baby2.age_stage) if baby2 != null else "gone"])
	K.expect(f, tried, "the couple tried for a baby through the interaction")
	K.expect(f, K.count_events("pregnant") == 1 and K.count_events("baby_born") == 1, "one pregnancy, one birth (%d / %d)" % [K.count_events("pregnant"), K.count_events("baby_born")])
	K.expect(f, (seen["tri"] as Array).has(1) and (seen["tri"] as Array).has(2) and (seen["tri"] as Array).has(3), "all three trimesters were lived through: %s" % str(seen["tri"]))
	K.expect(f, baby2 != null and baby_id >= 0, "the baby is still with the family")
	if baby2 != null:
		K.expect(f, (seen["stages"] as Array).has("baby") and (seen["stages"] as Array).has("toddler"), "the baby grew to a toddler: %s" % str(seen["stages"]))
		K.expect(f, baby2.age_stage in ["toddler", "child"], "after 20 days: %s" % baby2.age_stage)
		K.expect(f, Genetics.is_valid(baby2.appearance) and baby2.household_id == 1, "has an appearance and lives in the household")
		K.expect(f, Family.parents_of(baby_id) == [ann.id, bo.id] and Family.relation_label(baby_id, ann.id) == "Parent", "tree knows the parents")
		K.expect(f, float(baby2.skills.get("walking", {"xp": 0.0})["xp"]) > 0.0, "toddler skills grew")
	K.expect(f, float(seen["max_neglect"]) < 6.0 * 60.0, "the parents kept the baby out of child-services range (max neglect %.0f min)" % float(seen["max_neglect"]))
	K.expect(f, K.count_events("child_removed") == 0 and K.count_events("child_services_warning") == 0, "no child-services involvement")
	var cared: int = 0
	for p2 in [ann, bo]:
		for iid in ["feed_baby", "change_diaper", "rock_to_sleep", "play_with_baby", "hold_baby"]:
			cared += int((p2 as Folk).history_counts.get(iid, 0))
	K.expect(f, cared >= 10, "the parents looked after the baby (%d care interactions)" % cared)
	K.expect(f, w.get_folk(ann.id) != null and w.get_folk(bo.id) != null, "both parents are alive")
	Autonomy.debug_enabled = true
	K.teardown()
	return f
