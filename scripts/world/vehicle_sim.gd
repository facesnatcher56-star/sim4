class_name VehicleSim
extends RefCounted
## Moves the vehicles of the view layer along their paths: keeps the right lane, stops at red lights and at marked stops, brakes behind whoever is ahead
## and for folk on the road, never drives into another vehicle (older vehicles have the right of way at crossings). Plain data in, plain data out: no nodes,
## no World writes, no sim rng, so a test can run it headless. Time here is "vehicle seconds" (real seconds x the game speed scale; paused = 0).
##   add(kind, glb, path, opts) -> vehicle      step(dt)      signal_state(i, j, axis) -> "green" | "red" | "dark"      overlaps(a, b) (static)
## A vehicle is a Dictionary: id kind glb len wid path s v vmax vcap state(drive|dwell|parked|dead) stops[{s, hold, until, tag}] visits lights{siren, hazard} ignore_signals ...

var cfg: Dictionary = {}
var vehicles: Array = []
var vt: float = 0.0
var folks: PackedVector2Array = PackedVector2Array()
var dark_fn: Callable = Callable()          # (i, j) -> bool: the lights of this junction are out
var _next_id: int = 1
var ghost_log: Array = []                   # [kind, id, pos, blocker kind/state/pos] of the jams that were cleared (for tests)
var _blocker: Dictionary = {}
var ghosted: int = 0                        # how many times a jam was cleared by letting a vehicle through (a test wants this to stay 0)


func _init(c: Dictionary = {}) -> void:
	cfg = c if not c.is_empty() else SysUtil.table("vehicles")


func num(key: String, default: float) -> float:
	return float(cfg.get(key, default))


func size_of(kind: String) -> Vector2:
	var s: Array = (cfg.get("sizes", {}) as Dictionary).get(kind, [1.8, 4.2])
	return Vector2(float(s[0]), float(s[1]))


func speed_of(kind: String) -> float:
	var sp: Dictionary = cfg.get("speeds", {})
	match kind:
		"fire", "ambulance", "police":
			return float(sp.get("emergency", 12.0))
		_:
			return float(sp.get(kind, sp.get("car", 7.5)))


func add(kind: String, glb: String, path: VehiclePath, opts: Dictionary = {}) -> Dictionary:
	var sz: Vector2 = size_of(kind)
	var v: Dictionary = {"id": _next_id, "kind": kind, "glb": glb, "wid": sz.x, "len": sz.y, "path": path, "s": float(opts.get("s", 0.0)), "v": 0.0,
		"vmax": float(opts.get("vmax", speed_of(kind))), "state": "drive", "stops": opts.get("stops", []).duplicate(true), "visits": [],
		"lights": {"siren": false, "hazard": false}, "ignore_signals": kind in ["fire", "ambulance", "police"] or bool(opts.get("ignore_signals", false)),
		"end": str(opts.get("end", "dead")), "blocked_t": 0.0, "ghost_until": -1.0, "tag": str(opts.get("tag", "")), "key": str(opts.get("key", "")),
		"pos": path.at(float(opts.get("s", 0.0))), "dir": path.dir_at(float(opts.get("s", 0.0))), "color": opts.get("color", ""), "born": vt}
	_next_id += 1
	attach_visits(v, opts.get("visits", []))
	vehicles.append(v)
	return v


## Remember where along the path each junction is entered (the stop line) and left.
func attach_visits(v: Dictionary, visits: Array) -> void:
	var path: VehiclePath = v["path"]
	var from_s: float = 0.0
	var back: float = num("stop_back", 3.4) + 1.1
	var after: float = num("clear_after", 2.8)
	var out: Array = []
	for vis in visits:
		var ctr: Vector2 = VehicleRoads.junction_center(int(vis[0]), int(vis[1]))
		var sc: float = path.closest_s(ctr, from_s, 90.0)
		from_s = sc + 0.5
		var left: bool = int(vis[3]) == (int(vis[2]) + 3) % 4
		out.append({"i": int(vis[0]), "j": int(vis[1]), "axis": VehicleRoads.axis_of(int(vis[2])), "s_line": sc - back, "s_clear": sc + after, "left": left, "ctr": ctr, "din": int(vis[2]), "dout": int(vis[3])})
	v["visits"] = out


