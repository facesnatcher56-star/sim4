extends RefCounted
## Task 22: a household books a holiday, pays, travels (hidden journey), arrives in the loaded destination zone among locals, lives there, comes
## home with souvenirs / photos / a glow while the town advanced on the cheap layer, bills were paid, work and school are accounted for, and a
## save in the middle of the stay restores everything.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_quotes()
	_beach_trip()
	_save_mid_stay()
	_empty_house_and_alarm()
	_home_while_away()
	_work_and_school()
	K.teardown()
	return fails

func _quotes() -> void:
	var folk: Array = K.new_game("small")
	var q: Dictionary = Vacation.quote(1, "beach", {"length_days": 3})
	_check(bool(q["ok"]), "a beach quote works: %s" % str(q.get("reason", "")))
	_check(int(q["total"]) == int(q["travel"]) + int(q["lodging"]) + int(q["spending"]) + int(q["sitter"]) + int(q["package"]), "cost = travel + lodging + spending money (+ extras)")
	var camp: Dictionary = Vacation.quote(1, "camping", {"length_days": 3})
	var city: Dictionary = Vacation.quote(1, "city", {"length_days": 3})
	_check(int(camp["total"]) < int(q["total"]) and int(q["total"]) < int(city["total"]), "camping is cheaper than the beach, the big city dearer (%d / %d / %d)" % [camp["total"], q["total"], city["total"]])
	var cr: Dictionary = Vacation.quote(1, "cruise", {"length_days": 3, "cabin_class": "suite"})
	var cr2: Dictionary = Vacation.quote(1, "cruise", {"length_days": 3, "cabin_class": "inside"})
	_check(int(cr["total"]) > int(cr2["total"]), "a suite costs more than an inside cabin")
	var honey: Dictionary = Vacation.quote(1, "cruise", {"length_days": 3, "cabin_class": "inside", "package": "honeymoon"})
	_check(int(honey["total"]) > int(cr2["total"]), "the honeymoon package adds to the price")
	WorldIface.coins[1] = 100
	var poor: Dictionary = Vacation.quote(1, "city", {"length_days": 5})
	_check(not bool(poor["ok"]) and str(poor["reason"]) != "", "too poor: refused with a reason (%s)" % str(poor["reason"]))
	WorldIface.coins[1] = 6000
	var kids: Dictionary = Vacation.quote(1, "beach", {"length_days": 2, "who": [int(folk[0].id)]})
	_check(bool(kids["ok"]), "an adult may go alone")
	var bad: Dictionary = Vacation.quote(1, "nowhere", {})
	_check(not bool(bad["ok"]), "unknown destination refused")
	K.teardown()

