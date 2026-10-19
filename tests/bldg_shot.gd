extends SceneTree
## Not a unit test: windowed screenshots of the multi-floor buildings on the map, one picture per floor.
## godot --path . --resolution 1600x900 --script res://tests/bldg_shot.gd -- out_prefix lot:level[+level|out...] [lot:level,...] [seed=N] [zoom=N]   (zoom < 20 centres on the stair core)
## e.g. ... -- user://b hospital:0+1+3+-1 apartments:1 office:2 police:-1 courthouse:1
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://bldg"
	var wseed := 1
	var zoom_v := 26.0
	var jobs: Array = []
	for a in Array(args).slice(1):
		if str(a).begins_with("seed="):
			wseed = int(str(a).substr(5))
		elif str(a).begins_with("zoom="):
			zoom_v = float(str(a).substr(5))
		else:
			jobs.append(str(a))
	if jobs.is_empty():
		jobs = ["hospital:0+1+3+-1", "apartments:0+2", "office:0+2+-1", "police:0+-1", "courthouse:1", "school:1"]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W: WorldGrid = root.get_node("World")
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": wseed})
	await _frames(20)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	clock.total_minutes = 12 * 60
	Weather.force("sunny", 0.0)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	_main.hud.visible = true
	var f0: Folk = W.all_folk()[0]
	for job in jobs:
		var parts := str(job).split(":")
		var lot := parts[0]
		var region: Dictionary = W.regions.by_lot(lot)
		if region.is_empty():
			print("no lot ", lot)
			continue
		var rc: Rect2i = region["rect"]
		var tpl := LotLoader.template(str(region["template"]))
		print("lot ", lot, " template ", region["template"])
		var br := LotLoader.building_rect(str(region["template"]))
		var centre := rc.position + br.position + br.size / 2
		for ls in parts[1].split("+"):
			if ls == "out":                        # the building seen from outside (shell closed): the folk stands far away
				f0.tile = Vector2i(rc.position.x + 15, rc.end.y + 6)
				f0.level = 0
				lv.select("folk", f0.id)
				lv.focus_tile(centre)
				lv.set_zoom(34.0)
				lv._zoom = lv._zoom_target
				while lv._yaw_step != 1:
					lv.rotate_camera(1)
				await _frames(50)
				await create_timer(0.8).timeout
				var opath := "%s_%s_out.png" % [prefix, lot]
				root.get_texture().get_image().save_png(opath)
				print("saved ", opath)
				continue
			var level := int(ls)
			var stops: Dictionary = tpl.get("stops", {})
			var tile := centre
			if stops.has(str(level)):
				var st: Array = stops[str(level)]
				tile = Vector2i(int(st[0]), int(st[1])) + rc.position
			f0.tile = tile
			f0.level = level
			lv.select("folk", f0.id)
			lv.focus_tile(tile if zoom_v < 20.0 else centre)
			lv.set_zoom(zoom_v)
			lv._zoom = lv._zoom_target
			while lv._yaw_step != 1:
				lv.rotate_camera(1)
			await _frames(50)
			await create_timer(0.8).timeout
			var path := "%s_%s_%s.png" % [prefix, lot, "b%d" % -level if level < 0 else str(level)]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	quit()
