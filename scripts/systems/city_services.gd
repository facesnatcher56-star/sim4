class_name CityServices
extends RefCounted
## Emergency services as real places (task 12.3): fire engines, ambulances and patrol cars start from a station lot of the map and drive to the call.
## Response time = call handling + turnout (staffing follows the town budget) + the drive (distance between the lots, siren speed, traffic, dark lights,
## road works) + a wait when every unit is already out; no working phone line adds a delay (a neighbour has to raise the alarm).
##   CityServices.estimate(service, lot, opts) -> {minutes, parts}      dispatch(service, lot, opts) -> same, and one unit is out until it is back
##   CityServices.typical(service) -> average minutes over the lots of the map (the statistical townies use it)     death_mult() -> ambulance effect on far patients
## Tier behaviour: world-level; the units out are a short list (at most the units of the stations). Cadence: on a call; units come home at an absolute minute (checked
## when asked, no clock row). Data: data/services.json.

static var out: Array = []                 # [{service, back_min}] units that are on a call
static var stats: Dictionary = {}          # calls, minutes_sum and late per service
static var pending: Array = []             # ambulance holds [{fid, severity, reason, due, minutes}]

static func reset() -> void:
	out.clear()
	stats.clear()
	pending.clear()

static func cfg() -> Dictionary:
	return SysUtil.table("services")

static func station(service: String) -> Dictionary:
	var st: Dictionary = (cfg().get("stations", {}) as Dictionary).get(service, {})
	if not st.is_empty() and Workplace.map_ready() and Neighborhood.lot(str(st.get("lot", ""))).is_empty() and not Neighborhood.lot("police").is_empty():
		st = st.duplicate()
		st["lot"] = "police"                      # a map without its own fire station (an old game): the engine starts from the police lot
	return st

static func count(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n

static func units_out(service: String) -> int:
	var now: int = SysUtil.now()
	var n: int = 0
	for u in out:
		if str(u["service"]) == service and int(u["back_min"]) > now:
			n += 1
	return n

static func units_free(service: String) -> int:
	return int(station(service).get("units", 1)) - units_out(service)

## Tiles between the station and the lot (the roads run in a grid: Manhattan); a default when a lot has no door on this map.
static func distance_tiles(service: String, lot: String) -> int:
	var a: Vector2i = NeighborhoodLots.entry_tile(str(station(service).get("lot", "")))
	var b: Vector2i = NeighborhoodLots.entry_tile(lot)
	if a.x < 0 or b.x < 0:
		return int(cfg().get("default_tiles", 70))
	return absi(a.x - b.x) + absi(a.y - b.y)

static func map_ready() -> bool:
	return Workplace.map_ready() and not Neighborhood.lot(str(station("fire").get("lot", "police"))).is_empty()

static func dept(service: String) -> String:
	return "health" if service == "ambulance" else service

static func _turnout(service: String, rolled: float = -1.0) -> float:
	var tr: Array = station(service).get("turnout", [2, 4])
	var base: float = (float(tr[0]) + float(tr[1])) * 0.5 if rolled < 0.0 else rolled
	var staffing: float = clampf(CityBudget.funding(dept(service)), 0.4, 1.6)
	return base / lerpf(1.0, staffing, float(cfg().get("staffing_turnout", 0.6)))

static func estimate(service: String, lot: String, opts: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cfg()
	var dm: Array = c.get("dispatch_min", [1, 2])
	var handling: float = float(opts["handling"]) if opts.has("handling") else (float(dm[0]) + float(dm[1])) * 0.5
	var turnout: float = _turnout(service, float(opts["turnout"]) if opts.has("turnout") else -1.0)
	var tiles: int = distance_tiles(service, lot)
	var zone: String = TransportTraffic.zone_of_tile(NeighborhoodLots.entry_tile(lot)) if map_ready() else ""
	var traffic: float = lerpf(1.0, TransportTraffic.speed_mult(zone), float(c.get("traffic_effect", 0.5)))
	var drive: float = float(tiles) * Interaction.WALK_MIN_PER_TILE / (float(c.get("siren_speed", 4.0)) * maxf(traffic, 0.3))
	var wait: float = float(c.get("busy_wait", 8)) if units_free(service) <= 0 else 0.0
	var phone: float = float(c.get("no_phone_extra", 6)) if bool(opts.get("no_phone", false)) else 0.0
	var parts: Dictionary = {"handling": handling, "turnout": turnout, "drive": drive, "busy": wait, "phone": phone}
	return {"minutes": handling + turnout + drive + wait + phone, "parts": parts, "tiles": tiles}

## Roll the call handling and turnout like the real thing (seeded), mark a unit out, return the response (whole minutes).
static func dispatch(service: String, lot: String, opts: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cfg()
	var tr: Array = station(service).get("turnout", [2, 4])
	var dm: Array = c.get("dispatch_min", [1, 2])
	var o: Dictionary = opts.duplicate()
	o["handling"] = float(CityState.rng.randi_range(int(dm[0]), int(dm[1])))
	o["turnout"] = float(CityState.rng.randi_range(int(tr[0]), int(tr[1])))
	var e: Dictionary = estimate(service, lot, o)
	var m: int = maxi(int(round(float(e["minutes"]))), 1)
	e["minutes"] = m
	out.append({"service": service, "back_min": SysUtil.now() + m + int(station(service).get("on_scene", 30)) + int(float(e["parts"]["drive"]))})
	count("calls_" + service)
	count("minutes_" + service, m)
	VehicleFeed.post("dispatch", {"service": service, "lot": lot, "minutes": m, "drive": float(e["parts"]["drive"]), "on_scene": int(station(service).get("on_scene", 30))})      # the view layer draws the unit (read-only for the sim)
	if m > int(round(float((c.get("targets", {}) as Dictionary).get(service, 10)))) * 2:
		count("slow_" + service)
	_prune()
	return e

static func _prune() -> void:
	var now: int = SysUtil.now()
	for u in out.duplicate():
		if int(u["back_min"]) <= now:
			out.erase(u)

## Average response over the lots of the map without traffic dice: the statistical townies' version.
static func typical(service: String) -> float:
	if not map_ready():
		return float((cfg().get("targets", {}) as Dictionary).get(service, 10))
	var total: float = 0.0
	var n: int = 0
	for l in Neighborhood.lots():
		var id: String = str((l as Dictionary).get("id", ""))
		if id == "":
			continue
		total += float(estimate(service, id)["minutes"])
		n += 1
	return total / float(maxi(n, 1))

## Far patients: slower ambulances make a stay in hospital more dangerous (data: ambulance.death_mult_*).
static func death_mult() -> float:
	var a: Dictionary = cfg().get("ambulance", {})
	var target: float = float((cfg().get("targets", {}) as Dictionary).get("ambulance", 8))
	var over: float = (typical("ambulance") - target) / maxf(target, 1.0)
	return clampf(1.0 + over * float(a.get("death_mult_per_target", 0.5)), 0.7, float(a.get("death_mult_max", 2.0)))

static func to_dict() -> Dictionary:
	return {"out": out.duplicate(true), "stats": stats.duplicate(), "pending": pending.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	out = (d.get("out", []) as Array).duplicate(true)
	for u in out:
		SysUtil.ints_in(u, ["back_min"])
	for k in (d.get("stats", {}) as Dictionary):
		stats[str(k)] = int(d["stats"][k])
	pending = (d.get("pending", []) as Array).duplicate(true)
	for p in pending:
		SysUtil.ints_in(p, ["fid", "severity", "due", "minutes"])
