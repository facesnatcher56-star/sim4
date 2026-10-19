class_name Cruise
extends RefCounted
## The cruise ship (task 22). A cruise is a Vacation trip with dest "cruise": the five-deck ship (data/destinations/ship.json, the `levels`
## template format) is loaded into a zone when the first traveller boards and stays until everybody has left; ports of call load a holiday
## map into a second zone while the ship is docked. The cruise is a TIMELINE (CruiseRoute) of absolute minutes consumed in order:
## boarding, sailing, docking, shore day, last call, all aboard, programme items (captain's dinner, shows, theme nights), arrival, disembarking.
## Missing the ship (still ashore or in transit when it sails) leaves you behind: CruiseShore pays the expensive way home.
##
##   Cruise.describe(trip) -> {ship, route, ports, boarding: {open_min, all_aboard_min, sail_min}, arrive_min, return_min, cabins}
##   Cruise.command(trip, "go_ashore"|"board"|"linger", {folk_ids})
##   Cruise.ship_of(trip_id) / ship_ids() / on_board(trip) -> [folk]           task 22b hooks for the story probes
## State in trip["cruise"] (JSON-safe): route, timeline, idx, phase (booked | docked | sailing | home), name, class, package, cabins [{id, tile, level}],
## port, port_zone, port_lot, moves [{fid, min, to}], flights [{fid, leave_min, arrive_min, state, cost}], linger [fids], stranded [fids], sea, storm_until,
## roster-based NPCs live in trip["roster"], killer {..} (CruiseKiller), restricted (captain's order), ill [fids], log counters.
## Tier: FULL on the ship and in the port zone; cadence: timeline entries (exact minutes) + hourly stochastic checks; active set: cruises that are "there".

static func normalise(c: Dictionary) -> void:
	SysUtil.ints_in(c, ["idx", "port_zone", "storm_until"])
	for e in c.get("timeline", []):
		SysUtil.ints_in(e, ["min", "day"])
	for r in c.get("route", []):
		SysUtil.ints_in(r, ["day"])
	for m in c.get("moves", []):
		SysUtil.ints_in(m, ["fid", "min"])
	for fl in c.get("flights", []):
		SysUtil.ints_in(fl, ["fid", "leave_min", "arrive_min", "cost"])
	for k in ["linger", "stranded", "ill"]:
		c[k] = SysUtil.to_ints(c.get(k, []))
	for cb in c.get("cabins", []):
		SysUtil.ints_in(cb, ["level"])

static func cfg() -> Dictionary:
	return CruiseRoute.cfg()

static func of(t: Dictionary) -> Dictionary:
	return t.get("cruise", {})

# ------------------------------------------------------------------ booking
static func on_booked(t: Dictionary) -> void:
	var r := Vacation.rng_for(t)
	var built: Dictionary = CruiseRoute.build(int(t["sail_min"]), int(t["days"]), r)
	var s: Dictionary = CruiseRoute.ship()
	t["cruise"] = {"ship": str(s.get("id", "starlight")), "name": str(s.get("name", "Starlight Voyager")), "class": str(t["cabin_class"]), "package": str(t["package_id"]),
		"route": built["route"], "timeline": built["timeline"], "idx": 0, "phase": "booked", "port": "", "port_zone": -1, "port_lot": "", "moves": [], "flights": [],
		"linger": [], "stranded": [], "sea": "calm", "storm_until": 0, "cabins": [], "ill": [], "restricted": false, "killer": {}}
	t["label"] = str(s.get("name", "Cruise"))

