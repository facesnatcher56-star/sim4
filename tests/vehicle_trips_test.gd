extends RefCounted
## Task 12b: the trips of the players as vehicles (headless layer on the real map). A car waits at the kerb, the folk gets in, the car drives the lane route paced to the
## sim's minute and stops at the other kerb where the folk gets out; a taxi pulls up; a bike rides the sidewalk; a bus rider waits at the stop; emergency units drive to the
## call with the siren on; a crash shows two stopped cars with hazard lights and then a tow truck.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _setup() -> Array:
	var folk: Array = K.game("small")
	var mira = folk[0]
	var hid: int = int(mira.household_id)
	WorldIface.coins[hid] = 6000
	SimEnv.clock().advance_minutes(2 * 60)
	return [mira, hid]

func _layer_at(lot: String) -> VehicleView:
	var fr: Dictionary = VehicleRoads.frontage(lot)
	var vv: VehicleView = K.layer([Vector2(float(fr["gate"]), float(fr["hy"]) - 6.0), Vector2(100.0, 60.0)])
	vv.sync()
	return vv

func _find(vv: VehicleView, kind: String) -> Dictionary:
	for v in vv.sim.vehicles:
		if str(v["kind"]) == kind and str(v["state"]) != "dead":
			return v
	return {}

func run() -> Array:
	fails = []
	_car()
	_taxi()
	_bike()
	_bus()
	_emergency()
	_crash()
	K.Kit.teardown()
	return fails

func _count_overlaps(vv: VehicleView) -> int:
	var n := 0
	var vs: Array = vv.sim.vehicles
	for i in vs.size():
		for j in range(i + 1, vs.size()):
			if VehicleSim.overlaps(vs[i], vs[j]):
				n += 1
				if n <= 2:
					print("    overlap ", [vs[i]["kind"], vs[i]["tag"], vs[i]["state"], vs[i]["pos"], vs[i]["dir"], vs[i]["v"], vs[i]["id"]], [vs[j]["kind"], vs[j]["tag"], vs[j]["state"], vs[j]["pos"], vs[j]["dir"], vs[j]["v"], vs[j]["id"]])
	return n

func _car() -> void:
	var s: Array = _setup()
	var mira = s[0]
	var hid: int = s[1]
	var b: Dictionary = TransportCars.buy(hid, "hatch")
	var car: Dictionary = Transport.car(int(b["car"]))
	TransportCars.refuel(hid, int(car["id"]))
	mira.tile = NeighborhoodLots.entry_tile("home")
	var dest: Vector2i = NeighborhoodLots.entry_tile("office")
	var ride: Dictionary = TransportTrip.start(mira, dest, {"own_only": true, "from_lot": "home", "to_lot": "office"})
	_check(str(ride["mode"]) == "car", "the trip is by car (%s)" % str(ride["mode"]))
	var vv: VehicleView = _layer_at("home")
	vv.sync()
	var rec: Dictionary = vv.trips.recs.get(int(mira.id), {})
	_check(not rec.is_empty(), "the layer picked the trip up")
	var v: Dictionary = vv.trips._vehicle(rec) if not rec.is_empty() else {}
	_check(not v.is_empty() and str(v["tag"]) == "trip", "a vehicle was made for the trip")
	if v.is_empty():
		K.free_layer(vv)
		return
	var stopped_at_kerb := false
	var rode := false
	var alighted := false
	var overlaps := 0
	for step in 1800:
		K.run_seconds(vv, 0.05, 1, 0.05)
		var ph: String = str(rec["phase"])
		if ph == "ride":
			rode = true
		if ph == "alight" or ph == "done":
			alighted = true
		if str(v["state"]) == "dwell" and not (v["stops"] as Array).is_empty() and str(((v["stops"] as Array)[0] as Dictionary)["tag"]) == "alight":
			stopped_at_kerb = true
		if step % 10 == 0:
			overlaps += _count_overlaps(vv)
		if str(rec["phase"]) == "done" and str(v["state"]) in ["parked", "dead"]:
			break
	print("  [vehicles] car trip: rode %s, stopped at the kerb %s, got out %s, final %s, overlaps %d, game minute %d" % [rode, stopped_at_kerb, alighted, str(v["state"]), overlaps, SysUtil.now()])
	_check(rode, "the folk got in")
	_check(stopped_at_kerb, "the car stopped at the far kerb")
	_check(alighted, "the folk got out")
	_check(str(v["state"]) == "parked" or str(v["state"]) == "dead", "the car ends parked or gone (%s)" % str(v["state"]))
	_check(overlaps == 0, "no overlaps on the trip (%d)" % overlaps)
	K.free_layer(vv)

func _taxi() -> void:
	var s: Array = _setup()
	var mira = s[0]
	mira.tile = NeighborhoodLots.entry_tile("home")
	var dest: Vector2i = NeighborhoodLots.entry_tile("office")
	var now: int = SysUtil.now()
	Transport.active[str(mira.id)] = {"mode": "taxi", "minutes": 14.0, "cost": 20, "n": 100, "wait": 5.0, "to_lot": "office", "total_minutes": 14.0, "start_min": now, "arrive_min": now + 14,
		"dest_x": dest.x, "dest_y": dest.y, "folk": int(mira.id)}
	var vv: VehicleView = _layer_at("home")
	vv.sync()
	var found := false
	for v in vv.sim.vehicles:
		if str(v["glb"]) == "taxi":
			found = true
	_check(found, "a taxi pulls up for a taxi trip")
	var rec: Dictionary = vv.trips.recs.get(int(mira.id), {})
	K.run_seconds(vv, 40.0, 1, 0.05)
	_check(not rec.is_empty() and str(rec["phase"]) in ["ride", "alight", "done"], "the taxi rider got in (%s)" % str(rec.get("phase", "")))
	K.free_layer(vv)

