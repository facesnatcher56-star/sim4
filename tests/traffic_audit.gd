extends SceneTree
## Reviewer tool (not a test; the runner skips it): windowed traffic audit on the real game.
## godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tests/traffic_audit.gd -- <seed> <speed 1-3> <real seconds> <out dir|none> [start hour] [shot every s]
## Every frame, for every vehicle of the VehicleView layer, it checks whether it is inside the camera frustum, and counts:
##   buses in view, vehicles in view by kind, vehicles that VANISH while in view (on screen last frame, gone or hidden now),
##   vehicles that POP IN while in view (first seen already on screen), the sim's ghost count, and the signal states of junctions in view.
var _main: Node = null
var _frames := 0
var _seed := 101
var _speed := 1
var _secs := 120.0
var _out := "none"
var _hour := 8
var _shot_every := 15.0
var _t0 := 0.0
var _next_shot := 0.0
var _shots := 0
var _started := false
var _vv = null

var _prev_on: Dictionary = {}       # id -> kind (on screen last frame)
var _seen: Dictionary = {}          # id -> true
var _vanish: Dictionary = {}        # kind -> count
var _popin: Dictionary = {}         # kind -> count
var _inview_frames: Dictionary = {} # kind -> folk-frames
var _bus_max := 0
var _bus_frames := 0
var _bus_any_frames := 0
var _layer_off_frames := 0
var _check_frames := 0
var _hourly: Dictionary = {}        # game hour -> [frames, vehicle-frames in view, bus-frames]
var _born: Dictionary = {}          # game hour -> vehicles first seen (anywhere in the layer)
var _minutes: Dictionary = {}       # game hour -> game minutes watched
var _last_min: int = -1
var _sig_frames := 0
var _sig_all_same := 0
var _sig_top_share := 0.0
var _jam_seen := 0


func _clock():
	return root.get_node("Clock")


func _stamp() -> String:
	var c = _clock()
	return "d%d %02d:%02d" % [c.day(), c.hour(), c.minute()]


func _find_vv(n: Node):
	if str(n.name) == "VehicleView" and n.has_method("advance"):          # (not `is VehicleView`: that compiles the layer before the autoloads exist)
		return n
	for c in n.get_children():
		var r = _find_vv(c)
		if r != null:
			return r
	return null


func _on_screen(cam: Camera3D, p: Vector2) -> bool:
	var w := Vector3(p.x, 0.5, p.y)
	if not cam.is_position_in_frustum(w):
		return false
	var sp := cam.unproject_position(w)
	return sp.x >= 0 and sp.y >= 0 and sp.x <= 1280 and sp.y <= 720


func _check() -> void:
	var cam := root.get_viewport().get_camera_3d()
	if cam == null or _vv == null:
		return
	_check_frames += 1
	var h: int = int(_clock().hour())
	var hr: Array = _hourly.get(h, [0, 0, 0])
	hr[0] += 1
	if not _vv.active or not _vv.visible:
		_layer_off_frames += 1
	var now_on: Dictionary = {}
	var buses := 0
	for v in _vv.sim.vehicles:
		var id := int(v["id"])
		var kind := str(v["kind"])
		var node = _vv.nodes.node_of(id)
		var shown: bool = _vv.active and _vv.visible and (node == null or node.visible)
		var on := shown and _on_screen(cam, v["pos"])
		if on:
			now_on[id] = kind
			_inview_frames[kind] = int(_inview_frames.get(kind, 0)) + 1
			hr[1] += 1
			if kind == "bus":
				buses += 1
			if not _seen.has(id) and _check_frames > 30:
				_popin[kind] = int(_popin.get(kind, 0)) + 1
		if not _seen.has(id):
			_born[h] = int(_born.get(h, 0)) + 1
		_seen[id] = true
	var tot_min: int = int(_clock().total_minutes)
	if tot_min != _last_min:
		_last_min = tot_min
		_minutes[h] = int(_minutes.get(h, 0)) + 1
	_signals()
	for id in _prev_on:
		if not now_on.has(id):
			# still on the list and moved out of frame normally?
			var still := false
			for v in _vv.sim.vehicles:
				if int(v["id"]) == int(id):
					var node = _vv.nodes.node_of(int(id))
					still = _vv.active and _vv.visible and (node == null or node.visible)
					break
			if not still:
				var k: String = str(_prev_on[id])
				_vanish[k] = int(_vanish.get(k, 0)) + 1
	_prev_on = now_on
	if buses > 0:
		_bus_any_frames += 1
		hr[2] += 1
	_bus_frames += buses
	_bus_max = maxi(_bus_max, buses)
	_hourly[h] = hr


