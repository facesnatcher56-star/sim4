class_name VehicleTrips
extends RefCounted
## The players' trips (Transport.active: car, taxi, bike) as vehicles you can see. The sim has already decided the way, the cost and the minute of arrival;
## this only DRAWS it: the vehicle waits at the kerb in front of the gate, the folk walks to its door and gets in (the folk is hidden while riding), the
## vehicle drives the lane route paced to arrive at the sim's minute, stops at the other kerb and the folk gets out at the door. Bus riders wait at the
## marked stop and board the timetable bus (VehicleBuses). No sim writes.
##   recs[fid] = {fid, mode, phase (wait|ride|done), vid, door_a, door_d, ...}      is_riding(fid)      release_all()

const FolkHide := "in_vehicle"

var view: VehicleView
var recs: Dictionary = {}


func _init(v: VehicleView) -> void:
	view = v


func reset() -> void:
	release_all()
	recs.clear()


func is_riding(fid: int) -> bool:
	return recs.has(fid) and str(recs[fid]["phase"]) == "ride"


func release_all() -> void:
	for fid in recs.keys():
		_show(int(fid), Vector2.ZERO, false)
	recs.clear()


# ------------------------------------------------------------------ folk nodes
func _fv(fid: int) -> Node:
	if view.lot_view != null and view.lot_view.has_method("get_folk_view"):
		return view.lot_view.get_folk_view(fid)
	return null


func _hide(fid: int) -> void:
	var fv: Node = _fv(fid)
	if fv != null:
		fv.set_meta(FolkHide, true)
		if fv.has_meta("vehicle_goto"):
			fv.remove_meta("vehicle_goto")


## The folk steps out at `at` (world x, z); ZERO leaves it where its own walk is.
func _show(fid: int, at: Vector2, place: bool) -> void:
	var fv: Node = _fv(fid)
	if fv == null:
		return
	if fv.has_meta(FolkHide):
		fv.remove_meta(FolkHide)
	if fv.has_meta("vehicle_goto"):
		fv.remove_meta("vehicle_goto")
	if place and at != Vector2.ZERO:
		(fv as Node3D).position = Vector3(at.x, 0.0, at.y)
		fv.call("vehicle_landed")


func _goto(fid: int, door: Vector2) -> void:
	var fv: Node = _fv(fid)
	if fv != null:
		fv.set_meta("vehicle_goto", Vector2i(int(floorf(door.x)), int(floorf(door.y))))


func rider_pos(fid: int) -> Vector2:
	var fv: Node = _fv(fid)
	if fv != null:
		return Vector2((fv as Node3D).position.x, (fv as Node3D).position.z)
	var f = SysUtil.folk(fid)
	return Vector2(float(f.tile.x) + 0.5, float(f.tile.y) + 0.5) if f != null else Vector2.ZERO


# ------------------------------------------------------------------ discovery
func sync() -> void:
	var now: int = SysUtil.now()
	for key in Transport.active.keys():
		var p: Dictionary = Transport.active[key]
		var fid: int = int(key)
		var mode: String = str(p.get("mode", ""))
		if recs.has(fid):
			if int((recs[fid] as Dictionary)["start"]) == int(p["start_min"]):
				continue
			_abort(fid)
		if mode != "car" and mode != "taxi" and mode != "bike" and mode != "bus":
			continue
		if now - int(p["start_min"]) > 3:
			continue
		_begin(fid, p, mode)
	for fid2 in recs.keys():
		var r: Dictionary = recs[fid2]
		if str(r["phase"]) == "done" and not Transport.active.has(str(fid2)):
			recs.erase(fid2)


func _begin(fid: int, p: Dictionary, mode: String) -> void:
	var f = SysUtil.folk(fid)
	if f == null:
		return
	var from_lot: String = NeighborhoodLots.lot_at(f.tile)
	var to_lot: String = str(p.get("to_lot", ""))
	if from_lot == "" or to_lot == "" or from_lot == to_lot:
		return
	var fa: Dictionary = VehicleRoads.frontage(from_lot)
	var fb: Dictionary = VehicleRoads.frontage(to_lot)
	if fa.is_empty() or fb.is_empty():
		return
	var rec: Dictionary = {"fid": fid, "mode": mode, "phase": "wait", "start": int(p["start_min"]), "arrive": int(p["arrive_min"]), "from": from_lot, "to": to_lot,
		"vid": -1, "t0": view.sim.vt, "crash": str(p.get("crash", "")), "breakdown": bool(p.get("breakdown", false)), "car": int(p.get("car", -1)), "route": str(p.get("route", ""))}
	if mode == "bus":
		if not view.buses.board_info(rec, fa, fb):
			return
		if not (view.in_range(rec["door_a"]) or view.in_range(rec["door_d"])):
			return
		recs[fid] = rec
		_goto(fid, rec["door_a"])
		return
	var built: Dictionary = _vehicle_for(rec, fa, fb)
	if built.is_empty():
		return
	if not (view.in_range(rec["door_a"]) or view.in_range(rec["door_d"])):
		view.sim.kill(built["v"])
		return
	recs[fid] = rec
	_goto(fid, rec["door_a"])


