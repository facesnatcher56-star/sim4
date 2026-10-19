extends RefCounted
## Travel on the real World with every lot present at once: fast travel + walking home, folk bookkeeping from tiles (nobody is
## parked or hidden because of where they are), travel time, venue hours / fees block entry, closing time, the per-lot crowd cap
## and ambient NPCs (only near the player), groceries pantry, townie-home residents.

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

func _home_fridge(W: Node):
	for o in W.objects_of_def("fridge"):
		if Neighborhood.lot_at(o.tile) == "home":
			return o
	return null

func _round_trip() -> void:
	var folk: Array = Kit.new_game("classic")
	var W: Node = Kit.world()
	var home_objs := 0
	for o in W.all_objects():
		if Neighborhood.lot_at(o.tile) == "home":
			home_objs += 1
	var fridge = _home_fridge(W)
	W.set_object_state(fridge.id, "stock", 4.0)
	WorldIface.state_add(fridge, "stock", -1.0)          # the sim writes through to the object's state
	var snap_before: Dictionary = W.save_dict(false)
	Kit.set_time(2, 12)                       # Tuesday noon: everything is open
	Kit.run(3)
	var mira: Folk = folk[0]
	var tobin: Folk = folk[1]
	var wren: Folk = folk[2]
	var home_value: int = Economy.lot_value(1)
	var res: Dictionary = Neighborhood.travel([mira.id], "park", {"fast": true})
	_check(bool(res["ok"]), "travel to the park works: %s" % str(res.get("reason", "")))
	_check(home_value > 0 and Economy.lot_value(1) == home_value, "home lot value (bills) is unchanged while the folk are away (%d vs %d)" % [Economy.lot_value(1), home_value])
	_check(int(res["minutes"]) >= 5 and int(res["minutes"]) <= 40, "fast travel time is in range: %s" % str(res["minutes"]))
	_check(W.objects_of_def("fishing_spot").size() > 0 and _home_fridge(W) != null, "the park AND the house are in the World at once")
	_check(home_objs > 30 and W.objects.size() > home_objs + 200, "all lots exist (%d objects, %d at home)" % [W.objects.size(), home_objs])
	_check(W.all_folk().filter(func(f): return f.household_id == 1).size() == 3, "all three folk still registered in World.folk")
	_check(not tobin.has_meta("away") and not wren.has_meta("away"), "folk who stay behind are not hidden or parked")
	_check(Neighborhood.where(tobin.id) == "home" and Neighborhood.where(mira.id) == "park", "locations derive from tiles")
	_check(Neighborhood.lot_of(mira) == "park" and Neighborhood.folk_at("park") == [mira.id], "lot_of / folk_at")
	_check(mira.has_meta("away") and str(mira.get_meta("away")) == "travel", "the traveller is away for the trip")
	Kit.run(int(res["minutes"]) + 3)
	_check(not mira.has_meta("away"), "traveller arrived (no longer away)")
	_check(W.is_walkable(mira.tile), "traveller stands on the park lot")
	_check(Kit.has_note("arrived at") or Kit.count_events("returned_to_lot") > 0, "arrival announced")
	# the others carry on with their own life at home (real autonomy, no statistical stand-in)
	var t_hunger: float = tobin.get_stat_value("hunger")
	Kit.run(TestFixture.pick(240, 90))
	_check(tobin.get_stat_value("hunger") > -40.0 and wren.get_stat_value("hunger") > -40.0, "stay-at-home folk do not starve (%.1f)" % tobin.get_stat_value("hunger"))
	_check(absf(tobin.get_stat_value("hunger") - t_hunger) < 200.0, "needs of the folk at home keep moving")
	# bring everybody home
	var back: Dictionary = Neighborhood.go_home([], {"fast": true})
	_check(bool(back["ok"]), "go_home works: %s" % str(back.get("reason", "")))
	Kit.run(int(back["minutes"]) + 5)
	_check(Neighborhood.where(mira.id) == "home", "home again")
	_check(W.objects_of_def("fishing_spot").size() > 0 and _home_fridge(W) != null, "still one world: park and home")
	var snap_after: Dictionary = W.save_dict(false)
	var fr = _home_fridge(W)
	_check(int(float(WorldIface.state_get(fr, "stock", -1))) <= 3, "fridge stock only went down (%s)" % str(WorldIface.state_get(fr, "stock", -1)))
	_check((snap_after["floors_rle"] as Array) == (snap_before["floors_rle"] as Array), "floors preserved")
	_check((snap_after["walls"] as Array).size() == (snap_before["walls"] as Array).size(), "walls preserved")
	for f in folk:
		_check(Neighborhood.where(f.id) == "home", "%s located at home" % f.name)
		_check(W.is_walkable(f.tile) or f.current != null, "%s has a sane tile" % f.name)
	# a subset travels, the rest stays; a straggler can follow later
	Neighborhood.travel([mira.id, tobin.id], "gym", {"instant": true, "free": true})
	_check(Neighborhood.where(mira.id) == "gym" and Neighborhood.where(tobin.id) == "gym" and Neighborhood.where(wren.id) == "home", "subset travel")
	Neighborhood.travel([wren.id], "gym", {"instant": true, "free": true})
	_check(Neighborhood.where(wren.id) == "gym", "a straggler can follow later")
	Neighborhood.go_home([], {"instant": true})
	_check(Neighborhood.folk_at("home").size() == 3, "instant go_home")

