class_name TransportBus
extends RefCounted
## Buses on routes with stops and a REAL TIMETABLE (task 12.2, reworked by task 37). A small town runs one loop; a route is a list of lots in order (data/transport.json
## bus.routes) and the first stop's departure times per day type are data (`runs`: weekday, saturday, sunday). Later stops follow from the ride time. No bus is a body in
## the world: the timetable is a pure function of the game minute, so it is exact, free to ask and identical on every machine.
## Cause: a bus runs at the listed times (30 min at the rush hours, hourly by day, none after 20:00, a few on Sundays) because a town this size cannot fill a bus every
## few minutes; a route whose first stop equals its last is a loop (a rider can ride on past the end of the list). A second route only runs after the town has grown.
##   plan(from_lot, to_lot, now) -> {ok, wait, ride, walk, fare, route, transfers}      next_times(route_id, lot, n) -> [minutes]
##   departures(r, t0, t1) -> first-stop departures (absolute minutes)      next_text(lot) -> "Next bus 14:30"      timetable_text(lot) -> plain-word lines

const DEFAULT_SEG_TILES := 40
const NO_BUS := 9999.0

static func cfg() -> Dictionary:
	return Transport.sect("bus")

## Every route in the data, whether it runs yet or not.
static func all_routes() -> Array:
	return cfg().get("routes", [])

## The routes that run now (a route with `requires_built` waits for that many finished town-planning projects).
static func routes() -> Array:
	var out: Array = []
	for r in all_routes():
		if route_runs(r):
			out.append(r)
	return out

static func route_runs(r: Dictionary) -> bool:
	var need: int = int(r.get("requires_built", 0))
	if need <= 0:
		return true
	var n: int = 0
	for k in CityPlan.built:
		n += int(CityPlan.built[k])
	return n >= need

static func route(id: String) -> Dictionary:
	for r in all_routes():
		if str(r["id"]) == id:
			return r
	return {}

static func is_loop(r: Dictionary) -> bool:
	var s: Array = r["stops"]
	return s.size() > 2 and str(s[0]) == str(s[s.size() - 1])

## "06:30" -> minutes of the day.
static func hhmm(t) -> int:
	var p: PackedStringArray = str(t).split(":")
	return int(p[0]) * 60 + (int(p[1]) if p.size() > 1 else 0)

static func clock_text(minute: int) -> String:
	var m: int = posmod(minute, 1440)
	return "%02d:%02d" % [m / 60, m % 60]

static func day_type(wd: int) -> String:
	return "saturday" if wd == 5 else ("sunday" if wd == 6 else "weekday")

## Starved transport budget: every second run is cancelled.
static func thinned() -> bool:
	return CityBudget.funding("transport") < float(cfg().get("cut_below", 0.6))

## The first-stop departures (minutes of the day) of route `r` on weekday `wd` (0 Monday .. 6 Sunday).
static func runs_day(r: Dictionary, wd: int) -> Array:
	var out: Array = []
	var cut: bool = thinned()
	var k: int = 0
	for t in (r.get("runs", {}) as Dictionary).get(day_type(wd), []):
		k += 1
		if cut and k % 2 == 0:
			continue
		out.append(hhmm(t))
	return out

## Absolute departure minutes from the first stop within [t0, t1], in order.
static func departures(r: Dictionary, t0: int, t1: int) -> Array:
	var out: Array = []
	var d0: int = int(floor(float(t0) / 1440.0))
	var d1: int = int(floor(float(t1) / 1440.0))
	for day in range(maxi(d0, 0), d1 + 1):
		for m in runs_day(r, posmod(day, 7)):
			var t: int = day * 1440 + int(m)
			if t >= t0 and t <= t1:
				out.append(t)
	return out

## Local gap (minutes) between the runs around `hour` on weekday `wd`; NO_BUS outside service.
static func headway(r: Dictionary, hour: float, wd: int = 0) -> float:
	var runs: Array = runs_day(r, wd)
	var t: float = hour * 60.0
	var prev: float = -1.0
	for m in runs:
		if float(m) > t:
			return float(m) - prev if prev >= 0.0 else NO_BUS
		prev = float(m)
	return NO_BUS

