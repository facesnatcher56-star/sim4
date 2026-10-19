class_name VehicleAmbient
extends RefCounted
## Parked and passing cars of the vehicle layer: the cars that stand in the bays of the lots near a focus (how many follows TransportParking.ambient for the hour),
## the players' own cars at their lots, and a trickle of cars that leave one lot and park at another, driving the right lane and stopping at red lights.
## The population of a lot is a function of (lot, bay, day) so it is the same every time you look; far lots have none (they are only the ambient number).

var view: VehicleView
var occ: Dictionary = {}              # lot id -> Array (bay index -> vehicle id, 0 = free)
var _lots_done: Dictionary = {}       # lot id -> true while populated


func _init(v: VehicleView) -> void:
	view = v


func reset() -> void:
	occ.clear()
	_lots_done.clear()


func _lots() -> Array:
	return Neighborhood.lot_ids() if Workplace.map_ready() else []


func _glb_for_hash(h: int) -> String:
	var amb: Array = (view.cfg.get("models", {}) as Dictionary).get("ambient", ["car_sedan_red"])
	return str(amb[absi(h) % amb.size()])


func owner_glb(c: Dictionary) -> String:
	var m: Dictionary = (view.cfg.get("models", {}) as Dictionary).get(str(c.get("model", "hatch")), {"glb": "car_hatchback", "paint": ["red"]})
	var paints: Array = m.get("paint", ["red"])
	return "%s_%s" % [str(m.get("glb", "car_hatchback")), str(paints[int(c.get("id", 0)) % paints.size()])]


func sync() -> void:
	var lots: Array = _lots()
	for lot_id in lots:
		var fr: Dictionary = VehicleRoads.frontage(str(lot_id))
		if fr.is_empty():
			continue
		var mid := Vector2(float(fr["gate"]), float(fr["hy"]) - 8.0)
		if view.in_range(mid):
			if not _lots_done.has(lot_id):
				_populate(str(lot_id))
		elif _lots_done.has(lot_id) and view.beyond_drop(mid):
			_depopulate(str(lot_id))
	_finish_arrivals()
	_depart()


func _bays(lot_id: String) -> Array:
	return VehicleBays.of(lot_id)


func _occ(lot_id: String) -> Array:
	if not occ.has(lot_id):
		var a: Array = []
		a.resize(_bays(lot_id).size())
		a.fill(0)
		occ[lot_id] = a
	return occ[lot_id]


func _share(lot_id: String) -> float:
	return TransportParking.ambient(lot_id, SysUtil.hour_f())


func _populate(lot_id: String) -> void:
	_lots_done[lot_id] = true
	var bays: Array = _bays(lot_id)
	var o: Array = _occ(lot_id)
	var owner_cars: Array = []
	for k in Transport.cars:
		var c: Dictionary = Transport.cars[k]
		if str(c["at"]) == lot_id and (str(c["spot"]) == "drive" or str(c["spot"]) == "lot") and not bool(c["wreck"]) and not bool(c["towed"]):
			owner_cars.append(c)
	owner_cars.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	for k2 in bays.size():
		if int(o[k2]) != 0:
			continue
		var bay: Dictionary = bays[k2]
		var pos: Vector2 = bay["pos"]
		var h: int = hash("%s|%d|%d" % [lot_id, k2, SysUtil.day()])
		var face := Vector2(-1, 0) if (h & 1) == 0 else Vector2(1, 0)
		if not owner_cars.is_empty():
			var c2: Dictionary = owner_cars.pop_front()
			var ov: Dictionary = view.sim.add_parked("car", owner_glb(c2), pos, face, {"tag": "owner", "key": "car:%d" % int(c2["id"])})
			ov["lot"] = lot_id
			ov["bay"] = k2
			o[k2] = int(ov["id"])
			continue
		var roll: float = float((h >> 4) & 0xffff) / 65535.0
		if roll < _share(lot_id):
			var av: Dictionary = view.sim.add_parked("car", _glb_for_hash(h >> 9), pos, face, {"tag": "ambient", "key": "bay:%s:%d" % [lot_id, k2]})
			av["lot"] = lot_id
			av["bay"] = k2
			av["stay_until"] = view.sim.vt + view.rng.randf_range(10.0, 60.0)
			o[k2] = int(av["id"])


func _depopulate(lot_id: String) -> void:
	_lots_done.erase(lot_id)
	for v in view.sim.vehicles.duplicate():
		if (str(v["tag"]) == "ambient" or str(v["tag"]) == "owner") and str(v.get("lot", "")) == lot_id and str(v["state"]) == "parked":
			remove(v)
	occ.erase(lot_id)


func remove(v: Dictionary) -> void:
	_free_bay(v)
	view.sim.kill(v)


func _free_bay(v: Dictionary) -> void:
	var lot_id: String = str(v.get("lot", ""))
	if lot_id != "" and occ.has(lot_id):
		var o: Array = occ[lot_id]
		var k: int = int(v.get("bay", -1))
		if k >= 0 and k < o.size() and int(o[k]) == int(v["id"]):
			o[k] = 0


## A moving ambient car that has reached its bay is now a parked one.
func _finish_arrivals() -> void:
	for v in view.sim.vehicles:
		if str(v["tag"]) == "ambient" and v.has("dest_lot") and str(v["state"]) == "parked":
			v["lot"] = v["dest_lot"]
			v["bay"] = v["dest_bay"]
			v.erase("dest_lot")
			v["stay_until"] = view.sim.vt + view.rng.randf_range(20.0, 90.0)
			v["dir"] = (v["path"] as VehiclePath).dir_at(float((v["path"] as VehiclePath).length))
		elif str(v["tag"]) == "ambient" and str(v["state"]) != "parked" and (view.beyond_drop(v["pos"]) or float(v["blocked_t"]) > 6.0):
			_cancel(v)                         # out of sight, or stuck behind somebody standing in the way: it simply is not there any more


