class_name VacationTrip
extends RefCounted
## The life cycle of one trip: booked -> outbound (hidden journey, Away "vacation") -> there (the holiday map is loaded into a zone and the
## travellers are placed in it) -> inbound (hidden journey home, zone unloaded) -> done. Driven by absolute due minutes (Vacation.on_minute),
## so a clock jump or a load changes nothing. Cruises delegate "there" to Cruise (ship, ports, boarding).
##
## Trip record (JSON-safe): id, hid, dest, state, folk [ids], guests [townie ids], days, book_min, depart_min, arrive_min, end_min, return_min,
## travel_min, cost {total, travel, lodging, spending, sitter, package, lines}, sitter, wallet (spending money left), zone, lot, seed, weather,
## photos, fun, souvenirs [{id, label}], leave [..], log [..], home {..}, npcs [ids], left [folk ids], cruise {..}, postponed, summary {..}

const MAX_POSTPONE := 16

static func create(hid: int, dest: String, q: Dictionary, opts: Dictionary) -> Dictionary:
	var id: int = Vacation.next_id
	Vacation.next_id += 1
	var now: int = SysUtil.now()
	return {"id": id, "hid": hid, "dest": dest, "state": "booked", "folk": (q["who"] as Array).duplicate(), "guests": (q["guests"] as Array).duplicate(),
		"days": int(q["days"]), "book_min": now, "depart_min": int(q["depart_min"]), "arrive_min": int(q["arrive_min"]), "end_min": int(q["end_min"]),
		"return_min": int(q["return_min"]), "travel_min": int(q["travel_min"]), "sail_min": int(q.get("sail_min", 0)),
		"cost": {"total": int(q["total"]), "travel": int(q["travel"]), "lodging": int(q["lodging"]), "spending": int(q["spending"]), "sitter": int(q["sitter"]),
			"package": int(q["package"]), "lines": (q["lines"] as Array).duplicate(true)},
		"sitter": bool(opts.get("sitter", false)), "wallet": int(q["spending"]), "zone": -1, "lot": "", "seed": int(opts.get("seed", Vacation.rng.randi())),
		"weather": "", "weather_day": -1, "photos": 0, "fun": 0, "souvenirs": [], "leave": [], "log": [], "home": {}, "npcs": [], "left": [], "back": [],
		"postponed": 0, "cabin_class": str(q.get("cabin_class", "")), "package_id": str(q.get("package_id", "")), "cabins_n": int(q.get("cabins", 0)),
		"label": VacationCost.label_of(dest), "cruise": {}, "summary": {}}

static func normalise(t: Dictionary) -> void:
	SysUtil.ints_in(t, ["id", "hid", "days", "book_min", "depart_min", "arrive_min", "end_min", "return_min", "travel_min", "sail_min", "wallet", "zone", "photos",
		"fun", "postponed", "weather_day", "cabins_n"])
	t["folk"] = SysUtil.to_ints(t.get("folk", []))
	t["guests"] = SysUtil.to_ints(t.get("guests", []))
	t["npcs"] = SysUtil.to_ints(t.get("npcs", []))
	t["left"] = SysUtil.to_ints(t.get("left", []))
	t["back"] = SysUtil.to_ints(t.get("back", []))
	if not (t.get("cruise", {}) as Dictionary).is_empty():
		Cruise.normalise(t["cruise"])

static func members(t: Dictionary) -> Array:
	var out: Array = []
	for fid in t["folk"]:
		var f = SysUtil.folk(int(fid))
		if f != null:
			out.append(f)
	return out

static func home_tile() -> Vector2i:
	return Neighborhood.entry_tile(Neighborhood.HOME)

