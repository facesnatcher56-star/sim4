extends RefCounted
## Task 12b: the vehicle layer on the real map, headless. Parked cars stand in bays; passing cars keep to the road, stop at red lights, never overlap another vehicle
## and never run over a folk on the road; two cars on one lane queue instead of driving through each other.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _on_road_or_lot(w, p: Vector2) -> bool:
	var t := Vector2i(int(floorf(p.x)), int(floorf(p.y)))
	var f: String = w.get_floor(t)
	if f == "asphalt" or f == "crosswalk" or f == "sidewalk":
		return true
	return NeighborhoodLots.lot_at(t) != ""

func run() -> Array:
	fails = []
	K.game()
	var w = WorldIface.world()
	SimEnv.clock().advance_minutes(5 * 60)          # a busy morning: 12:00
	var home: Dictionary = VehicleRoads.frontage("home")
	var vv: VehicleView = K.layer([Vector2(float(home["gate"]), float(home["hy"]) - 4.0)])
	vv.sync()
	var parked := 0
	for v in vv.sim.vehicles:
		if str(v["state"]) == "parked":
			parked += 1
	_check(parked >= 3, "cars stand in the bays near the focus (%d)" % parked)
	# run two minutes of vehicle time: cars come and go
	var overlaps := 0
	var off := 0
	var max_moving := 0
	var started := 0
	for step in 2400:
		K.run_seconds(vv, 0.05, 1, 0.05)
		if step % 10 == 0:
			var moving := 0
			for v in vv.sim.vehicles:
				if str(v["state"]) != "parked":
					moving += 1
					if not _on_road_or_lot(w, v["pos"]):
						off += 1
			max_moving = maxi(max_moving, moving)
			var vs: Array = vv.sim.vehicles
			for i in vs.size():
				for j in range(i + 1, vs.size()):
					if VehicleSim.overlaps(vs[i], vs[j]):
						overlaps += 1
						if overlaps <= 3:
							print("    overlap: ", [vs[i]["kind"], vs[i]["tag"], vs[i]["state"], vs[i]["pos"], vs[i]["dir"], vs[i]["v"], vs[i].get("vcap"), vs[i]["blocked_t"], vs[i]["s"], vs[i]["id"]], [vs[j]["kind"], vs[j]["tag"], vs[j]["state"], vs[j]["pos"], vs[j]["dir"], vs[j]["v"], vs[j].get("vcap"), vs[j]["blocked_t"], vs[j]["s"], vs[j]["id"]], " t ", SysUtil.now())
	print("  [vehicles] ambient: parked %d, most moving at once %d, overlaps %d, off-road samples %d, ghosted %d" % [parked, max_moving, overlaps, off, vv.sim.ghosted])
	for g in vv.sim.ghost_log:
		print("    ghost: ", g)
	_check(max_moving >= 1, "at least one car drove somewhere (%d)" % max_moving)
	_check(overlaps == 0, "no two vehicles overlap (%d samples)" % overlaps)
	_check(off == 0, "moving vehicles stay on the road or inside a lot (%d samples off)" % off)
	_check(vv.sim.ghosted == 0, "no jam had to be cleared by ghosting (%d)" % vv.sim.ghosted)
	K.free_layer(vv)
	_signal_stop()
	_queue()
	_folk_on_road()
	_box_block()
	K.Kit.teardown()
	return fails

func _straight(jx: int, jy: int, from_x: float) -> VehiclePath:
	var c: Vector2 = VehicleRoads.junction_center(jx, jy)
	return VehiclePath.make([Vector2(from_x, c.y - 1.0), Vector2(c.x - 40.0 + 80.0, c.y - 1.0)], 0.0)

