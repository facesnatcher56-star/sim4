extends RefCounted
## Task 22 / 22b: a household goes on a 3-day cruise. The book_and_go hook tells the ship, route, ports and boarding times; the ship (five decks)
## is loaded when they board with crew and passengers aboard; the port of call loads on the shore day and unloads when the ship sails; the
## cruise programme runs and everything is in the chronicle with place "cruise"; they come home with memories, photos and souvenirs while the town
## advanced on the cheap layer; bills were paid; a save in the middle of the voyage restores the ship, a missed boarding leaves folk behind.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_three_day_cruise()
	_missed_boarding()
	_save_mid_voyage()
	K.teardown()
	return fails

func _ship_zone(t: Dictionary) -> int:
	return int(t["zone"])

func _three_day_cruise() -> void:
	var folk: Array = K.new_game("small")
	var coins0: int = Economy.balance(1)
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 3, "cabin_class": "ocean", "guests": [], "seed": 11})
	_check(bool(res["ok"]), "cruise booked: %s" % str(res.get("reason", "")))
	var tid: int = int(res["trip"])
	_check(str(res["ship"].get("name", "")) != "" and int(res["ship"].get("decks", 0)) == 5, "result names the ship and its decks: %s" % str(res.get("ship", {})))
	_check((res["route"] as Array).size() == 4 and str(res["route"][0]["kind"]) == "embark" and str(res["route"][3]["kind"]) == "home", "route embark / port / sea / home")
	_check((res["ports"] as Array).size() == 1, "one port of call on a 3-day cruise: %s" % str(res.get("ports", [])))
	_check(int(res["boarding"]["sail_min"]) > K.now() and int(res["boarding"]["open_min"]) > 0, "boarding times are given")
	_check(Economy.balance(1) < coins0, "the household paid")
	var t: Dictionary = Vacation.trip(tid)
	K.run(35)
	_check(Vacation.state_of(tid) == "there", "boarded (%s)" % Vacation.state_of(tid))
	_check(DestLoader.region_of_zone(_ship_zone(t)) >= 0, "the ship is loaded into a zone")
	var mira: Folk = folk[0]
	_check(Vacation.on_trip(int(mira.id)) and mira.has_buff("on_cruise"), "on the cruise")
	_check(mira.level == 0 and NeighborhoodLots.lot_at(mira.tile) == str(t["lot"]), "standing on the ship's promenade deck")
	K.run(30)
	var crew: int = CruiseCrew.crew(t).size()
	var pax: int = CruiseCrew.passengers(t).size()
	_check(crew >= 8 and pax >= 4, "crew (%d) and passengers (%d) are aboard" % [crew, pax])
	_check(not CruiseCrew.crew(t, "captain").is_empty() and not CruiseCrew.crew(t, "medical").is_empty() and not CruiseCrew.crew(t, "security").is_empty(), "captain, medical officer and security are aboard")
	_check(not CruiseCrew.crew(t, "waiter").is_empty() and not CruiseCrew.crew(t, "entertainer").is_empty() and not CruiseCrew.crew(t, "cleaner").is_empty(), "waiters, an entertainer and a cleaner")
	var levels := {}
	for c in CruiseCrew.crew(t):
		levels[int(c.level)] = true
	_check(levels.size() >= 3, "the crew is spread over the decks (%s)" % str(levels.keys()))
	# day 0 sails at 17:00 and the welcome buffet / safety drill happen
	K.warp(int(res["boarding"]["sail_min"]) - K.now() + 90)
	_check(str(t["cruise"]["phase"]) == "sailing", "under way")
	_check(VacationLog.count("port") >= 2, "port log lines exist")
	_check(mira.has_buff("well_fed_hearty") or VacationLog.count("dinner") >= 1, "the welcome buffet happened")
	# day 1: port
	var dock_min: int = -1
	for e in t["cruise"]["timeline"]:
		if str(e["kind"]) == "dock":
			dock_min = int(e["min"])
	K.warp(dock_min - K.now() + 30)
	_check(int(t["cruise"]["port_zone"]) >= 0 and DestLoader.region_of_zone(int(t["cruise"]["port_zone"])) >= 0, "the port of call is loaded when the ship docks")
	_check(int(t["cruise"]["port_zone"]) != _ship_zone(t), "in a second zone")
	K.warp(120)
	var ashore: int = CruiseShore.ashore_members(t).size()
	_check(ashore == folk.size(), "the party is ashore (%d)" % ashore)
	_check(NeighborhoodLots.lot_at(mira.tile) == str(t["cruise"]["port_lot"]), "standing in the port")
	var sail_min: int = -1
	for e2 in t["cruise"]["timeline"]:
		if str(e2["kind"]) == "sail" and int(e2["day"]) == 1:
			sail_min = int(e2["min"])
	K.warp(sail_min - K.now() - 100)                         # 15:20, the last call comes at 15:30
	K.warp(60)
	_check(Vacation.state_of(tid) == "there", "still on the cruise")
	K.warp(sail_min - K.now() + 40)
	_check(CruiseShore.ashore_members(t).is_empty() and NeighborhoodLots.lot_at(mira.tile) == str(t["lot"]), "everyone is back on the ship")
	_check(int(t["cruise"]["port_zone"]) < 0, "the port zone is unloaded again after sailing")
	_check(t["cruise"]["stranded"].is_empty(), "nobody was left behind")
	# day 2 at sea, day 3 home
	K.warp(1440 + 5 * 60)
	_check(VacationLog.count("dinner") >= 2 and VacationLog.count("show") >= 1, "dinners and shows are in the story log (%d / %d)" % [VacationLog.count("dinner"), VacationLog.count("show")])
	var home_min: int = int(t["return_min"])
	K.warp(home_min - K.now() + 90)
	_check(Vacation.trip(tid).is_empty(), "the cruise is over")
	_check(DestLoader.region_of_zone(0) < 0 and DestLoader.region_of_zone(1) < 0, "both zones are unloaded")
	_check(NeighborhoodLots.lot_at(mira.tile) == "home" and not Vacation.on_trip(int(mira.id)), "home again")
	_check(Vacation.history_list().size() == 1 and int(Vacation.history_list()[0]["photos"]) >= 1, "photos came home (%s)" % str(Vacation.history_list()))
	_check(mira.has_buff("vacation_glow"), "vacation glow")
	var cruise_lines := 0
	for p in ChronicleHook.recent:
		if str(p.get("place", "")) == "cruise":
			cruise_lines += 1
	_check(cruise_lines >= 3, "chronicle lines with place 'cruise' (recent ring: %d)" % cruise_lines)
	_check(VacationLog.count("boarding") == 1 and VacationLog.count("port") >= 4, "the whole cruise is logged")
	K.teardown()

