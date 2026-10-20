class_name VehicleControl
extends RefCounted
## Who controls each junction of the street lattice (task 37), from data/junctions.json: traffic lights only on the main roads, stop and give-way signs on the side streets,
## uncontrolled junctions at the edges of town and two mini roundabouts. Every junction has its own light timing (main road longer green, own offset, a pedestrian phase where
## there is a zebra crossing, a flashing night mode on the quiet lights). Plain data in, plain data out: no nodes, no randomness (the per-junction variety is a hash of the
## junction id), so a headless test and the game agree.
##   kind(i, j) -> "signal" | "stop" | "giveway" | "free" | "roundabout"      state(i, j, axis, vt, hour) -> "green" | "red" | "stop" | "yield" | "flash" | "free" | "round"
##   green_left(i, j, axis, vt, hour)      info(i, j) -> the resolved dictionary      zebra_arms(i, j) -> ["N", "E", ...]      cause(i, j) -> one line why cars behave so here
## Axis: 0 = the east-west street, 1 = the north-south street (VehicleRoads.axis_of).

var t: Dictionary = {}
var _info: Dictionary = {}
var _zebra_lots: Dictionary = {}          # "i,j" -> {arm: true} from the lots people really cross in front of
var _zebra_ready: bool = false

static var shared_cache: VehicleControl = null


func _init(table: Dictionary = {}) -> void:
	t = table if not table.is_empty() else SysUtil.table("junctions")


## One shared instance for static users (floor markings).
static func shared() -> VehicleControl:
	if shared_cache == null:
		shared_cache = VehicleControl.new()
	return shared_cache


static func forget() -> void:
	shared_cache = null


## A well mixed number in [0, 1) from a string (hash() alone changes little when only the last characters change).
static func mix01(key: String) -> float:
	var h: int = hash(key) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777216.0


func _h(i: int, j: int, salt: int) -> float:
	return mix01("%d|%d|%d" % [i, j, salt])


func _span(key: String, u: float) -> float:
	var a: Array = (t.get("signal", {}) as Dictionary).get(key, [3.0, 4.0])
	return lerpf(float(a[0]), float(a[1]), u)


func is_main_row(j: int) -> bool:
	return _has_int(t.get("main_rows", []), j)


func is_main_col(i: int) -> bool:
	return _has_int(t.get("main_cols", []), i)


static func _has_int(a: Array, v: int) -> bool:
	for x in a:
		if int(x) == v:
			return true
	return false


## Resolved description of junction (i, j), cached.
func info(i: int, j: int) -> Dictionary:
	var key := "%d,%d" % [i, j]
	if _info.has(key):
		return _info[key]
	var nx: int = VehicleRoads.xs().size()
	var ny: int = VehicleRoads.ys().size()
	var mr: bool = is_main_row(j)
	var mc: bool = is_main_col(i)
	var d: Dictionary = {"i": i, "j": j}
	if mr and mc:
		d.merge({"type": "signal", "class": "major", "minor": -1, "main": 0})
	elif mr:
		d.merge({"type": "stop", "minor": 1, "main": 0})
	elif mc:
		d.merge({"type": "stop", "minor": 0, "main": 1})
	elif i == 0 or j == 0 or i == nx - 1 or j == ny - 1:
		d.merge({"type": "free", "minor": -1, "main": 0})
	else:
		d.merge({"type": "giveway" if (i + j) % 2 == 0 else "stop", "minor": 1, "main": 0})
	var ov: Dictionary = (t.get("junctions", {}) as Dictionary).get(key, {})
	d.merge(ov, true)
	if str(d["type"]) == "signal":
		if not d.has("class"):
			d["class"] = "minor"
		d["main"] = 0 if not mc or mr else 1
		d["minor"] = -1
	var arms: Array = (d.get("zebra", []) as Array).duplicate()
	for a in zebra_from_lots(i, j):
		if not arms.has(a):
			arms.append(a)
	d["zebra"] = arms
	d["worn"] = float(d.get("worn", _h(i, j, 5) * 0.8))
	if str(d["type"]) == "signal":
		var g1: float = _span("main_green_s", _h(i, j, 1)) * (1.0 if str(d["class"]) == "minor" else 1.25)
		var g2: float = _span("side_green_s", _h(i, j, 2))
		var r: float = _span("all_red_s", _h(i, j, 3))
		var ped: float = float((t.get("signal", {}) as Dictionary).get("ped_s", 3.0)) if not arms.is_empty() else 0.0
		var cycle: float = g1 + g2 + 2.0 * r + ped
		d["g_main"] = g1
		d["g_side"] = g2
		d["all_red"] = r
		d["ped"] = ped
		d["cycle"] = cycle
		d["offset"] = _h(i, j, 4) * cycle
	if not d.has("poles"):
		var all := [0, 1, 2, 3]
		var keep: Array = []
		var n: int = 2 + int(_h(i, j, 6) * 2.99)
		var start: int = int(_h(i, j, 7) * 3.99)
		for k in 4:
			if keep.size() < n:
				keep.append(all[(start + k) % 4])
		d["poles"] = keep
	_info[key] = d
	return d


func kind(i: int, j: int) -> String:
	return str(info(i, j)["type"])


func cause(i: int, j: int) -> String:
	var d: Dictionary = info(i, j)
	return str((t.get("causes", {}) as Dictionary).get(str(d["type"]), ""))


func zebra_arms(i: int, j: int) -> Array:
	return info(i, j)["zebra"]


