extends RefCounted
## Task 12.2: cars (buy, fuel, park, insure, crash, tow), bikes, buses with a timetable, mode choice by time / cost / weather, traffic, lights, road works.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := C.setup()
	var h: Dictionary = C.home(w)
	var ada: Folk = h["ada"]
	K.set_time(3, 8)
	WorldIface.coins[1] = 6000
	# --- data sanity
	for r in TransportBus.routes():
		for stop in r["stops"]:
			K.expect(f, not Neighborhood.lot(str(stop)).is_empty(), "bus stop %s of the %s is a real lot" % [stop, r["name"]])
	# --- buying, fuel, parking
	var b: Dictionary = TransportCars.buy(1, "hatch")
	var car: Dictionary = Transport.car(int(b["car"]))
	K.expect(f, bool(b["ok"]) and WorldIface.coins[1] == 6000 - 2400 and str(car["spot"]) == "drive" and str(car["at"]) == "home", "buying a car costs coins and parks it on the drive")
	K.expect(f, Transport.describe(car).find("Town Hatchback") == 0 and Transport.describe(car).find("fuel 50 percent") > 0, "the car is described in plain words: %s" % Transport.describe(car))
	var r: Dictionary = TransportCars.refuel(1, int(car["id"]))
	K.expect(f, bool(r["ok"]) and float(car["fuel"]) == 40.0 and int(r["cost"]) == int(ceil(20.0 * 2.4)), "filling up costs coins by the missing fuel")
	K.expect(f, not bool(TransportCars.refuel(1, int(car["id"]))["ok"]), "a full tank cannot be filled")
	WorldIface.coins[1] = 3
	K.expect(f, not bool(TransportCars.buy(1, "banger")["ok"]), "no coins, no car")
	WorldIface.coins[1] = 6000
	var ev: Dictionary = Transport.car(int(TransportCars.buy(1, "ev")["car"]))
	ev["fuel"] = 0.0
	var charge: Dictionary = TransportCars.refuel(1, int(ev["id"]))
	K.expect(f, int(charge["cost"]) == int(ceil(40.0 * 1.4 * 0.6)), "charging an electric car at home is cheaper (%d coins)" % int(charge["cost"]))
	TransportCars.sell(1, int(ev["id"]))
	K.expect(f, Transport.cars_of(1).size() == 1 and WorldIface.coins[1] > 3000, "selling pays the car's worth")
	# --- mode choice
	var far := Vector2i(112, 12)
	var opts := {"n": 100, "from_lot": "home", "to_lot": "cafe"}
	var p: Dictionary = TransportTrip.plan(ada, far, opts)
	K.expect(f, str(p["mode"]) == "car" and float(p["minutes"]) < 30.0, "a far trip with the car at home goes by car (%s %.1f min)" % [p["mode"], float(p["minutes"])])
	K.expect(f, str(TransportTrip.plan(ada, Vector2i(20, 12), {"n": 8, "from_lot": "home", "to_lot": "cafe"})["mode"]) == "walk", "a short trip is on foot")
	car["at"] = "market"
	K.expect(f, str(TransportTrip.plan(ada, far, opts)["mode"]) != "car", "the car at another lot cannot be used")
	car["at"] = "home"
	car["fuel"] = 0.2
	K.expect(f, str(TransportTrip.plan(ada, far, opts)["mode"]) != "car", "no fuel, no drive")
	car["fuel"] = 30.0
	Transport.bikes["1"] = 1
	K.expect(f, str(TransportTrip.plan(ada, far, opts)["mode"]) == "bike", "a bike is faster than the car in the rush hour")
	Weather.force("snow")
	K.expect(f, str(TransportTrip.plan(ada, far, opts)["mode"]) != "bike", "nobody cycles in the snow")
	Weather.force("sunny")
	Transport.bikes.clear()
	WorldIface.coins[1] = 3
	K.expect(f, str(TransportTrip.plan(ada, far, {"n": 100, "from_lot": "home", "to_lot": "cafe", "modes": ["taxi", "bus"]})["mode"]) == "walk", "without coins for the fare, walking")
	WorldIface.coins[1] = 6000
	var kid := K.make_folk(w, "Kit Voss", [], 1, Vector2i(14, 12), "child")
	K.expect(f, str(TransportTrip.plan(kid, far, opts)["mode"]) != "car", "children do not drive")
	# --- a car trip: fuel, parking at the other end, arrival
	var fuel0: float = float(car["fuel"])
	var coins0: int = int(WorldIface.coins[1])
	var trip: Dictionary = TransportTrip.start(ada, far, opts)
	K.expect(f, str(trip["mode"]) == "car" and float(car["fuel"]) < fuel0 and str(car["spot"]) == "", "the trip uses fuel and leaves the drive")
	K.expect(f, Transport.busy() and int(trip["arrive_min"]) > SysUtil.now(), "the trip is under way")
	K.expect(f, str(TransportTrip.start(ada, far, opts)["mode"]) == "car" and float(car["fuel"]) == float(fuel0 - TransportCars.fuel_use(car, 100)), "asking again does not charge twice")
	trip["crash"] = ""
	trip.erase("crash")
	C.run_hours(1)
	K.expect(f, not Transport.busy() and str(car["at"]) == "cafe" and str(car["spot"]) == "lot", "at arrival the car is parked at the cafe")
	# --- parking limits, car park, street, tow, pound
	var cap: int = TransportParking.capacity("cafe")
	K.expect(f, cap == 8 and TransportParking.spaces_free("cafe", 12.0) == cap - int(ceil(0.15 * cap)) - 1, "spaces: capacity minus other people minus own cars")
	K.expect(f, TransportParking.spaces_free("office", 11.0) < TransportParking.spaces_free("office", 3.0), "offices fill up in the working day")
	var c2: Dictionary = Transport.car(int(TransportCars.buy(1, "banger")["car"]))
	c2["spot"] = ""
	for i in 20:
		var filler := {"id": 900 + i, "hid": 77, "model": "hatch", "plate": "X", "fuel": 1.0, "cond": 1.0, "at": "market", "spot": "lot", "bought": 1, "wreck": false, "ready_day": -1, "towed": false, "pound_day": -1, "trips": 0}
		Transport.cars[str(900 + i)] = filler
	var park: Dictionary = TransportParking.park(c2, "market")
	K.expect(f, str(park["spot"]) == "garage" and int(park["extra_min"]) > 0, "a full lot sends the car to the car park (fee %d a day)" % int(park["fee"]))
	var bal0: int = int(WorldIface.coins[1])
	TransportParking.on_day(4)
	K.expect(f, int(WorldIface.coins[1]) < bal0, "the car park charges a daily fee")
	WorldIface.coins[1] = 10
	park = TransportParking.park(c2, "market")
	K.expect(f, str(park["spot"]) == "street" and int(park["extra_min"]) >= 3, "poor drivers park on the street after a search")
	CityState.rng.seed = 1
	var towed: bool = false
	for i in 12:
		TransportParking.on_day(5 + i)
		if bool(c2["towed"]):
			towed = true
			break
	K.expect(f, towed and K.has_note("towed"), "a car left on a venue street overnight gets towed")
	WorldIface.coins[1] = 3000
	K.set_time(30, 9)
	var fee: int = TransportCars.pound_fee(c2)
	var col: Dictionary = TransportCars.collect(1, int(c2["id"]))
	K.expect(f, bool(col["ok"]) and not bool(c2["towed"]) and int(col["paid"]) == fee and fee > 60, "the pound fee grows each day and gets the car back (%d)" % fee)
	for i in 20:
		Transport.cars.erase(str(900 + i))
	# --- crashes
	var cond0: float = float(car["cond"])
	var cfg_crash: Dictionary = Transport.sect("crash")
	(cfg_crash["wreck"] as Dictionary)["death"] = 0.0
	car["at"] = "home"
	TransportCrash.apply(ada, {"crash": "minor", "mode": "car", "car": int(car["id"])})
	K.expect(f, float(car["cond"]) < cond0 and K.has_note("bump"), "a minor crash dents the car")
	BankInsurance.buy(1, "car")
	TransportCrash.apply(ada, {"crash": "serious", "mode": "car", "car": int(car["id"])})
	K.expect(f, float(car["cond"]) < 0.8 and Health.is_injured(ada) and K.has_note("crashed"), "a serious crash hurts the driver and the car")
	TransportCrash.apply(ada, {"crash": "wreck", "mode": "car", "car": int(car["id"])})
	K.expect(f, bool(car["wreck"]) and not TransportCars.ready(car), "a wreck cannot be driven")
	var quote: int = TransportCars.repair_quote(car)
	var bal1: int = int(WorldIface.coins[1])
	var rep: Dictionary = TransportCars.repair(1, int(car["id"]))
	K.expect(f, bool(rep["ok"]) and int(rep["covered"]) == int(floor(float(quote) * 0.7)) and bal1 - int(WorldIface.coins[1]) == quote - int(rep["covered"]), "the car policy pays 70 percent of repairs")
	K.expect(f, not TransportCars.ready(car) and int(car["ready_day"]) > SysUtil.day(), "the garage keeps it a few days")
	K.set_time(40, 9)
	TransportCars.on_day(40)
	K.expect(f, TransportCars.ready(car), "then it is ready again")
	# --- buses and the timetable
	var loop: Dictionary = TransportBus.route("loop")
	K.set_time(3, 8)                                      # day 3 is a Wednesday
	K.expect(f, TransportBus.routes().size() == 1 and not loop.is_empty(), "a small town runs one bus route (%d)" % TransportBus.routes().size())
	var peak: float = TransportBus.headway(loop, 8.0, 2)
	var by_day: float = TransportBus.headway(loop, 13.0, 2)
	K.expect(f, peak <= 30.0 and by_day >= 60.0 - 0.01 and by_day <= 60.0 + 0.01, "30 minutes at the rush hour, 60 by day (%.0f / %.0f min)" % [peak, by_day])
	K.expect(f, TransportBus.headway(loop, 21.0, 2) >= TransportBus.NO_BUS and TransportBus.headway(loop, 2.0, 2) >= TransportBus.NO_BUS, "no bus after 20:00 and none at night")
	K.expect(f, TransportBus.runs_day(loop, 6).size() * 2 < TransportBus.runs_day(loop, 2).size(), "Sundays have far fewer buses")
	var times: Array = TransportBus.next_times("loop", "market", 3)
	K.expect(f, times.size() == 3 and times[0] >= SysUtil.now() and times[1] > times[0] and times[2] > times[1], "the next buses at a stop are in order")
	K.expect(f, TransportBus.wait_at(loop, 3, SysUtil.now()) <= 30.01, "nobody waits longer than the rush-hour gap")
	var direct: Dictionary = TransportBus.plan("market", "school")
	var back: Dictionary = TransportBus.plan("hospital", "works")
	K.expect(f, bool(direct["ok"]) and int(direct["transfers"]) == 0 and int(direct["fare"]) == 4, "market to school is one bus, fare 4")
	K.expect(f, not bool(back["ok"]), "the bus only runs one way through town: hospital to works has no bus")
	K.expect(f, str(TransportBus.timetable_text("market")[0]).find("Town Bus") == 0 and TransportBus.next_text("market").begins_with("Next bus "), "the stop shows the next bus: %s" % TransportBus.next_text("market"))
	K.set_time(3, 22)
	K.expect(f, not bool(TransportBus.plan("market", "school")["ok"]) or float(TransportBus.plan("market", "school")["wait"]) > 60.0, "at 22:00 nobody can plan a bus ride that leaves soon")
	K.set_time(3, 8)
	var n_full: int = TransportBus.runs_day(loop, 2).size()
	CityBudget.set_funding("transport", 0.5)
	K.expect(f, TransportBus.runs_day(loop, 2).size() < n_full, "a starved transport budget means fewer buses")
	CityBudget.set_funding("transport", 1.0)
	CityPlan.built["residential"] = 1
	K.expect(f, TransportBus.routes().size() == 2, "a second route runs once the town has grown")
	CityPlan.built.clear()
	# --- traffic, lights, works, roads
	K.set_time(3, 8)
	var d_rush: float = TransportTraffic.density(8.0)
	K.expect(f, d_rush > TransportTraffic.density(3.0) * 5.0 and d_rush > TransportTraffic.density(13.0), "traffic peaks in the rush hours")
	K.set_time(6, 8)
	K.expect(f, TransportTraffic.density(8.0) < d_rush, "weekends are quieter")
	K.set_time(3, 8)
	Weather.force("rain")
	K.expect(f, TransportTraffic.density(8.0) > d_rush, "rain adds cars")
	Weather.force("sunny")
	K.expect(f, TransportTraffic.speed_mult("", 8.0) < TransportTraffic.speed_mult("", 3.0), "rush hour is slower than the night")
	var seen: Dictionary = {}
	for m in 8:
		K.set_time(3, 8, m)
		seen[TransportTraffic.light_phase(1, 2, "north")] = true
	K.expect(f, seen.has("walk") and seen.has("stop") and not seen.has("dark"), "lights cycle between walk and stop")
	Utilities.begin("power", "north", 3.0, "fault", {"silent": true, "apply": false})
	K.expect(f, TransportTraffic.light_phase(1, 2, "north") == "dark" and TransportTraffic.speed_mult("north", 8.0) < TransportTraffic.speed_mult("south", 8.0), "no power: the lights are out and traffic crawls")
	Utilities.finish(Utilities.outage_of("power", "north"))
	TransportTraffic.add_works("east", "resurface", 3.0)
	K.expect(f, TransportTraffic.works_in("east") and TransportTraffic.speed_mult("east", 8.0) < TransportTraffic.speed_mult("south", 8.0), "road works slow the zone")
	Transport.works.clear()
	var main: Dictionary = UtilityEvents.start("water", "south", "burst_main", {"silent": true, "hours": 24})
	K.expect(f, TransportTraffic.works_in("south") and not main.is_empty(), "a burst water main means the crew digs up the street")
	Utilities.finish(main)
	Transport.works.clear()
	Transport.sect("roads")["works_chance_per_day"] = 1.0
	TransportTraffic.set_quality("west", 0.5)
	for d in 6:
		TransportTraffic.on_day(10 + d)
	K.expect(f, TransportTraffic.works_in("west") or TransportTraffic.quality("west") > 0.6, "poor roads get resurfaced (%.2f)" % TransportTraffic.quality("west"))
	TransportTraffic.set_quality("north", 0.2)
	K.expect(f, TransportTraffic.pothole("north"), "a poor road has potholes")
	var crash_ok: float = TransportCrash.chance(ada, {"mode": "car"})
	TransportTraffic.set_quality("north", 0.9)
	TransportTraffic.set_quality("south", 0.9)
	TransportTraffic.set_quality("east", 0.9)
	TransportTraffic.set_quality("west", 0.9)
	K.expect(f, TransportCrash.chance(ada, {"mode": "car"}) < crash_ok * 2.0 and TransportCrash.chance(ada, {"mode": "car"}) > 0.0, "crash chance depends on the road")
	# --- a crash that waits for the end of the trip; the command layer
	WorldIface.coins[1] = 6000
	var res: Dictionary = Commands.run({"action": "city", "folk_id": ada.id, "args": {"action": "buy_bike"}})
	K.expect(f, bool(res["ok"]) and Transport.bikes_of(1) == 1, "buying a bike is a command")
	res = Commands.run({"action": "city", "folk_id": ada.id, "args": {"action": "buy_car", "args": {"model": "estate"}}})
	K.expect(f, bool(res["ok"]) and Transport.cars_of(1).size() == 3, "so is buying a car")
	res = Commands.run({"action": "city", "folk_id": ada.id, "args": {"action": "buy_car", "args": {"model": "estate"}}})
	K.expect(f, not bool(res["ok"]) and str(res["msg"]).find("room") > 0, "three cars is the limit (%s)" % str(res["msg"]))
	# --- save and load
	car["fuel"] = 12.5
	TransportTrip.start(ada, far, {"n": 100, "from_lot": "home", "to_lot": "gym", "modes": ["bus"]})
	var before: String = JSON.stringify(CityState.to_dict())
	CityState.from_dict(JSON.parse_string(before))
	var after: String = JSON.stringify(CityState.to_dict())
	var at: int = 0
	while at < mini(before.length(), after.length()) and before[at] == after[at]:
		at += 1
	K.expect(f, after == before, "cars, trips, roads and works survive a JSON round trip (differs at: %s | %s)" % [before.substr(maxi(at - 40, 0), 90), after.substr(maxi(at - 40, 0), 90)])
	K.teardown()
	return f
