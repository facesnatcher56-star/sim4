extends SceneTree
## POV hover sweep (reviewer tool, not a test): sweeps the mouse over the home view, tallies what the hover picks, saves shots. args: out_dir
var _main: Node = null
var _f := 0
var _pts: Array = []
var _i := 0
var _tally: Dictionary = {}
var _out := ""
func _process(_d: float) -> bool:
	if _main == null:
		_out = OS.get_cmdline_user_args()[0]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_f += 1
	if _f == 5:
		var r := RandomNumberGenerator.new(); r.seed = 101
		var h := HouseholdSetup.make_household("family", r)
		_main.start_new_game(h, str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	if _f == 60:
		root.get_node("Clock").set_speed(0)
		_main.lot_view.frame_home()
		_main.lot_view._snap_camera()
		root.get_texture().get_image().save_png(_out + "/home_default.png")
		print("WALLMODE ", _main.lot_view.wall_mode)
		for y in range(120, 700, 40):
			for x in range(300, 1240, 40):
				_pts.append(Vector2(x, y))
	if _f > 62 and _i < _pts.size():
		if _f % 2 == 1:
			Input.warp_mouse(_pts[_i])
		else:
			var lv = _main.lot_view
			lv._update_hover()
			var k := str(lv.hover_kind)
			if k == "object":
				var o = root.get_node("World").get_object(lv.hover_id)
				k = "object:" + (str(o.def_id) if o != null else "?")
				if o != null and _tally.get(k, 0) == 0 and (str(o.def_id).contains("window") or str(o.def_id).contains("light") or str(o.def_id).contains("lamp")):
					lv._update_highlights()
					root.get_texture().get_image().save_png("%s/hover_%s.png" % [_out, str(o.def_id)])
			_tally[k] = int(_tally.get(k, 0)) + 1
			_i += 1
		return false
	if _i >= _pts.size() and _pts.size() > 0:
		var keys := _tally.keys()
		keys.sort_custom(func(a, b): return _tally[a] > _tally[b])
		for k in keys:
			print("HOVER %4d %s" % [_tally[k], k])
		quit(0)
	return false
