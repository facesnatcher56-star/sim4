extends RefCounted
## Travel on the real World: lot swap + restore, folk bookkeeping (off-lot folk stay in World.folk and keep their needs),
## travel time, venue hours / fees block entry, the crowd cap and ambient NPCs, groceries pantry, townie-home residents.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_round_trip()
	_hours_and_fees()
	_crowd()
	_staff_and_meetings()
	_pantry_and_homes()
	Kit.teardown()
	return fails

func _round_trip() -> void:
	var folk: Array = Kit.new_game("classic")
	var W: Node = Kit.world()
	var home_objs: int = W.objects.size()
	var fridge = W.objects_of_def("fridge")[0]
	W.set_object_state(fridge.id, "stock", 4.0)
	WorldIface.state_add(fridge, "stock", -1.0)          # the sim writes the Stat mirror only; the stash must still keep it
	var snap_before: Dictionary = W.save_dict(false)
	Kit.set_time(2, 12)                       # Tuesday noon: everything is open
	Kit.run(3)
	var mira: Folk = folk[0]
	var tobin: Folk = folk[1]
	var wren: Folk = folk[2]
	var res: Dictionary = Neighborhood.travel([mira.id], "park")
	_check(bool(res["ok"]), "travel to the park works: %s" % str(res.get("reason", "")))
	_check(Neighborhood.current_lot == "park", "park is the loaded lot")
	_check(int(res["minutes"]) >= 5 and int(res["minutes"]) <= 40, "travel time is in range: %s" % str(res["minutes"]))
	_check(W.objects_of_def("fishing_spot").size() > 0 and W.objects_of_def("fridge").is_empty(), "the park (not the house) is in the World")
	_check(W.all_folk().filter(func(f): return f.household_id == 1).size() == 3, "all three folk still registered in World.folk")
	_check(tobin.has_meta("offlot") and wren.has_meta("offlot"), "folk who stayed behind are marked off-lot")
	_check(Neighborhood.where(tobin.id) == "home" and Neighborhood.where(mira.id) == "park", "locations recorded")
	_check(mira.has_meta("away") and str(mira.get_meta("away")) == "travel", "the traveller is away for the trip")
	var t_hunger: float = tobin.get_stat_value("hunger")
	Kit.run(int(res["minutes"]) + 3)
	_check(not mira.has_meta("away"), "traveller arrived (no longer away)")
	var entries: Array = W.starter_spawn_tiles
	_check(W.is_walkable(mira.tile), "traveller stands on the park lot")
	_check(Kit.has_note("arrived at") or Kit.count_events("returned_to_lot") > 0, "arrival announced")
	# off-lot needs still tick but are kept sane by the statistical rules
	Kit.run(240)
	_check(tobin.get_stat_value("hunger") > -40.0 and wren.get_stat_value("hunger") > -40.0, "stay-at-home folk do not starve (%.1f)" % tobin.get_stat_value("hunger"))
	_check(absf(tobin.get_stat_value("hunger") - t_hunger) < 200.0, "needs of off-lot folk keep moving")
	# bring everybody home
	var back: Dictionary = Neighborhood.go_home()
	_check(bool(back["ok"]), "go_home works: %s" % str(back.get("reason", "")))
	_check(Neighborhood.current_lot == "home", "home loaded again")
	_check(W.objects.size() == home_objs, "home object count preserved (%d vs %d)" % [W.objects.size(), home_objs])
	var snap_after: Dictionary = W.save_dict(false)
	var fr = W.objects_of_def("fridge")[0]
	_check(int(float(WorldIface.state_get(fr, "stock", -1))) == 3, "fridge stock preserved across the round trip (%s)" % str(WorldIface.state_get(fr, "stock", -1)))
	_check((snap_after["floors"] as Array) == (snap_before["floors"] as Array), "floors preserved")
	_check((snap_after["walls"] as Array).size() == (snap_before["walls"] as Array).size(), "walls preserved")
	Kit.run(60)
	for f in folk:
		_check(not f.has_meta("offlot"), "%s is back on the home lot" % f.name)
		_check(Neighborhood.where(f.id) == "home", "%s located at home" % f.name)
		_check(W.is_walkable(f.tile) or f.current != null, "%s has a sane tile" % f.name)
	# travelling with a subset keeps the other folk at home as off-lot folk, then bringing one back
	Neighborhood.travel([mira.id, tobin.id], "gym")
	_check(Neighborhood.current_lot == "gym" and wren.has_meta("offlot"), "subset travel parks the rest")
	Neighborhood.travel([wren.id], "gym")
	_check(not wren.has_meta("offlot") and Neighborhood.where(wren.id) == "gym", "an off-lot folk can be brought along later")
	Neighborhood.go_home()

