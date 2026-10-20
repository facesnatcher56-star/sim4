class_name VehicleBuses
extends RefCounted
## Bus bodies for the timetable of TransportBus (which is a pure function of the game minute: "no bus is a body in the world"). A bus of route r leaves its first
## stop at offset + n x headway and calls at stop i at the minute the timetable says; here it is drawn driving the lane route between the stop kerbs, standing at
## every marked stop for the dwell time. A bus exists only while it is near a focus. Riders of the players' bus trips wait at the shelter and board (VehicleTrips).
##   board_info(rec, fa, fb) fills the rider record: wait, doors, walk      geometry(route_id) -> {path, stop_s, arr, total, lots}

var view: VehicleView
var _geo: Dictionary = {}


func _init(v: VehicleView) -> void:
	view = v


func reset() -> void:
	_geo.clear()


func _bx() -> float:
	return float((view.cfg.get("bus_stop", {}) as Dictionary).get("bus_x_from_gate", 8.5))


func _dwell() -> float:
	return float((view.cfg.get("bus_stop", {}) as Dictionary).get("dwell_min", 0.5))


func geometry(rid: String) -> Dictionary:
	if _geo.has(rid):
		return _geo[rid]
	var r: Dictionary = TransportBus.route(rid)
	var g: Dictionary = {}
	if not r.is_empty():
		var stops: Array = r["stops"]
		var fr: Array = []
		var ok: bool = true
		for lot_id in stops:
			var f: Dictionary = VehicleRoads.frontage(str(lot_id))
			ok = ok and not f.is_empty()
			fr.append(f)
		if ok and fr.size() >= 2:
			var lane: float = float(view.cfg.get("lane", 1.0))
			var first := Vector2(float(fr[0]["gate"]) + _bx(), float(fr[0]["lane_z"]))
			# the bus comes in from the nearest road end of the map to its first stop and, after the last stop, drives out of the map by the nearest road end
			var entry: Dictionary = _best_entry(fr[0], first.x, lane)
			var pts: Array = []
			var visits: Array = []
			if not entry.is_empty():
				pts.append_array(entry["pts"])
				visits.append_array(entry["visits"])
			else:
				pts.append(first)
			for i in range(fr.size() - 1):
				var leg: Dictionary = VehicleRoads.lane_route(fr[i], float(fr[i]["gate"]) + _bx(), fr[i + 1], float(fr[i + 1]["gate"]) + _bx(), lane)
				var lp: Array = leg["pts"]
				for k in range(1, lp.size()):
					pts.append(lp[k])
				visits.append_array(leg["visits"])
			var last: int = fr.size() - 1
			var end_x: float = float(fr[last]["gate"]) + _bx()
			var ex_end: Dictionary = VehicleRoads.nearest_end(fr[last], lane)
			var ex: Dictionary = VehicleRoads.exit_route(fr[last], end_x, ex_end, lane) if not ex_end.is_empty() else {}
			if not ex.is_empty():
				var ep: Array = ex["pts"]
				for k2 in range(1, ep.size()):
					pts.append(ep[k2])
				visits.append_array(ex["visits"])
			var path: VehiclePath = VehiclePath.make(pts, 2.9)
			var stop_s: Array = []
			var from_s: float = 0.0
			for i2 in fr.size():
				var s: float = path.closest_s(Vector2(float(fr[i2]["gate"]) + _bx(), float(fr[i2]["lane_z"])), from_s, 260.0)
				stop_s.append(s)
				from_s = s + 2.0
			var arr: Array = []
			for i3 in fr.size():
				arr.append(TransportBus.offset_at(r, i3) - float(r.get("offset", 0)))
			g = {"path": path, "stop_s": stop_s, "arr": arr, "total": float(arr[arr.size() - 1]) + _dwell(), "lots": stops, "offset": float(r.get("offset", 0)), "visits": visits,
				"entry_s": float(stop_s[0])}
	_geo[rid] = g
	return g


func _best_entry(f0: Dictionary, end_x: float, lane: float) -> Dictionary:
	var best: Dictionary = {}
	var best_len: float = 1.0e9
	for e in VehicleRoads.edge_ends():
		var rt: Dictionary = VehicleRoads.entry_route(e, f0, end_x, lane)
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