static func describe(t: Dictionary) -> Dictionary:
	var c: Dictionary = of(t)
	if c.is_empty():
		return {}
	var tl: Array = c["timeline"]
	var open_min: int = CruiseRoute.first_min(tl, "board_open")
	return {"ship": {"id": str(c["ship"]), "name": str(c["name"]), "decks": 5, "cabin_class": str(c["class"]), "package": str(c["package"])},
		"route": (c["route"] as Array).duplicate(true), "ports": CruiseRoute.ports_of(c["route"]), "length_days": int(t["days"]),
		"boarding": {"open_min": open_min, "all_aboard_min": CruiseRoute.first_min(tl, "all_aboard"), "sail_min": int(t["sail_min"])},
		"boarding_min": int(t["arrive_min"]), "sail_min": int(t["sail_min"]), "arrive_min": int(t["arrive_min"]), "return_min": int(t["return_min"]),
		"home_dock_min": CruiseRoute.first_min(tl, "home_dock")}

static func on_depart(_t: Dictionary) -> void:
	pass

## The travellers board: the ship map is loaded and the crew, passengers and the party are placed on it.
static func arrive(t: Dictionary, zone: int) -> void:
	var c: Dictionary = t["cruise"]
	var lot: String = "trip_%d" % zone
	var res: Dictionary = DestLoader.load_zone(zone, "ship", lot, str(c["name"]))
	if not bool(res["ok"]):
		push_warning("Cruise: ship loaded with problems: %s" % str(res.get("failed", [])))
	t["zone"] = zone
	t["lot"] = lot
	var rc: Rect2i = res["rect"]
	c["phase"] = "docked"
	_assign_cabins(t, rc)
	var lobby: Array = DestDefs.map("ship").get("lobby", [15, 14, 0])
	var tile := rc.position + Vector2i(int(lobby[0]), int(lobby[1]))
	VacationTrip.place_party(t, [tile, tile + Vector2i(1, 0), tile + Vector2i(-1, 0), tile + Vector2i(0, 1)], int(lobby[2]), lot, zone)
	t["state"] = "there"
	CruiseCrew.start(t)
	VacationLife.roll_weather(t)
	var names: Array = VacationTrip.members(t).map(func(x): return str(x.name))
	SysUtil.notify("%s boarded %s." % [", ".join(names), str(c["name"])], "travel")
	SysUtil.game_event("arrived_on_holiday", {"trip": int(t["id"]), "dest": "cruise", "household_id": int(t["hid"]), "folk_ids": (t["folk"] as Array).duplicate()})
	VacationLog.note(t, "boarding", "%s boarded %s." % [", ".join(names), str(c["name"])], t["folk"], 1, true)
	_package_welcome(t)

static func _assign_cabins(t: Dictionary, rc: Rect2i) -> void:
	var c: Dictionary = t["cruise"]
	var all: Array = DestLoader.cabin_list("ship", rc)
	var want: String = str(c["class"])
	var mine: Array = []
	for cb in all:
		if str(cb["class"]) == want and mine.size() < int(t.get("cabins_n", 1)):
			mine.append({"id": str(cb["id"]), "tile": [cb["tile"].x, cb["tile"].y], "level": int(cb["level"])})
	c["cabins"] = mine

static func _package_welcome(t: Dictionary) -> void:
	var pk: Dictionary = (cfg().get("packages", {}) as Dictionary).get(str(t.get("package_id", "")), {})
	if pk.is_empty() or int(pk.get("extra", 0)) <= 0:
		return
	for f in VacationTrip.members(t):
		if str(pk.get("buff", "")) != "":
			f.add_buff(str(pk["buff"]))
	VacationLog.note(t, "package", str(pk.get("text", "")), t["folk"], 1, true)

# ------------------------------------------------------------------ the timeline
static func step(t: Dictionary, now: int) -> void:
	var c: Dictionary = t["cruise"]
	var tl: Array = c["timeline"]
	while int(c["idx"]) < tl.size() and int(tl[int(c["idx"])]["min"]) <= now:
		var e: Dictionary = tl[int(c["idx"])]
		c["idx"] = int(c["idx"]) + 1
		_handle(t, e)
		if str(t["state"]) != "there":
			return
	CruiseShore.step_moves(t, now)
	CruiseShore.step_flights(t, now)

