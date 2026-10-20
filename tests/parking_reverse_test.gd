extends RefCounted
## Task 42 (fast): a car that leaves a driveway backs out: it waits in its place for the lane to be clear, the body keeps pointing at the house while it moves away (reversing lights), then swings
## round to the way it drives (west, with the lane) and goes; a car that arrives turns in from the lane and stops nose to the house in its place, centre on the place.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func run() -> Array:
	fails = []
	K.game("classic", 1)
	var lot: String = ""
	var pl: Dictionary = {}
	for l in Neighborhood.lot_ids():
		for p in VehicleBays.of(str(l)):
			if str(p["kind"]) == "driveway" and pl.is_empty():
				pl = p
				lot = str(l)
	_check(not pl.is_empty(), "the map has a driveway")
	if pl.is_empty():
		K.Kit.teardown()
		return fails
	var fr: Dictionary = VehicleRoads.frontage(lot)
	var vv: VehicleView = K.layer([pl["pos"]])
	vv.seeding = false
	vv.sync()
	vv.sim.vehicles.clear()
	vv.ambient.occ.clear()
	for v0 in vv.sim.vehicles:
		v0["state"] = "dead"
	var v: Dictionary = vv.sim.add_parked("car", "car_hatchback_red", pl["pos"], pl["face"], {"tag": "ambient"})
	v["lot"] = lot
	v["bay"] = 0
	vv.ambient._occ(lot)[0] = int(v["id"])
	vv.ambient._leave(v)
	var rev_steps: int = 0
	var rev_ok: int = 0
	var max_back: float = 0.0
	var swung: bool = false
	var left_west: bool = false
	for i in 400:
		vv.sim.step(0.05)
		if VehicleSim.reversing(v):
			rev_steps += 1
			var d: Vector2 = v["dir"]
			if d.y < -0.7:
				rev_ok += 1
			max_back = maxf(max_back, (v["pos"] as Vector2).y - (pl["pos"] as Vector2).y)
		elif float(v["s"]) > float(v.get("back_m", 0.0)) + 3.5 and float(v["v"]) > 1.0:
			swung = swung or (v["dir"] as Vector2).x < -0.7
		if str(v["state"]) == "dead" or (v["pos"] as Vector2).x < float(fr["gate"]) - 30.0:
			left_west = true
			break
	print("  [parking] backing out: %d steps reversing, body pointed at the house in %d, backed %.1f m, swung round %s, left west %s" % [rev_steps, rev_ok, max_back, str(swung), str(left_west)])
	_check(rev_steps >= 10, "the car backs out of the driveway (%d reversing steps)" % rev_steps)
	_check(rev_ok >= rev_steps - 4, "while backing the body points at the house (%d of %d)" % [rev_ok, rev_steps])
	_check(max_back >= 3.0, "it backs a few metres (%.1f)" % max_back)
	_check(swung, "it swings round to drive west")
	_check(left_west, "it drives off west along the lane")
	# a car arriving: from a road end to the driveway
	var e: Dictionary = VehicleRoads.edge_ends()[0]
	vv.seeding = true
	var ok: bool = vv.ambient.drive_in(e, lot, 0, 0.0, "car_sedan_blue")
	_check(ok, "a car can drive in to the driveway from a road end")
	var arrived: Dictionary = {}
	for v1 in vv.sim.vehicles:
		if v1.has("dest_lot"):
			arrived = v1
	if not arrived.is_empty():
		for i2 in 3000:
			vv.sim.step(0.05)
			if str(arrived["state"]) == "parked":
				break
		_check(str(arrived["state"]) == "parked", "the arriving car parks (%s)" % str(arrived["state"]))
		var off: float = (arrived["pos"] as Vector2).distance_to(pl["pos"])
		_check(off < 0.5, "it stops with its centre on the place (%.2f m off)" % off)
		_check((arrived["dir"] as Vector2).y < -0.9, "it stands nose to the house (%s)" % str(arrived["dir"]))
	K.free_layer(vv)
	K.Kit.teardown()
	return fails
