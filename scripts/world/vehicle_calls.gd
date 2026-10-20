class_name VehicleCalls
extends RefCounted
## Emergency units and crashes of the vehicle layer.
## Units: CityServices.dispatch posts a VehicleFeed entry; at the minute the unit leaves the station it drives (siren, roof bar flashing, lights ignored) to the lot of the
## call, stands there for the time on scene and drives home. The sim's response time already includes the drive; the vehicle is paced to arrive at that minute.
## Crashes: a trip of the players with a crash or a breakdown (Transport.active[..].crash / .breakdown) stops on the road with hazard lights, a second car stands
## ahead of it with hazard lights, and after the delay a tow truck comes for a serious crash or a wreck; a minor one drives on.

var view: VehicleView
var _seen: int = 0
var _units: Array = []                 # scheduled {service, fs, fb, leave, arrive, scene_min, vid, state}
var _crashes: Dictionary = {}          # fid -> {started, other, tow, kind}


func _init(v: VehicleView) -> void:
	view = v
	_seen = VehicleFeed.last_seq()


func reset() -> void:
	_units.clear()
	_crashes.clear()
	_seen = VehicleFeed.last_seq()


func _kind(service: String) -> String:
	return {"fire": "fire", "ambulance": "ambulance", "police": "police"}.get(service, "ambulance")


func sync() -> void:
	for e in VehicleFeed.since(_seen):
		_seen = maxi(_seen, int(e["seq"]))
		if str(e["kind"]) == "dispatch":
			_schedule(e)
	var now: float = view.now_f()
	for u in _units.duplicate():
		if str(u["state"]) == "wait" and now >= float(u["leave"]):
			_launch(u, now)
		elif str(u["state"]) == "wait" and now > float(u["arrive"]) + float(u["scene_min"]) + 60.0:
			_units.erase(u)
		elif str(u["state"]) == "out" and _vehicle(int(u["vid"])).is_empty():
			_units.erase(u)


func _vehicle(id: int) -> Dictionary:
	for v in view.sim.vehicles:
		if int(v["id"]) == id and str(v["state"]) != "dead":
			return v
	return {}


func _schedule(e: Dictionary) -> void:
	var service: String = str(e["service"])
	var st_lot: String = str(CityServices.station(service).get("lot", ""))
	var fs: Dictionary = VehicleRoads.frontage(st_lot)
	var fb: Dictionary = VehicleRoads.frontage(str(e["lot"]))
	if fs.is_empty() or fb.is_empty():
		return
	var arrive: float = float(e["now"]) + float(e["minutes"])
	var leave: float = maxf(arrive - maxf(float(e["drive"]), 0.5), float(e["now"]))
	_units.append({"service": service, "fs": fs, "fb": fb, "leave": leave, "arrive": arrive, "scene_min": float(e["on_scene"]), "vid": -1, "state": "wait"})


func _launch(u: Dictionary, now: float) -> void:
	var r: Dictionary = VehicleRoutes.round_trip(u["fs"], u["fb"])
	if r.is_empty():
		u["state"] = "done"
		_units.erase(u)
		return
	var path: VehiclePath = r["path"]
	var frac: float = clampf((now - float(u["leave"])) / maxf(float(u["arrive"]) - float(u["leave"]), 0.5), 0.0, 1.0)
	var s0: float = float(r["scene_s"]) * frac
	var here := path.at(s0)
	var there := path.at(float(r["scene_s"]))
	if not (view.in_range(here) or view.in_range(there) or view.in_range(path.at(0.0))):
		u["state"] = "done"
		_units.erase(u)
		return
	var hold: float = clampf(float(u["scene_min"]) * view.vt_per_min(), float((view.cfg.get("emergency", {}) as Dictionary).get("hold_s_min", 5.0)), 30.0)
	var v: Dictionary = view.sim.add(_kind(str(u["service"])), "", path, {"s": s0, "end": "dead", "visits": r["visits"], "tag": "unit"})
	v["vanish_ok"] = true                                    # a unit drives out of and back into its station: the garage door is where it starts and ends
	v["glb"] = str((view.cfg.get("kind_glb", {}) as Dictionary).get(str(v["kind"]), "ambulance"))
	v["stops"] = [{"s": float(r["scene_s"]), "hold": true, "until": 0.0, "tag": "scene", "arm": true, "hold_s": hold}]
	(v["lights"] as Dictionary)["siren"] = true
	v["unit_arrive"] = float(u["arrive"])
	v["scene_s"] = float(r["scene_s"])
	u["vid"] = int(v["id"])
	u["state"] = "out"


func tick(_dt: float) -> void:
	var now: float = view.now_f()
	var k: float = view.vt_per_min()
	var maxv: float = float((view.cfg.get("speeds", {}) as Dictionary).get("emergency", 12.0)) * 1.3
	for v in view.sim.vehicles:
		if str(v["tag"]) != "unit":
			continue
		var stops: Array = v["stops"]
		if not stops.is_empty():
			var st: Dictionary = stops[0]
			if bool(st.get("arm", false)) and str(v["state"]) == "dwell":
				st["arm"] = false
				st["hold"] = false
				st["until"] = view.sim.vt + float(st["hold_s"])         # on scene: stand for the time
			var left: float = maxf(float(v["unit_arrive"]) - now, 0.15)
			v["vcap"] = clampf((float(st["s"]) - float(v["s"])) / maxf(left * k, 0.3), 1.5, maxv)
		else:
			v.erase("vcap")
			(v["lights"] as Dictionary)["siren"] = float(v["s"]) < float(v["scene_s"]) + 40.0
	_tick_crashes()