func _vehicle_for(rec: Dictionary, fa: Dictionary, fb: Dictionary) -> Dictionary:
	var mode: String = str(rec["mode"])
	var sim: VehicleSim = view.sim
	var r: Dictionary
	var v: Dictionary = {}
	var ga: float = float(fa["gate"])
	if mode == "bike":
		var sr: Dictionary = VehicleRoads.sidewalk_route(fa, ga, fb, float(fb["gate"]) + 1.0, float(view.cfg.get("sidewalk_lane", 2.5)))
		var pts: Array = [Vector2(ga, float(fa["hy"]) + 0.5)]
		pts.append_array(sr["pts"])
		var path: VehiclePath = VehiclePath.make(pts, 1.2)
		r = {"path": path, "visits": [], "pickup_s": 0.0, "drop_s": path.length - 0.05, "pickup_door": Vector2(ga, float(fa["hy"]) + 0.5),
			"drop_door": Vector2(float(fb["gate"]) + 1.0, float(fb["hy"]) + 0.5)}
		v = sim.add("bike", "bike", path, {"end": "dead", "ignore_signals": true, "color": _shirt(int(rec["fid"]))})
	else:
		var bay_pos := Vector2.ZERO
		var dest_pos := Vector2.ZERO
		var dest_bay: int = -1
		var kind: String = "car"
		var glb: String = "taxi"
		var existing: Dictionary = {}
		var pre: Dictionary = {}
		var post: Dictionary = {}
		if mode == "car":
			existing = sim.by_key("car:%d" % int(rec["car"]))
			var c: Dictionary = Transport.car(int(rec["car"]))
			glb = view.ambient.owner_glb(c) if not c.is_empty() else "car_hatchback_red"
			if not existing.is_empty() and str(existing["state"]) == "parked":
				bay_pos = existing["pos"]
			var free: int = _free_bay(str(rec["to"]))
			if free >= 0:
				dest_bay = free
				dest_pos = (VehicleBays.of(str(rec["to"]))[free] as Dictionary)["pos"]
		else:
			kind = "taxi"
			pre = _drive_in(fa)                                  # the taxi comes from a road end of the map and leaves by one: it never starts or ends on the picture
		if dest_bay < 0:
			post = _drive_out(fb)
		r = VehicleRoutes.trip(fa, bay_pos, fb, dest_pos, 0.0, pre, post)
		if r.is_empty():
			return {}
		var path2: VehiclePath = r["path"]
		if existing.is_empty():
			v = sim.add(kind, glb, path2, {"end": "park" if dest_bay >= 0 else "dead", "key": "car:%d" % int(rec["car"]) if mode == "car" else ""})
			v["gate_yield"] = r["gate_yield"]
		else:
			v = existing
			sim.restart(v, path2, r["visits"], "park" if dest_bay >= 0 else "dead", r["gate_yield"])
		if dest_bay >= 0:
			view.ambient._occ(str(rec["to"]))[dest_bay] = int(v["id"])
			v["dest_lot"] = str(rec["to"])
			v["dest_bay"] = dest_bay
		v["tag"] = "trip"
	v["tag"] = "trip"
	var stops: Array = [{"s": float(r["pickup_s"]), "hold": true, "tag": "board"}]
	if str(rec["crash"]) != "" or bool(rec["breakdown"]):
		var s_c: float = float(r["pickup_s"]) + (float(r["drop_s"]) - float(r["pickup_s"])) * float((view.cfg.get("crash", {}) as Dictionary).get("at", 0.55))
		stops.append({"s": s_c, "hold": true, "tag": "crash"})
		rec["crash_s"] = s_c
	stops.append({"s": float(r["drop_s"]), "hold": true, "tag": "alight"})
	v["stops"] = stops
	sim.attach_visits(v, r["visits"])
	rec["vid"] = int(v["id"])
	rec["door_a"] = r["pickup_door"]
	rec["door_d"] = r["drop_door"]
	rec["path"] = r["path"]
	return {"v": v, "r": r}


## From the nearest road end of the map to the lane in front of `fa` (empty if none).
func _drive_in(fa: Dictionary) -> Dictionary:
	var lane: float = float(view.cfg.get("lane", 1.0))
	var best: Dictionary = {}
	var best_len: float = 1.0e9
	for e in VehicleRoads.edge_ends():
		var rt: Dictionary = VehicleRoads.entry_route(e, fa, float(fa["gate"]) + 2.0, lane)
		if rt.is_empty():
			continue
		var l: float = 0.0
		var pp: Array = rt["pts"]
		for k in range(1, pp.size()):
			l += (pp[k] as Vector2).distance_to(pp[k - 1])
		if l < best_len:
			best_len = l
			best = rt
	return best