# ------------------------------------------------------------------ the machine
static func step(t: Dictionary, now: int) -> void:
	if str(t["state"]) in ["outbound", "there", "inbound"]:
		for f in members(t):
			if Hospital.is_in(int(f.id)):
				detach_to_hospital(t, f)
	match str(t["state"]):
		"booked":
			if now >= int(t["depart_min"]):
				depart(t, now)
		"outbound":
			if now >= int(t["arrive_min"]):
				arrive(t, now)
		"there":
			if members(t).is_empty():
				abort(t, "nobody is left on the trip")
			elif str(t["dest"]) == "cruise":
				Cruise.step(t, now)
			elif now >= int(t["end_min"]):
				leave_destination(t, false)
		"inbound":
			if now >= int(t["return_min"]):
				come_back(t)

## Leave: the travellers set off (hidden). A busy traveller postpones the departure (up to 8 hours), then the trip is cancelled.
static func depart(t: Dictionary, now: int) -> void:
	if str(t["dest"]) == "cruise" and now + int(t["travel_min"]) >= int(t["sail_min"]) - 15:
		Vacation.cancel(int(t["id"]), "called off: the party could not reach the ship before it sailed")
		return
	for f in members(t):
		var br: String = VacationCost.busy_reason(f)
		if br != "":
			t["postponed"] = int(t["postponed"]) + 1
			t["depart_min"] = now + 30
			t["arrive_min"] = int(t["arrive_min"]) + 30
			t["end_min"] = int(t["end_min"]) + 30
			t["return_min"] = int(t["return_min"]) + 30
			if int(t["postponed"]) > MAX_POSTPONE:
				Vacation.cancel(int(t["id"]), "called off (%s)" % br)
			return
	t["state"] = "outbound"
	t["depart_min"] = now
	var tmin: int = int(t["travel_min"])
	t["arrive_min"] = now + tmin
	var cruise: bool = str(t["dest"]) == "cruise"
	for f2 in members(t):
		Vacation._by_folk[int(f2.id)] = int(t["id"])
		f2.cancel_current("trip")
		f2.clear_queue()
		f2.set_meta("trip_id", int(t["id"]))
		f2.add_buff("on_trip")
		if cruise:
			f2.add_buff("on_cruise")
		Away.send(f2, float(maxi(tmin, 2)), "vacation", {"label": "Travelling to %s" % str(t["label"]), "trip": int(t["id"])})
	VacationHome.begin(t)
	var names: Array = members(t).map(func(x): return str(x.name))
	SysUtil.notify("%s set off for %s." % [", ".join(names), str(t["label"])], "travel")
	SysUtil.game_event("left_on_holiday", {"trip": int(t["id"]), "dest": str(t["dest"]), "household_id": int(t["hid"]), "folk_ids": (t["folk"] as Array).duplicate()})
	VacationLog.note(t, "departure", "%s set off for %s." % [", ".join(names), str(t["label"])], t["folk"], 1, false)
	if cruise:
		Cruise.on_depart(t)

static func arrive(t: Dictionary, now: int) -> void:
	var zone: int = Vacation.free_zone()
	if zone < 0:
		t["arrive_min"] = now + 30
		return
	if str(t["dest"]) == "cruise":
		Cruise.arrive(t, zone)
		return
	var dd: Dictionary = VacationCost.dest_def(str(t["dest"]))
	var lot: String = "trip_%d" % zone
	var res: Dictionary = DestLoader.load_zone(zone, str(dd.get("map", t["dest"])), lot, str(t["label"]))
	if not bool(res["ok"]):
		push_warning("Vacation: map %s loaded with problems: %s" % [str(t["dest"]), str(res.get("failed", []))])
	t["zone"] = zone
	t["lot"] = lot
	place_party(t, res["spawn"], 0, lot, zone)
	t["state"] = "there"
	VacationLife.start(t)
	var names: Array = members(t).map(func(x): return str(x.name))
	SysUtil.notify("%s arrived at %s." % [", ".join(names), str(t["label"])], "travel")
	SysUtil.game_event("arrived_on_holiday", {"trip": int(t["id"]), "dest": str(t["dest"]), "household_id": int(t["hid"]), "folk_ids": (t["folk"] as Array).duplicate()})
	VacationLog.note(t, "arrival", "%s arrived at %s." % [", ".join(names), str(t["label"])], t["folk"], 1, false)