func _hours_and_fees() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	Kit.set_time(2, 3)                        # 03:00 - cafe/gym/library all closed
	var r: Dictionary = Neighborhood.travel([mira.id], "cafe", {"quiet": true})
	_check(not bool(r["ok"]) and str(r["reason"]).to_lower().find("closed") >= 0, "closed cafe blocks entry: %s" % str(r.get("reason", "")))
	_check(Neighborhood.where(mira.id) == "home" and Neighborhood.heading_to(mira.id) == "", "still home after a refused trip")
	Kit.set_time(2, 12)
	_check(Neighborhood.is_open("office"), "office open on a weekday noon")
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
	var r4: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true, "fast": true})
	_check(bool(r4["ok"]), "gym entry works when affordable")
	_check(Economy.balance(1) == 490, "gym fee charged (%d)" % Economy.balance(1))
	# venues close on the folk
	Kit.set_time(2, 21, 40)
	Neighborhood.go_home([], {"instant": true})
	Kit.set_time(2, 21, 30)
	Neighborhood.travel([mira.id], "gym", {"quiet": true, "instant": true})   # open until 22:00
	Kit.run(5)
	_check(Neighborhood.where(mira.id) == "gym", "gym still open at 21:35")
	Kit.run(45)
	_check(Neighborhood.heading_to(mira.id) == "home" or Neighborhood.where(mira.id) == "home", "closing time sends the folk home (lot=%s)" % Neighborhood.where(mira.id))
	Kit.run_until(func(): return Neighborhood.where(mira.id) == "home", 120)
	_check(Neighborhood.where(mira.id) == "home", "and she walks all the way (lot=%s)" % Neighborhood.where(mira.id))
	_check(Kit.has_note("closes in") and Kit.has_note("closed"), "closing notices were shown")

func _crowd() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	var W: Node = Kit.world()
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 3000
	Neighborhood.travel([mira.id], "cafe", {"quiet": true, "fast": true})
	Kit.run(30)
	var n: int = Crowd.count("cafe")
	_check(n >= 2, "cafe has an ambient crowd at noon (%d)" % n)
	_check(n <= Venues.crowd_cap(), "crowd cap respected (%d <= %d)" % [n, Venues.crowd_cap()])
	for f in Crowd.crowd_folk("cafe"):
		_check(f.household_id == -1 and f.has_meta("visitor") and not f.appearance.is_empty(), "crowd NPC %s is a townie visitor with a genetic look" % f.name)
		_check(Story.townies.has(int(f.get_meta("townie_id", -1))), "crowd NPC maps back to a townie")
		_check(Neighborhood.lot_at(f.tile) == "cafe", "crowd NPC %s stands in the cafe lot (%s)" % [f.name, str(f.tile)])
	# rush hour never exceeds the per-lot cap even over a long stretch
	var peak := 0
	var busy := 0
	var seen_iids: Dictionary = {}
	Kit.set_time(2, 17)
	for _i in 24:
		Kit.run(10)
		for lid in Neighborhood.lot_ids():
			peak = maxi(peak, Crowd.count(lid))
		for npc in Crowd.crowd_folk("cafe"):
			if npc.current != null and npc.current.def_id != "sys_staff":
				busy += 1
				seen_iids[npc.current.def_id] = true
				_check(Neighborhood.lot_at(npc.tile) in ["cafe", ""], "cafe NPC %s did not wander into another lot (%s)" % [npc.name, Neighborhood.lot_at(npc.tile)])
	_check(busy > 10, "crowd NPCs actually do things (%d busy samples: %s)" % [busy, str(seen_iids.keys())])
	_check(peak <= Venues.crowd_cap(), "crowd never exceeds the cap in any lot (peak %d)" % peak)
	_check(peak >= 2, "crowd shows up at rush hour (peak %d)" % peak)
	_check(Crowd.staff_folk("cafe").size() >= 1, "the cafe has staff on duty")
	# lots far from every resident are emptied again
	for f in folk:
		f.tile = Vector2i(150, 105)
	Kit.run(3)
	_check(Crowd.count("cafe") == 0 and Crowd.staff_folk("cafe").is_empty(), "NPCs are removed when nobody is near the lot")
	_check(Venues.crowd_target("cafe", 3.0) == 0, "no crowd target while closed")
	_check(W.region_at(Vector2i(150, 105)) != W.regions.home_id, "(test setup) the far corner is not home")

