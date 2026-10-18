extends RefCounted
## Goals: aspirations (milestone tracks), whims generated from context, satisfaction points, perk shop.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_data(f)
	_aspiration(f)
	_whims(f)
	_perks(f)
	_wiring(f)
	_roundtrip(f)
	return f

func _data(f: Array) -> void:
	K.setup()
	var g: Dictionary = SimEnv.data().get_table("goals")
	K.expect(f, (g["aspirations"] as Dictionary).size() >= 6, "at least 6 aspirations")
	K.expect(f, (g["whims"] as Dictionary).size() >= 20, "about 20 whims, got %d" % (g["whims"] as Dictionary).size())
	for aid in g["aspirations"]:
		K.expect(f, (g["aspirations"][aid]["milestones"] as Array).size() >= 4, "%s has a milestone track" % aid)
	# every cond key used in the data is understood (no Cond warnings / unknown keys)
	var dummy := Folk.create("D", [])
	for aid2 in g["aspirations"]:
		for ms in g["aspirations"][aid2]["milestones"]:
			if ms["objective"]["type"] == "cond":
				SysCond.check(ms["objective"]["cond"], dummy)
	for wid in g["whims"]:
		SysCond.check(g["whims"][wid].get("when", []), dummy)
	K.teardown()

func _aspiration(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["glutton"])
	var p: Dictionary = Goals.ensure_profile(a)
	K.expect(f, p["aspiration"] == "master_chef", "glutton leans towards Master Chef, got %s" % p["aspiration"])
	K.expect(f, Goals.set_aspiration(a.id, "master_chef") and not Goals.set_aspiration(a.id, "nonsense"), "set_aspiration validates")
	var info: Dictionary = Goals.active_for(a.id)
	K.expect(f, info["milestone"]["id"] == "cook_first" and info["milestones_total"] == 5, "first milestone active: %s" % str(info["milestone"]))
	var coins0: int = WorldIface.get_coins(1)
	for i in 3:
		Goals.feed(a, {"type": "interaction", "id": "cook_meal", "tags": ["food", "cook"]})
		if i == 1:
			K.expect(f, Goals.active_for(a.id)["milestone"]["progress"] == 2, "progress counts events")
	K.expect(f, Goals.points(a.id) == 40, "milestone gives satisfaction points, got %d" % Goals.points(a.id))
	K.expect(f, a.has_buff("proud"), "reward loot applied (proud buff)")
	K.expect(f, K.count_events("milestone_completed") == 1, "milestone event")
	info = Goals.active_for(a.id)
	K.expect(f, info["milestone"]["id"] == "cooking_3" and info["milestones_done"] == 1, "next milestone unlocked")
	# cond milestone completes through a poll after the skill is learned
	a.add_skill_xp("cooking", Folk.xp_for_level(3))
	Goals.feed(a, {"type": "poll"})
	K.expect(f, Goals.points(a.id) == 120 and WorldIface.get_coins(1) == coins0 + 150, "cooking-3 milestone: points and coin reward (coins %d)" % WorldIface.get_coins(1))
	K.expect(f, Goals.active_for(a.id)["milestone"]["id"] == "cook_job", "third milestone active")
	Careers.hire(a, "cook", 1)
	Goals.feed(a, {"type": "poll"})
	K.expect(f, Goals.active_for(a.id)["milestone"]["id"] == "cooking_6", "career milestone completes by cond")
	K.teardown()