func _beach_trip() -> void:
	var folk: Array = K.new_game("small")
	var mira: Folk = folk[0]
	var ids: Array = K.add_folk_ids(folk)
	var coins0: int = Economy.balance(1)
	var res: Dictionary = Vacation.book_and_go(1, "beach", {"length_days": 2, "travel_min": 40, "seed": 5})
	_check(bool(res["ok"]), "booking works: %s" % str(res.get("reason", "")))
	var tid: int = int(res["trip"])
	_check(Economy.balance(1) == coins0 - int(res["total"]), "the household paid the price")
	_check(Vacation.state_of(tid) == "booked", "booked first")
	K.run(3)
	_check(Vacation.state_of(tid) == "outbound" and SysUtil.is_away(mira) and Vacation.on_trip(int(mira.id)), "then travelling: hidden (away), on the trip")
	_check(DestLoader.region_of_zone(0) < 0, "the map is not loaded during the journey")
	var bills_before: int = Economy.bills.size()
	K.run(45)
	_check(Vacation.state_of(tid) == "there", "arrived (%s)" % Vacation.state_of(tid))
	var t: Dictionary = Vacation.trip(tid)
	_check(NeighborhoodLots.lot_at(mira.tile) == str(t["lot"]) and DestLoader.region_of_zone(int(t["zone"])) >= 0, "standing in the loaded destination lot")
	_check(not SysUtil.is_away(mira) and not mira.has_meta("away"), "visible again")
	_check(Neighborhood.lot_of(mira) != Neighborhood.HOME, "not at home")
	K.run(60)
	var locals: int = VacationLife.present_ids(t).size()
	_check(locals >= 3, "locals live there (%d)" % locals)
	# the holiday: a couple of fun activities and a souvenir are logged through the game events
	SysUtil.game_event("vacation_fun", {"folk_id": int(mira.id)})
	SysUtil.game_event("souvenir_bought", {"folk_id": int(mira.id)})
	for i in 12:
		SysUtil.game_event("vacation_fun", {"folk_id": int(folk[1].id)})
	K.warp(2 * 1440 - 60)
	_check(Vacation.state_of(tid) in ["inbound", "there"], "after two days they are heading home (%s)" % Vacation.state_of(tid))
	K.run(60)
	_check(Vacation.state_of(tid) == "inbound" or Vacation.trip(tid).is_empty(), "journey home")
	K.run(60)
	_check(Vacation.trip(tid).is_empty(), "the trip is over")
	_check(DestLoader.region_of_zone(0) < 0 and NeighborhoodLots.lot_at(Vector2i(20, 105)) == "", "the zone is unloaded again")
	_check(not SysUtil.is_away(mira) and NeighborhoodLots.lot_at(mira.tile) == "home", "home again (%s)" % NeighborhoodLots.lot_at(mira.tile))
	_check(Vacation.souvenirs_of(1).size() >= 1, "a souvenir came home")
	_check(Vacation.photos_of(1).size() >= 1, "photos were taken (%d)" % Vacation.photos_of(1).size())
	_check(mira.has_buff("vacation_glow"), "vacation glow")
	_check(mira.has_buff("well_rested_trip"), "well rested")
	_check(not mira.has_buff("on_trip"), "no longer on a trip")
	_check(Economy.bills.size() > bills_before or Economy.next_bill_day > 0, "the town's bills kept coming while they were away")
	_check(Vacation.history_list().size() == 1, "one trip in the history")
	_check(VacationLog.count("arrival") == 1 and VacationLog.count("return") >= 1, "story log has arrival and return")
	var chron := 0
	for p in ChronicleHook.recent:
		if str(p.get("place", "")) == "vacation":
			chron += 1
	_check(chron >= 2, "chronicle lines carry place 'vacation' (%d)" % chron)
	K.teardown()

func _save_mid_stay() -> void:
	var folk: Array = K.new_game("small")
	var res: Dictionary = Vacation.book_and_go(1, "mountain", {"length_days": 3, "travel_min": 30, "seed": 9})
	var tid: int = int(res["trip"])
	K.run(80)
	var t: Dictionary = Vacation.trip(tid)
	_check(str(t["state"]) == "there", "arrived at the mountain")
	var zone: int = int(t["zone"])
	var snap: Dictionary = SaveLoad.snapshot("mid-stay")
	var json: Variant = JSON.parse_string(JSON.stringify(snap))
	K.run(120)
	_check(SaveLoad.restore(json as Dictionary), "snapshot restores")
	var t2: Dictionary = Vacation.trip(tid)
	_check(not t2.is_empty() and str(t2["state"]) == "there" and int(t2["zone"]) == zone, "the trip and its zone survive a save / load")
	_check(DestLoader.region_of_zone(zone) >= 0, "the mountain map is still loaded")
	var f0 = SysUtil.folk(int(t2["folk"][0]))
	_check(f0 != null and Vacation.on_trip(int(f0.id)) and NeighborhoodLots.lot_at(f0.tile) == str(t2["lot"]), "the traveller is still there")
	K.run(5)
	_check(VacationLife.present_ids(t2).size() >= 1, "locals are back after a load")
	K.warp(3 * 1440 + 200)
	_check(Vacation.trip(tid).is_empty(), "the loaded trip still finishes")
	K.teardown()

