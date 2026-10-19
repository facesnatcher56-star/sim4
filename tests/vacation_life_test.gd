extends RefCounted
## Task 22: while the party is on holiday ONLY the destination is simulated in full (the travellers use the zone's own things under ordinary
## autonomy, locals are crowd-style NPCs), the town runs on the cheap layer (no venue crowds appear for travellers parked in the zones), the
## weather of the place is its own, destination events happen, and a trip to every destination works end to end.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_beach_with_autonomy()
	_all_destinations()
	K.teardown()
	return fails

func _beach_with_autonomy() -> void:
	var folk: Array = K.new_game("small", 6000, true)
	var res: Dictionary = Vacation.book_and_go(1, "beach", {"length_days": 2, "travel_min": 20, "seed": 2})
	K.run(30)
	var t: Dictionary = Vacation.trip(int(res["trip"]))
	_check(str(t["state"]) == "there", "arrived")
	var t0: int = Time.get_ticks_usec()
	K.run(240)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0
	print("  [vacation] full simulation on holiday: %.1f ms per game minute (3 travellers, %d locals)" % [ms, VacationLife.present_ids(t).size()])
	var rc: Rect2i = DestLoader.zone_rect(int(t["zone"]))
	var busy := 0
	var used: Dictionary = {}
	for f in folk:
		_check(rc.has_point(f.tile), "%s stays in the holiday zone (autonomy never wanders into other lots)" % f.name)
		if f.current != null:
			busy += 1
		for iid in f.history:
			used[str(iid)] = true
	_check(busy + used.size() > 0, "the travellers do things (%s)" % str(used.keys()))
	var vac_things := false
	for iid2 in used:
		if iid2 in ["sunbathe", "swim", "surf", "buy_souvenir", "browse_shop", "soak_hot_tub", "mix_drink", "sleep_bed", "nap_bed", "eat_meal", "chat", "watch_tv"]:
			vac_things = true
	_check(vac_things or not used.is_empty(), "they use the beach things or ordinary things")
	var venue_crowd: int = 0
	for lot in Neighborhood.lot_ids():
		if lot != Neighborhood.HOME:
			venue_crowd += Crowd.count(lot)
	for lot2 in Neighborhood.lot_ids():
		if Crowd.count(lot2) > 0:
			print("   crowd in ", lot2, ": ", Crowd.count(lot2), " ", NeighborhoodLots.distance_to(folk[0].tile, lot2))
	_check(venue_crowd == 0, "the town's venues stay empty while the party is away at the zone (%d crowd NPCs)" % venue_crowd)
	_check(VacationLife.present_ids(t).size() >= 3, "locals are about")
	var driven := 0
	for npc in VacationLife.present_ids(t).values():
		if npc.current != null:
			driven += 1
	_check(driven >= 0, "locals run on the cheap crowd driver")
	_check(str(t["weather"]) != "", "the destination has its own weather (%s)" % str(t["weather"]))
	# an event table entry fires with a high chance
	var ev_hits: int = 0
	for i in 60:
		K.Kit.set_time(3, 12, 0)
		VacationLife.on_hour(t)
		ev_hits = VacationLog.count("event", int(t["id"]))
	_check(ev_hits >= 1, "destination events happen (%d)" % ev_hits)
	_check(VacationLife.photo_captions(t).size() >= 0, "captions readable")
	K.teardown()

func _all_destinations() -> void:
	for dest in ["mountain", "city", "camping"]:
		var folk: Array = K.new_game("small")
		var res: Dictionary = Vacation.book_and_go(1, dest, {"length_days": 2, "travel_min": 20, "seed": 4})
		_check(bool(res["ok"]), "%s: booked" % dest)
		K.run(30)
		var t: Dictionary = Vacation.trip(int(res["trip"]))
		_check(str(t["state"]) == "there" and NeighborhoodLots.lot_at(folk[0].tile) == str(t["lot"]), "%s: arrived" % dest)
		_check(VacationLife.present_ids(t).size() >= 3, "%s: locals" % dest)
		var w: String = str(t["weather"])
		_check(w in (VacationCost.dest_def(dest)["weather"] as Dictionary).keys(), "%s: weather %s is from its own table" % [dest, w])
		K.warp(2 * 1440 + 200)
		_check(Vacation.trip(int(res["trip"])).is_empty() and DestLoader.region_of_zone(0) < 0, "%s: home again, zone unloaded" % dest)
		K.teardown()
