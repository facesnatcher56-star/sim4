extends RefCounted
## Every extra interaction runs end-to-end through the real Interaction / Cond / Loot engine on a stub world,
## plus behavioural checks: cooking tiers, spoilage, garden growth, fireplace reset, trait refusals and autonomy weights.

const K = preload("res://tests/content_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_all_interactions(f)
	_cooking_tiers(f)
	_daily_rules(f)
	_traits_decide(f)
	_effects(f)
	return f

func _first_object_for(iid: String, d: Dictionary) -> String:
	var objs: Dictionary = SimEnv.data().objects()
	var only: Array = d.get("objects", [])
	for oid in only:
		if objs.has(oid) and (objs[oid]["interactions"] as Array).has(iid):
			return str(oid)
	for oid2 in only:
		if objs.has(oid2):
			return str(oid2)
	return ""

func _all_interactions(f: Array) -> void:
	var legacy: Dictionary = K.read_json("res://tests/content_legacy_ids.json")
	var legacy_ints: Array = legacy["interactions"]
	var data = SimEnv.data()
	var ran := 0
	var iids: Array = []
	Kit.setup()
	data = SimEnv.data()
	for iid in data.interactions():
		if not legacy_ints.has(iid):
			iids.append(iid)
	# extended legacy interactions must still run on the new objects
	var extra_pairs: Array = [["sleep_bed", "single_bed"], ["sleep_bed", "bunk_bed"], ["sit_chair", "dining_chair"], ["sit_chair", "bar_stool"],
		["read_book", "bookcase_tall"], ["toggle_lamp", "nightstand"], ["toggle_lamp", "ceiling_fan"], ["toggle_lamp", "pendant_light"],
		["paint_canvas", "easel_large"], ["clean_object", "grill"], ["clean_object", "hot_tub"], ["clean_object", "fridge"]]
	Kit.teardown()
	for iid in iids:
		var w := Kit.setup(777)
		var d: Dictionary = SimEnv.data().interaction_def(iid)
		var f1 := K.new_folk(w, "Tester")
		var f2: Folk = null
		if str(d.get("target", "object")) == "folk":
			f2 = K.new_folk(w, "Partner", [], Vector2i(13, 12))
		var odef := _first_object_for(iid, d)
		if str(d.get("target", "object")) == "object" and odef == "":
			f.append("interaction %s: no object to run it on" % iid)
			Kit.teardown()
			continue
		var res: Dictionary = K.run_interaction(w, iid, odef, f1, f2)
		Kit.expect(f, bool(res["ok"]), "interaction %s on %s: %s" % [iid, odef, str(res["why"])])
		if bool(res["ok"]):
			ran += 1
			var ir: Interaction = res["ir"]
			Kit.expect(f, ir.success, "interaction %s finished but not successfully" % iid)
		Kit.teardown()
	for pr in extra_pairs:
		var w2 := Kit.setup(778)
		var d2: Dictionary = SimEnv.data().interaction_def(str(pr[0]))
		var f3 := K.new_folk(w2, "Tester")
		var res2: Dictionary = K.run_interaction(w2, str(pr[0]), str(pr[1]), f3)
		Kit.expect(f, bool(res2["ok"]), "legacy interaction %s on new object %s: %s" % [pr[0], pr[1], str(res2["why"])])
		Kit.teardown()
	Kit.expect(f, ran >= 50, "at least 50 new interactions should run, ran %d" % ran)
	print("  content_run: %d new interactions ran to completion" % ran)

func _cooking_tiers(f: Array) -> void:
	var w := Kit.setup(31)
	var stove = w.add_object("stove", Vector2i(10, 10))
	var chef := K.new_folk(w, "Chef", [], Vector2i(10, 12))
	(chef.needs["hunger"] as Stat).set_value(-30.0)
	var rookie := K.new_folk(w, "Rookie", [], Vector2i(14, 12))
	(rookie.needs["hunger"] as Stat).set_value(-30.0)
	chef.add_skill_xp("cooking", Folk.xp_for_level(6) + 1.0)
	var good := Interaction.create("cook_meal_good", rookie, stove.id)
	var gourmet := Interaction.create("cook_meal_gourmet", rookie, stove.id)
	Kit.expect(f, not good.can_run(rookie, stove) and not gourmet.can_run(rookie, stove), "cooking tiers: level 0 cannot cook good/gourmet meals")
	var gourmet_c := Interaction.create("cook_meal_gourmet", chef, stove.id)
	var basic_c := Interaction.create("cook_meal", chef, stove.id)
	Kit.expect(f, gourmet_c.can_run(chef, stove), "cooking tiers: level 6 unlocks the gourmet meal")
	var sg: float = float(Autonomy.evaluate(chef, {"id": "cook_meal_gourmet", "target_id": stove.id, "kind": "object", "obj": stove, "folk": null})["score"])
	var sb: float = float(Autonomy.evaluate(chef, {"id": "cook_meal", "target_id": stove.id, "kind": "object", "obj": stove, "folk": null})["score"])
	Kit.expect(f, sg > sb, "cooking tiers: a skilled cook prefers the gourmet meal (%.2f vs %.2f)" % [sg, sb])
	# gourmet cook -> gourmet eat -> bigger hunger/fun and the gourmet buff
	var table = w.add_object("table", Vector2i(10, 14))
	var res: Dictionary = K.run_interaction(w, "cook_meal_gourmet", "stove", chef)
	Kit.expect(f, bool(res["ok"]) and chef.has_buff("meal_ready_gourmet"), "gourmet cook leaves a gourmet meal ready")
	Kit.expect(f, not Interaction.create("cook_meal", chef, stove.id).can_run(chef, stove), "basic cooking is blocked while a better meal is ready")
	var h0: float = chef.get_stat_value("hunger")
	var fun0: float = chef.get_stat_value("fun")
	(chef.needs["fun"] as Stat).set_value(0.0)
	fun0 = 0.0
	(chef.needs["hunger"] as Stat).set_value(-40.0)
	h0 = -40.0
	var eat := Interaction.create("eat_meal_gourmet", chef, table.id, true)
	Kit.expect(f, eat.can_run(chef, table), "gourmet meal can be eaten at the table")
	eat.start()
	var guard := 0
	while eat.state != "finished" and guard < 100:
		eat.tick(1.0)
		guard += 1
	Kit.expect(f, chef.has_buff("well_fed_gourmet") and not chef.has_buff("meal_ready_gourmet"), "eating gourmet gives well_fed_gourmet and consumes the plate")
	var gain_g: float = chef.get_stat_value("hunger") - h0
	# a basic meal for comparison
	var other := K.new_folk(w, "Basic", [], Vector2i(16, 12))
	(other.needs["hunger"] as Stat).set_value(-40.0)
	other.add_buff("meal_ready")
	var eat_b := Interaction.create("eat_meal", other, table.id, true)
	eat_b.start()
	guard = 0
	while eat_b.state != "finished" and guard < 100:
		eat_b.tick(1.0)
		guard += 1
	var gain_b: float = other.get_stat_value("hunger") + 40.0
	Kit.expect(f, gain_g > gain_b, "gourmet meal restores more hunger than a basic one (%.1f vs %.1f)" % [gain_g, gain_b])
	Kit.expect(f, chef.get_stat_value("fun") > 0.0, "gourmet meal also lifts fun")
	var well: Dictionary = SimEnv.data().buff_def("well_fed_gourmet")
	var base: Dictionary = SimEnv.data().buff_def("well_fed")
	Kit.expect(f, int(well["mood"]["happy"]) > int(base["mood"]["happy"]) and float(well["need_decay_mult"]["hunger"]) < float(base["need_decay_mult"]["hunger"]), "well_fed_gourmet is a stronger buff than well_fed")
	Kit.teardown()

func _daily_rules(f: Array) -> void:
	var w := Kit.setup(55)
	SysUtil.seed_rng(55)
	# spoilage
	var fr = w.add_object("fridge", Vector2i(10, 10))
	WorldIface.state_set(fr, "stock", 10.0)
	var spoiled_total := 0
	for day in 12:
		spoiled_total += ContentRules.apply_object_day(fr)
	Kit.expect(f, spoiled_total > 0 and float(WorldIface.state_get(fr, "spoiled", 0.0)) > 0.0, "fridge stock spoils over days (lost %d)" % spoiled_total)
	Kit.expect(f, float(WorldIface.state_get(fr, "stock", 10.0)) < 10.0, "spoiled items leave the stock")
	Kit.expect(f, float(WorldIface.state_get(fr, "dirtiness", 0.0)) > 0.0, "spoiled food makes a mess")
	var folk := K.new_folk(w, "Neat")
	var res: Dictionary = K.run_interaction(w, "toss_spoiled_food", "fridge", folk)
	Kit.expect(f, bool(res["ok"]), "toss_spoiled_food runs: %s" % str(res["why"]))
	WorldIface.state_set(fr, "stock", 0.0)
	Kit.expect(f, ContentRules.apply_object_day(fr) == 0, "an empty fridge spoils nothing")
	# garden: needs water to grow, then becomes harvestable
	var gp = w.add_object("garden_plot", Vector2i(14, 10))
	WorldIface.state_set(gp, "growth", 1.0)
	WorldIface.state_set(gp, "water", 6.0)
	for day2 in 4:
		ContentRules.apply_object_day(gp)
		WorldIface.state_set(gp, "water", 6.0)
	Kit.expect(f, float(WorldIface.state_get(gp, "growth", 0.0)) > 7.0, "a watered garden plot grows to harvest (growth %.1f)" % float(WorldIface.state_get(gp, "growth", 0.0)))
	WorldIface.state_set(gp, "growth", 1.0)
	WorldIface.state_set(gp, "water", 0.0)
	ContentRules.apply_object_day(gp)
	Kit.expect(f, float(WorldIface.state_get(gp, "growth", 0.0)) == 1.0, "a dry garden plot does not grow")
	var gard := K.new_folk(w, "Gardener", [], Vector2i(14, 12))
	WorldIface.state_set(gp, "growth", 9.0)
	var res2: Dictionary = K.run_interaction(w, "harvest_crops", "garden_plot", gard)
	Kit.expect(f, bool(res2["ok"]) and gard.has_buff("fresh_produce"), "harvest gives fresh produce")
	# fireplace burns out overnight; alarm batteries drain; laundry piles up
	var fp = w.add_object("fireplace", Vector2i(18, 10))
	WorldIface.state_set(fp, "lit", true)
	ContentRules.apply_object_day(fp)
	Kit.expect(f, not bool(WorldIface.state_get(fp, "lit", true)), "the fire burns out by the next day")
	var sa = w.add_object("smoke_alarm", Vector2i(20, 10))
	ContentRules.apply_object_day(sa)
	Kit.expect(f, float(WorldIface.state_get(sa, "battery", 10.0)) < 10.0, "alarm batteries drain")
	var wm = w.add_object("washing_machine", Vector2i(22, 10))
	WorldIface.state_set(wm, "fullness", 0.0)
	for d3 in 3:
		ContentRules.apply_object_day(wm)
	Kit.expect(f, float(WorldIface.state_get(wm, "fullness", 0.0)) > 4.0, "laundry piles up until it is worth a wash")
	Kit.teardown()

func _score(folk: Folk, iid: String, obj) -> Dictionary:
	return Autonomy.evaluate(folk, {"id": iid, "target_id": obj.id, "kind": "object", "obj": obj, "folk": null})

func _traits_decide(f: Array) -> void:
	var w := Kit.setup(91)
	var vend = w.add_object("vending_machine", Vector2i(10, 10))
	var tub = w.add_object("hot_tub", Vector2i(14, 10))
	var gs = w.add_object("guitar_stand", Vector2i(18, 10))
	var frugal := K.new_folk(w, "Frugal", ["frugal"])
	var normal := K.new_folk(w, "Normal")
	var foodie := K.new_folk(w, "Foodie", ["foodie"])
	var germ := K.new_folk(w, "Germ", ["germaphobe"])
	var musical := K.new_folk(w, "Musical", ["musical"])
	for p in [frugal, normal, foodie, germ, musical]:
		(p.needs["hunger"] as Stat).set_value(-20.0)
		(p.needs["comfort"] as Stat).set_value(-20.0)
		p.household_id = 1
	WorldIface.coins[1] = 500
	Kit.expect(f, bool(_score(frugal, "buy_snack", vend)["skipped"]), "frugal folk refuse to buy from the vending machine")
	Kit.expect(f, bool(_score(foodie, "buy_snack", vend)["skipped"]), "foodies refuse junk food")
	Kit.expect(f, not bool(_score(normal, "buy_snack", vend)["skipped"]), "ordinary folk will buy a snack")
	Kit.expect(f, bool(_score(germ, "soak_hot_tub", tub)["skipped"]) and bool(_score(germ, "buy_snack", vend)["skipped"]), "germaphobes avoid the hot tub and the vending machine")
	Kit.expect(f, not bool(_score(normal, "soak_hot_tub", tub)["skipped"]), "ordinary folk soak in the hot tub")
	musical.add_skill_xp("guitar", 10.0)
	normal.add_skill_xp("guitar", 10.0)
	var sm: float = float(_score(musical, "play_guitar", gs)["score"])
	var sn: float = float(_score(normal, "play_guitar", gs)["score"])
	Kit.expect(f, sm > sn * 1.5, "musical folk are much more drawn to the guitar (%.2f vs %.2f)" % [sm, sn])
	var clumsy := K.new_folk(w, "Clumsy", ["clumsy"])
	clumsy.add_skill_xp("handiness", Folk.xp_for_level(3) + 1.0)
	var wb = w.add_object("workbench", Vector2i(22, 10))
	Kit.expect(f, bool(_score(clumsy, "build_gadget", wb)["skipped"]), "clumsy folk refuse to build gadgets")
	Kit.teardown()

func _effects(f: Array) -> void:
	# decision-changing buffs: caffeine, tipsy, melodic
	var w := Kit.setup(5)
	var folk := K.new_folk(w, "Fx")
	folk.add_buff("caffeinated")
	var e0: float = (folk.needs["energy"] as Stat).value
	folk.tick_needs(60.0)
	var fast: float = e0 - (folk.needs["energy"] as Stat).value
	folk.remove_buff("caffeinated")
	(folk.needs["energy"] as Stat).set_value(e0)
	folk.tick_needs(60.0)
	var base: float = e0 - (folk.needs["energy"] as Stat).value
	Kit.expect(f, fast < base, "caffeinated slows energy decay (%.2f vs %.2f)" % [fast, base])
	# brew coffee: needs beans, uses one
	var cm = w.add_object("coffee_maker", Vector2i(10, 10))
	var res: Dictionary = K.run_interaction(w, "brew_coffee", "coffee_maker", folk)
	Kit.expect(f, bool(res["ok"]) and folk.has_buff("caffeinated") and float(WorldIface.state_get(res["obj"], "beans", 8.0)) < 8.0, "brew_coffee uses beans and gives the buff")
	# broken things get repaired
	var tv = w.add_object("tv", Vector2i(14, 10))
	WorldIface.state_set(tv, "broken", true)
	var rep := Interaction.create("repair_object", folk, tv.id, true)
	Kit.expect(f, rep.can_run(folk, tv), "repair_object works on broken objects")
	rep.start()
	var guard := 0
	while rep.state != "finished" and guard < 100:
		rep.tick(1.0)
		guard += 1
	Kit.expect(f, not bool(WorldIface.state_get(tv, "broken", true)), "repair_object fixes the object")
	Kit.expect(f, folk.skill_level("handiness") >= 0 and float((folk.skills["handiness"] as Dictionary)["xp"]) > 0.0, "repairing trains handiness")
	var rep2 := Interaction.create("repair_object", folk, tv.id, true)
	Kit.expect(f, not rep2.can_run(folk, tv), "nothing to repair on a working TV")
	# new skills level through xp alone
	for s in ["guitar", "piano", "gardening", "fishing", "writing"]:
		folk.add_skill_xp(s, Folk.xp_for_level(2) + 1.0)
		Kit.expect(f, folk.skill_level(s) == 2, "new skill %s levels up without registration" % s)
	var d2: Dictionary = folk.to_dict()
	var back: Folk = Folk.from_dict(JSON.parse_string(JSON.stringify(d2)))
	Kit.expect(f, back.skill_level("guitar") == 2 and back.skill_level("fishing") == 2, "new skills survive save/load")
	Kit.teardown()
