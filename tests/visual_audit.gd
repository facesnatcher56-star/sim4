extends SceneTree
## Visual audit (reviewer tool, not a test): windowed check of how folk look in the real game. Real frames, real clock speed.
## args: scenario seed speed(1..3) real_seconds out_dir [shot_every_s]
## Measures per visible folk view: walk vs run frames, sitting off the seat, standing/walking inside a blocked tile,
## folk overlapping each other; saves screenshots round-robin on household folk and on the first anomalies.
var _main: Node = null
var _frames := 0
var _scen := "family"
var _seed := 101
var _speed := 1
var _secs := 120.0
var _out := "/tmp/vis"
var _shot_every := 6.0
var _t0 := 0.0
var _next_shot := 0.0
var _rr := 0
var _started := false
var _pending_shot := ""        # name of a shot to take after the camera settles
var _pending_at := 0.0
var _pending_folk := -1
var _shots := 0

# metrics
var _move_frames := 0
var _run_frames := 0
var _run_by_folk: Dictionary = {}
var _sit_frames := 0
var _sit_off := 0
var _sit_off_max := 0.0
var _blocked_frames := 0
var _overlap_frames := 0
var _vis_frames := 0
var _sit_hold: Dictionary = {}     # folk id -> frames in sit pose
var _anoms: Dictionary = {}        # kind|detail -> count
var _anom_shots: Dictionary = {}   # kind -> shots taken

func _lv():
	return _main.lot_view

func _W():
	return root.get_node("World")

func _clock():
	return root.get_node("Clock")

func _stamp() -> String:
	var c = _clock()
	return "d%d %02d:%02d" % [c.day(), c.hour(), c.minute()]

func _hh() -> Array:
	var out: Array = []
	for f in _W().all_folk():
		if int(f.household_id) == 1:
			out.append(f)
	return out

func _cur_id(f) -> String:
	return str(f.current.def_id) if f.current != null else "-"

func _anom(kind: String, detail: String, fid: int, skey: String = "") -> void:
	var k := kind + " | " + detail
	_anoms[k] = int(_anoms.get(k, 0)) + 1
	if int(_anoms[k]) == 1:
		print("ANOM %s %s %s" % [_stamp(), kind, detail])
	var sk := kind + skey
	var n: int = int(_anom_shots.get(sk, 0))
	if n < 2 and _pending_shot == "":
		_anom_shots[sk] = n + 1
		_queue_shot("anom_%s%s_%d" % [kind, skey.replace(" ", ""), n + 1], fid)

func _queue_shot(name: String, fid: int) -> void:
	if _out == "none":
		return
	_pending_shot = name
	_pending_folk = fid
	_pending_at = Time.get_ticks_msec() / 1000.0 + 0.6
	var lv = _lv()
	var fv = lv.get_folk_view(fid)
	if fv != null:
		lv.set_zoom(7.0)
		lv.focus_tile(_W().pos_to_tile(fv.position))
		lv._snap_camera()

func _take_pending() -> void:
	var lv = _lv()
	var fv = lv.get_folk_view(_pending_folk)
	if fv != null:
		lv.focus_tile(_W().pos_to_tile(fv.position))
		lv._snap_camera()
	var f = _W().get_folk(_pending_folk)
	var path := "%s/%02d_%s.png" % [_out, _shots, _pending_shot]
	root.get_texture().get_image().save_png(path)
	_shots += 1
	print("SHOT %s %s %s doing %s pose %s anim %s" % [_stamp(), path.get_file(), str(f.name) if f != null else "?", _cur_id(f) if f != null else "?", str(fv.pose) if fv != null else "?", _clip(fv)])
	_pending_shot = ""

func _clip(fv) -> String:
	if fv == null or fv._anim == null:
		return "-"
	return str(fv._anim.current_animation)