func _empty_house_and_alarm() -> void:
	K.new_game("small")
	K.Kit.set_time(2, 0, 30)                   # the burglary dice only run at night
	var base: float = _burglary_rate()
	var res: Dictionary = Vacation.book_and_go(1, "camping", {"length_days": 2, "travel_min": 30})
	_check(bool(res["ok"]), "camping booked")
	K.run(5)
	_check(Vacation.household_empty(1), "the house stands empty")
	var away: float = _burglary_rate()
	_check(away > base * 2.0, "an empty house is a better target (%.2f vs %.2f a year)" % [away, base])
	var sitter_trip: Dictionary = Vacation.trip_of_household(1)
	sitter_trip["sitter"] = true
	var with_sitter: float = _burglary_rate()
	_check(with_sitter < away and with_sitter > base, "a house-sitter lowers it, but it stays higher than at home (%.2f)" % with_sitter)
	sitter_trip["sitter"] = false
	var w = WorldIface.world()
	var oid: int = -1
	var rect: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	for y in range(rect.position.y + 2, rect.end.y - 2):
		for x in range(rect.position.x + 2, rect.end.x - 2):
			if oid < 0 and w.defs.has("burglar_alarm"):
				oid = int(w.place_object("burglar_alarm", Vector2i(x, y), 0))
	_check(oid > 0, "an alarm was placed")
	if oid > 0:
		Economy.owner[oid] = 1
		var with_alarm: float = _burglary_rate()
		_check(with_alarm < away * 0.8, "an alarm lowers the risk of an empty house (%.2f vs %.2f)" % [with_alarm, away])
	K.warp(3 * 1440)
	_check(Vacation.trip_of_household(1).is_empty(), "the trip is over")
	_check(_burglary_rate() < away * 0.6, "back home the multiplier is gone (%.2f)" % _burglary_rate())
	K.teardown()
func _burglary_rate() -> float:
	return IncidentRisk.effective_rate(IncidentDefs.get_def("burglary"), IncidentSubject.of_household(1))
func _home_while_away() -> void:
	K.new_game("small")
	Kit_set_day(4)
	Weather.force("sunny")                          # rain would water the yard plants
	var w = WorldIface.world()
	var plant: int = -1
	var rect: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	for y in range(rect.position.y + 2, rect.end.y - 2):
		for x in range(rect.position.x + 2, rect.end.x - 2):
			if plant < 0:
				plant = int(w.place_object("plant", Vector2i(x, y), 0))
	_check(plant > 0, "a plant at home")
	Economy.owner[plant] = 1
	var water0: float = float(WorldIface.state_get(w.objects[plant], "water", 0.0))
	var res: Dictionary = Vacation.book_and_go(1, "camping", {"length_days": 9, "travel_min": 30, "seed": 3})
	_check(bool(res["ok"]), "a nine day camping trip: %s" % str(res.get("reason", "")))
	var tid: int = int(res["trip"])
	var balance0: int = Economy.balance(1)
	K.warp(9 * 1440 + 200)
	_check(Vacation.trip(tid).is_empty(), "back from the long trip")
	var paid := 0
	for e in Economy.ledger_for(1):
		if str(e["reason"]) == "bills":
			paid += absi(int(e["amount"]))
	_check(paid > 0, "the bills were paid while they were away (%d coins)" % paid)
	var late := 0
	for bl in Economy.bills:
		if bool(bl["late"]):
			late += 1
	_check(late == 0, "no bill went overdue")
	var water1: float = float(WorldIface.state_get(w.objects[plant], "water", 10.0))
	_check(water1 < water0 - 5.0, "the plant dried out (%.1f -> %.1f)" % [water0, water1])
	var hist: Dictionary = Vacation.history_list()[0] if not Vacation.history_list().is_empty() else {}
	_check(not hist.is_empty(), "history entry")
	var mb_mail := -1.0
	for o in SysUtil.all_world_objects():
		if str(o.def_id) == "mailbox" and NeighborhoodLots.lot_at(o.tile) == Neighborhood.HOME:
			mb_mail = float(WorldIface.state_get(o, "mail", 0.0))
	_check(mb_mail < 0.0 or mb_mail >= 3.0, "mail piled up (%.1f)" % mb_mail)
	var notes := 0
	for n in K.Kit.notes:
		if str(n[0]).begins_with("Back home:"):
			notes += 1
	_check(notes == 1, "one 'Back home' report")
	# a house-sitter keeps the plants
	K.teardown()
	K.new_game("small")
	Kit_set_day(4)
	Weather.force("sunny")
	var plant2: int = -1
	for y2 in range(rect.position.y + 2, rect.end.y - 2):
		for x2 in range(rect.position.x + 2, rect.end.x - 2):
			if plant2 < 0:
				plant2 = int(w.place_object("plant", Vector2i(x2, y2), 0))
	Economy.owner[plant2] = 1
	var res2: Dictionary = Vacation.book_and_go(1, "camping", {"length_days": 5, "travel_min": 30, "sitter": true})
	_check(bool(res2["ok"]) and int(Vacation.trip(int(res2["trip"]))["cost"]["sitter"]) > 0, "a sitter costs extra")
	K.warp(5 * 1440 + 100)
	_check(float(WorldIface.state_get(w.objects[plant2], "water", 0.0)) >= 5.9, "with a sitter the plant is fine")
	K.teardown()