## A vehicle standing in a bay (state "parked"): position and heading only.
func add_parked(kind: String, glb: String, pos: Vector2, dir: Vector2, opts: Dictionary = {}) -> Dictionary:
	var path: VehiclePath = VehiclePath.make([pos - dir.normalized() * 0.5, pos + dir.normalized() * 0.5], 0.0)
	var o: Dictionary = opts.duplicate()
	o["s"] = 0.5
	var v: Dictionary = add(kind, glb, path, o)
	v["state"] = "parked"
	return v


## Send a standing (or finished) vehicle along a new path.
func restart(v: Dictionary, path: VehiclePath, visits: Array, end: String = "dead") -> void:
	v["path"] = path
	v["s"] = 0.0
	v["v"] = 0.0
	v["state"] = "drive"
	v["end"] = end
	v["stops"] = []
	v["blocked_t"] = 0.0
	v["pos"] = path.at(0.0)
	v["dir"] = path.dir_at(0.0)
	attach_visits(v, visits)


func signal_state(i: int, j: int, axis: int) -> String:
	if dark_fn.is_valid() and bool(dark_fn.call(i, j)):
		return "dark"
	var sg: Dictionary = cfg.get("signal", {})
	var cycle: float = float(sg.get("cycle_s", 11.0))
	var green: float = float(sg.get("green_s", 3.6))
	var red: float = float(sg.get("all_red_s", 1.9))
	var t: float = fposmod(vt + float(i * 3 + j * 5) * 1.7, cycle)
	if t < green:
		return "green" if axis == 1 else "red"
	if t >= green + red and t < 2.0 * green + red:
		return "green" if axis == 0 else "red"
	return "red"


## Seconds until the green of this axis ends (a big number when the lights are out).
func green_left(i: int, j: int, axis: int) -> float:
	if dark_fn.is_valid() and bool(dark_fn.call(i, j)):
		return 999.0
	var sg: Dictionary = cfg.get("signal", {})
	var cycle: float = float(sg.get("cycle_s", 11.0))
	var green: float = float(sg.get("green_s", 3.6))
	var red: float = float(sg.get("all_red_s", 1.9))
	var t: float = fposmod(vt + float(i * 3 + j * 5) * 1.7, cycle)
	if axis == 1 and t < green:
		return green - t
	if axis == 0 and t >= green + red and t < 2.0 * green + red:
		return 2.0 * green + red - t
	return 0.0


func _brake(d: float) -> float:
	if d <= 0.0:
		return 0.0
	return sqrt(2.0 * num("decel", 16.0) * 0.55 * d)


func step(dt: float) -> void:
	vt += dt
	if dt <= 0.0:
		return
	for v in vehicles:
		if str(v["state"]) != "parked" and str(v["state"]) != "dead":
			_step_one(v, dt)
	var keep: Array = []
	for v2 in vehicles:
		if str(v2["state"]) != "dead":
			keep.append(v2)
	vehicles = keep


## Heading of a body on its path: both ends of the body (front and rear axle) follow the path, so a long vehicle cuts a corner like a real one and its ends never swing out.
static func heading(path: VehiclePath, s: float, length: float) -> Vector2:
	if length < 3.0:
		return path.dir_at(s)
	var d: Vector2 = path.at(minf(s + length * 0.4, path.length)) - path.at(maxf(s - length * 0.4, 0.0))
	return d.normalized() if d.length() > 0.2 else path.dir_at(s)


## Where the body centre is for the path distance `s` (midpoint of the two axles).
static func centre(path: VehiclePath, s: float, length: float) -> Vector2:
	if length < 3.0:
		return path.at(s)
	return (path.at(minf(s + length * 0.4, path.length)) + path.at(maxf(s - length * 0.4, 0.0))) * 0.5