## From the lane in front of `fb` to the nearest road end of the map.
func _drive_out(fb: Dictionary) -> Dictionary:
	var lane: float = float(view.cfg.get("lane", 1.0))
	var e: Dictionary = VehicleRoads.nearest_end(fb, lane)
	return VehicleRoads.exit_route(fb, float(fb["gate"]) - 1.5, e, lane) if not e.is_empty() else {}


func _free_bay(lot_id: String) -> int:
	var o: Array = view.ambient._occ(lot_id)
	for k in o.size():
		if int(o[k]) == 0:
			return k
	return -1


func _shirt(fid: int) -> String:
	var c: Color = UIU.folk_colors.get(fid, Color("#3d85c6"))
	return "#" + c.to_html(false)


func _vehicle(rec: Dictionary) -> Dictionary:
	for v in view.sim.vehicles:
		if int(v["id"]) == int(rec["vid"]) and str(v["state"]) != "dead":
			return v
	return {}


func _abort(fid: int) -> void:
	var rec: Dictionary = recs[fid]
	_show(fid, Vector2.ZERO, false)
	var v: Dictionary = _vehicle(rec)
	if not v.is_empty():
		for st in v["stops"]:
			(st as Dictionary)["hold"] = false
	recs.erase(fid)


# ------------------------------------------------------------------ per frame
func tick(_dt: float) -> void:
	var now: float = view.now_f()
	var k: float = view.vt_per_min()
	var maxv: float = float((view.cfg.get("speeds", {}) as Dictionary).get("ride_max", 11.5))
	var creep: float = float((view.cfg.get("speeds", {}) as Dictionary).get("creep", 1.6))
	var reach: float = float((view.cfg.get("boarding", {}) as Dictionary).get("door_reach", 2.6))
	for fid in recs.keys():
		var rec: Dictionary = recs[fid]
		if str(rec["mode"]) == "bus":
			_tick_bus(rec, now)
			continue
		var v: Dictionary = _vehicle(rec)
		if v.is_empty():
			if str(rec["phase"]) != "done":
				_show(int(fid), Vector2.ZERO, false)
				rec["phase"] = "done"
			continue
		if str(rec["phase"]) == "wait":
			var near: bool = rider_pos(int(fid)).distance_to(rec["door_a"]) <= reach
			var ready: bool = str(v["state"]) == "dwell"
			if ready and (near or view.sim.vt - float(rec["t0"]) > 10.0):
				_hide(int(fid))
				rec["phase"] = "ride"
				rec["board_vt"] = view.sim.vt
				if not (v["stops"] as Array).is_empty():
					((v["stops"] as Array)[0] as Dictionary)["hold"] = false
		elif str(rec["phase"]) == "ride":
			var stops: Array = v["stops"]
			var next_s: float = float((stops[0] as Dictionary)["s"]) if not stops.is_empty() else (v["path"] as VehiclePath).length
			var left_min: float = maxf(float(rec["arrive"]) - now - 0.3, 0.2)
			var cap: float = (next_s - float(v["s"])) / maxf(left_min * k, 0.4)
			v["vcap"] = clampf(cap, creep, maxv)
			var at_stop: bool = str(v["state"]) == "dwell" and not stops.is_empty() and str((stops[0] as Dictionary)["tag"]) == "alight"
			if at_stop or view.sim.vt - float(rec.get("board_vt", 0.0)) > 60.0:
				_alight(int(fid), rec, v)
		elif str(rec["phase"]) == "alight":
			if str(v["state"]) != "dwell":
				rec["phase"] = "done"


func _alight(fid: int, rec: Dictionary, v: Dictionary) -> void:
	_show(fid, rec["door_d"], true)
	rec["phase"] = "alight"
	var stops: Array = v["stops"]
	if not stops.is_empty() and str((stops[0] as Dictionary)["tag"]) == "alight":
		var st: Dictionary = stops[0]
		st["hold"] = false
		st["until"] = view.sim.vt + 1.3
	v.erase("vcap")
	if str(rec["mode"]) == "bike":
		rec["phase"] = "done"
		# the bike is not killed: it ends its path where the rider got off and stays there until the picture has moved on (VehicleSim end_hold)


func _tick_bus(rec: Dictionary, now: float) -> void:
	var fid: int = int(rec["fid"])
	match str(rec["phase"]):
		"wait":
			var board_min: float = float(rec["start"]) + float(rec["wait"])
			if now >= board_min or view.sim.vt - float(rec["t0"]) > 40.0:
				if rider_pos(fid).distance_to(rec["door_a"]) <= 3.5 or now >= board_min + 1.0:
					_hide(fid)
					rec["phase"] = "ride"
		"ride":
			var off_min: float = float(rec["arrive"]) - float(rec["walk_min"])
			if now >= off_min:
				_show(fid, rec["door_d"], true)
				rec["phase"] = "done"