## Where along the path the timetable puts the bus `u` minutes after it left its first stop.
func target_s(g: Dictionary, u: float) -> float:
	var arr: Array = g["arr"]
	var ss: Array = g["stop_s"]
	var dw: float = _dwell()
	if u <= float(arr[0]):
		return float(ss[0])
	for i in range(arr.size()):
		var a: float = float(arr[i])
		if u < a + dw:
			return float(ss[i])
		if i + 1 < arr.size() and u < float(arr[i + 1]):
			var f: float = (u - a - dw) / maxf(float(arr[i + 1]) - a - dw, 0.01)
			return lerpf(float(ss[i]), float(ss[i + 1]), clampf(f, 0.0, 1.0))
	return (g["path"] as VehiclePath).length


func sync() -> void:
	var now: float = view.now_f()
	var vmax: float = float((view.cfg.get("speeds", {}) as Dictionary).get("bus", 6.5))
	for r in TransportBus.routes():
		var rid: String = str(r["id"])
		var g: Dictionary = geometry(rid)
		if g.is_empty():
			continue
		# a run is on the road from `lead` minutes before it leaves its first stop (the drive in from the map edge) until the end of its way
		var lead: float = float(g["entry_s"]) / maxf(vmax * view.vt_per_min(), 0.3)
		var from_t: int = int(floor(now - float(g["total"]))) - 1
		for d_time in TransportBus.departures(r, from_t, int(floor(now + lead)) + 1):
			var u: float = now - float(d_time)
			var s_t: float = target_s(g, u) if u >= 0.0 else 0.0
			var path: VehiclePath = g["path"]
			var p: Vector2 = path.at(s_t)
			if _has_run(rid, float(d_time)) or _count() >= int((view.cfg.get("bus_stop", {}) as Dictionary).get("max_buses", 8)):
				continue
			if u < -lead:
				continue
			if not view.seeding and view.on_screen(p, 8.0):
				continue                                      # never appears on the picture: it starts when its start is off screen
			if not view.sim.spot_free(p, 8.4, 2.0):
				continue
			var v: Dictionary = view.sim.add("bus", "bus", path, {"s": s_t, "end": "dead", "tag": "bus", "visits": g["visits"]})
			v["bus_rid"] = rid
			v["bus_d"] = float(d_time)


func _count() -> int:
	var n: int = 0
	for v in view.sim.vehicles:
		if str(v["tag"]) == "bus":
			n += 1
	return n


func _has_run(rid: String, d_time: float) -> bool:
	for v in view.sim.vehicles:
		if str(v["tag"]) == "bus" and str(v["bus_rid"]) == rid and absf(float(v["bus_d"]) - d_time) < 0.5:
			return true
	return false


## Pace every bus to the timetable.
func tick(_dt: float) -> void:
	var now: float = view.now_f()
	for v in view.sim.vehicles:
		if str(v["tag"]) != "bus":
			continue
		var g: Dictionary = geometry(str(v["bus_rid"]))
		if g.is_empty():
			view.sim.kill(v)
			continue
		var s_t: float = target_s(g, now - float(v["bus_d"]))
		var ahead: float = s_t - float(v["s"])
		v["vcap"] = clampf(ahead / 0.45, 0.0, float(v["vmax"]) * 1.35)
		if ahead < 0.5 and view.sim._in_box(v["pos"]):
			v.erase("vcap")                                  # never stand in a junction waiting for the timetable


func board_info(rec: Dictionary, fa: Dictionary, fb: Dictionary) -> bool:
	var p: Dictionary = TransportBus.plan(str(rec["from"]), str(rec["to"]), int(rec["start"]))
	if not bool(p.get("ok", false)):
		return false
	var off: float = float((view.cfg.get("bus_stop", {}) as Dictionary).get("x_from_gate", 6.0))
	rec["wait"] = float(p["wait"])
	rec["walk_min"] = float(p["walk"]) * 0.5
	rec["door_a"] = Vector2(float(fa["gate"]) + off, float(fa["hy"]) + 0.5)
	rec["door_d"] = Vector2(float(fb["gate"]) + off, float(fb["hy"]) + 0.5)
	return true