## Minutes a bus needs from stop `a` to the next stop `b`: the real length of the lane route (VehicleRoads.leg_length: lanes flow one way, so a bus goes round the block
## between stops) at `tiles_per_min`, plus the dwell. Cause: the minutes on the sign must be what the bus in the street really takes.
static func segment_min(a: String, b: String) -> float:
	var m: Dictionary = Transport.sect("modes").get("bus", {})
	var tiles: float = VehicleRoads.leg_length(a, b)
	if tiles < 0.0:
		var ta: Vector2i = NeighborhoodLots.entry_tile(a)
		var tb: Vector2i = NeighborhoodLots.entry_tile(b)
		tiles = float(DEFAULT_SEG_TILES)
		if ta.x >= 0 and tb.x >= 0:
			tiles = float(absi(ta.x - tb.x) + absi(ta.y - tb.y)) * float(cfg().get("detour", 1.25))
	return tiles / float(cfg().get("tiles_per_min", 6.0)) + float(m.get("dwell", 0.5))

static func offset_at(r: Dictionary, idx: int) -> float:
	var t: float = float(r.get("offset", 0))
	var stops: Array = r["stops"]
	for i in idx:
		t += segment_min(str(stops[i]), str(stops[i + 1]))
	return t

## Minutes the whole run takes (first stop to the last).
static func run_minutes(r: Dictionary) -> float:
	return offset_at(r, (r["stops"] as Array).size() - 1)

## Minutes from `now` until the next bus of route `r` calls at stop index `idx` (NO_BUS when none runs in the next two days).
static func wait_at(r: Dictionary, idx: int, now: int) -> float:
	var off: float = offset_at(r, idx)
	var from: int = now - int(ceil(off))
	for d in departures(r, from, from + 2 * 1440):
		var w: float = float(d) + off - float(now)
		if w >= 0.0:
			return w
	return NO_BUS

## Ride minutes from stop index `i` to the next call at lot `lot` (a loop goes on past its end), or -1.
static func ride_to(r: Dictionary, i: int, lot: String) -> float:
	var stops: Array = r["stops"]
	for k in range(i + 1, stops.size()):
		if str(stops[k]) == lot:
			return offset_at(r, k) - offset_at(r, i)
	if is_loop(r):
		for k2 in range(1, i):
			if str(stops[k2]) == lot:
				return offset_at(r, stops.size() - 1) - offset_at(r, i) + offset_at(r, k2)
	return -1.0

static func plan(from_lot: String, to_lot: String, now: int = -1) -> Dictionary:
	var t: int = SysUtil.now() if now < 0 else now
	var m: Dictionary = Transport.sect("modes").get("bus", {})
	var walk: float = float(m.get("walk_min", 3)) * 2.0
	var max_wait: float = float(cfg().get("max_wait", 75))
	var best: Dictionary = {"ok": false}
	var rs: Array = routes()
	for r in rs:
		var stops: Array = r["stops"]
		var i: int = stops.find(from_lot)
		if i < 0 or i == stops.size() - 1:
			continue
		var ride: float = ride_to(r, i, to_lot)
		if ride < 0.0:
			continue
		var w: float = wait_at(r, i, t)
		if w > max_wait:
			continue
		var tot: float = w + ride + walk
		if not bool(best["ok"]) or tot < float(best["total"]):
			best = {"ok": true, "route": str(r["id"]), "wait": w, "ride": ride, "walk": walk, "transfers": 0, "total": tot}
	if bool(best["ok"]):
		return _with_fare(best, m)
	# one change at a shared stop
	for ra in rs:
		var sa: Array = ra["stops"]
		var i2: int = sa.find(from_lot)
		if i2 < 0 or i2 == sa.size() - 1:
			continue
		for rb in rs:
			if rb == ra:
				continue
			var sb: Array = rb["stops"]
			for hub in sa:
				var hi: int = sb.find(hub)
				if hi < 0 or hi == sb.size() - 1 or hub == from_lot or hub == to_lot:
					continue
				var ride1: float = ride_to(ra, i2, str(hub))
				var ride2: float = ride_to(rb, hi, to_lot)
				if ride1 < 0.0 or ride2 < 0.0:
					continue
				var w1: float = wait_at(ra, i2, t)
				var w2: float = wait_at(rb, hi, t + int(w1 + ride1))
				if w1 > max_wait or w2 > max_wait:
					continue
				var tot2: float = w1 + ride1 + w2 + ride2 + walk
				if not bool(best["ok"]) or tot2 < float(best["total"]):
					best = {"ok": true, "route": str(ra["id"]) + "+" + str(rb["id"]), "wait": w1 + w2, "ride": ride1 + ride2, "walk": walk, "transfers": 1, "total": tot2}
	return _with_fare(best, m) if bool(best["ok"]) else best

