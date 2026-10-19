class_name TransportTrip
extends RefCounted
## One trip between two places (task 12.2): which way to go (on foot, bike, bus, taxi, own car) by TIME, COST and WEATHER, then the consequences: fares and fuel,
## the car moving and parking at the other end, wear, breakdowns and crashes. Used by commutes (Commute._walk, Workplace.commute_minutes) and by the
## player's own lot trips (own vehicles only: buses and taxis are for commutes and for the player's explicit choice).
##   plan(f, dest_tile, opts) -> {mode, minutes, cost, car, ...}     no side effects     opts: commute, own_only, modes (allowed list), n (tiles)
##   start(f, dest_tile, opts) -> plan + {total_minutes}              charges and commits; hand `ride_minutes` to the walking interaction
## Tier: the trip belongs to a FULL resident; townies do not travel in this system. Cadence: a trip is decided once at its start and finished at its arrival minute.

const DRIVERS := ["adult", "elder"]
const RIDERS := ["child", "teen", "adult", "elder"]

static func cfg() -> Dictionary:
	return Transport.cfg()

static func _mode(id: String) -> Dictionary:
	return (Transport.sect("modes").get(id, {}) as Dictionary)

static func weather_mult(mode: String) -> float:
	return float((_mode(mode).get("weather", {}) as Dictionary).get(Weather.current(), 1.0))

static func vot(hid: int) -> float:
	var v: Dictionary = Transport.sect("value_of_time")
	var m: float = float(v.get("coin_min", 0.6))
	if Economy.balance(hid) < float(v.get("poor_below", 150)):
		m *= float(v.get("poor_mult", 2.5))
	return m

static func _walk_plan(n: int, walk_min: float) -> Dictionary:
	return {"mode": "walk", "minutes": walk_min, "cost": 0, "n": n, "score": walk_min}