## Lots whose front people cross: the arm of the nearer junction that leads along the lot's street (school, market, shops, every bus stop).
func zebra_from_lots(i: int, j: int) -> Array:
	if not _zebra_ready:
		_zebra_ready = true
		var lots: Array = (t.get("zebra_lots", []) as Array).duplicate()
		for r in TransportBus.all_routes():
			for l in r["stops"]:
				if not lots.has(l):
					lots.append(l)
		for lot_id in lots:
			var fr: Dictionary = VehicleRoads.frontage(str(lot_id))
			if fr.is_empty():
				continue
			var c: int = int(fr["c"])
			var xs: Array = VehicleRoads.xs()
			var half: float = float(VehicleRoads.road_w()) * 0.5
			var west_d: float = absf(float(fr["gate"]) - (float(xs[c]) + half))
			var east_d: float = absf(float(fr["gate"]) - (float(xs[c + 1]) + half))
			var key := "%d,%d" % [c if west_d <= east_d else c + 1, int(fr["jr"])]
			var arm: String = "E" if west_d <= east_d else "W"
			if not _zebra_lots.has(key):
				_zebra_lots[key] = {}
			_zebra_lots[key][arm] = true
	return (_zebra_lots.get("%d,%d" % [i, j], {}) as Dictionary).keys()


## The junction and arm a "crosswalk" floor tile belongs to ({i, j, arm}), or {}. (The walkable crosswalk floor exists on every arm; only the arms in zebra_arms get paint.)
func zebra_at(tile: Vector2i) -> Dictionary:
	var rw: int = VehicleRoads.road_w()
	var xs: Array = VehicleRoads.xs()
	var ys: Array = VehicleRoads.ys()
	for i in xs.size():
		var jx: int = int(xs[i])
		for j in ys.size():
			var jy: int = int(ys[j])
			if tile.x >= jx + 1 and tile.x < jx + rw - 1:
				if tile.y == jy - 1:
					return {"i": i, "j": j, "arm": "N"}
				if tile.y == jy + rw:
					return {"i": i, "j": j, "arm": "S"}
			elif tile.y >= jy + 1 and tile.y < jy + rw - 1:
				if tile.x == jx - 1:
					return {"i": i, "j": j, "arm": "W"}
				if tile.x == jx + rw:
					return {"i": i, "j": j, "arm": "E"}
	return {}


# ------------------------------------------------------------------ the state of a way
func _night(hour: float) -> bool:
	var s: Dictionary = t.get("signal", {})
	return hour >= float(s.get("night_from", 23.0)) or hour < float(s.get("night_to", 5.5))


func _phase_t(d: Dictionary, vt: float) -> float:
	return fposmod(vt + float(d["offset"]), float(d["cycle"]))


## What a vehicle on `axis` meets at junction (i, j): "green" / "red" for a light, "stop" / "yield" for a sign it has to obey, "green" for the priority street of a sign
## junction, "flash" for the main road of a quiet light at night, "free" / "round" for the uncontrolled and the roundabout.
func state(i: int, j: int, axis: int, vt: float, hour: float = 12.0) -> String:
	var d: Dictionary = info(i, j)
	match str(d["type"]):
		"signal":
			var main: int = int(d["main"])
			if str(d["class"]) == "minor" and _night(hour):
				return "flash" if axis == main else "stop"
			var tt: float = _phase_t(d, vt)
			var g1: float = float(d["g_main"])
			var r: float = float(d["all_red"])
			if tt < g1:
				return "green" if axis == main else "red"
			if tt >= g1 + r and tt < g1 + r + float(d["g_side"]):
				return "green" if axis != main else "red"
			return "red"
		"stop":
			return "stop" if axis == int(d["minor"]) else "green"
		"giveway":
			return "yield" if axis == int(d["minor"]) else "green"
		"roundabout":
			return "round"
	return "free"


## Seconds until the green of `axis` ends (0 when it is not green; a big number for everything that is not a cycling light).
func green_left(i: int, j: int, axis: int, vt: float, hour: float = 12.0) -> float:
	var d: Dictionary = info(i, j)
	if str(d["type"]) != "signal":
		return 999.0
	if str(d["class"]) == "minor" and _night(hour):
		return 999.0 if axis == int(d["main"]) else 0.0
	var main: int = int(d["main"])
	var tt: float = _phase_t(d, vt)
	var g1: float = float(d["g_main"])
	var r: float = float(d["all_red"])
	if axis == main and tt < g1:
		return g1 - tt
	if axis != main and tt >= g1 + r and tt < g1 + r + float(d["g_side"]):
		return g1 + r + float(d["g_side"]) - tt
	return 0.0


## The pedestrian phase of a light with a crossing: both streets red, people may cross.
func ped_phase(i: int, j: int, vt: float, hour: float = 12.0) -> bool:
	var d: Dictionary = info(i, j)
	if str(d["type"]) != "signal" or float(d["ped"]) <= 0.0:
		return false
	if str(d["class"]) == "minor" and _night(hour):
		return false
	return _phase_t(d, vt) >= float(d["cycle"]) - float(d["ped"])


## What a light head shows (for the pictures): green / amber / red, "flash" blinking amber, "walk" during the pedestrian phase (cars are on red then).
func head(i: int, j: int, axis: int, vt: float, hour: float = 12.0) -> String:
	var st: String = state(i, j, axis, vt, hour)
	if st == "green" and green_left(i, j, axis, vt, hour) < float((t.get("signal", {}) as Dictionary).get("amber_s", 0.9)):
		return "amber"
	return st
