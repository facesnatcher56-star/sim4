class_name Transport
extends RefCounted
## Transport (task 12.2): the state and the public API. A household can own cars and bikes; trips between lots pick a way to travel by time, cost and
## weather (TransportTrip); buses run on routes with a timetable (TransportBus); parking is limited per lot, with a car park and street tows
## (TransportParking); traffic, lights and road works live in TransportTraffic. Everything is data: data/transport.json.
##   Transport.cars_of(hid) / car_of(hid) / bikes_of(hid)       Transport.cfg() / num(...)
## Player actions are commands (TransportCmd, command layer action "city"): buy_car, sell_car, refuel, repair, collect_car, buy_bike.
## Tier behaviour: only the players' households own vehicles (FULL, per trip); townies commute statistically and only show up as ambient parking
## and the traffic curve. Cadence: trips finish at absolute minutes (a gated minute row; idle = one emptiness test), parking tows and road wear daily.
## Caps: cars per household 3, trip records are deleted on arrival, stats are counters.

static var cars: Dictionary = {}          # str(id) -> {id, hid, model, plate, fuel, cond, at, spot, bought, wreck, ready_day, towed, pound_day, trips, paid_fine}
static var bikes: Dictionary = {}         # str(hid) -> count
static var active: Dictionary = {}        # str(folk id) -> trip plan in progress (see TransportTrip)
static var roads: Dictionary = {}         # zone -> road quality 0..1
static var works: Array = []              # road works {id, zone, kind, start, end}
static var stats: Dictionary = {}
static var seq: int = 1
static var rev: int = 0                   # bumped whenever cars, bikes or trips change (invalidates cached commute estimates)

static func reset() -> void:
	cars.clear()
	bikes.clear()
	active.clear()
	roads.clear()
	works.clear()
	stats.clear()
	seq = 1
	TransportParking.reset()
	TransportTrip._est.clear()

static func cfg() -> Dictionary:
	return SysUtil.table("transport")

static func sect(key: String) -> Dictionary:
	return cfg().get(key, {})

static func num(group: String, key: String, default: float = 0.0) -> float:
	return float(sect(group).get(key, default))

static func count(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n
	rev += 1

static func busy() -> bool:
	return not active.is_empty()

# ------------------------------------------------------------------ vehicles
static func cars_of(hid: int) -> Array:
	var out: Array = []
	for k in cars:
		if int(cars[k]["hid"]) == hid:
			out.append(cars[k])
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out

static func car(id: int) -> Dictionary:
	return cars.get(str(id), {})

static func bikes_of(hid: int) -> int:
	return int(bikes.get(str(hid), 0))

static func model_def(model: String) -> Dictionary:
	return (sect("cars").get("models", {}) as Dictionary).get(model, {})

static func price_mult() -> float:
	return MarketEconomy.price_mult()

## Plain words for a car: "Town Hatchback (fuel 62 percent, good)".
static func describe(c: Dictionary) -> String:
	var d: Dictionary = model_def(str(c["model"]))
	var cond: float = float(c["cond"])
	var shape: String = "wrecked" if bool(c["wreck"]) else ("good" if cond >= 0.75 else ("worn" if cond >= 0.4 else "in a poor state"))
	var tank: float = maxf(float(d.get("tank", 40)), 1.0)
	return "%s (%s %d percent, %s)" % [str(d.get("label", "Car")), "charge" if str(d.get("fuel", "")) == "electric" else "fuel", int(round(float(c["fuel"]) / tank * 100.0)), shape]

# ------------------------------------------------------------------ the hooks (sim_registry rows)
static func on_minute() -> void:
	TransportTrip.on_minute()

static func on_day(day: int) -> void:
	TransportParking.on_day(day)
	TransportTraffic.on_day(day)
	TransportCars.on_day(day)

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"cars": cars.duplicate(true), "bikes": bikes.duplicate(), "active": active.duplicate(true), "roads": roads.duplicate(), "works": works.duplicate(true),
		"stats": stats.duplicate(), "seq": seq, "parking": TransportParking.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	cars = (d.get("cars", {}) as Dictionary).duplicate(true)
	for k in cars:
		SysUtil.ints_in(cars[k], ["id", "hid", "bought", "ready_day", "pound_day", "trips"])
	bikes = {}
	for k2 in (d.get("bikes", {}) as Dictionary):
		bikes[str(k2)] = int(d["bikes"][k2])
	active = (d.get("active", {}) as Dictionary).duplicate(true)
	for k3 in active:
		SysUtil.ints_in(active[k3], ["car", "arrive_min", "start_min", "cost", "dest_x", "dest_y", "folk", "n", "transfers"])
	roads = (d.get("roads", {}) as Dictionary).duplicate()
	works = (d.get("works", []) as Array).duplicate(true)
	for w in works:
		SysUtil.ints_in(w, ["id", "start", "end"])
	stats = {}
	for k4 in (d.get("stats", {}) as Dictionary):
		stats[str(k4)] = int(d["stats"][k4])
	seq = int(d.get("seq", 1))
	TransportParking.from_dict(d.get("parking", {}))