func _step_one(v: Dictionary, dt: float) -> void:
	var path: VehiclePath = v["path"]
	var vis0: Array = v["visits"]
	while not vis0.is_empty() and float(v["s"]) - float(v["len"]) * 0.5 > float((vis0[0] as Dictionary)["s_clear"]):
		vis0.pop_front()
	v["pos"] = centre(path, float(v["s"]), float(v["len"]))
	v["dir"] = heading(path, float(v["s"]), float(v["len"]))
	var half: float = float(v["len"]) * 0.5
	var lim: float = float(v["vmax"])
	if v.has("vcap"):
		lim = minf(lim, float(v["vcap"]))
	var stops: Array = v["stops"]
	if str(v["state"]) == "dwell":
		var st0: Dictionary = stops[0]
		if bool(st0.get("hold", false)) or vt < float(st0.get("until", 0.0)):
			v["v"] = 0.0
			return
		stops.pop_front()
		v["state"] = "drive"
	if not stops.is_empty():
		var st: Dictionary = stops[0]
		var d: float = float(st["s"]) - float(v["s"])
		if d <= 0.08:
			v["s"] = float(st["s"])
			v["v"] = 0.0
			if bool(st.get("hold", false)) or vt < float(st.get("until", 0.0)):
				v["state"] = "dwell"
				v["pos"] = path.at(float(v["s"]))
				return
			stops.pop_front()
		else:
			lim = minf(lim, _brake(d))
	var dend: float = path.length - float(v["s"])
	if dend <= 0.05:
		v["v"] = 0.0
		v["state"] = "parked" if str(v["end"]) == "park" else "dead"
		return
	if str(v["end"]) == "park":
		lim = minf(lim, maxf(_brake(dend), 0.7))
	var obstructed: bool = false
	v["wait_for"] = -1
	if not bool(v["ignore_signals"]):
		lim = minf(lim, _signals_limit(v, half))
	var ol: float = _obstacle_limit(v, half)
	if ol < lim:
		lim = ol
		obstructed = ol < 0.15
	var accel: float = num("accel", 9.0)
	var sp: float = float(v["v"])
	sp = minf(lim, sp + accel * dt) if sp < lim else maxf(lim, sp - num("decel", 16.0) * dt)
	v["v"] = sp
	if obstructed and sp < 0.1:
		v["blocked_t"] = float(v["blocked_t"]) + dt
		if float(v["blocked_t"]) > num("ghost_after_s", 20.0):
			v["ghost_until"] = vt + 4.0
			v["blocked_t"] = 0.0
			ghosted += 1
			var near: Array = []
			for o2 in vehicles:
				if (o2["pos"] as Vector2).distance_to(v["pos"]) < 14.0:
					near.append([int(o2["id"]), str(o2["kind"]), o2["pos"], o2["dir"], snappedf(float(o2["v"]), 0.1), str(o2["state"]), int(o2.get("wait_for", -1)), snappedf(float(o2["blocked_t"]), 0.1), (o2["visits"] as Array).size()])
			ghost_log.append(near)
			ghost_log.append([str(v["kind"]), int(v["id"]), v["pos"], str(_blocker.get("kind", "?")), str(_blocker.get("state", "?")), _blocker.get("pos", Vector2.ZERO), str(_blocker.get("tag", ""))])
	else:
		v["blocked_t"] = 0.0
	v["s"] = minf(float(v["s"]) + sp * dt, path.length)
	v["pos"] = centre(path, float(v["s"]), float(v["len"]))
	v["dir"] = heading(path, float(v["s"]), float(v["len"]))


func _signals_limit(v: Dictionary, half: float) -> float:
	var lim: float = INF
	var visits: Array = v["visits"]
	for vis in visits:
		var d: float = float(vis["s_line"]) - (float(v["s"]) + half)
		if d > 60.0:
			break
		var st: String = signal_state(int(vis["i"]), int(vis["j"]), int(vis["axis"]))
		if st == "green" and d > -0.3:
			var need: float = (maxf(d, 0.0) + float(vis["s_clear"]) - float(vis["s_line"]) + float(v["len"])) / maxf(float(v["v"]), 3.5)
			var slack: float = float((cfg.get("signal", {}) as Dictionary).get("all_red_s", 1.9)) * 0.8
			if green_left(int(vis["i"]), int(vis["j"]), int(vis["axis"])) + slack < need:
				st = "red"                                 # it could not clear the crossing before the light changes: wait for the next green
		if st == "red":
			if d > -0.4:
				lim = minf(lim, _brake(maxf(d, 0.0)))
		elif st == "dark":
			if d > -0.4 and d < 7.0:
				lim = minf(lim, maxf(_brake(maxf(d, 0.0)) * 0.6, float((cfg.get("speeds", {}) as Dictionary).get("creep", 1.6))))
		if d > -0.4 and d < 5.0 and st != "red" and (_no_room_beyond(v, half, float(vis["s_clear"])) or (bool(vis["left"]) and _oncoming_to(v, vis["ctr"])) or _box_conflict(v, vis, st == "dark")):
			lim = minf(lim, _brake(maxf(d, 0.0)))          # never block the crossing: wait at the line until there is room on the far side
		if d > -0.4:
			break                                     # only the next junction matters
	return lim


