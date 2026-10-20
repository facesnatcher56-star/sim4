class_name VehicleAmbient
extends RefCounted
## Parked and passing cars of the vehicle layer: the cars that stand in the bays of the lots near a focus (how many follows TransportParking.ambient for the hour),
## the players' own cars at their lots, and a trickle of cars that leave one lot and park at another, driving the right lane and stopping at red lights.
## The population of a lot is a function of (lot, bay, day) so it is the same every time you look. Task 37: EVERY lot is populated once (a car never pops in as the camera
## pans), cars arrive from the map edge through the street lattice and leave towards it, only off the picture; the driver of a car that has parked gets out and walks
## away up the path, and somebody walks down to a parked car before it leaves (VehicleWalkers). Cause: a parked car is somebody's way to a place.

var view: VehicleView
var occ: Dictionary = {}              # lot id -> Array (bay index -> vehicle id, 0 = free)
var _lots_done: Dictionary = {}       # lot id -> true while populated
var _exits: Dictionary = {}           # lot id -> the road end its leaving cars drive to


func _init(v: VehicleView) -> void:
	view = v


func reset() -> void:
	occ.clear()
	_lots_done.clear()
	_exits.clear()


func _lots() -> Array:
	return Neighborhood.lot_ids() if Workplace.map_ready() else []


func _glb_for_hash(h: int) -> String:
	var amb: Array = (view.cfg.get("models", {}) as Dictionary).get("ambient", ["car_sedan_red"])
	return str(amb[absi(h) % amb.size()])


func owner_glb(c: Dictionary) -> String:
	var m: Dictionary = (view.cfg.get("models", {}) as Dictionary).get(str(c.get("model", "hatch")), {"glb": "car_hatchback", "paint": ["red"]})
	var paints: Array = m.get("paint", ["red"])
	return "%s_%s" % [str(m.get("glb", "car_hatchback")), str(paints[int(c.get("id", 0)) % paints.size()])]


const BAY_CLEAR_S := 4.5

func sync() -> void:
	_release_bays()
	for lot_id in _lots():
		if not _lots_done.has(lot_id) and not VehicleRoads.frontage(str(lot_id)).is_empty():
			_populate(str(lot_id))
	_finish_arrivals()
	_depart()


## A bay a car has driven out of (4.5 m along its way) can take the next car.
func _release_bays() -> void:
	for v in view.sim.vehicles:
		if v.has("bay_free_s") and (float(v["s"]) > float(v["bay_free_s"]) or str(v["state"]) == "dead"):
			v.erase("bay_free_s")
			_free_bay(v)


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


## A moving ambient car that has reached its bay is now a parked one; its driver gets out and walks away to the lot.
func _finish_arrivals() -> void:
	for v in view.sim.vehicles:
		if str(v["tag"]) == "ambient" and v.has("dest_lot") and str(v["state"]) == "parked":
			v["lot"] = v["dest_lot"]
			v["bay"] = v["dest_bay"]
			v.erase("dest_lot")
			v["stay_until"] = view.sim.vt + view.rng.randf_range(20.0, 90.0)
			v["dir"] = (v["path"] as VehiclePath).dir_at(float((v["path"] as VehiclePath).length))
			var fr: Dictionary = VehicleRoads.frontage(str(v["lot"]))
			if not fr.is_empty():
				view.walkers.add((v["pos"] as Vector2) + Vector2(0, -1.2), door_of(fr), int(v["id"]) * 7)


## The front yard of a lot (bays, gate): one car moves about in it at a time.
static func yard_rect(fr: Dictionary) -> Rect2:
	var rc: Rect2i = fr["rc"]
	return Rect2(float(rc.position.x), float(rc.end.y) - 6.0, float(rc.size.x), 6.5)


## Where an arriving car waits on the lane (just before it turns in) while the yard is busy.
static func yard_entry(fr: Dictionary, path: VehiclePath) -> Dictionary:
	var s_turn: float = path.closest_s(Vector2(float(fr["gate"]) + VehicleRoutes.GATE_LANE, float(fr["lane_z"])), maxf(path.length - 32.0, 0.0), 40.0)
	return {"s": maxf(s_turn - 3.0, 0.5), "rect": yard_rect(fr)}


func door_of(fr: Dictionary) -> Vector2:
	return Vector2(float(fr["gate"]), float(fr["hy"]) - 9.0)


func moving_count() -> int:
	var n: int = 0
	for v in view.sim.vehicles:
		if str(v["tag"]) == "ambient" and str(v["state"]) != "parked":
			n += 1
	return n


## Every sync: lots below their share of parked cars get an arrival from the map edge; parked cars past their stay leave town or move to another lot.
## Whoever leaves is fetched by a walker first (VehicleWalkers), then the car pulls out.
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
		if str(v["tag"]) == "ambient" and str(v["state"]) == "parked" and not v.has("dest_lot") and not v.has("leaving") and view.sim.vt >= float(v.get("stay_until", 0.0)) and view.in_range(v["pos"], 1.0):
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
		_begin_departure(v2, "", -1)
		return
	var d: Array = dests[view.rng.randi() % dests.size()]
	_begin_departure(v2, str(d[0]), int(d[1]))