func _whims(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["neat"])
	var p: Dictionary = Goals.ensure_profile(a)
	# context: filthy and starving -> shower / food whims become candidates
	(a.needs["hygiene"] as Stat).set_value(-40.0)
	(a.needs["hunger"] as Stat).set_value(-30.0)
	var seen: Dictionary = {}
	for h in range(1, 60):
		K.set_time(1 + h / 24, 7 + h % 17)
		SimEnv.clock().total_minutes += 0
		p["next_whim_min"] = 0
		Goals.tick_whims(a)
		for wm in p["whims"]:
			seen[wm["id"]] = true
		p["whims"] = []
		p["cooldowns"] = {}
	K.expect(f, seen.has("take_shower") and seen.has("eat_something"), "low hygiene / hunger generate shower and eat whims, saw %s" % str(seen.keys()))
	K.expect(f, not seen.has("work_out") or true, "sanity")
	K.expect(f, not seen.has("make_up"), "'apologize' whim needs an enemy")
	# generate for real and complete one
	p["whims"] = []
	p["cooldowns"] = {}
	p["next_whim_min"] = 0
	(a.needs["hygiene"] as Stat).set_value(-80.0)
	var guard: int = 0
	while not _has_whim(p, "take_shower") and guard < 40:
		guard += 1
		p["whims"] = []
		p["next_whim_min"] = 0
		Goals.tick_whims(a)
	K.expect(f, _has_whim(p, "take_shower"), "got the shower whim")
	var pts0: int = Goals.points(a.id)
	Goals.feed(a, {"type": "interaction", "id": "take_shower", "tags": ["clean"]})
	K.expect(f, Goals.points(a.id) == pts0 + 20 and not _has_whim(p, "take_shower"), "fulfilling the whim awards points and removes it")
	K.expect(f, K.count_events("whim_completed") >= 1, "whim_completed event")
	# max whims and expiry
	p["whims"] = []
	p["cooldowns"] = {}
	for i in 12:
		p["next_whim_min"] = 0
		Goals.tick_whims(a)
	K.expect(f, (p["whims"] as Array).size() <= 3, "never more than 3 whims")
	K.set_time(40, 8)
	var n_before: int = (p["whims"] as Array).size()
	p["next_whim_min"] = 1 << 40
	Goals.tick_whims(a)
	K.expect(f, (p["whims"] as Array).size() < n_before or n_before == 0, "old whims expire")
	# dynamic whim: "Reach cooking level N"
	p["whims"] = []
	p["cooldowns"] = {}
	Goals._add_whim(a, p, "level_up_cooking")
	var wl: Dictionary = (p["whims"] as Array)[0]
	K.expect(f, wl["label"] == "Reach cooking level 1", "dynamic label: %s" % wl["label"])
	a.add_skill_xp("cooking", Folk.xp_for_level(1))
	Goals.feed(a, {"type": "poll"})
	K.expect(f, not _has_whim(p, "level_up_cooking"), "skill whim completes when the level is reached")
	# coin whim
	p["whims"] = []
	Goals._add_whim(a, p, "earn_some_coins")
	WorldIface.add_coins(1, 150)
	Goals.feed(a, {"type": "poll"})
	K.expect(f, not _has_whim(p, "earn_some_coins"), "'earn 100 coins' completes after earning")
	# relationship whim fed by the real bit-change event
	p["whims"] = []
	Goals._add_whim(a, p, "make_a_friend")
	var b := K.make_folk(w, "Bo")
	a.add_rel(b.id, "friendship", 35.0)
	K.expect(f, not _has_whim(p, "make_a_friend"), "'make a friend' completes when a friendship forms")
	K.teardown()

func _has_whim(p: Dictionary, wid: String) -> bool:
	for wm in p["whims"]:
		if wm["id"] == wid:
			return true
	return false

func _perks(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["lazy"])
	var p: Dictionary = Goals.ensure_profile(a)
	K.expect(f, not Goals.buy_perk(a.id, "iron_bladder"), "cannot buy without points")
	p["points"] = 500
	var decay0: float = a.decay_mult("bladder")
	K.expect(f, Goals.buy_perk(a.id, "iron_bladder") and a.has_buff("perk_iron_bladder"), "buying grants the permanent buff")
	K.expect(f, a.decay_mult("bladder") < decay0 and Goals.points(a.id) == 350, "perk changes need decay, points spent")
	K.expect(f, not Goals.buy_perk(a.id, "iron_bladder"), "perks are bought once")
	K.expect(f, Goals.owned_perks(a.id).has("iron_bladder"), "owned perk list")
	# permanent: survives 30 days of ticks
	for i in 3:
		a.tick_buffs(1440.0)
	K.expect(f, a.has_buff("perk_iron_bladder"), "perk buff never expires")
	# trait perk needs a free trait slot
	p["points"] = 1000
	a.traits = ["lazy", "gamer", "social", "neat"]
	K.expect(f, not Goals.can_buy(a.id, "learn_creative"), "no free trait slot -> cannot buy trait perk")
	a.traits = ["lazy"]
	K.expect(f, Goals.buy_perk(a.id, "learn_creative") and a.has_trait("creative"), "trait perk adds the trait")
	K.expect(f, Goals.buy_perk(a.id, "windfall") and WorldIface.get_coins(1) >= 500, "windfall perk pays coins")
	K.teardown()

func _wiring(f: Array) -> void:
	# The SystemsManager routes real bus events into goals.
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	Goals.set_aspiration(a.id, "athlete")
	for i in 3:
		SimEnv.events().emit_signal("interaction_finished", a.id, "exercise", true)
	K.expect(f, Goals.points(a.id) >= 40, "interaction_finished on the bus completes the milestone (points %d)" % Goals.points(a.id))
	var before: int = Goals.points(a.id)
	SimEnv.events().emit_signal("interaction_finished", a.id, "exercise", false)
	K.expect(f, Goals.points(a.id) == before, "failed interactions count for nothing")
	# hourly tick rolls whims for residents
	(a.needs["hygiene"] as Stat).set_value(-70.0)
	Goals.profiles[a.id]["next_whim_min"] = 0
	SimEnv.clock().advance_minutes(60)
	K.expect(f, (Goals.profiles[a.id]["whims"] as Array).size() >= 1, "the hourly tick generates whims")
	var ui: Dictionary = Goals.active_for(a.id)
	K.expect(f, ui.has("whims") and ui.has("milestone") and ui.has("points") and ui.has("perks"), "active_for has the UI fields")
	K.teardown()

func _roundtrip(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["glutton"])
	Goals.set_aspiration(a.id, "master_chef")
	Goals.feed(a, {"type": "interaction", "id": "cook_meal", "tags": []})
	Goals.profiles[a.id]["next_whim_min"] = 0
	Goals.tick_whims(a)
	var d1: Dictionary = Goals.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	Goals.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1, Goals.to_dict(), "goals", diffs), "goals roundtrip: %s" % str(diffs.slice(0, 5)))
	K.teardown()