func _hours_and_fees() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	Kit.set_time(2, 3)                        # 03:00 - cafe/gym/library all closed
	var r: Dictionary = Neighborhood.travel([mira.id], "cafe", {"quiet": true})
	_check(not bool(r["ok"]) and str(r["reason"]).to_lower().find("closed") >= 0, "closed cafe blocks entry: %s" % str(r.get("reason", "")))
	_check(Neighborhood.current_lot == "home", "still home after a refused trip")
	Kit.set_time(2, 12)
	_check(not Neighborhood.is_open("office") == false, "office open on a weekday noon")
	Kit.set_time(6, 12)                       # day 6 -> weekday index 5 (weekend)
	_check(not Neighborhood.is_open("office") and not Neighborhood.is_open("school"), "office and school are closed at the weekend")
	var r2: Dictionary = Neighborhood.travel([mira.id], "school", {"quiet": true})
	_check(not bool(r2["ok"]), "school closed on weekends")
	Kit.set_time(2, 12)
	# entry fee at the gym
	WorldIface.coins[1] = 5
	var r3: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true})
	_check(not bool(r3["ok"]) and str(r3["reason"]).find("Entry") >= 0, "unaffordable entry fee blocks travel: %s" % str(r3.get("reason", "")))
	WorldIface.coins[1] = 500
	var r4: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true})
	_check(bool(r4["ok"]), "gym entry works when affordable")
	_check(Economy.balance(1) == 490, "gym fee charged (%d)" % Economy.balance(1))
	# venues close on the folk
	Kit.set_time(2, 21, 40)
	Neighborhood.go_home()
	Kit.set_time(2, 21, 30)
	Neighborhood.travel([mira.id], "gym", {"quiet": true})   # open until 22:00
	Kit.run(5)
	_check(Neighborhood.current_lot == "gym", "gym still open at 21:35")
	Kit.run(45)
	_check(Neighborhood.current_lot == "home", "closing time sends the folk home (lot=%s)" % Neighborhood.current_lot)
	_check(Kit.has_note("closes in") and Kit.has_note("closed"), "closing notices were shown")

func _crowd() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 3000
	Neighborhood.travel([mira.id], "cafe", {"quiet": true})
	Kit.run(30)
	var n: int = Crowd.count()
	_check(n >= 2, "cafe has an ambient crowd at noon (%d)" % n)
	_check(n <= Venues.crowd_cap(), "crowd cap respected (%d <= %d)" % [n, Venues.crowd_cap()])
	for f in Crowd.crowd_folk():
		_check(f.household_id == -1 and f.has_meta("visitor") and not f.appearance.is_empty(), "crowd NPC %s is a townie visitor with a genetic look" % f.name)
		_check(Story.townies.has(int(f.get_meta("townie_id", -1))), "crowd NPC maps back to a townie")
	# rush hour never exceeds the cap even over a long stretch
	var peak := 0
	var busy := 0
	var seen_iids: Dictionary = {}
	Kit.set_time(2, 17)
	for _i in 24:
		Kit.run(10)
		peak = maxi(peak, Crowd.count())
		for npc in Crowd.crowd_folk():
			if npc.current != null and npc.current.def_id != "sys_staff":
				busy += 1
				seen_iids[npc.current.def_id] = true
	_check(busy > 10, "crowd NPCs actually do things (%d busy samples: %s)" % [busy, str(seen_iids.keys())])
	_check(peak <= Venues.crowd_cap(), "crowd never exceeds the cap (peak %d)" % peak)
	_check(peak >= 2, "crowd shows up at rush hour (peak %d)" % peak)
	var staff: Array = Crowd.staff_folk()
	_check(staff.size() >= 1, "the cafe has staff on duty")
	# leaving the lot clears the NPCs
	Neighborhood.go_home()
	_check(Crowd.count() == 0 and Crowd.staff_folk().is_empty(), "NPCs are removed when the lot is left")
	_check(Venues.crowd_target("cafe", 3.0) == 0, "no crowd target while closed")

