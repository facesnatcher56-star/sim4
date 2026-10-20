class_name VehicleFiller
extends RefCounted
## Filler traffic of the vehicle layer (task 37, VIEW ONLY): cars that come in from a road end of the map, drive through the streets and leave at another end, or drive to a
## business car park, stay a while and leave. Cause: a town has through traffic and customers, so the roads are never empty by day and nearly empty at night.
## The schedule is a pure function of (world seed, game minute): the same minute of the same game always brings the same cars (no sim rng, no frame dice). How many per hour
## follows the hour, the day of the week and the road (more on the main road); at game speed 2 and 3 fewer cars start per game minute, because a car crosses the map in the
## same real time, so the picture holds about as many cars at every speed. A car appears only off the picture (outside the map edge) and leaves the same way.
##   filler.sync()      filler.rate_per_hour(hour, weekday) -> cars per hour      filler.pick_end(u) -> road end      filler.stats

var view: VehicleView
var stats: Dictionary = {"spawned": 0, "through": 0, "to_lot": 0, "deferred": 0, "dropped": 0, "full": 0, "no_route": 0, "gone": 0, "on_screen": 0, "blocked": 0}
var _done_min: int = -1
var _pending: Array = []
var _routes: Dictionary = {}
var _ends: Array = []
var _weights: Array = []
var _wsum: float = 0.0


func _init(v: VehicleView) -> void:
	view = v


func reset() -> void:
	_done_min = -1
	_pending.clear()
	_routes.clear()
	_ends.clear()


func cfg() -> Dictionary:
	return view.cfg.get("filler", {})


static func h01(key: String) -> float:
	return VehicleControl.mix01(key)


func _ensure_ends() -> void:
	if not _ends.is_empty():
		return
	_ends = VehicleRoads.edge_ends()
	_wsum = 0.0
	_weights.clear()
	var mw: float = float(cfg().get("main_weight", 3.0))
	for e in _ends:
		var main: bool = view.sim.control.is_main_col(int(e["i"])) if str(e["key"]).begins_with("N") else view.sim.control.is_main_row(int(e["j"]))
		e["main"] = main
		_wsum += mw if main else 1.0
		_weights.append(_wsum)


## A road end picked by `u` in 0..1, the main roads weighted heavier.
func pick_end(u: float, not_key: String = "") -> Dictionary:
	_ensure_ends()
	var x: float = u * _wsum
	for k in _ends.size():
		if x <= float(_weights[k]) and str(_ends[k]["key"]) != not_key:
			return _ends[k]
	for e in _ends:
		if str(e["key"]) != not_key:
			return e
	return _ends[0]


## Cars per hour entering the town at this hour on this weekday (0 Monday .. 6 Sunday).
func rate_per_hour(hour: float, wd: int) -> float:
	var c: Dictionary = cfg()
	var curve: Array = c.get("curve_weekend", []) if wd >= 5 else c.get("curve", [])
	if curve.is_empty():
		return 0.0
	var i: int = int(floor(hour)) % curve.size()
	var j: int = (i + 1) % curve.size()
	var r: float = lerpf(float(curve[i]), float(curve[j]), hour - floor(hour)) * float(c.get("per_hour_max", 30.0)) * float((c.get("day_mult", [1, 1, 1, 1, 1, 1, 1]) as Array)[wd % 7])
	return maxf(r, float(c.get("floor_per_hour", 1.5)))


## Cars that start per game minute at this game speed, relative to speed 1 (a crossing takes the same real time at every speed).
func _pace() -> float:
	var sp: int = clampi(Clock.speed, 1, 3)
	var per_min: float = view.speed_scale(sp) / float(Clock.MIN_PER_SEC[sp])
	return clampf(per_min / (view.speed_scale(1) / float(Clock.MIN_PER_SEC[1])), 0.05, 1.0)


func alive() -> int:
	var n: int = 0
	for v in view.sim.vehicles:
		if str(v["tag"]) == "filler" or (str(v["tag"]) == "ambient" and v.has("dest_lot") and bool(v.get("from_edge", false))):
			n += 1
	return n