# ------------------------------------------------------------------ crashes
func _tick_crashes() -> void:
	for gone in _crashes.keys():
		if not view.trips.recs.has(gone):
			_crashes.erase(gone)
	var delay: float = float((Transport.sect("crash") as Dictionary).get("delay_min", 25))
	var cc: Dictionary = view.cfg.get("crash", {})
	var now: float = view.now_f()
	for fid in view.trips.recs:
		var rec: Dictionary = view.trips.recs[fid]
		if not rec.has("crash_s") or str(rec["mode"]) == "bus":
			continue
		var v: Dictionary = view.trips._vehicle(rec)
		if v.is_empty():
			continue
		var st: Dictionary = _crashes.get(fid, {})
		if st.is_empty():
			if str(rec["phase"]) == "ride" and str(v["state"]) == "dwell" and not (v["stops"] as Array).is_empty() and str(((v["stops"] as Array)[0] as Dictionary)["tag"]) == "crash":
				_begin_crash(int(fid), rec, v, now)
			continue
		var kind: String = str(st["kind"])
		var tow: Dictionary = view.trips._vehicle({"vid": int(st.get("tow", -1))}) if int(st.get("tow", -1)) >= 0 else {}
		var due_tow: bool = (cc.get("tow_kinds", []) as Array).has(kind)
		if due_tow and not bool(st.get("loaded", false)):
			if not st.has("tow") and now >= float(st["started"]) + float(cc.get("tow_after_min", 8)) * 0.5:
				_send_tow(st, rec, v)
				tow = view.trips._vehicle({"vid": int(st.get("tow", -1))})
			if not tow.is_empty() and str(tow["state"]) == "dwell" and not st.has("load_at"):
				st["load_at"] = now
			if st.has("load_at") and now >= float(st["load_at"]) + 1.0:
				v["hidden"] = true                                              # on the flat bed
				st["loaded"] = true
				var ts: Array = tow["stops"]
				if not ts.is_empty():
					(ts[0] as Dictionary)["hold"] = false
				_release_other(st)
				_release(rec, v)
		elif not due_tow and now >= float(st["started"]) + minf(delay, 12.0):
			_release_other(st)
			_release(rec, v)
			st["loaded"] = true


func _begin_crash(fid: int, rec: Dictionary, v: Dictionary, now: float) -> void:
	var cc: Dictionary = view.cfg.get("crash", {})
	var path: VehiclePath = v["path"]
	var s_o: float = float(v["s"]) + float(cc.get("other_gap", 5.6))
	var kind: String = str(rec["crash"]) if str(rec["crash"]) != "" else "breakdown"
	var st: Dictionary = {"started": now, "kind": kind}
	(v["lights"] as Dictionary)["hazard"] = true
	if kind != "breakdown" and s_o < path.length - 6.0:
		var amb: Array = (view.cfg.get("models", {}) as Dictionary).get("ambient", ["car_sedan_blue"])
		var o: Dictionary = view.sim.add("car", str(amb[fid % amb.size()]), path, {"s": s_o, "end": "dead", "tag": "other", "ignore_signals": true})
		o["stops"] = [{"s": s_o + 0.2, "hold": true, "tag": "crash_other"}]
		(o["lights"] as Dictionary)["hazard"] = true
		st["other"] = int(o["id"])
	_crashes[fid] = st


func _send_tow(st: Dictionary, rec: Dictionary, v: Dictionary) -> void:
	var path: VehiclePath = v["path"]
	var s_crash: float = float(v["s"])
	var s0: float = maxf(s_crash - 48.0, 0.0)
	var tow: Dictionary = view.sim.add("tow", "tow_truck", path, {"s": s0, "end": "dead", "tag": "other", "ignore_signals": true})
	var stop_s: float = s_crash - (float(v["len"]) + float(tow["len"])) * 0.5 - 1.2
	if stop_s <= s0 + 2.0:
		view.sim.kill(tow)
		return
	tow["stops"] = [{"s": stop_s, "hold": true, "tag": "tow_hook"}]
	(tow["lights"] as Dictionary)["amber"] = true
	(tow["lights"] as Dictionary)["hazard"] = true
	st["tow"] = int(tow["id"])


func _release_other(st: Dictionary) -> void:
	var o: Dictionary = view.trips._vehicle({"vid": int(st.get("other", -1))}) if int(st.get("other", -1)) >= 0 else {}
	if not o.is_empty():
		(o["lights"] as Dictionary)["hazard"] = false
		for s in o["stops"]:
			(s as Dictionary)["hold"] = false


func _release(rec: Dictionary, v: Dictionary) -> void:
	(v["lights"] as Dictionary)["hazard"] = false
	var stops: Array = v["stops"]
	if not stops.is_empty() and str((stops[0] as Dictionary)["tag"]) == "crash":
		(stops[0] as Dictionary)["hold"] = false
	rec.erase("crash_s")