## A car on a westbound lane stops short of the line while its axis is red and goes when green.
func _signal_stop() -> void:
	var sim := VehicleSim.new()
	var c: Vector2 = VehicleRoads.junction_center(1, 1)
	var path: VehiclePath = VehiclePath.make([Vector2(c.x + 30.0, c.y - 1.0), Vector2(c.x - 30.0, c.y - 1.0)], 0.0)
	var v: Dictionary = sim.add("car", "car_sedan_red", path, {"visits": [[1, 1, VehicleRoads.W, VehicleRoads.W]]})
	var line_s: float = float((v["visits"] as Array)[0]["s_line"])
	var stopped_before_line := false
	var passed_on_green := false
	var jammed_red := 0
	for k in 4000:
		sim.step(0.02)
		var st: String = sim.signal_state(1, 1, 0)
		if st != "green" and float(v["s"]) + float(v["len"]) * 0.5 > line_s + 0.8 and float(v["s"]) + float(v["len"]) * 0.5 < line_s + 3.0 and float(v["v"]) > 2.0:
			jammed_red += 1
		if float(v["v"]) < 0.05 and float(v["s"]) + float(v["len"]) * 0.5 <= line_s + 0.2 and float(v["s"]) > line_s - 12.0 and st != "green":
			stopped_before_line = true
		if float(v["s"]) > line_s + 15.0:
			passed_on_green = true
			break
	_check(stopped_before_line or passed_on_green, "the car met the junction")
	_check(passed_on_green, "the car got through the junction in the end")
	_check(jammed_red == 0, "never drove across the line on red (%d samples)" % jammed_red)

## A fast car behind a stopped one queues.
func _queue() -> void:
	var sim := VehicleSim.new()
	var path: VehiclePath = VehiclePath.make([Vector2(10, 10), Vector2(80, 10)], 0.0)
	var a: Dictionary = sim.add("car", "car_sedan_red", path, {"s": 40.0, "stops": [{"s": 50.0, "hold": true, "tag": "x"}]})
	var b: Dictionary = sim.add("car", "car_sedan_blue", path, {"s": 10.0})
	var min_gap := 99.0
	for k in 450:
		sim.step(0.02)
		min_gap = minf(min_gap, float(a["s"]) - float(b["s"]) - (float(a["len"]) + float(b["len"])) * 0.5)
	_check(min_gap > 0.2, "the car behind stops behind the one ahead (gap %.2f)" % min_gap)
	_check(not VehicleSim.overlaps(a, b), "queued cars do not overlap")

## A folk standing in the lane stops the car.
func _folk_on_road() -> void:
	var sim := VehicleSim.new()
	var path: VehiclePath = VehiclePath.make([Vector2(10, 10), Vector2(80, 10)], 0.0)
	var v: Dictionary = sim.add("car", "car_sedan_red", path, {})
	sim.folks = PackedVector2Array([Vector2(40.0, 10.3)])
	for k in 450:
		sim.step(0.02)
	var nose: float = float(v["s"]) + float(v["len"]) * 0.5 + 10.0
	_check(nose < 40.0 and float(v["v"]) < 0.05, "a car stops for a folk in front of it (nose at x=%.1f)" % nose)
	sim.folks = PackedVector2Array()
	for k2 in 300:
		sim.step(0.02)
	_check(float(v["s"]) + 10.0 > 41.0, "and drives on when the folk has gone")

## A bus standing with its tail in a junction: crossing cars wait for it, they do not drive through.
func _box_block() -> void:
	var sim := VehicleSim.new()
	var c: Vector2 = VehicleRoads.junction_center(1, 2)
	var bus_path: VehiclePath = VehiclePath.make([Vector2(c.x - 1.6, c.y + 1.0), Vector2(c.x + 40.0, c.y + 1.0)], 0.0)
	var bus: Dictionary = sim.add("bus", "bus", bus_path, {"s": 5.0, "stops": [{"s": 5.0, "hold": true, "tag": "x"}]})
	sim.step(0.1)
	var car_path: VehiclePath = VehiclePath.make([Vector2(c.x - 1.0, c.y - 30.0), Vector2(c.x - 1.0, c.y + 30.0)], 0.0)
	var car: Dictionary = sim.add("car", "car_sedan_red", car_path, {"visits": [[1, 2, VehicleRoads.S, VehicleRoads.S]], "ignore_signals": true})
	var hit := 0
	for k in 400:
		sim.step(0.02)
		if VehicleSim.overlaps(bus, car):
			hit += 1
	print("  [vehicles] box block: car stopped at z=%.1f (bus tail at z=%.1f) v=%.1f hits %d" % [(car["pos"] as Vector2).y, c.y + 1.0, float(car["v"]), hit])
	_check(hit == 0, "a car does not drive through a bus standing in the junction (%d samples)" % hit)
