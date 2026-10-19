class_name TransportTraffic
extends RefCounted
## Traffic (task 12.2): the density of cars by hour, day and weather, traffic lights at the junctions of the street grid (they stop working when the
## zone has no power), road works, and road quality that ages and is renewed by works the town budget pays for.
##   density(hour, zone) 0..1+      speed_mult(zone, hour) 0..1      tile_mult(tile, hour, kind) risk multiplier for a person on a road tile
##   light_phase(jx, jy) "walk" | "stop" | "dark"      add_works(zone, kind, days)      quality(zone)
## Not a car simulation: ambient cars are numbers; the player's own trips use speed_mult for their time and crash chance.
## Cadence: daily road upkeep (zones x 1), works end by their own minute.

static func cfg() -> Dictionary:
	return Transport.sect("traffic")

static func zone_of_tile(tile: Vector2i) -> String:
	var m: Dictionary = Transport.sect("map")
	var dx: float = float(tile.x) - float(m.get("w", 160)) * 0.5
	var dy: float = float(tile.y) - float(m.get("h", 136)) * 0.5
	if absf(dy) >= absf(dx) * 0.85:
		return "north" if dy < 0.0 else "south"
	return "west" if dx < 0.0 else "east"

# ------------------------------------------------------------------ density and speed
static func density(hour: float = -1.0, zone: String = "") -> float:
	var c: Dictionary = cfg()
	var curve: Array = c.get("curve", [0.3])
	var h: float = SysUtil.hour_f() if hour < 0.0 else hour
	var i: int = int(floor(h)) % curve.size()
	var j: int = (i + 1) % curve.size()
	var d: float = lerpf(float(curve[i]), float(curve[j]), h - floor(h))
	if Seasons.is_weekend():
		d *= float(c.get("weekend", 0.65))
	d *= float((c.get("weather", {}) as Dictionary).get(Weather.current(), 1.0))
	if zone != "" and works_in(zone):
		d *= 1.15
	return d

static func speed_mult(zone: String = "", hour: float = -1.0) -> float:
	var c: Dictionary = cfg()
	var s: float = 1.0 - (1.0 - float(c.get("jam_speed", 0.5))) * clampf(density(hour, zone), 0.0, 1.0)
	if zone != "" and works_in(zone):
		s *= float(c.get("works_speed", 0.75))
	if zone != "" and lights_out(zone):
		s *= float(Transport.sect("lights").get("dark_speed", 0.85))
	return s

# ------------------------------------------------------------------ lights
static func lights_out(zone: String) -> bool:
	return zone != "" and Utilities.is_down("power", zone)

static func light_phase(jx: int, jy: int, zone: String = "") -> String:
	if lights_out(zone):
		return "dark"
	var l: Dictionary = Transport.sect("lights")
	var cycle: int = maxi(int(l.get("cycle_min", 4)), 2)
	var t: int = (SysUtil.now() + jx * 7 + jy * 3) % cycle
	return "walk" if float(t) < float(cycle) * float(l.get("walk_share", 0.5)) else "stop"

## The junction (column, row) of the street grid whose box contains the tile (grown by 2 for the crossings), or Vector2i(-1, -1).
static func junction_at(tile: Vector2i) -> Vector2i:
	var lay: Dictionary = SimEnv.data().get_table("map_layout")
	var rw: int = int(lay.get("road_w", 6)) + 2
	var vx: Array = lay.get("vroads_x", [])
	var hy: Array = lay.get("hroads_y", [])
	for i in vx.size():
		if tile.x >= int(vx[i]) - 1 and tile.x < int(vx[i]) + rw:
			for j in hy.size():
				if tile.y >= int(hy[j]) - 1 and tile.y < int(hy[j]) + rw:
					return Vector2i(i, j)
	return Vector2i(-1, -1)

## Traffic.risk_at multiplier. Only on the real map (the stub worlds of the tests have no street grid); only at crossings of junctions.
static func tile_mult(tile: Vector2i, _hour: float, kind: String) -> float:
	if kind != "crosswalk" or not Workplace.map_ready():
		return 1.0
	var j: Vector2i = junction_at(tile)
	if j.x < 0:
		return 1.0
	var l: Dictionary = Transport.sect("lights")
	match light_phase(j.x, j.y, zone_of_tile(tile)):
		"walk":
			return float(l.get("walk_risk", 0.3))
		"dark":
			return float(l.get("dark_risk", 1.25))
	return float(l.get("stop_risk", 1.5))

# ------------------------------------------------------------------ road works and quality
static func works_in(zone: String) -> bool:
	var now: int = SysUtil.now()
	for w in Transport.works:
		if str(w["zone"]) == zone and int(w["end"]) > now:
			return true
	return false

static func add_works(zone: String, kind: String, days: float) -> Dictionary:
	for w in Transport.works:
		if str(w["zone"]) == zone and str(w["kind"]) == kind and int(w["end"]) > SysUtil.now():
			return w
	var now: int = SysUtil.now()
	var rec: Dictionary = {"id": Transport.seq, "zone": zone, "kind": kind, "start": now, "end": now + int(round(days * 1440.0))}
	Transport.seq += 1
	Transport.works.append(rec)
	Transport.count("works_" + kind)
	return rec

static func quality(zone: String) -> float:
	return float(Transport.roads.get(zone, float(Transport.sect("roads").get("start", 0.85))))

static func set_quality(zone: String, q: float) -> void:
	Transport.roads[zone] = clampf(q, 0.0, 1.0)

static func mean_quality() -> float:
	var t: float = 0.0
	var zs: Array = CityState.zone_ids()
	for z in zs:
		t += quality(str(z))
	return t / float(maxi(zs.size(), 1))

static func pothole(zone: String) -> bool:
	return quality(zone) < float(Transport.sect("roads").get("pothole_below", 0.4))

## Daily: roads wear (faster in the cold), finished works renew them, the budget starts new resurfacing where the road is poor.
static func on_day(_day: int) -> void:
	var r: Dictionary = Transport.sect("roads")
	var now: int = SysUtil.now()
	for w in Transport.works.duplicate():
		if int(w["end"]) <= now:
			Transport.works.erase(w)
			if str(w["kind"]) == "resurface":
				set_quality(str(w["zone"]), quality(str(w["zone"])) + float(r.get("works_gain", 0.5)))
				Transport.count("resurfaced")
	for zone in CityState.zone_ids():
		var z: String = str(zone)
		var decay: float = float(r.get("decay_per_day", 0.006)) + (float(r.get("decay_cold", 0.004)) if Weather.temperature() < 0.0 else 0.0)
		set_quality(z, quality(z) - decay / clampf(CityBudget.funding("roads"), 0.4, 1.5))
		if quality(z) < float(r.get("works_below", 0.55)) and not works_in(z):
			if CityState.chance(float(r.get("works_chance_per_day", 0.25)) * CityBudget.funding("roads")):
				add_works(z, "resurface", float(CityState.range_i(r.get("works_days", [2, 5]))))
				if CityState.zone_of_household(Players.primary_household()) == z:
					SysUtil.notify("Road works have started on %s. Expect slower traffic." % CityState.zone_label(z), "info")