## The best way to get `f` to `dest`. Always has a mode (walking at worst).
static func plan(f, dest: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var n: int = int(opts["n"]) if opts.has("n") else WorldIface.path_length(f.tile, dest)
	if n < 0:
		return {"mode": "walk", "minutes": -1.0, "cost": 0, "n": n, "score": 0.0}
	var walk_min: float = float(n) * Interaction.WALK_MIN_PER_TILE / Workplace.speed_factor(f)
	var best: Dictionary = _walk_plan(n, walk_min)
	if n < int(cfg().get("min_ride_tiles", 24)):
		return best
	var hid: int = int(f.household_id)
	var stage: String = str(f.age_stage)
	var allowed: Array = opts.get("modes", ["bike", "car", "bus", "taxi"])
	if bool(opts.get("own_only", false)):
		allowed = ["bike", "car"]
	var from_lot: String = str(opts["from_lot"]) if opts.has("from_lot") else NeighborhoodLots.lot_at(f.tile)
	var to_lot: String = str(opts["to_lot"]) if opts.has("to_lot") else NeighborhoodLots.lot_at(dest)
	var nominal: float = float(n) * Interaction.WALK_MIN_PER_TILE
	var zone: String = TransportTraffic.zone_of_tile(f.tile)
	var traffic: float = maxf(TransportTraffic.speed_mult(zone), 0.2)
	var k: float = vot(hid)
	var cands: Array = []
	if allowed.has("bike") and Transport.bikes_of(hid) > 0 and RIDERS.has(stage) and weather_mult("bike") > 0.0:
		var m: float = nominal / (float(_mode("bike").get("speed", 2.3)) * weather_mult("bike") * Health.speed_mult(f))
		cands.append({"mode": "bike", "minutes": m, "cost": 0, "n": n, "score": m})
	if allowed.has("car") and DRIVERS.has(stage):
		for c in Transport.cars_of(hid):
			if TransportCars.ready(c) and str(c["at"]) == from_lot and float(c["fuel"]) >= TransportCars.fuel_use(c, n):
				var park: float = 0.0 if TransportParking.spaces_free(to_lot) > 0 else 6.0
				var m2: float = nominal / (float(_mode("car").get("speed", 3.2)) * traffic) + park
				var fuel_cost: float = TransportCars.fuel_use(c, n) * TransportCars.fuel_unit_price(c, from_lot == TransportCars.home_lot(hid))
				cands.append({"mode": "car", "minutes": m2, "cost": 0, "fuel_cost": fuel_cost, "car": int(c["id"]), "n": n, "score": m2 + fuel_cost * k * 0.5})
				break
	if allowed.has("bus") and from_lot != "" and to_lot != "" and from_lot != to_lot and stage != "toddler":
		var bp: Dictionary = TransportBus.plan(from_lot, to_lot)
		if bool(bp["ok"]) and Economy.balance(hid) >= int(bp["fare"]):
			var m3: float = float(bp["wait"]) + float(bp["ride"]) + float(bp["walk"])
			cands.append({"mode": "bus", "minutes": m3, "cost": int(bp["fare"]), "n": n, "route": str(bp["route"]), "score": m3 + float(bp["fare"]) * k})
	if allowed.has("taxi") and RIDERS.has(stage) and stage != "child" and not f.has_buff("no_signal"):
		var tx: Dictionary = Transport.sect("modes").get("taxi", {})
		var w: Array = tx.get("wait", [3, 9])
		var wait: float = (float(w[0]) + float(w[1])) * 0.5 + (float(tx.get("night_wait_add", 6)) if _taxi_night() else 0.0)
		var cost: int = int(round((float(tx.get("base", 8)) + float(tx.get("per_tile", 0.06)) * float(n)) * Transport.price_mult()))
		if Economy.balance(hid) >= cost:
			var m4: float = wait + nominal / (float(tx.get("speed", 3.0)) * traffic)
			cands.append({"mode": "taxi", "minutes": m4, "cost": cost, "n": n, "wait": wait, "score": m4 + float(cost) * k})
	# comfort: nobody likes a wet walk
	var wet: float = 1.0 + 0.25 * Weather.precip_intensity()
	best["score"] = float(best["score"]) * wet
	for c2 in cands:
		if str(c2["mode"]) == "bike":
			c2["score"] = float(c2["score"]) * wet
		if float(c2["score"]) < float(best["score"]):
			best = c2
	return best

static var _est: Dictionary = {}          # folk id -> [bucket, tile, minutes] (a commute is asked about every minute near the shift start)

## Planned minutes of the best way for a commute, cached for ten game minutes.
static func estimate(f, dest: Vector2i, n: int) -> float:
	var bucket: int = SysUtil.now() / 10
	var rec: Array = _est.get(int(f.id), [])
	if not rec.is_empty() and int(rec[0]) == bucket and rec[1] == dest and rec[3] == f.tile and int(rec[4]) == Transport.rev:
		return float(rec[2])
	var m: float = float(plan(f, dest, {"n": n, "commute": true})["minutes"])
	_est[int(f.id)] = [bucket, dest, m, f.tile, Transport.rev]
	return m

static func _taxi_night() -> bool:
	var h: float = SysUtil.hour_f()
	var t: Dictionary = Transport.sect("taxi")
	return h >= float(t.get("night_from", 22)) or h < float(t.get("night_to", 6))

## Decide and commit a trip. Returns the plan with `total_minutes` (the time the walk takes now: crash delay included).
static func start(f, dest: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var fid: int = int(f.id)
	var now: int = SysUtil.now()
	var cur: Dictionary = Transport.active.get(str(fid), {})
	if not cur.is_empty() and int(cur["start_min"]) > now - 180 and int(cur.get("dest_x", -1)) == dest.x and int(cur.get("dest_y", -1)) == dest.y:
		return cur                                      # the same trip asked again (a lost walk is started again): no second fare
	var p: Dictionary = plan(f, dest, opts)
	p["to_lot"] = str(opts["to_lot"]) if opts.has("to_lot") else NeighborhoodLots.lot_at(dest)
	p["total_minutes"] = float(p["minutes"])
	if str(p["mode"]) == "walk":
		return p
	var hid: int = int(f.household_id)
	var cost: int = int(p.get("cost", 0))
	if cost > 0 and not Economy.spend(hid, cost, "fare" if str(p["mode"]) == "bus" else "taxi"):
		return _walk_plan(int(p["n"]), float(p["minutes"]))
	if str(p["mode"]) == "car":
		var c: Dictionary = Transport.car(int(p["car"]))
		c["fuel"] = maxf(float(c["fuel"]) - TransportCars.fuel_use(c, int(p["n"])), 0.0)
		TransportParking.leave(c)
		c["trips"] = int(c["trips"]) + 1
		c["cond"] = maxf(float(c["cond"]) - TransportCrash.wear(c), 0.0)
		if float(c["cond"]) < float(Transport.num("cars", "breakdown_below", 0.35)) and CityState.chance(0.25):
			p["breakdown"] = true
			p["total_minutes"] = float(p["total_minutes"]) + float(Transport.num("cars", "breakdown_delay_min", 30))
	var crash: String = TransportCrash.roll(f, p)
	if crash != "":
		p["crash"] = crash
		p["total_minutes"] = float(p["total_minutes"]) + float(Transport.num("crash", "delay_min", 25))
	p["start_min"] = now
	p["arrive_min"] = now + int(ceil(float(p["total_minutes"])))
	p["dest_x"] = dest.x
	p["dest_y"] = dest.y
	p["folk"] = fid
	Transport.active[str(fid)] = p
	Transport.count("trips_" + str(p["mode"]))
	return p

# ------------------------------------------------------------------ arrival
static func on_minute() -> void:
	var now: int = SysUtil.now()
	for k in Transport.active.keys():
		if int((Transport.active[k] as Dictionary)["arrive_min"]) <= now:
			finish(int(k))

static func finish(fid: int) -> void:
	var p: Dictionary = Transport.active.get(str(fid), {})
	if p.is_empty():
		return
	Transport.active.erase(str(fid))
	var f = SysUtil.folk(fid)
	if str(p["mode"]) == "car":
		var c: Dictionary = Transport.car(int(p["car"]))
		if not c.is_empty():
			var park: Dictionary = TransportParking.park(c, str(p.get("to_lot", c["at"])))
			if int(park["fee"]) > 0:
				SysUtil.notify("The car goes into the car park (%d coins a day)." % int(park["fee"]), "info")
	if f != null and bool(p.get("breakdown", false)):
		SysUtil.notify(str(Transport.sect("text").get("breakdown", "The car broke down.")).replace("{name}", str(f.name)), "warn")
	if p.has("crash") and f != null:
		TransportCrash.apply(f, p)