func sync() -> void:
	if not Workplace.map_ready():
		return
	_ensure_ends()
	var now: int = SysUtil.now()
	if _done_min < 0:
		_done_min = now - int(cfg().get("seed_back_min", 30)) - 1
	var back: int = int(cfg().get("seed_back_min", 30)) if view.seeding else 6      # after a jump in time (sleep, skip) only the last minutes matter
	var from: int = maxi(_done_min + 1, now - back)
	for m in range(from, now + 1):
		_minute(m, now)
	_done_min = now
	var keep: Array = []
	for rec in _pending:
		if now - int(rec["m"]) > int(cfg().get("retry_min", 6)):
			stats["dropped"] = int(stats["dropped"]) + 1
		elif not _try(rec, now):
			keep.append(rec)
	_pending = keep


func _minute(m: int, now: int) -> void:
	var wd: int = posmod(m / 1440, 7)
	var hour: float = float(m % 1440) / 60.0
	var e: float = rate_per_hour(hour, wd) / 60.0 * _pace()
	var n: int = int(floor(e + h01("fl|%d|%d" % [Neighborhood.world_seed, m])))
	for k in n:
		var rec: Dictionary = _rec(m, k)
		if not _try(rec, now):
			stats["deferred"] = int(stats["deferred"]) + 1
			_pending.append(rec)


func _rec(m: int, k: int) -> Dictionary:
	var key := "%d|%d|%d" % [Neighborhood.world_seed, m, k]
	var entry: Dictionary = pick_end(h01(key + "a"))
	var rec: Dictionary = {"m": m, "k": k, "entry": entry, "glb": view.ambient._glb_for_hash(int(h01(key + "g") * 100000.0)), "through": h01(key + "t") < float(cfg().get("through_share", 0.62))}
	rec["exit"] = pick_end(h01(key + "b"), str(entry["key"]))
	rec["lot_u"] = h01(key + "l")
	return rec


func _route(a: Dictionary, b: Dictionary) -> Dictionary:
	var key: String = "%s>%s" % [str(a["key"]), str(b["key"])]
	if not _routes.has(key):
		_routes[key] = VehicleRoads.through_route(a, b, float(view.cfg.get("lane", 1.0)))
	return _routes[key]


## Lots that take customers: business lots with a free bay.
func _lot_with_bay(u: float) -> Array:
	var types: Array = cfg().get("lot_types", ["office", "market", "hospital", "school"])
	var cands: Array = []
	for lot_id in view.ambient._lots_done:
		if types.has(TransportParking.lot_type(str(lot_id))):
			var o: Array = view.ambient._occ(str(lot_id))
			for k in o.size():
				if int(o[k]) == 0:
					cands.append([str(lot_id), k])
					break
	if cands.is_empty():
		return []
	cands.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
	return cands[int(u * float(cands.size())) % cands.size()]


## Start the car if the road end is off the picture and free. False = try again at the next sync.
func _try(rec: Dictionary, now: int) -> bool:
	if alive() >= int(cfg().get("max_alive", 24)):
		stats["full"] = int(stats["full"]) + 1
		return true                                           # the road is full: this one never came
	var s0: float = 0.0
	if view.seeding:
		s0 = float(now - int(rec["m"])) * view.vt_per_min() * float((view.cfg.get("speeds", {}) as Dictionary).get("car", 7.5)) * 0.8
	if bool(rec["through"]):
		var r: Dictionary = _route(rec["entry"], rec["exit"])
		if r.is_empty():
			stats["no_route"] = int(stats["no_route"]) + 1
			return true
		var path: VehiclePath = VehiclePath.make(r["pts"], float(view.cfg.get("corner_radius", 1.8)))
		if s0 >= path.length - 6.0:
			stats["gone"] = int(stats["gone"]) + 1
			return true                                       # it has been and gone
		var p0: Vector2 = path.at(s0)
		if not view.seeding and view.on_screen(p0, 8.0):
			stats["on_screen"] = int(stats["on_screen"]) + 1
			return false
		if not view.sim.spot_free(p0, 4.2, 1.8, 2.5):
			stats["blocked"] = int(stats["blocked"]) + 1
			return false
		view.sim.add("car", str(rec["glb"]), path, {"end": "dead", "tag": "filler", "visits": r["visits"], "s": s0})
		stats["spawned"] = int(stats["spawned"]) + 1
		stats["through"] = int(stats["through"]) + 1
		return true
	var pick: Array = _lot_with_bay(float(rec["lot_u"]))
	if pick.is_empty():
		rec["through"] = true
		return false
	if view.ambient.drive_in(rec["entry"], str(pick[0]), int(pick[1]), s0, str(rec["glb"])):
		stats["spawned"] = int(stats["spawned"]) + 1
		stats["to_lot"] = int(stats["to_lot"]) + 1
		return true
	return false