## Put the party on free tiles around `spawn` (list of tiles) at `level` of the zone's map and make them visible.
static func place_party(t: Dictionary, spawn: Array, level: int, lot: String, zone: int, ids: Array = []) -> void:
	var i: int = 0
	for f in members(t):
		if not ids.is_empty() and not ids.has(int(f.id)):
			continue
		var base: Vector2i = spawn[i % spawn.size()]
		place_one(f, base if i < spawn.size() else NeighborhoodTravel._spread(base, i), level, lot, zone)
		i += 1

## One traveller appears at `tile` / `level` of the zone's lot (the hidden journey ends).
static func place_one(f, tile: Vector2i, level: int, lot: String, zone: int) -> void:
	end_transit(f)
	var w = WorldIface.world()
	if w != null:
		w.release_all(int(f.id))
	f.tile = tile
	f.level = level
	f.set_meta("trip_zone", zone)
	NeighborhoodLots.mark_inside(f, lot)
	f.idle_until_min = 0
	Neighborhood.refresh_view(int(f.id))

## A traveller taken ill enough for the hospital (HospitalWard moves them to the ward, Hospital.admit recalls any Away) leaves the trip:
## the hospital owns them now and sends them home when they are discharged.
static func detach_to_hospital(t: Dictionary, f) -> void:
	var fid: int = int(f.id)
	f.remove_meta("trip_id")
	f.remove_meta("trip_zone")
	f.remove_buff("on_trip")
	f.remove_buff("on_cruise")
	(t["folk"] as Array).erase(fid)
	(t["left"] as Array).append(fid)
	Vacation._by_folk.erase(fid)
	SysUtil.notify("%s was taken to hospital and the holiday is over for them." % f.name, "warn")
	VacationLog.note(t, "incident", "%s was taken to hospital and left the trip." % f.name, [fid], 3, true)

## A traveller who got home on their own (flown home after missing the ship): the holiday is over for them.
static func send_home_early(t: Dictionary, f) -> void:
	var fid: int = int(f.id)
	end_transit(f)
	f.tile = home_tile()
	f.level = 0
	NeighborhoodLots.mark_inside(f, Neighborhood.HOME)
	f.remove_meta("trip_id")
	f.remove_meta("trip_zone")
	f.remove_buff("on_trip")
	f.remove_buff("on_cruise")
	f.remove_buff("left_behind")
	f.add_buff("homesick")
	f.remember("vacation:" + str(t["dest"]), -0.5)
	f.idle_until_min = 0
	Neighborhood.refresh_view(fid)
	(t["folk"] as Array).erase(fid)
	(t["left"] as Array).append(fid)
	Vacation._by_folk.erase(fid)
	VacationLog.note(t, "return", "%s got home on their own, long after the ship." % f.name, [fid], 2, true)

## The journey is over for this folk: end the hidden Away.
static func end_transit(f) -> void:
	var fid: int = int(f.id)
	if Away.pending.has(fid):
		for q in f.queue.duplicate():
			if (q as Interaction).def_id == Away.IID:
				f.queue.erase(q)
		Away.pending.erase(fid)
	if Away.active.has(fid):
		if f.current != null and f.current.def_id == Away.IID:
			f.current.cancel("arrived")
		else:
			Away.active.erase(fid)
	if f.has_meta("away") and str(f.get_meta("away")) == "vacation":
		f.remove_meta("away")
		f.remove_buff("away")