func _staff_and_meetings() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 3000
	Neighborhood.travel([mira.id], "park", {"quiet": true})
	var met_before: int = Kit.count_events("met_townie")
	var known_before := 0
	for t in Story.alive_townies():
		if RelationshipService.knows(mira.id, int(t["id"])):
			known_before += 1
	Kit.run(240)
	var known_after := 0
	for t in Story.alive_townies():
		if RelationshipService.knows(mira.id, int(t["id"])):
			known_after += 1
	_check(known_after > known_before or Kit.count_events("met_townie") > met_before, "chance meetings at the park create introductions (%d -> %d)" % [known_before, known_after])
	# hangout invitation
	var tid: int = int(Story.alive_townies()[0]["id"])
	Neighborhood.go_home()
	Kit.set_time(2, 13)
	var rec: Dictionary = Story.invite_to_venue(tid, mira.id, "park", 30, 90)
	_check(not rec.is_empty(), "invite_to_venue returns a record")
	var fr_before: float = RelationshipService.value(mira.id, tid, "friendship")
	Neighborhood.travel([mira.id], "park", {"quiet": true})
	Kit.run(45)
	_check(Kit.count_events("venue_invite") == 1, "invite event emitted")
	var host_npc = SysUtil.folk(tid)
	_check(host_npc != null and host_npc.has_meta("meetup"), "the invited townie turned up at the park")
	Kit.run(110)
	_check(Kit.count_events("hangout_done") == 1, "hangout finished")
	_check(RelationshipService.value(mira.id, tid, "friendship") > fr_before, "hangout raised friendship")
	Neighborhood.go_home()

func _pantry_and_homes() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	var W: Node = Kit.world()
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 3000
	var fr = W.objects_of_def("fridge")[0]
	W.set_object_state(fr.id, "stock", 0.0)
	Neighborhood.travel([mira.id], "market", {"quiet": true})
	Kit.run(30)
	var cooler = W.objects_of_def("grocery_cooler")[0]
	var ir := Interaction.create("buy_groceries", mira, cooler.id, true)
	_check(ir != null and ir.can_run(mira, null, false), "buy_groceries can run at a cooler")
	mira.enqueue(ir)
	Kit.run(20)
	_check(Neighborhood.pantry > 0, "groceries went into the pantry (%d)" % Neighborhood.pantry)
	Neighborhood.go_home()
	var fr2 = W.objects_of_def("fridge")[0]
	_check(float(WorldIface.state_get(fr2, "stock", 0)) >= 4.0, "pantry restocked the home fridge (%s)" % str(WorldIface.state_get(fr2, "stock", 0)))
	# townie homes list residents
	var total := 0
	for hid in ["townie_a", "townie_b", "townie_c"]:
		total += Neighborhood.residents_of(hid).size()
	_check(total >= 6, "townies live in the three homes (%d)" % total)
	Kit.set_time(2, 12)
	var r: Dictionary = Neighborhood.travel([mira.id], "townie_a", {"quiet": true})
	_check(bool(r["ok"]), "visiting a townie home works")
	Kit.run(30)
	_check(Crowd.count() >= 0 and Neighborhood.venue_type() == "townie_home", "townie home is a venue type")
	Neighborhood.go_home()