func _missed_boarding() -> void:
	var folk: Array = K.new_game("small")
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 3, "cabin_class": "inside", "seed": 4})
	var tid: int = int(res["trip"])
	var t: Dictionary = Vacation.trip(tid)
	K.warp(60)
	var dock_min: int = -1
	var sail_min: int = -1
	for e in t["cruise"]["timeline"]:
		if str(e["kind"]) == "dock":
			dock_min = int(e["min"])
		if str(e["kind"]) == "sail" and int(e["day"]) == 1:
			sail_min = int(e["min"])
	K.warp(dock_min - K.now() + 140)
	var wren: Folk = folk[2]
	Cruise.command(t, "linger", {"folk_ids": [int(wren.id)]})
	var coins_before: int = Economy.balance(1)
	K.warp(sail_min - K.now() + 30)
	_check(wren.has_buff("left_behind") and (t["cruise"]["stranded"] as Array).has(int(wren.id)), "Wren stayed ashore and was left behind")
	_check(CruiseShore.ashore_members(t).size() == 1 and int(t["cruise"]["port_zone"]) >= 0, "the port stays loaded for the stranded")
	_check(not (t["cruise"]["stranded"] as Array).has(int(folk[0].id)), "the others made it")
	_check(VacationLog.count("missed") >= 1, "the missed boarding is in the story")
	K.warp(3 * 60)
	_check(Economy.balance(1) <= coins_before - 380, "the flight home is expensive (%d -> %d)" % [coins_before, Economy.balance(1)])
	_check(int(t["cruise"]["port_zone"]) < 0, "port unloaded once the stranded left")
	K.warp(11 * 60)
	_check(NeighborhoodLots.lot_at(wren.tile) == "home" and not Vacation.on_trip(int(wren.id)) and wren.has_buff("homesick"), "Wren got home by plane, stressed")
	_check(not (t["folk"] as Array).has(int(wren.id)) and (t["left"] as Array).has(int(wren.id)), "the trip record knows")
	_check(Vacation.state_of(tid) == "there", "the others are still cruising")
	K.warp(int(t["return_min"]) - K.now() + 90)
	_check(Vacation.trip(tid).is_empty(), "the cruise ended")
	K.teardown()

func _save_mid_voyage() -> void:
	var folk: Array = K.new_game("small")
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 3, "cabin_class": "suite", "seed": 21})
	var tid: int = int(res["trip"])
	var t: Dictionary = Vacation.trip(tid)
	K.warp(int(res["boarding"]["sail_min"]) - K.now() + 4 * 60)
	var zone: int = int(t["zone"])
	var idx: int = int(t["cruise"]["idx"])
	var snap: Dictionary = SaveLoad.snapshot("mid-voyage")
	var json: Variant = JSON.parse_string(JSON.stringify(snap))
	K.warp(7 * 60)
	_check(SaveLoad.restore(json as Dictionary), "restore ok")
	var t2: Dictionary = Vacation.trip(tid)
	_check(not t2.is_empty() and int(t2["zone"]) == zone and int(t2["cruise"]["idx"]) == idx, "voyage state restored (idx %d)" % idx)
	_check(DestLoader.region_of_zone(zone) >= 0 and WorldIface.world().levels.any(), "the ship and its decks are back")
	K.run(5)
	_check(CruiseCrew.crew(t2).size() >= 8, "crew respawned after the load (%d)" % CruiseCrew.crew(t2).size())
	var f0 = SysUtil.folk(int(t2["folk"][0]))
	_check(f0 != null and f0.has_buff("on_cruise") and Vacation.on_trip(int(f0.id)), "the party is still aboard")
	K.warp(int(t2["return_min"]) - K.now() + 90)
	_check(Vacation.trip(tid).is_empty(), "the restored cruise ends properly")
	K.teardown()