## Stay over (or the player said "come home"): the party is hidden again for the journey home, the zone is unloaded.
static func leave_destination(t: Dictionary, early: bool) -> void:
	VacationLife.stop(t)
	var home: Vector2i = home_tile()
	var tmin: int = int(t["travel_min"])
	var i: int = 0
	for f in members(t):
		f.cancel_current("trip")
		f.clear_queue()
		f.remove_meta("trip_zone")
		f.tile = home if i == 0 else NeighborhoodTravel._spread(home, i)
		f.level = 0
		NeighborhoodLots.mark_inside(f, Neighborhood.HOME)
		Away.send(f, float(maxi(tmin, 2)), "vacation", {"label": "Travelling home", "trip": int(t["id"])})
		i += 1
	if int(t["zone"]) >= 0:
		DestLoader.unload_zone(int(t["zone"]))
		t["zone"] = -1
	t["state"] = "inbound"
	t["end_min"] = SysUtil.now()
	t["return_min"] = SysUtil.now() + tmin
	var cruise: bool = str(t["dest"]) == "cruise"
	VacationLog.note(t, "return", "The party left %s%s." % [str(t["label"]), " early" if early else ""], t["folk"], 1, false)
	if cruise:
		Cruise.on_leave(t)

## Home again: the journey ends, the return effects apply, the house is looked at, the trip becomes history.
static func come_back(t: Dictionary) -> void:
	var home: Vector2i = home_tile()
	var i: int = 0
	var back: Array = []
	for f in members(t):
		end_transit(f)
		f.tile = home if i == 0 else NeighborhoodTravel._spread(home, i)
		f.level = 0
		NeighborhoodLots.mark_inside(f, Neighborhood.HOME)
		f.idle_until_min = 0
		f.remove_meta("trip_id")
		f.remove_buff("on_trip")
		f.remove_buff("on_cruise")
		Neighborhood.refresh_view(int(f.id))
		back.append(int(f.id))
		i += 1
	t["back"] = back
	VacationReturn.apply(t)
	VacationHome.finish(t)
	t["state"] = "done"
	SysUtil.game_event("returned_from_holiday", {"trip": int(t["id"]), "dest": str(t["dest"]), "household_id": int(t["hid"]), "folk_ids": back.duplicate(),
		"photos": int(t["photos"]), "souvenirs": (t["souvenirs"] as Array).size()})
	Vacation.history.append(t.get("summary", {}))
	while Vacation.history.size() > int(Vacation.cfg().get("history_cap", 40)):
		Vacation.history.pop_front()
	Vacation._finish(t)

## Everyone on the trip is gone (died, left behind and flown home...): tidy up.
static func abort(t: Dictionary, why: String) -> void:
	VacationLife.stop(t)
	if str(t["dest"]) == "cruise":
		Cruise.on_leave(t)
	if int(t["zone"]) >= 0:
		DestLoader.unload_zone(int(t["zone"]))
	VacationLog.note(t, "return", "The trip ended: %s." % why, t["folk"], 2, false)
	VacationHome.finish(t)
	t["summary"] = {"trip": int(t["id"]), "dest": str(t["dest"]), "label": str(t["label"]), "aborted": why, "day": SysUtil.day()}
	Vacation.history.append(t["summary"])
	Vacation._finish(t)

## After a load: the zone content came with the world save; metas and NPCs are rebuilt.
static func after_load(t: Dictionary) -> void:
	if str(t["state"]) == "there":
		for f in members(t):
			f.set_meta("trip_zone", int(t["zone"]))
			f.set_meta("trip_id", int(t["id"]))
			NeighborhoodLots.mark_inside(f, str(t["lot"]))
		VacationLife.after_load(t)
		if str(t["dest"]) == "cruise":
			Cruise.after_load(t)
	elif str(t["state"]) in ["outbound", "inbound"]:
		var left: int = (int(t["arrive_min"]) if str(t["state"]) == "outbound" else int(t["return_min"])) - SysUtil.now()
		for f2 in members(t):
			f2.set_meta("trip_id", int(t["id"]))
			var fid: int = int(f2.id)
			if not Away.active.has(fid) and not Away.pending.has(fid):       # saved before the hidden journey had started: start it now
				Away.send(f2, float(maxi(left, 2)), "vacation", {"label": "Travelling", "trip": int(t["id"])})