static func _with_fare(p: Dictionary, m: Dictionary) -> Dictionary:
	p["fare"] = int(round(float(m.get("fare", 4)) * Transport.price_mult() * CityPolicy.fare_mult()))
	return p

## The next `n` times (game minutes) a bus of route `route_id` calls at lot `lot`.
static func next_times(route_id: String, lot: String, n: int = 3, from: int = -1) -> Array:
	var r: Dictionary = route(route_id)
	var out: Array = []
	if r.is_empty() or not route_runs(r):
		return out
	var idx: int = (r["stops"] as Array).find(lot)
	if idx < 0 or idx == (r["stops"] as Array).size() - 1:
		return out
	var t: int = SysUtil.now() if from < 0 else from
	for k in n:
		var w: float = wait_at(r, idx, t)
		if w >= NO_BUS:
			break
		t += int(ceil(w))
		out.append(t)
		t += 1
	return out

## Every time of day (minutes) the buses of route `route_id` call at `lot` on the day of absolute minute `now`, in order (the printed timetable of the stop).
static func calls_today(route_id: String, lot: String, now: int = -1) -> Array:
	var r: Dictionary = route(route_id)
	var out: Array = []
	var t: int = SysUtil.now() if now < 0 else now
	if r.is_empty() or not route_runs(r):
		return out
	var idx: int = (r["stops"] as Array).find(lot)
	if idx < 0 or idx == (r["stops"] as Array).size() - 1:
		return out
	var off: int = int(round(offset_at(r, idx)))
	for m in runs_day(r, posmod(t / 1440, 7)):
		out.append(int(m) + off)
	return out

## "Next bus 14:30" for a stop (the soonest call of any running route), or why there is none.
static func next_text(lot: String, from: int = -1) -> String:
	var t: int = SysUtil.now() if from < 0 else from
	var best: int = -1
	for r in routes():
		var ts: Array = next_times(str(r["id"]), lot, 1, t)
		if not ts.is_empty() and (best < 0 or int(ts[0]) < best):
			best = int(ts[0])
	if best < 0:
		for r2 in routes():
			if str((r2["stops"] as Array).back()) == lot and not is_loop(r2):
				return "Last stop: the bus goes on out of town"
		return "No buses"
	var day_diff: int = best / 1440 - t / 1440
	if day_diff <= 0:
		return "Next bus %s" % clock_text(best)
	if day_diff == 1:
		return "No more buses today. First tomorrow %s" % clock_text(best)
	return "No bus until %s" % clock_text(best)

## "Town Loop: next bus 08:30, then 09:00, 10:00" lines for a lot.
static func timetable_text(lot: String) -> Array:
	var out: Array = []
	var t: int = SysUtil.now()
	for r in routes():
		var ts: Array = next_times(str(r["id"]), lot, 3, t)
		if ts.is_empty():
			continue
		var bits: Array = []
		for x in ts:
			bits.append(clock_text(int(x)))
		var lead: String = "next bus " if int(ts[0]) / 1440 <= t / 1440 else "no more today, tomorrow "
		out.append("%s: %s%s" % [str(r["name"]), lead, ", then ".join(bits)])
	return out