## Is there room for a vehicle of this size here (nobody's footprint within reach)?
func spot_free(pos: Vector2, length: float, wid: float, margin: float = 0.6) -> bool:
	for o in vehicles:
		if str(o["state"]) == "dead":
			continue
		if (o["pos"] as Vector2).distance_to(pos) < (length + float(o["len"])) * 0.5 + margin + maxf(wid, float(o["wid"])) * 0.3:
			return false
	return true


## Does a (standing) vehicle reach into a junction box with its body?
func _occupies_box(o: Dictionary) -> bool:
	var h: Vector2 = o["dir"]
	var hl: float = float(o["len"]) * 0.5
	var p: Vector2 = o["pos"]
	return _in_box(p) or _in_box(p + h * hl) or _in_box(p - h * hl) or _in_box(p + h * hl * 0.5) or _in_box(p - h * hl * 0.5)


## Is the point inside the box of a junction (where a stopped vehicle blocks everybody crossing)?
func _in_box(p: Vector2) -> bool:
	return VehicleRoads.junction_at_point(p).x >= 0


## Somebody is inside this junction (or about to be, and older) on a crossing movement: wait at the line. Opposite directions conflict only when one of them turns left.
func _box_conflict(v: Dictionary, vis: Dictionary, dark: bool) -> bool:
	for u in vehicles:
		if u == v or str(u["state"]) == "dead":
			continue
		var uv: Array = u["visits"]
		if uv.is_empty():
			continue
		var uvis: Dictionary = uv[0]
		if int(uvis["i"]) != int(vis["i"]) or int(uvis["j"]) != int(vis["j"]):
			continue
		var front: float = float(u["s"]) + float(u["len"]) * 0.5
		var inside: bool = front > float(uvis["s_line"]) + 0.3
		var about: bool = dark and int(u["id"]) < int(v["id"]) and front > float(uvis["s_line"]) - 2.5
		if not inside and not about:
			continue
		if int(uvis["axis"]) != int(vis["axis"]) or (int(uvis["din"]) != int(vis["din"]) and (bool(uvis["left"]) or bool(vis["left"]))):
			v["wait_for"] = int(u["id"])
			return true
	return false


## A left turn gives way to traffic coming the other way into the same junction.
func _oncoming_to(v: Dictionary, ctr: Vector2) -> bool:
	var h: Vector2 = v["dir"]
	for o in vehicles:
		if o == v or str(o["state"]) == "dead" or str(o["state"]) == "parked":
			continue
		if h.dot(o["dir"]) > -0.6:
			continue
		var to_c: Vector2 = ctr - (o["pos"] as Vector2)
		var along: float = to_c.dot(o["dir"])
		if along > -float(o["len"]) * 0.5 - 1.0 and along < 22.0 and absf(to_c.dot(VehicleRoads.right_of(o["dir"]))) < 4.0 and float(o["v"]) > 0.3:
			return true
	return false


## A queue stands just past the junction: no room to clear the crossing.
func _no_room_beyond(v: Dictionary, half: float, s_clear: float) -> bool:
	var h: Vector2 = v["dir"]
	var rt: Vector2 = VehicleRoads.right_of(h)
	var pos: Vector2 = v["pos"]
	var need: float = s_clear - float(v["s"]) + float(v["len"]) + 0.8
	for o in vehicles:
		if o == v or str(o["state"]) == "dead":
			continue
		var d: Vector2 = (o["pos"] as Vector2) - pos
		var along: float = d.dot(h)
		if along <= 0.0 or along > 40.0 or float(o["v"]) > 1.2:
			continue
		if absf(d.dot(rt)) < (float(v["wid"]) + float(o["wid"])) * 0.5 and h.dot(o["dir"]) > 0.7:
			if along - float(o["len"]) * 0.5 < need + half:
				return true
	return false


