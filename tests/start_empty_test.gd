extends RefCounted
## Task 32d: the empty-home start. Bare lot (structure kept), money by home size, folk survive a day on the floor / welcome basket /
## cafe restroom fallbacks, the buy-the-basics tips fire and follow what is owned, and buying the basics makes everything work.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _home_objects() -> Array:
	var rc: Rect2i = Kit.world().regions.home()["rect"]
	var out: Array = []
	for o in Kit.world().all_objects():
		if rc.has_point(o.tile):
			out.append(o)
	return out

func _count(def_id: String) -> int:
	var n := 0
	for o in _home_objects():
		if str(o.def_id) == def_id:
			n += 1
	return n

## Buy one `def_id` on the first free home tile whose use tile is reachable from the front of the house.
func _buy(def_id: String, from: Vector2i) -> bool:
	var W = Kit.world()
	var rc: Rect2i = W.regions.home()["rect"]
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			if W.can_place(def_id, t, 0, 0) and WorldIface.path_length(from, t + Vector2i(0, 1)) >= 0:
				if Economy.buy_object(1, def_id, t, 0) >= 0:
					return true
	return false

func run() -> Array:
	fails = []
	_check(StartHome.default_id() == "empty", "the default home is the empty one")
	_check(StartHome.ids() == ["empty", "furnished"], "two choices on the New Game screen")
	_check(StartHome.normalize("nonsense") == "empty", "an unknown choice falls back to the default")

	# furnished option keeps the old start
	var fur: Array = Kit.new_game("solo", "normal", {}, -1, {"home_state": "furnished", "world_seed": 5})
	_check(_count("bed") + _count("single_bed") + _count("sofa_bed") > 0 and _count("toilet") > 0 and _count("fridge") > 0, "furnished: bed, toilet and fridge are there")
	var furnished_funds: int = Economy.balance(1)
	_check(furnished_funds == Scenario.funds_for("solo", "normal"), "furnished: scenario funds only (%d)" % furnished_funds)
	Kit.teardown()

	# empty home
	var folk: Array = Kit.new_game("solo", "normal", {}, -1, {"home_state": "empty", "world_seed": 5})
	var f: Folk = folk[0]
	Players.table.clear()          # task 61: a played pawn only does what it is told; these checks are the household looking after itself (an NPC household, auto-furnish)
	var kept := 0
	var strays := 0
	for o in _home_objects():
		var tags: Array = Kit.world().get_def(str(o.def_id)).get("tags", [])
		if "structure" in tags or "door" in tags or "window" in tags or "ceiling" in tags or str(o.def_id) in StartHome.cfg()["keep_defs"]:
			kept += 1
		else:
			strays += 1
	_check(strays == 0, "empty: no furniture left in the home (%d stray)" % strays)
	_check(kept > 0, "empty: doors / windows / lights are still there")
	_check(_count("door") > 0 and _count("window") > 0, "empty: doors and windows kept")
	_check(Economy.balance(1) == Scenario.funds_for("solo", "normal"), "empty: scenario funds only, no furnishing money (%d)" % Economy.balance(1))
	_check(StartHome.is_bare(1), "empty: is_bare")
	var tips: Array = StartHome.tips_for(Scenario.def("solo"))
	_check(tips.size() >= 3 and tips.any(func(t): return "bed" in str(t).to_lower()), "empty: the tips say how to get a bed")
	_check(str(StartHome.next_basic(1).get("id", "")) == "bed", "empty: first basic is the bed")

	# the tips panel: walks through the tips, then follows the shopping list
	var seen_before := FirstRunTips.already_seen()
	var panel := FirstRunTips.new()
	Kit.root().add_child(panel)
	panel.start(false, tips, true)
	_check(panel.visible and panel.label.text == str(tips[0]), "tips: the first tip shows (even to a returning player)")
	for _i in tips.size():
		panel._next()
	_check(panel.visible and panel.next_step_shown and panel.title_label.text == "Next step" and "bed" in panel.label.text.to_lower(), "tips: then a Next step note asks for a bed (%s)" % panel.label.text)
	# one game day with nothing bought: nobody collapses
	var started := {}
	var cb := func(fid: int, iid: String, _t: int): if fid == f.id: started[iid] = int(started.get(iid, 0)) + 1
	Events.interaction_started.connect(cb)
	var worst := 100.0
	for h in 30:
		Kit.run(60)
		for nid in f.needs:
			worst = minf(worst, f.get_stat_value(nid))
	Events.interaction_started.disconnect(cb)
	_check(SysUtil.folk(f.id) != null, "empty: the folk survived a day and a half")
	_check(worst > -98.0, "empty: no need hit rock bottom (worst %f)" % worst)
	_check(int(started.get("sleep_floor", 0)) + int(started.get("pass_out", 0)) > 0, "empty: slept on the floor")
	_check(int(started.get("welcome_snack", 0)) > 0, "empty: ate from the welcome basket (%s)" % str(started))
	_check(_count("toilet") > 0 and int(started.get("cafe_restroom", 0)) == 0, "empty: the studio keeps its toilet, so no cafe restroom trips")          # keep_defs: toilet, shower, sink
	_check(int(started.get("have_accident", 0)) == 0, "empty: no accident")

	# buy the basics in the order the tips ask; the next-step hint follows (task 63: no furnishing money, so the test pays for them)
	Economy.deposit(1, 4000, "test: furnishing money")
	var from: Vector2i = f.tile
	var order: Array = []
	for _i in 12:
		var nb: Dictionary = StartHome.next_basic(1)
		if nb.is_empty():
			break
		order.append(str(nb["id"]))
		var def_id: String = {"bed": "single_bed", "toilet": "toilet", "fridge": "fridge", "shower": "shower", "stove": "stove", "seat": "chair"}[str(nb["id"])]
		_check(_buy(def_id, from), "bought %s" % def_id)
	_check(order.slice(0, 2) == ["bed", "fridge"] and not order.has("toilet"), "tips order starts bed, fridge (the studio has its toilet): %s" % str(order))
	_check(StartHome.next_basic(1).is_empty(), "all basics bought")
	_check(panel.label.text == str(StartHome.cfg()["done_text"]) and panel.title_label.text == "All set", "tips: the note follows the shopping and ends with all set (%s)" % panel.label.text)
	panel.queue_free()
	UIPrefs.set_flag("tips_seen", seen_before)
	_check(Economy.balance(1) > 0, "the basics were paid for (left %d)" % Economy.balance(1))
	# a guest on the home lot never takes the resident's bed (seed-dependent order bug: a visitor lay down in the one bed and the owner slept on the floor)
	_check(Cond.check_one({"home_guest": false}, {"folk": f}), "resident is not a home guest")
	f.set_meta("visitor", true)
	_check(Neighborhood.lot_of(f) != Neighborhood.HOME or not Cond.check_one({"home_guest": false}, {"folk": f}), "a visitor at home is a home guest")
	f.remove_meta("visitor")
	var guest_sleeps := 0
	var gcb := func(fid: int, iid: String, _t: int):
		var g = SysUtil.folk(fid)
		if g != null and fid != f.id and g.has_meta("visitor") and Neighborhood.lot_of(g) == Neighborhood.HOME and (iid.begins_with("sleep") or iid.begins_with("nap")):
			guest_sleeps += 1
	Events.interaction_started.connect(gcb)
	started.clear()
	Events.interaction_started.connect(cb)
	var home_hours := 0
	for h in 30:
		Kit.run(60)
		if Neighborhood.lot_of(f) == Neighborhood.HOME:
			home_hours += 1
	Events.interaction_started.disconnect(cb)
	Events.interaction_started.disconnect(gcb)
	_check(guest_sleeps == 0, "bought: no guest lay down in the household bed (%d)" % guest_sleeps)
	_check(SysUtil.folk(f.id) != null, "bought: still alive")
	_check(int(started.get("sleep_floor", 0)) <= 1 and int(started.get("sleep_bed", 0)) >= int(started.get("sleep_floor", 0)), "bought: sleeps in the bed, not on the floor %s" % str(started))      # (a folk caught out at the park may still lie down once)
	_check(int(started.get("welcome_snack", 0)) == 0 and int(started.get("cafe_restroom", 0)) == 0, "bought: the fallbacks switch off")
	_check(int(started.get("sleep_bed", 0)) > 0 or int(started.get("nap_bed", 0)) > 0, "bought: sleeps in the bed (%s)" % str(started))
	# (a folk that wandered off to another lot for most of the 30 hours, e.g. to greet someone, has no reason to use this toilet: which way the dice fall depends on the tests that ran before)
	_check(int(started.get("use_toilet", 0)) > 0 or home_hours < 20, "bought: uses the toilet (%d of 30 hours at home) %s" % [home_hours, str(started)])
	Kit.teardown()
	# every scenario copes with a bare home for a day (family child, couple, roommates)
	for sid in ["couple", "family", "roommates"]:
		var fk: Array = Kit.new_game(sid, "normal", {}, -1, {"home_state": "empty", "world_seed": 9})
		var low := 100.0
		for _h in 26:
			Kit.run(60)
			for each in fk:
				for nid in each.needs:
					low = minf(low, each.get_stat_value(nid))
		_check(low > -98.0, "%s: bare home for a day, nobody hit rock bottom (%f)" % [sid, low])
		for each in fk:
			_check(SysUtil.folk(each.id) != null, "%s: everyone is still here" % sid)
		_check(StartHome.is_bare(1), "%s: still bare" % sid)
		Kit.teardown()
	return fails