func _check() -> void:
	var lv = _lv()
	var W = _W()
	var views: Array = []
	for f in W.all_folk():
		var fv = lv.get_folk_view(int(f.id))
		if fv == null or not fv.visible:
			continue
		views.append([f, fv])
	for pr in views:
		var f = pr[0]
		var fv = pr[1]
		_vis_frames += 1
		var clip := _clip(fv)
		var moving: bool = fv._moving or not fv._waypoints.is_empty()
		if moving:
			_move_frames += 1
			if clip == "Run":
				_run_frames += 1
				_run_by_folk[str(f.name)] = int(_run_by_folk.get(str(f.name), 0)) + 1
		var tile: Vector2i = W.pos_to_tile(fv.position)
		var lvl: int = int(f.level)
		if str(fv.pose) == "sit":
			_sit_hold[int(f.id)] = int(_sit_hold.get(int(f.id), 0)) + 1
			if int(_sit_hold[int(f.id)]) > 40:
				_sit_frames += 1
				var res = W.reservation_of(int(f.id))
				var t: Vector3 = fv._target
				var off := Vector2(fv.position.x - t.x, fv.position.z - t.z).length()
				if res == null:
					_anom("sit_no_seat", "%s doing %s" % [f.name, _cur_id(f)], int(f.id))
				elif off > 0.12:
					_sit_off += 1
					_sit_off_max = maxf(_sit_off_max, off)
					var o = W.get_object(res[0])
					_anom("sit_off_seat", "%s on %s (%s) off %.2f" % [f.name, str(o.def_id) if o != null else "?", _cur_id(f), off], int(f.id))
		else:
			_sit_hold.erase(int(f.id))
		var using_here := false
		var rs = W.reservation_of(int(f.id))
		if rs is Array:
			var ro = W.get_object(rs[0])
			if ro != null and ro.slot_tile(int(rs[1])) == tile:
				using_here = true
		if str(fv.pose) in ["idle", "walk", "use", "stand"] and not using_here and not W.is_walkable(tile, lvl):
			var o2 = W.object_at(tile, lvl)
			_blocked_frames += 1
			_anom("in_blocked", "%s %s at %s on %s (%s)" % [f.name, str(fv.pose), str(tile), str(o2.def_id) if o2 != null else "wall/none", _cur_id(f)], int(f.id), "_" + (str(o2.def_id) if o2 != null else "wall"))
	for i in views.size():
		for j in range(i + 1, views.size()):
			var a = views[i]
			var b = views[j]
			if str(a[1].pose) in ["sit", "lie"] or str(b[1].pose) in ["sit", "lie"]:
				continue
			if int(a[0].level) != int(b[0].level):
				continue
			var d := Vector2(a[1].position.x - b[1].position.x, a[1].position.z - b[1].position.z).length()
			if d < 0.3:
				_overlap_frames += 1
				_anom("overlap", "%s & %s (%s / %s)" % [a[0].name, b[0].name, _cur_id(a[0]), _cur_id(b[0])], int(a[0].id))

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0: _scen = args[0]
		if args.size() > 1: _seed = int(args[1])
		if args.size() > 2: _speed = int(args[2])
		if args.size() > 3: _secs = float(args[3])
		if args.size() > 4: _out = args[4]
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
		var h := HouseholdSetup.make_household(_scen, r)
		var start_id := str(Scenario.def(_scen).get("start_id", "classic"))
		_main.start_new_game(h, start_id, {"scenario": _scen, "difficulty": "normal", "world_seed": _seed})
		return false
	if _frames == 30:
		_clock().set_speed(_speed)
		_main.hud.visible = false
		Input.warp_mouse(Vector2(2, 2))
		_t0 = Time.get_ticks_msec() / 1000.0
		_next_shot = _t0 + 3.0
		_started = true
		print("VIS scenario %s seed %d speed %d for %.0f s; household: %s" % [_scen, _seed, _speed, _secs, ", ".join(_hh().map(func(x): return str(x.name)))])
		return false
	if not _started:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	_check()
	if _pending_shot != "" and now >= _pending_at:
		_take_pending()
	elif _pending_shot == "" and now >= _next_shot:
		_next_shot = now + _shot_every
		var hh := _hh()
		var vis: Array = []
		for f in hh:
			var fv = _lv().get_folk_view(int(f.id))
			if fv != null and fv.visible:
				vis.append(f)
		if not vis.is_empty():
			var f = vis[_rr % vis.size()]
			_rr += 1
			_queue_shot("rr_%s" % str(f.name).split(" ")[0], int(f.id))
	if now - _t0 >= _secs:
		print("VIS done %s: real %.0f s, frames %d, fps %.1f" % [_stamp(), now - _t0, _frames, float(_frames) / maxf(now - _t0, 1.0)])
		print("VIS moving folk-frames %d, running %d (%.0f%%); by folk %s" % [_move_frames, _run_frames, 100.0 * _run_frames / maxf(_move_frames, 1), str(_run_by_folk)])
		print("VIS sitting folk-frames %d, off the seat %d (max %.2f m)" % [_sit_frames, _sit_off, _sit_off_max])
		print("VIS in a blocked tile %d of %d folk-frames; overlapping pairs %d" % [_blocked_frames, _vis_frames, _overlap_frames])
		var keys: Array = _anoms.keys()
		keys.sort_custom(func(a, b): return int(_anoms[a]) > int(_anoms[b]))
		for k in keys.slice(0, 40):
			print("ANOMCOUNT %5d %s" % [_anoms[k], k])
		quit(0)
	return false
