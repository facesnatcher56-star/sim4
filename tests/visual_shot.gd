extends SceneTree
## Not a unit test: player-POV camera screenshots (zoom / rotation / hour / selection).
## godot --path . --resolution 1600x900 --script res://tests/visual_shot.gd -- out_prefix name:zoom:rot:hour:focus[:hud] ...
## focus = folk index (selects it and centres on it) or "c" (default camera framing, nothing selected).
var _main: Node = null

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://vis"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(20)
	var clock = root.get_node("Clock")
	var W = root.get_node("World")
	clock.set_speed(0)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	var ids: Array = []
	for f in W.all_folk():
		ids.append(f.id)
	var cur_rot := 0
	for i in range(1, args.size()):
		var p: PackedStringArray = args[i].split(":")
		clock.total_minutes = int(float(p[3]) * 60.0)
		lv.set_zoom(float(p[1]))
		var rot := int(p[2])
		if rot != cur_rot:
			lv.rotate_camera(rot - cur_rot)
			cur_rot = rot
		var vis := p.size() > 5 and p[5] == "1"
		_main.hud.visible = vis
		if p[4] == "c":
			lv.select("none", -1)
			lv.frame_home()
			if float(p[1]) > 0.0 and p.size() > 6:
				lv.set_zoom(float(p[1]))
		else:
			var fid: int = ids[int(p[4])]
			lv.select("folk", fid)
			var fv = lv.get_folk_view(fid)
			lv.focus_tile(W.pos_to_tile(fv.position))
		Weather.force("sunny", 0.0)
		if p.size() > 6 and p[6] != "":
			var tp: PackedStringArray = p[6].split("=")     # e.g. place=bed
			lv.set_tool(tp[0], tp[1] if tp.size() > 1 else "")
		else:
			lv.set_tool("select")
		if p.size() > 7 and p[7] != "":
			lv.set_wall_mode(int(p[7]))
		if p.size() > 8:
			lv.show_names = p[8] == "1"
		if p.size() > 9 and p[9] != "":
			var mxy: PackedStringArray = p[9].split(",")
			Input.warp_mouse(Vector2(float(mxy[0]), float(mxy[1])))     # drives hover / ghost
		lv._update_daylight()
		await create_timer(1.2).timeout
		root.get_texture().get_image().save_png("%s_%s.png" % [prefix, p[0]])
		print("saved ", p[0])
	quit(0)