## The driver walks down from the lot to the parked car; the car goes when the walker has arrived.
func _begin_departure(v: Dictionary, dest_lot: String, dest_bay: int) -> void:
	var fr: Dictionary = VehicleRoads.frontage(str(v["lot"]))
	var bay: Dictionary = _bays(str(v["lot"]))[int(v["bay"])]
	v["leaving"] = true
	v["plan_lot"] = dest_lot
	if dest_lot != "":
		_occ(dest_lot)[dest_bay] = int(v["id"])
		v["plan_bay"] = dest_bay
	view.walkers.add(door_of(fr), (bay["pos"] as Vector2) + Vector2(0, -1.2), int(v["id"]) * 5, Callable(self, "_depart_now").bind(v))


func _depart_now(v: Dictionary) -> void:
	if str(v["state"]) != "parked" or not v.has("leaving"):
		return
	v.erase("leaving")
	var dl: String = str(v.get("plan_lot", ""))
	var db: int = int(v.get("plan_bay", -1))
	v.erase("plan_lot")
	v.erase("plan_bay")
	if dl != "":
		if _send(v, dl, db):
			return
		_occ(dl)[db] = 0
	_leave(v)


## A lot that has fewer cars than its share at this hour gets one driving in from a road end of the map (only when that end is off the picture).
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
			return drive_in(view.filler.pick_end(view.rng.randf()), lot_id, k2, 0.0, _glb_for_hash(view.rng.randi()))
	return false


## A car from road end `end` to bay `k` of `lot_id`, `s0` tiles into its way. Never appears on the picture (except while the layer is being filled in).
func drive_in(end: Dictionary, lot_id: String, k: int, s0: float, glb: String) -> bool:
	var fr: Dictionary = VehicleRoads.frontage(lot_id)
	var bay: Dictionary = _bays(lot_id)[k]
	var g: float = float(fr["gate"])
	var r: Dictionary = VehicleRoads.entry_route(end, fr, g + VehicleRoutes.GATE_LANE, float(view.cfg.get("lane", 1.0)))
	if r.is_empty():
		return false
	var pts: Array = (r["pts"] as Array).duplicate()
	pts.append(Vector2(g + VehicleRoutes.GATE_LANE, (bay["pos"] as Vector2).y))
	pts.append(bay["pos"])
	var path: VehiclePath = VehiclePath.make(pts, 1.8)
	s0 = minf(s0, path.length - 8.0)
	var p0: Vector2 = path.at(s0)
	if not view.seeding and view.on_screen(p0, 8.0):
		return false
	if not view.sim.spot_free(p0, 4.2, 1.8, 2.0):
		return false
	var v: Dictionary = view.sim.add("car", glb, path, {"end": "park", "tag": "ambient", "key": "", "visits": r["visits"], "s": s0})
	v["yard"] = yard_entry(fr, path)
	v["dest_lot"] = lot_id
	v["dest_bay"] = k
	v["from_edge"] = true
	_occ(lot_id)[k] = int(v["id"])
	return true


## The car drives out of its bay, along the lane, through the streets to the nearest road end of the map and out of it.
func _leave(v: Dictionary) -> void:
	var lot_id: String = str(v["lot"])
	var fr: Dictionary = VehicleRoads.frontage(lot_id)
	var bay: Dictionary = _bays(lot_id)[int(v["bay"])]
	var g: float = float(fr["gate"])
	if not _exits.has(lot_id):
		_exits[lot_id] = VehicleRoads.nearest_end(fr, float(view.cfg.get("lane", 1.0)))
	var r: Dictionary = VehicleRoads.exit_route(fr, g - VehicleRoutes.GATE_LANE, _exits[lot_id], float(view.cfg.get("lane", 1.0)))
	var pts: Array = [bay["pos"], Vector2(g - VehicleRoutes.GATE_LANE, (bay["pos"] as Vector2).y)]
	pts.append_array(r["pts"])
	v["bay_free_s"] = BAY_CLEAR_S                          # the bay is only free for the next car once this one has really driven out of it
	var lp: VehiclePath = VehiclePath.make(pts, 1.8)
	var gyl: Dictionary = {"s": 0.3, "x": g, "z": float(fr["lane_z"]), "hy": float(fr["hy"]), "rect": yard_rect(fr)}
	view.sim.restart(v, lp, r["visits"], "dead", gyl)


func _send(v: Dictionary, dest_lot: String, dest_bay: int) -> bool:
	var fa: Dictionary = VehicleRoads.frontage(str(v["lot"]))
	var fb: Dictionary = VehicleRoads.frontage(dest_lot)
	var bay_a: Dictionary = _bays(str(v["lot"]))[int(v["bay"])]
	var bay_b: Dictionary = _bays(dest_lot)[dest_bay]
	var r: Dictionary = VehicleRoutes.trip(fa, bay_a["pos"], fb, bay_b["pos"])
	if r.is_empty():
		return false
	v["bay_free_s"] = BAY_CLEAR_S
	_occ(dest_lot)[dest_bay] = int(v["id"])
	v["dest_lot"] = dest_lot
	v["dest_bay"] = dest_bay
	view.sim.restart(v, r["path"], r["visits"], "park", r["gate_yield"])
	v["yard"] = yard_entry(fb, r["path"])
	return true