static func _handle(t: Dictionary, e: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	match str(e["kind"]):
		"board_open":
			VacationLog.note(t, "port", "Boarding opened for %s." % str(c["name"]), [], 1, false)
		"dock":
			CruiseShore.dock(t, str(e["port"]), int(e["day"]))
		"ashore":
			CruiseShore.send_ashore(t)
		"last_call":
			CruiseShore.last_call(t)
		"auto_board":
			CruiseShore.auto_board(t, false)
		"all_aboard":
			CruiseShore.auto_board(t, true)
		"sail":
			CruiseShore.sail(t, int(e["day"]))
		"sea_day":
			CruiseLife.sea_day(t, int(e["day"]))
		"program":
			CruiseLife.program(t, e)
		"home_dock":
			c["phase"] = "home"
			VacationLog.note(t, "port", "%s docked at the home quay. Time to pack." % str(c["name"]), t["folk"], 1, true)
			CruiseCrime.handover(t, "the home quay")
			SysUtil.notify("%s is back at the quay. Passengers disembark at 09:00." % str(c["name"]), "travel")
		"disembark":
			CruiseShore.disembark(t)
		_:
			CruiseIncidents.on_timeline(t, e)

## Insert an extra timeline entry (fire out, search ends, security checks ...) after the ones already consumed, keeping the order.
static func schedule(t: Dictionary, minute: int, kind: String, extra: Dictionary = {}) -> void:
	var c: Dictionary = t["cruise"]
	var e: Dictionary = {"min": minute, "kind": kind, "day": 0}
	e.merge(extra, true)
	var tl: Array = c["timeline"]
	var i: int = int(c["idx"])
	while i < tl.size() and int(tl[i]["min"]) <= minute:
		i += 1
	tl.insert(i, e)

# ------------------------------------------------------------------ queries / commands
static func members_aboard(t: Dictionary) -> Array:
	var out: Array = []
	if int(t.get("zone", -1)) < 0:
		return out
	var rc := DestLoader.zone_rect(int(t["zone"]))
	for f in VacationTrip.members(t):
		if rc.has_point(f.tile) and not SysUtil.is_away(f):
			out.append(f)
	return out

static func on_board(t: Dictionary) -> Array:
	return members_aboard(t)

static func ship_of(trip_id: int) -> Dictionary:
	var t: Dictionary = Vacation.trip(trip_id)
	return describe(t) if str(t.get("dest", "")) == "cruise" else {}

static func ship_ids() -> Array:
	var out: Array = []
	for t in Vacation.active_trips():
		if str(t["dest"]) == "cruise":
			out.append(int(t["id"]))
	return out

static func command(t: Dictionary, action: String, args: Dictionary) -> Dictionary:
	if t.is_empty() or str(t["dest"]) != "cruise":
		return {"ok": false, "reason": "no cruise"}
	var ids: Array = args.get("folk_ids", t["folk"])
	match action:
		"go_ashore":
			return {"ok": CruiseShore.send_ashore(t, ids) > 0}
		"board":
			return {"ok": CruiseShore.board_now(t, ids) > 0}
		"linger":
			var c: Dictionary = t["cruise"]
			for fid in ids:
				if not (c["linger"] as Array).has(int(fid)):
					(c["linger"] as Array).append(int(fid))
			return {"ok": true}
	return {"ok": false, "reason": "unknown action"}

# ------------------------------------------------------------------ hourly
static func on_hour(t: Dictionary) -> void:
	CruiseLife.on_hour(t)
	CruiseIncidents.noro_hour(t)
	CruiseCrime.security_hour(t)
	CruiseKiller.on_hour(t)

static func on_leave(t: Dictionary) -> void:
	CruiseKiller.on_leave(t)
	CruiseShore.unload_port(t)
	var c: Dictionary = t["cruise"]
	c["phase"] = "home"

static func after_load(t: Dictionary) -> void:
	CruiseCrew.after_load(t)