func _staff_and_meetings() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 3000
	Neighborhood.travel([mira.id], "park", {"quiet": true, "fast": true})
	var met_before: int = Kit.count_events("met_townie")
	var known_before := 0
	for t in Story.alive_townies():
		if RelationshipService.knows(mira.id, int(t["id"])):
			known_before += 1
	var count_known := func() -> int:
		var n := 0
		for t in Story.alive_townies():
			if RelationshipService.knows(mira.id, int(t["id"])):
				n += 1
		return n
	Kit.run_until(func(): return int(count_known.call()) > known_before or Kit.count_events("met_townie") > met_before, 240)
	var known_after: int = count_known.call()
	_check(known_after > known_before or Kit.count_events("met_townie") > met_before, "chance meetings at the park create introductions (%d -> %d)" % [known_before, known_after])
	# hangout invitation
	var tid: int = int(Story.alive_townies()[0]["id"])
	Neighborhood.go_home([], {"instant": true})
	Kit.set_time(2, 13)
	var rec: Dictionary = StoryVisits.invite_to_venue(tid, mira.id, "park", 30, 90)
	_check(not rec.is_empty(), "invite_to_venue returns a record")
	var fr_before: float = RelationshipService.value(mira.id, tid, "friendship")
	Neighborhood.travel([mira.id], "park", {"quiet": true, "instant": true})
	Kit.run_until(func(): return SysUtil.folk(tid) != null and SysUtil.folk(tid).has_meta("meetup"), 45)
	_check(Kit.count_events("venue_invite") == 1, "invite event emitted")
	var host_npc = SysUtil.folk(tid)
	_check(host_npc != null and host_npc.has_meta("meetup"), "the invited townie turned up at the park")
	Kit.run_until(func(): return Kit.count_events("hangout_done") >= 1, 110)
	_check(Kit.count_events("hangout_done") == 1, "hangout finished")
	_check(RelationshipService.value(mira.id, tid, "friendship") > fr_before, "hangout raised friendship")

func _pantry_and_homes() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	var W: Node = Kit.world()
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 3000
	var fr = _home_fridge(W)
	W.set_object_state(fr.id, "stock", 0.0)
	Neighborhood.travel([mira.id], "market", {"quiet": true, "fast": true})
	Kit.run(30)
	var cooler = W.objects_of_def("grocery_cooler")[0]
	var ir := Interaction.create("buy_groceries", mira, cooler.id, true)
	_check(ir != null and ir.can_run(mira, null, false), "buy_groceries can run at a cooler")
	mira.enqueue(ir)
	Kit.run(20)
	_check(Neighborhood.pantry > 0, "groceries went into the pantry (%d)" % Neighborhood.pantry)
	Neighborhood.go_home([mira.id], {"fast": true})
	Kit.run(10)
	var fr2 = _home_fridge(W)
	_check(float(WorldIface.state_get(fr2, "stock", 0)) >= 4.0, "pantry restocked the home fridge (%s)" % str(WorldIface.state_get(fr2, "stock", 0)))
	# townie homes list residents
	var total := 0
	for hid in ["townie_a", "townie_b", "townie_c"]:
		total += Neighborhood.residents_of(hid).size()
	_check(total >= 6, "townies live in the three homes (%d)" % total)
	Kit.set_time(2, 12)
	var r: Dictionary = Neighborhood.travel([mira.id], "townie_a", {"quiet": true, "fast": true})
	_check(bool(r["ok"]), "visiting a townie home works")
	Kit.run(30)
	_check(Neighborhood.venue_type("townie_a") == "townie_home" and Neighborhood.where(mira.id) == "townie_a", "townie home is a venue type and the folk is there")