## How alike are the lights? Per frame: the share of the traffic-light junctions that show the same pair of states (north-south / east-west) as the most common pair.
func _signals() -> void:
	var ctl = _vv.sim.control
	var tally := {}
	var n := 0
	for id in VehicleRoads.junction_ids():
		if ctl.kind(id.x, id.y) != "signal":
			continue
		var k: String = _vv.sim.signal_state(id.x, id.y, 0) + "/" + _vv.sim.signal_state(id.x, id.y, 1)
		tally[k] = int(tally.get(k, 0)) + 1
		n += 1
	if n == 0:
		return
	var top := 0
	for k2 in tally:
		top = maxi(top, int(tally[k2]))
	_sig_frames += 1
	_sig_top_share += float(top) / float(n)
	if top == n:
		_sig_all_same += 1


func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0: _seed = int(args[0])
		if args.size() > 1: _speed = int(args[1])
		if args.size() > 2: _secs = float(args[2])
		if args.size() > 3: _out = args[3]
		if args.size() > 4: _hour = int(args[4])
		if args.size() > 5: _shot_every = float(args[5])
		if _out != "none":
			DirAccess.make_dir_recursive_absolute(_out)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var r := RandomNumberGenerator.new()
		r.seed = _seed
		var h := HouseholdSetup.make_household("solo", r)
		_main.start_new_game(h, str(Scenario.def("solo").get("start_id", "small")), {"scenario": "solo", "difficulty": "normal", "world_seed": _seed})
		return false
	if _frames == 20:
		var c = _clock()
		var n := 0
		while int(c.hour()) != _hour and n < 1440:
			c.advance_minutes(1)
			n += 1
		return false
	if _frames == 30:
		_vv = _find_vv(_main)
		_clock().set_speed(_speed)
		_main.hud.visible = false
		Input.warp_mouse(Vector2(2, 2))
		_t0 = Time.get_ticks_msec() / 1000.0
		_next_shot = _t0 + 5.0
		_started = true
		print("TRAFFIC seed %d speed %d for %.0f s from %s; layer %s" % [_seed, _speed, _secs, _stamp(), "found" if _vv != null else "MISSING"])
		return false
	if not _started:
		return false
	_check()
	var now := Time.get_ticks_msec() / 1000.0
	if _out != "none" and now >= _next_shot:
		_next_shot = now + _shot_every
		var path := "%s/%02d_%s.png" % [_out, _shots, _stamp().replace(" ", "_").replace(":", "")]
		root.get_texture().get_image().save_png(path)
		_shots += 1
	if now - _t0 >= _secs:
		var fr := float(maxi(_check_frames, 1))
		print("TRAFFIC done %s: real %.0f s, frames %d" % [_stamp(), now - _t0, _check_frames])
		print("TRAFFIC layer hidden %d of %d frames" % [_layer_off_frames, _check_frames])
		print("TRAFFIC in view (avg per frame): %s" % str(_inview_frames.keys().map(func(k): return "%s %.2f" % [k, _inview_frames[k] / fr])))
		print("TRAFFIC buses: max %d at once, in view on %.0f%% of frames, avg %.2f" % [_bus_max, 100.0 * _bus_any_frames / fr, _bus_frames / fr])
		print("TRAFFIC vanished while in view: %s" % str(_vanish))
		print("TRAFFIC popped in while in view: %s" % str(_popin))
		print("TRAFFIC ghosted (a vehicle faded through a jam; always 0 since task 37): %d" % int(_vv.sim.ghosted))
		var causes := {}
		for j in _vv.sim.jam_log:
			causes[j["cause"]] = int(causes.get(j["cause"], 0)) + 1
		print("TRAFFIC jams (waited %.0f s or more): %s, vehicles that backed up to free a deadlock: %d" % [float(_vv.sim.num("jam_after_s", 22.0)), str(causes), int(_vv.sim.reversals)])
		print("TRAFFIC lights: on average %.0f%% of the traffic-light junctions show the same pair of states; all of them alike in %.1f%% of the frames" % [100.0 * _sig_top_share / maxf(_sig_frames, 1), 100.0 * _sig_all_same / maxf(_sig_frames, 1)])
		print("TRAFFIC filler: %s" % str(_vv.filler.stats))
		var hs: Array = _hourly.keys()
		hs.sort()
		for hh in hs:
			var a: Array = _hourly[hh]
			print("TRAFFIC hour %02d: vehicles in view %.2f, bus on screen %.0f%%, new vehicles per game minute %.2f" % [hh, float(a[1]) / maxf(a[0], 1), 100.0 * a[2] / maxf(a[0], 1), float(_born.get(hh, 0)) / maxf(float(_minutes.get(hh, 1)), 1.0)])
		quit(0)
	return false