func _bike() -> void:
	var s: Array = _setup()
	var mira = s[0]
	var hid: int = s[1]
	Transport.bikes[str(hid)] = 1
	mira.tile = NeighborhoodLots.entry_tile("home")
	var dest: Vector2i = NeighborhoodLots.entry_tile("office")
	var ride: Dictionary = TransportTrip.start(mira, dest, {"own_only": true, "from_lot": "home", "to_lot": "office"})
	var vv: VehicleView = _layer_at("home")
	vv.sync()
	var bk: Dictionary = _find(vv, "bike")
	_check(str(ride["mode"]) == "bike" and not bk.is_empty(), "a bike trip shows a bike")
	if not bk.is_empty():
		var w = WorldIface.world()
		var bad := 0
		for k in 900:
			K.run_seconds(vv, 0.05, 1, 0.05)
			if str(bk["state"]) == "dead":
				break
			var p: Vector2 = bk["pos"]
			var t := Vector2i(int(floorf(p.x)), int(floorf(p.y)))
			var f: String = w.get_floor(t)
			if f != "sidewalk" and f != "crosswalk" and f != "asphalt" and NeighborhoodLots.lot_at(t) == "":
				bad += 1
		_check(bad == 0, "the bike stays on the sidewalk or crossings (%d samples off)" % bad)
	K.free_layer(vv)

func _bus() -> void:
	var s: Array = _setup()
	var mira = s[0]
	mira.tile = NeighborhoodLots.entry_tile("market")
	var dest: Vector2i = NeighborhoodLots.entry_tile("school")
	var calls: Array = TransportBus.next_times("loop", "market", 1, SysUtil.now() + 5)
	SimEnv.clock().total_minutes = int(calls[0]) - 2             # two minutes before a bus of the town loop calls at the market
	var ride: Dictionary = TransportTrip.start(mira, dest, {"modes": ["bus"], "from_lot": "market", "to_lot": "school", "n": 90})
	_check(str(ride["mode"]) == "bus", "with a bus two minutes away a long trip goes by bus (%s)" % str(ride["mode"]))
	if str(ride["mode"]) != "bus":
		return
	var vv: VehicleView = _layer_at("market")
	vv.sync()
	var rec: Dictionary = vv.trips.recs.get(int(mira.id), {})
	_check(not rec.is_empty() and str(rec["mode"]) == "bus" and str(rec["phase"]) == "wait", "a bus rider waits at the stop")
	var buses := 0
	for v in vv.sim.vehicles:
		if str(v["kind"]) == "bus":
			buses += 1
	_check(buses >= 1, "timetable buses are on the road near the camera (%d)" % buses)
	K.run_seconds(vv, 30.0, 1, 0.05)
	_check(not rec.is_empty() and (str(rec["phase"]) == "ride" or str(rec["phase"]) == "done"), "the rider boarded")
	K.free_layer(vv)

func _emergency() -> void:
	_setup()
	var vv: VehicleView = _layer_at("home")
	var e: Dictionary = CityServices.dispatch("fire", "market")
	vv.sync()
	var eng: Dictionary = {}
	var saw_siren := false
	var reached := false
	for k in 3000:
		K.run_seconds(vv, 0.05, 1, 0.05)
		var u: Dictionary = _find(vv, "fire")
		if not u.is_empty():
			eng = u
			saw_siren = saw_siren or bool((u["lights"] as Dictionary)["siren"])
			if str(u["state"]) == "dwell":
				reached = true
				break
	print("  [vehicles] fire call: response %d min, engine seen %s, siren %s, reached the scene %s" % [int(e["minutes"]), not eng.is_empty(), saw_siren, reached])
	_check(not eng.is_empty() and saw_siren, "a fire engine drives out with its siren on")
	_check(reached, "it stops at the lot of the call")
	K.free_layer(vv)

func _crash() -> void:
	var s: Array = _setup()
	var mira = s[0]
	var hid: int = s[1]
	var b: Dictionary = TransportCars.buy(hid, "hatch")
	var car: Dictionary = Transport.car(int(b["car"]))
	TransportCars.refuel(hid, int(car["id"]))
	mira.tile = NeighborhoodLots.entry_tile("home")
	TransportTrip.start(mira, NeighborhoodLots.entry_tile("office"), {"own_only": true, "from_lot": "home", "to_lot": "office"})
	(Transport.active[str(mira.id)] as Dictionary)["crash"] = "serious"
	var vv: VehicleView = _layer_at("home")
	vv.sync()
	var rec: Dictionary = vv.trips.recs.get(int(mira.id), {})
	_check(not rec.is_empty() and rec.has("crash_s"), "a crash trip has a crash stop on its route")
	var hazards := 0
	var two_stopped := false
	var tow := false
	for step in 4000:
		K.run_seconds(vv, 0.05, 1, 0.05)
		var haz: int = 0
		for v in vv.sim.vehicles:
			if bool((v["lights"] as Dictionary).get("hazard", false)) and str(v["kind"]) != "tow":
				haz += 1
			if str(v["kind"]) == "tow":
				tow = true
		if haz >= 2:
			two_stopped = true
		hazards = maxi(hazards, haz)
		if tow and two_stopped:
			break
	print("  [vehicles] crash: cars with hazard lights %d, tow truck %s" % [hazards, tow])
	_check(two_stopped, "two cars stand with hazard lights (%d)" % hazards)
	_check(tow, "a tow truck comes for a serious crash")
	K.free_layer(vv)