func _cancel(v: Dictionary) -> void:
	var dl: String = str(v.get("dest_lot", ""))
	if dl != "" and occ.has(dl):
		var o: Array = occ[dl]
		var k: int = int(v.get("dest_bay", -1))
		if k >= 0 and k < o.size() and int(o[k]) == int(v["id"]):
			o[k] = 0
	view.sim.kill(v)


func moving_count() -> int:
	var n: int = 0
	for v in view.sim.vehicles:
		if str(v["tag"]) == "ambient" and str(v["state"]) != "parked":
			n += 1
	return n


## Every sync: lots below their share of parked cars get an arrival; parked cars past their stay leave town or move to another lot near the camera.
func _depart() -> void:
	var amb: Dictionary = view.cfg.get("ambient", {})
	if moving_count() >= int(amb.get("max_moving", 10)):
		return
	var dens: float = maxf(float(amb.get("density_floor", 0.25)), TransportTraffic.density())
	var rate: float = float(amb.get("depart_per_s", 0.35)) * VehicleView.SYNC_EVERY * dens * 3.0
	if view.rng.randf() > rate:
		return
	if view.rng.randf() < 0.5 and _arrive_somewhere():
		return
	var cands: Array = []
	for v in view.sim.vehicles:
		if str(v["tag"]) == "ambient" and str(v["state"]) == "parked" and not v.has("dest_lot") and view.sim.vt >= float(v.get("stay_until", 0.0)) and view.in_range(v["pos"], 0.9):
			cands.append(v)
	if cands.is_empty():
		return
	var v2: Dictionary = cands[view.rng.randi() % cands.size()]
	var dests: Array = []
	for lot_id in _lots_done:
		if str(lot_id) == str(v2["lot"]):
			continue
		var o: Array = _occ(str(lot_id))
		for k in o.size():
			if int(o[k]) == 0:
				dests.append([str(lot_id), k])
	if view.rng.randf() < 0.45 or dests.is_empty():
		_leave(v2)
		return
	var d: Array = dests[view.rng.randi() % dests.size()]
	_send(v2, str(d[0]), int(d[1]))


## A lot that has fewer cars than its share at this hour gets one driving in from up the street.
func _arrive_somewhere() -> bool:
	var h: float = SysUtil.hour_f()
	var lots: Array = _lots_done.keys()
	if lots.is_empty():
		return false
	var lot_id: String = str(lots[view.rng.randi() % lots.size()])
	var bays: Array = _bays(lot_id)
	var o: Array = _occ(lot_id)
	var taken: int = 0
	for k in o.size():
		if int(o[k]) != 0:
			taken += 1
	if float(taken) >= float(bays.size()) * TransportParking.ambient(lot_id, h) - 0.01:
		return false
	for k2 in o.size():
		if int(o[k2]) == 0:
			var fr: Dictionary = VehicleRoads.frontage(lot_id)
			var g: float = float(fr["gate"])
			var bay: Dictionary = bays[k2]
			var up: Dictionary = VehicleRoads.upstream_end(fr)
			var path: VehiclePath = VehiclePath.make([up["pt"], Vector2(g + VehicleRoutes.GATE_LANE, float(fr["lane_z"])), Vector2(g + VehicleRoutes.GATE_LANE, (bay["pos"] as Vector2).y), bay["pos"]], 1.8)
			if not view.in_range(path.at(0.0), 1.0) or not view.sim.spot_free(path.at(0.0), 4.2, 1.8, 2.0):
				return false
			var v: Dictionary = view.sim.add("car", _glb_for_hash(view.rng.randi()), path, {"end": "park", "tag": "ambient", "key": "", "visits": up["visits"]})
			v["dest_lot"] = lot_id
			v["dest_bay"] = k2
			o[k2] = int(v["id"])
			return true
	return false


## The car drives out of its bay, along the lane and out of the picture.
func _leave(v: Dictionary) -> void:
	var fr: Dictionary = VehicleRoads.frontage(str(v["lot"]))
	var bay: Dictionary = _bays(str(v["lot"]))[int(v["bay"])]
	var g: float = float(fr["gate"])
	var down: Dictionary = VehicleRoads.downstream_end(fr)
	var pts: Array = [bay["pos"], Vector2(g - VehicleRoutes.GATE_LANE, (bay["pos"] as Vector2).y), Vector2(g - VehicleRoutes.GATE_LANE, float(fr["lane_z"])), down["pt"]]
	_free_bay(v)
	view.sim.restart(v, VehiclePath.make(pts, 1.8), down["visits"], "dead")


func _send(v: Dictionary, dest_lot: String, dest_bay: int) -> bool:
	var fa: Dictionary = VehicleRoads.frontage(str(v["lot"]))
	var fb: Dictionary = VehicleRoads.frontage(dest_lot)
	var bay_a: Dictionary = _bays(str(v["lot"]))[int(v["bay"])]
	var bay_b: Dictionary = _bays(dest_lot)[dest_bay]
	var r: Dictionary = VehicleRoutes.trip(fa, bay_a["pos"], fb, bay_b["pos"])
	if r.is_empty():
		return false
	_free_bay(v)
	_occ(dest_lot)[dest_bay] = int(v["id"])
	v["dest_lot"] = dest_lot
	v["dest_bay"] = dest_bay
	view.sim.restart(v, r["path"], r["visits"], "park")
	return true