func _obstacle_limit(v: Dictionary, half: float) -> float:
	if vt < float(v["ghost_until"]):
		return INF
	var h: Vector2 = v["dir"]
	var rt: Vector2 = VehicleRoads.right_of(h)
	var lim: float = INF
	_blocker = {}
	var look: float = num("look", 6.0) + float(v["v"]) * 0.6
	var gap: float = num("gap", 0.9)
	var pos: Vector2 = v["pos"]
	var wid: float = float(v["wid"])
	for o in vehicles:
		if o == v or str(o["state"]) == "dead":
			continue
		var d: Vector2 = (o["pos"] as Vector2) - pos
		if d.length_squared() > 900.0:
			continue
		var oh: float = float(o["len"]) * 0.5
		var cs: float = h.dot(o["dir"])
		var margin: float = wid * 0.5 + 0.12
		var near_only: bool = false
		if cs < -0.7:
			margin = wid * 0.5                                   # oncoming in the other lane: only a real intrusion counts (a left turn across it gives way by age)
		if cs <= 0.7:
			var yields: bool = int(o["id"]) < int(v["id"]) or float(o["v"]) < 0.3
			if not yields:
				continue                                         # the other one gives way to me
		if int(o.get("wait_for", -1)) == int(v["id"]):
			near_only = true                                     # it waits for me (a deadlock in the making): only stop for it when it is really in my way
		var best: float = INF
		var ohd: Vector2 = o["dir"]
		var ort: Vector2 = VehicleRoads.right_of(ohd)
		var ow: float = float(o["wid"]) * 0.5 * 0.95
		var ol: float = oh * 0.95
		var nl: int = int(ceil(ol * 2.0 / 1.1))
		var pts_o: Array = []
		for ia in nl + 1:
			var sx: float = -1.0 + 2.0 * float(ia) / float(nl)
			for sy in [-1.0, 0.0, 1.0]:
				pts_o.append((o["pos"] as Vector2) + ohd * (ol * sx) + ort * (ow * sy))
		var horizon: float = 2.4 if near_only else look + half + 6.0
		var vpath: VehiclePath = v["path"]
		var dd: float = 0.2
		while dd <= horizon and best == INF:
			var sp: float = float(v["s"]) + dd
			if sp > vpath.length + 0.5:
				break
			var pc: Vector2 = centre(vpath, sp, float(v["len"]))
			var nose: Vector2 = vpath.at(minf(sp + half * 0.9, vpath.length))
			for q in pts_o:
				if (q as Vector2).distance_squared_to(nose) < margin * margin or (q as Vector2).distance_squared_to(pc) < margin * margin:
					best = dd
					break
			dd += 0.8
		if best < INF:
			var bl: float = _brake(best - gap)
			if bl < lim:
				lim = bl
				_blocker = o
				v["wait_for"] = int(o["id"])
	for p in folks:
		var dp: Vector2 = p - pos
		var al: float = dp.dot(h)
		if al <= 0.0 or al > look + half:
			continue
		if absf(dp.dot(rt)) < wid * 0.5 + 0.45:
			var fl: float = _brake(al - half - 0.55)
			if fl < lim:
				lim = fl
				_blocker = {"kind": "folk", "state": "stand", "pos": p, "tag": "folk"}
	return lim


# ------------------------------------------------------------------ queries and checks
func by_key(key: String) -> Dictionary:
	for v in vehicles:
		if str(v["key"]) == key and str(v["state"]) != "dead":
			return v
	return {}


func kill(v: Dictionary) -> void:
	v["state"] = "dead"


## The four corners of a vehicle's footprint, shrunk a little (for overlap checks).
static func corners(v: Dictionary, shrink: float = 0.75) -> Array:
	var h: Vector2 = v["dir"]
	var r: Vector2 = VehicleRoads.right_of(h)
	var p: Vector2 = v["pos"]
	var hl: float = float(v["len"]) * 0.5 * shrink
	var hw: float = float(v["wid"]) * 0.5 * shrink
	return [p + h * hl + r * hw, p + h * hl - r * hw, p - h * hl - r * hw, p - h * hl + r * hw]


static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	if (a["pos"] as Vector2).distance_to(b["pos"]) > (float(a["len"]) + float(b["len"])) * 0.5:
		return false
	var ca: Array = corners(a)
	var cb: Array = corners(b)
	var min_pen: float = 1.0e9
	for shape in [ca, cb]:
		for i in 2:
			var edge: Vector2 = (shape[i + 1] as Vector2) - (shape[i] as Vector2)
			var axis := Vector2(-edge.y, edge.x).normalized()
			var amin: float = 1.0e9
			var amax: float = -1.0e9
			var bmin: float = 1.0e9
			var bmax: float = -1.0e9
			for p in ca:
				var t: float = (p as Vector2).dot(axis)
				amin = minf(amin, t)
				amax = maxf(amax, t)
			for q in cb:
				var t2: float = (q as Vector2).dot(axis)
				bmin = minf(bmin, t2)
				bmax = maxf(bmax, t2)
			if amax < bmin or bmax < amin:
				return false
			min_pen = minf(min_pen, minf(amax, bmax) - maxf(amin, bmin))
	return min_pen > 0.15                         # a skim of a corner is not an overlap
