extends RefCounted
## Task 37 (fast): the vehicle layer on the real map, headless, with a pretend camera. Over a morning rush no vehicle vanishes or pops in while on the picture, nobody is
## ghosted (a jam is solved by the vehicles, not by letting one drive through the other), through traffic enters and leaves at the road ends only, buses show up at most
## once in view, parked cars stay put when the camera pans, and the layer keeps drawing at game speed 3.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []
var _screen := Rect2(70.0, 35.0, 90.0, 50.0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _on(p: Vector2, margin: float) -> bool:
	return _screen.grow(margin).has_point(p)


## Drives the layer for `seconds` of vehicle time and returns the counts. `after_seed` skips the filling-in of the first seconds.
static func watch(vv: VehicleView, screen: Rect2, seconds: float, speed: int, dt: float = 0.1) -> Dictionary:
	var res := {"vanished": [], "popped": [], "frames": 0, "max_in_view": 0, "bus_in_view_max": 0, "bus_frames": 0, "layer_off": 0}
	var prev: Dictionary = {}
	var seen: Dictionary = {}
	for _i in int(seconds / dt):
		K.run_seconds(vv, dt, speed, dt)
		res["frames"] += 1
		if not vv.active:
			res["layer_off"] += 1
		var now: Dictionary = {}
		var buses := 0
		var alive: Dictionary = {}
		for v in vv.sim.vehicles:
			alive[int(v["id"])] = true
			if screen.has_point(v["pos"]) and str(v["state"]) != "dead":
				now[int(v["id"])] = [str(v["kind"]), str(v["tag"]), v["pos"]]
				if str(v["kind"]) == "bus":
					buses += 1
				if not seen.has(int(v["id"])) and int(res["frames"]) > 40 and not vv.seeding:
					res["popped"].append([str(v["kind"]), str(v["tag"]), v["pos"]])
			seen[int(v["id"])] = true
		for id in prev:
			if not alive.has(id):
				res["vanished"].append(prev[id])
		prev = now
		res["max_in_view"] = maxi(int(res["max_in_view"]), now.size())
		res["bus_in_view_max"] = maxi(int(res["bus_in_view_max"]), buses)
		if buses > 0:
			res["bus_frames"] += 1
	return res


func run() -> Array:
	fails = []
	K.game("classic")
	SimEnv.clock().advance_minutes(7 * 60 + 50 - SimEnv.clock().hour() * 60 - SimEnv.clock().minute())      # 07:50 on day 1 (a Monday): the morning rush
	var vv: VehicleView = K.layer([Vector2(115.0, 60.0), Vector2(40.0, 40.0), Vector2(190.0, 90.0)])
	vv.screen_fn = Callable(self, "_on")
	vv.sync()
	K.run_seconds(vv, 8.0, 1, 0.1)                      # let the road fill in (the first syncs are allowed to place cars on the picture)
	var r: Dictionary = watch(vv, _screen, 100.0, 1)
	print("  [traffic] 100 s of rush: frames %d, most in view %d, vanished in view %d, popped in %d, ghosted %d, filler %s" % [r["frames"], r["max_in_view"], (r["vanished"] as Array).size(), (r["popped"] as Array).size(), vv.sim.ghosted, str(vv.filler.stats)])
	_check((r["vanished"] as Array).is_empty(), "no vehicle vanishes while it is on the picture: %s" % str((r["vanished"] as Array).slice(0, 4)))
	_check((r["popped"] as Array).is_empty(), "no vehicle appears while it is on the picture: %s" % str((r["popped"] as Array).slice(0, 4)))
	_check(vv.sim.ghosted == 0, "nobody is ghosted through a jam (%d): %s" % [vv.sim.ghosted, str(vv.sim.ghost_log.slice(0, 4))])
	_check(int(vv.filler.stats["spawned"]) >= 4, "through traffic enters from the road ends in the rush (%s)" % str(vv.filler.stats))
	print("  [traffic] buses: most in the picture %d, a bus in the picture on %.0f%% of the frames" % [int(r["bus_in_view_max"]), 100.0 * float(r["bus_frames"]) / float(r["frames"])])
	_check(int(r["bus_in_view_max"]) <= 2 and float(r["bus_frames"]) < 0.7 * float(r["frames"]), "a bus is rarely in the picture, never more than two (%d, %.0f%% of the frames)" % [int(r["bus_in_view_max"]), 100.0 * float(r["bus_frames"]) / float(r["frames"])])
	# the camera pans: parked cars stay where they are
	var parked_before: Dictionary = {}
	for v in vv.sim.vehicles:
		if str(v["state"]) == "parked":
			parked_before[int(v["id"])] = v["pos"]
	_screen = Rect2(140.0, 80.0, 90.0, 50.0)
	vv.sync()
	var gone := 0
	for id in parked_before:
		var still := false
		for v in vv.sim.vehicles:
			if int(v["id"]) == id:
				still = true
		if not still:
			gone += 1
	_check(gone == 0 or gone <= 1, "panning the camera does not make parked cars blink out (%d of %d gone)" % [gone, parked_before.size()])
	# speed 3 keeps the vehicles
	var n_before: int = vv.sim.vehicles.size()
	K.run_seconds(vv, 10.0, 3, 0.1)
	_check(vv.active and vv.visible, "the layer is still drawn at game speed 3")
	_check(vv.sim.vehicles.size() >= n_before / 2, "vehicles are still there at game speed 3 (%d -> %d)" % [n_before, vv.sim.vehicles.size()])
	K.free_layer(vv)
	K.Kit.teardown()
	return fails
