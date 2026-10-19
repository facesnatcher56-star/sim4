class_name CruiseShore
extends RefCounted
## Ports of call and the rules of the quay (task 22). When the ship docks the port's holiday map is loaded into a second zone; at 09:00 the
## party goes ashore (a short hidden transit, then they stand in the port); at 15:30 there is a last call, at 16:00 and 16:30 everybody who is not busy
## with something the player chose (or lingering on purpose) is called back; at sailing time anyone still ashore (or on the way) is LEFT BEHIND:
## they wait, pay the expensive flight home and arrive late and stressed. The port zone is unloaded when the last person has gone.

static func cfg() -> Dictionary:
	return CruiseRoute.cfg()

static func port_def(id: String) -> Dictionary:
	return ((cfg().get("ports", {}) as Dictionary).get(id, {}) as Dictionary)

static func port_rect(c: Dictionary) -> Rect2i:
	return DestLoader.zone_rect(int(c["port_zone"]))

static func ashore_members(t: Dictionary) -> Array:
	var c: Dictionary = t["cruise"]
	var out: Array = []
	if int(c["port_zone"]) < 0:
		return out
	var rc := port_rect(c)
	for f in VacationTrip.members(t):
		if rc.has_point(f.tile) and not SysUtil.is_away(f):
			out.append(f)
	return out

# ------------------------------------------------------------------ docking
static func dock(t: Dictionary, port: String, day: int) -> void:
	var c: Dictionary = t["cruise"]
	var pd: Dictionary = port_def(port)
	c["port"] = port
	var noro: bool = SysUtil.now() < int(c.get("noro_until", 0)) and bool(CruiseRoute.cfg().get("incident", {}).get("noro_cancel_port", true))
	if SysUtil.now() < int(c["storm_until"]) or noro:
		c["phase"] = "sailing"
		VacationLog.note(t, "port", "%s did not dock at %s (%s). The ship stayed at sea." % [str(c["name"]), str(pd.get("label", port)), "the stomach bug outbreak" if noro else "the storm"], t["folk"], 2, true)
		SysUtil.notify("The port of %s was cancelled because of the weather." % str(pd.get("label", port)), "warn")
		c["port"] = ""
		return
	var zone: int = Vacation.free_zone()
	if zone < 0:
		c["port"] = ""
		return
	var lot: String = "trip_%d" % zone
	var res: Dictionary = DestLoader.load_zone(zone, str(pd.get("map", "beach")), lot, str(pd.get("label", port)))
	c["port_zone"] = zone
	c["port_lot"] = lot
	c["phase"] = "docked"
	t["roster_port"] = res.get("spawn", [])
	VacationLog.note(t, "port", "%s docked at %s. Shore day: the ship sails at %s." % [str(c["name"]), str(pd.get("label", port)), _hh(float(CruiseRoute.ship().get("sail_hour", 17.0)))], t["folk"], 1, true)
	CruiseCrime.handover(t, str(pd.get("label", port)))
	SysUtil.notify("%s: %s. Shore day until %s." % [str(pd.get("label", port)), str(pd.get("blurb", "")).trim_suffix("."), _hh(float(CruiseRoute.ship().get("all_aboard_hour", 16.5)))], "travel")

static func _hh(h: float) -> String:
	return "%02d:%02d" % [int(h), int(round((h - floorf(h)) * 60.0))]

# ------------------------------------------------------------------ going ashore / back
static func send_ashore(t: Dictionary, ids: Array = []) -> int:
	var c: Dictionary = t["cruise"]
	if int(c["port_zone"]) < 0 or str(c["phase"]) != "docked":
		return 0
	var n: int = 0
	for f in Cruise.members_aboard(t):
		if not ids.is_empty() and not SysUtil.has_int(ids, int(f.id)):
			continue
		if f.has_buff("sick") or Hospital.is_in(int(f.id)) or bool(c.get("restricted", false)) or _moving(c, int(f.id)):
			continue
		_start_move(t, f, "port", int(CruiseRoute.ship().get("board_walk_min", 25)) / 2)
		n += 1
	if n > 0:
		VacationLog.note(t, "port", "%d of the party went ashore at %s." % [n, str(port_def(str(c["port"])).get("label", ""))], t["folk"], 1, false)
	return n

static func _moving(c: Dictionary, fid: int) -> bool:
	for m in c["moves"]:
		if int(m["fid"]) == fid:
			return true
	return false