func Kit_set_day(day: int) -> void:
	K.Kit.set_time(day, 8, 0)
func _work_and_school() -> void:
	var folk: Array = K.new_game("small")
	var mira: Folk = folk[0]
	Careers.hire(mira, "coder", 1)
	var kid := Folk.create("Pip", ["active"])
	kid.household_id = 1
	kid.age_stage = "child"
	WorldIface.world().add_folk(kid, folk[1].tile)
	Careers.enroll_school()
	K.Kit.set_time(7, 20, 0)                            # Sunday evening: Monday to Wednesday are work and school days
	var q: Dictionary = Vacation.quote(1, "camping", {"length_days": 3})
	_check(bool(q["ok"]), "quote with a worker and a pupil: %s" % str(q.get("reason", "")))
	var rows: Dictionary = {}
	for r in q["leave"]:
		rows[int(r["folk_id"])] = r
	_check(rows.has(int(mira.id)) and int(rows[int(mira.id)]["work_days"]) == 3 and int(rows[int(mira.id)]["paid"]) == 3, "the preview shows 3 work days, all paid leave (level 1: 2 + 1 days)")
	_check(rows.has(int(kid.id)) and int(rows[int(kid.id)]["school_days"]) >= 2, "and school days missed for the child (%s)" % str(rows.get(int(kid.id), {})))
	var perf0: float = CareerProgress.performance_of(int(mira.id))
	var grade0: float = float(Careers.school[int(kid.id)]["grade"])
	var coins0: int = Economy.balance(1)
	var res: Dictionary = Vacation.book_and_go(1, "camping", {"length_days": 3, "travel_min": 30})
	_check(bool(res["ok"]), "booked")
	var pay_before: int = Economy.balance(1)
	K.warp(3 * 1440 + 300)
	_check(Vacation.trip_of_household(1).is_empty(), "back")
	var paid_leave := 0
	for e in Economy.ledger_for(1):
		if str(e["reason"]) == "paid leave":
			paid_leave += int(e["amount"])
	_check(paid_leave > 0, "paid leave was paid (%d coins)" % paid_leave)
	_check(is_equal_approx(CareerProgress.performance_of(int(mira.id)), perf0), "paid days cost no performance")
	_check(float(Careers.school[int(kid.id)]["grade"]) < grade0, "the school grade dropped (%.0f -> %.0f)" % [grade0, float(Careers.school[int(kid.id)]["grade"])])
	# a second, unpaid trip: the allowance is used up
	K.Kit.set_time(14, 20, 0)
	Vacation.leave_used[int(mira.id)] = {"year": VacationWork.year_of(14), "used": 99}
	var q2: Dictionary = Vacation.quote(1, "camping", {"length_days": 2, "who": [int(mira.id)]})
	var row2: Dictionary = q2["leave"][0] if not (q2["leave"] as Array).is_empty() else {}
	_check(not row2.is_empty() and int(row2["unpaid"]) == 2 and int(row2["paid"]) == 0, "no paid leave left: both work days are unpaid (%s)" % str(row2))
	var perf1: float = CareerProgress.performance_of(int(mira.id))
	var skipped0: int = int(Careers.jobs[int(mira.id)]["days_skipped"])
	Vacation.book_and_go(1, "camping", {"length_days": 2, "who": [int(mira.id)], "travel_min": 30})
	K.warp(2 * 1440 + 300)
	_check(CareerProgress.performance_of(int(mira.id)) < perf1 - 5.0 and int(Careers.jobs[int(mira.id)]["days_skipped"]) == skipped0 + 2, "unpaid days hurt the job (%.1f -> %.1f)" % [perf1, CareerProgress.performance_of(int(mira.id))])
	K.teardown()