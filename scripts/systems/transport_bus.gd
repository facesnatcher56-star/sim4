class_name TransportBus
extends RefCounted
## Buses on routes with stops and a timetable (task 12.2). A route is a list of lots in order (data/transport.json bus.routes); buses run both ways with
## a headway that depends on the time of day (rush hour, day, evening, night) and the transport budget. No bus is a body in the world: the timetable is
## a pure function of the game minute, so it is exact, free to ask and identical on every machine.
##   plan(from_lot, to_lot, now) -> {ok, wait, ride, walk, fare, route, transfers}      next_times(route_id, lot, n) -> [minutes]
##   headway(route, hour) -> minutes            timetable_text(lot) -> plain-word next buses

const DEFAULT_SEG_TILES := 40

static func cfg() -> Dictionary:
	return Transport.sect("bus")

static func routes() -> Array:
	return cfg().get("routes", [])

static func route(id: String) -> Dictionary:
	for r in routes():
		if str(r["id"]) == id:
			return r
	return {}

static func band(hour: float) -> String:
	var bands: Dictionary = cfg().get("bands", {})
	for b in ["peak", "evening", "night"]:
		for span in bands.get(b, []):
			if hour >= float(span[0]) and hour < float(span[1]):
				return b
	return "day"

static func headway(r: Dictionary, hour: float) -> float:
	var base: float = float((r.get("headway", {}) as Dictionary).get(band(hour), 15))
	var slack: float = float(cfg().get("roads_funding_headway", 0.35))
	return base * (1.0 + (1.0 - CityBudget.funding("transport")) * slack) / clampf(TransportTraffic.speed_mult("", hour) * 1.4, 0.7, 1.0)

## Minutes a bus needs from stop `a` to the next stop `b`.
static func segment_min(a: String, b: String) -> float:
	var ta: Vector2i = NeighborhoodLots.entry_tile(a)
	var tb: Vector2i = NeighborhoodLots.entry_tile(b)
	var tiles: int = DEFAULT_SEG_TILES
	if ta.x >= 0 and tb.x >= 0:
		tiles = absi(ta.x - tb.x) + absi(ta.y - tb.y)
	var m: Dictionary = Transport.sect("modes").get("bus", {})
	return float(tiles) * Interaction.WALK_MIN_PER_TILE / float(m.get("speed", 2.2)) + float(m.get("dwell", 0.5))

static func offset_at(r: Dictionary, idx: int) -> float:
	var t: float = float(r.get("offset", 0))
	var stops: Array = r["stops"]
	for i in idx:
		t += segment_min(str(stops[i]), str(stops[i + 1]))
	return t

## Minutes from `now` until the next bus of route `r` calls at stop index `idx` (any direction counts: the second bus runs the other way).
static func wait_at(r: Dictionary, idx: int, now: int) -> float:
	var hw: float = headway(r, float(now % 1440) / 60.0)
	var phase: float = fposmod(offset_at(r, idx), hw)
	var w: float = fposmod(phase - float(now), hw)
	return w

static func ride_between(r: Dictionary, i: int, j: int) -> float:
	var lo: int = mini(i, j)
	var hi: int = maxi(i, j)
	return offset_at(r, hi) - offset_at(r, lo)

static func plan(from_lot: String, to_lot: String, now: int = -1) -> Dictionary:
	var t: int = SysUtil.now() if now < 0 else now
	var m: Dictionary = Transport.sect("modes").get("bus", {})
	var walk: float = float(m.get("walk_min", 3)) * 2.0
	var best: Dictionary = {"ok": false}
	var rs: Array = routes()
	for r in rs:
		var stops: Array = r["stops"]
		var i: int = stops.find(from_lot)
		var j: int = stops.find(to_lot)
		if i >= 0 and j >= 0 and i != j:
			var tot: float = wait_at(r, i, t) + ride_between(r, i, j) + walk
			if not bool(best["ok"]) or tot < float(best["total"]):
				best = {"ok": true, "route": str(r["id"]), "wait": wait_at(r, i, t), "ride": ride_between(r, i, j), "walk": walk, "transfers": 0, "total": tot}
	if bool(best["ok"]):
		return _with_fare(best, m)
	# one change at a shared stop
	for ra in rs:
		var sa: Array = ra["stops"]
		var i2: int = sa.find(from_lot)
		if i2 < 0:
			continue
		for rb in rs:
			if rb == ra:
				continue
			var sb: Array = rb["stops"]
			var j2: int = sb.find(to_lot)
			if j2 < 0:
				continue
			for hub in sa:
				var hi: int = sb.find(hub)
				if hi < 0 or hub == from_lot or hub == to_lot:
					continue
				var w1: float = wait_at(ra, i2, t)
				var ride1: float = ride_between(ra, i2, sa.find(hub))
				var w2: float = wait_at(rb, hi, t + int(w1 + ride1))
				var tot2: float = w1 + ride1 + w2 + ride_between(rb, hi, j2) + walk
				if not bool(best["ok"]) or tot2 < float(best["total"]):
					best = {"ok": true, "route": str(ra["id"]) + "+" + str(rb["id"]), "wait": w1 + w2, "ride": ride1 + ride_between(rb, hi, j2), "walk": walk, "transfers": 1, "total": tot2}
	return _with_fare(best, m) if bool(best["ok"]) else best

static func _with_fare(p: Dictionary, m: Dictionary) -> Dictionary:
	p["fare"] = int(round(float(m.get("fare", 4)) * Transport.price_mult()))
	return p

## The next `n` times (game minutes) a bus of route `route_id` calls at lot `lot`.
static func next_times(route_id: String, lot: String, n: int = 3) -> Array:
	var r: Dictionary = route(route_id)
	var idx: int = (r.get("stops", []) as Array).find(lot)
	var out: Array = []
	if r.is_empty() or idx < 0:
		return out
	var t: int = SysUtil.now()
	for k in n:
		var w: float = wait_at(r, idx, t)
		t += int(ceil(w))
		out.append(t)
		t += 1
	return out

static func clock_text(minute: int) -> String:
	var m: int = minute % 1440
	return "%02d:%02d" % [m / 60, m % 60]

## "Cafe: Green Line 08:12, 08:24, 08:36" lines for a lot.
static func timetable_text(lot: String) -> Array:
	var out: Array = []
	for r in routes():
		if (r["stops"] as Array).has(lot):
			var bits: Array = []
			for t in next_times(str(r["id"]), lot, 3):
				bits.append(clock_text(int(t)))
			out.append("%s: %s" % [str(r["name"]), ", ".join(bits)])
	return out