static func last_call(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	if int(c["port_zone"]) < 0:
		return
	var left: Array = ashore_members(t)
	if left.is_empty():
		return
	var names: Array = left.map(func(x): return str(x.name))
	SysUtil.notify("Last call! %s must be back on the ship by %s or it sails without them." % [", ".join(names), _hh(float(CruiseRoute.ship().get("all_aboard_hour", 16.5)))], "warn")
	VacationLog.note(t, "port", "Last call at the quay: %s still ashore." % ", ".join(names), left.map(func(x): return int(x.id)), 1, false)

## `final` = the 16:30 call. Busy (player-chosen action running) or lingering folk are skipped, and so may miss the ship.
static func auto_board(t: Dictionary, final: bool) -> int:
	var c: Dictionary = t["cruise"]
	if int(c["port_zone"]) < 0 and str(c["phase"]) == "docked":
		return 0
	var n: int = 0
	for f in ashore_members(t):
		if _moving(c, int(f.id)) or SysUtil.has_int(c["linger"], int(f.id)):
			continue
		if CareerShifts.player_busy(f):
			if final:
				SysUtil.notify("%s is still busy ashore. The ship is about to sail!" % f.name, "warn")
			continue
		_start_move(t, f, "ship", 15)
		n += 1
	return n

static func board_now(t: Dictionary, ids: Array) -> int:
	var n: int = 0
	var c: Dictionary = t["cruise"]
	for f in ashore_members(t):
		if SysUtil.has_int(ids, int(f.id)) and not _moving(c, int(f.id)):
			(c["linger"] as Array).erase(int(f.id))
			_start_move(t, f, "ship", 15)
			n += 1
	return n

static func _start_move(t: Dictionary, f, to: String, minutes: int) -> void:
	var c: Dictionary = t["cruise"]
	f.cancel_current("trip")
	f.clear_queue()
	Away.send(f, float(maxi(minutes, 2)), "vacation", {"label": "Walking to the %s" % ("quay" if to == "ship" else "town"), "trip": int(t["id"])})
	(c["moves"] as Array).append({"fid": int(f.id), "min": SysUtil.now() + maxi(minutes, 2), "to": to})

static func step_moves(t: Dictionary, now: int) -> void:
	var c: Dictionary = t["cruise"]
	if (c["moves"] as Array).is_empty():
		return
	var keep: Array = []
	for m in c["moves"]:
		if int(m["min"]) > now:
			keep.append(m)
			continue
		var f = SysUtil.folk(int(m["fid"]))
		if f == null:
			continue
		if str(m["to"]) == "port":
			if int(c["port_zone"]) >= 0:
				var sp: Array = t.get("roster_port", [])
				var base: Vector2i = (sp[0] if not sp.is_empty() else port_rect(c).position + Vector2i(15, 20))
				VacationTrip.place_one(f, NeighborhoodTravel._spread(base, int(f.id) % 6), 0, str(c["port_lot"]), int(c["port_zone"]))
		else:
			var lobby: Array = DestDefs.map("ship").get("lobby", [15, 14, 0])
			var rc := DestLoader.zone_rect(int(t["zone"]))
			var tile := rc.position + Vector2i(int(lobby[0]), int(lobby[1]))
			VacationTrip.place_one(f, NeighborhoodTravel._spread(tile, int(f.id) % 6), int(lobby[2]), str(t["lot"]), int(t["zone"]))
			VacationLog.note(t, "port", "%s is back on board." % f.name, [int(f.id)], 1, false)
	c["moves"] = keep

# ------------------------------------------------------------------ sailing, left behind
static func sail(t: Dictionary, day: int) -> void:
	var c: Dictionary = t["cruise"]
	c["phase"] = "sailing"
	if day == 0:
		VacationLog.note(t, "port", "%s sailed from the home quay." % str(c["name"]), t["folk"], 2, true)
		SysUtil.notify("%s is under way!" % str(c["name"]), "travel")
		return
	var stranded: Array = []
	if int(c["port_zone"]) >= 0:
		var rc := port_rect(c)
		for f in VacationTrip.members(t):
			if rc.has_point(f.tile):                        # still ashore, or on the way back when the gangway closed
				stranded.append(f)
	for f3 in stranded:
		left_behind(t, f3, day)
	var pd: Dictionary = port_def(str(c["port"]))
	VacationLog.note(t, "port", "%s sailed from %s%s." % [str(c["name"]), str(pd.get("label", "port")), " without %d of the party" % stranded.size() if not stranded.is_empty() else ""], t["folk"], 1, true)
	c["port"] = ""
	if stranded.is_empty():
		unload_port(t)

static func _move_of(c: Dictionary, fid: int) -> Dictionary:
	for m in c["moves"]:
		if int(m["fid"]) == fid:
			return m
	return {}

static func left_behind(t: Dictionary, f, day: int) -> void:
	var c: Dictionary = t["cruise"]
	var fid: int = int(f.id)
	var kept: Array = []
	for m in c["moves"]:
		if int(m["fid"]) != fid:
			kept.append(m)
	c["moves"] = kept
	VacationTrip.end_transit(f)
	if not in_port_zone(f, c):
		var sp: Array = t.get("roster_port", [])
		var base: Vector2i = (sp[0] if not sp.is_empty() else port_rect(c).position + Vector2i(15, 20))
		VacationTrip.place_one(f, NeighborhoodTravel._spread(base, fid % 6), 0, str(c["port_lot"]), int(c["port_zone"]))
	f.add_buff("left_behind")
	if not (c["stranded"] as Array).has(fid):
		(c["stranded"] as Array).append(fid)
	var lb: Dictionary = cfg().get("left_behind", {})
	var days_left: int = maxi(int(t["days"]) - day, 0)
	var cost: int = int(lb.get("flight_base", 380)) + int(lb.get("flight_per_day_left", 45)) * days_left
	(c["flights"] as Array).append({"fid": fid, "leave_min": SysUtil.now() + int(lb.get("wait_min", 120)), "arrive_min": -1, "state": "waiting", "cost": cost})
	SysUtil.notify("%s missed the ship! It sailed without them. The way home will cost %d coins." % [f.name, cost], "bad")
	VacationLog.note(t, "missed", "%s missed the boarding and was left behind at %s. A flight home costs %d coins." % [f.name, str(port_def(str(c["port"])).get("label", "the port")), cost], [fid], 3, true)
	SysUtil.game_event("left_behind", {"trip": int(t["id"]), "folk_id": fid, "household_id": int(t["hid"]), "cost": cost})

static func in_port_zone(f, c: Dictionary) -> bool:
	return int(c["port_zone"]) >= 0 and port_rect(c).has_point(f.tile)

static func step_flights(t: Dictionary, now: int) -> void:
	var c: Dictionary = t["cruise"]
	if (c["flights"] as Array).is_empty():
		return
	var lb: Dictionary = cfg().get("left_behind", {})
	for fl in c["flights"]:
		var f = SysUtil.folk(int(fl["fid"]))
		if f == null:
			fl["state"] = "gone"
			continue
		if str(fl["state"]) == "waiting" and now >= int(fl["leave_min"]):
			Economy.deposit(int(t["hid"]), -int(fl["cost"]), "flight home")
			fl["state"] = "flying"
			fl["arrive_min"] = now + int(lb.get("transit_min", 600))
			f.cancel_current("trip")
			f.clear_queue()
			f.tile = VacationTrip.home_tile()
			f.level = 0
			f.remove_meta("trip_zone")
			NeighborhoodLots.mark_inside(f, Neighborhood.HOME)
			Away.send(f, float(int(lb.get("transit_min", 600))), "vacation", {"label": "Flying home", "trip": int(t["id"])})
			VacationLog.note(t, "missed", "%s flew home alone (%d coins)." % [f.name, int(fl["cost"])], [int(f.id)], 2, true)
			if ashore_members(t).is_empty() and (c["moves"] as Array).is_empty():
				unload_port(t)
		elif str(fl["state"]) == "flying" and now >= int(fl["arrive_min"]):
			fl["state"] = "home"
			VacationTrip.send_home_early(t, f)
	var keep: Array = []
	for fl2 in c["flights"]:
		if str(fl2["state"]) not in ["home", "gone"]:
			keep.append(fl2)
	c["flights"] = keep

static func unload_port(t: Dictionary) -> void:
	var c: Dictionary = t.get("cruise", {})
	if c.is_empty() or int(c.get("port_zone", -1)) < 0:
		return
	if not ashore_members(t).is_empty():
		return
	DestLoader.unload_zone(int(c["port_zone"]))
	c["port_zone"] = -1
	c["port_lot"] = ""
	t.erase("roster_port")

# ------------------------------------------------------------------ the end of the cruise
static func disembark(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	CruiseLife.surface_secrets(t)
	c["flights"] = []
	VacationLog.note(t, "port", "The party disembarked from %s." % str(c["name"]), t["folk"], 1, false)
	VacationTrip.leave_destination(t, false)
