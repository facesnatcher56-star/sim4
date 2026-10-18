extends SceneTree
## Not a unit test: windowed screenshots + frame-time probe of the 160x120 map with all its lots.
## godot --path . --resolution 1600x900 --script res://tests/bigmap_shot.gd -- out_prefix name:zoom:hour:weather:tx,tz:rot[:hud] ...
## tx,tz = camera target in tiles ("home" = frame_home(), "follow" = select folk 0, "lot=cafe" = middle of that lot).
## Control specs (no screenshot): go:<lot>[:fast] (everybody walks there / fast travels, then 120 min pass), min:<n> (advance), shells:0|1,
## walk:<lot>[:min] (first folk starts walking, then `min` (default 12) minutes pass), play:<seconds>[:speed] (real time at that game speed), sel:<n> (select folk n). Special spec "perf" runs the frame-time probe
## (home view and zoomed out, sunny / rain, 3 folk) and prints ms/frame + draw calls.
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _measure(label: String, n: int = 240) -> void:
	await _frames(60)
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var draws := 0.0
	var prims := 0.0
	var gpu := 0.0
	var cpu := 0.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	print("%-30s %.2f ms/frame (%.0f fps)  script %.2f ms  render cpu %.2f gpu %.2f ms  draw calls %.0f  prims %.0fk" % [label, ms, 1000.0 / ms, proc / n * 1000.0, cpu / n, gpu / n, draws / n, prims / n / 1000.0])


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://big"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W = root.get_node("World")
	var t0 := Time.get_ticks_usec()
	_main.start_new_game(_main.default_household())
	await _frames(3)
	print("start_new_game + 3 frames: %.0f ms, %d regions" % [float(Time.get_ticks_usec() - t0) / 1000.0, W.regions.regions.size()])
	await _frames(20)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	for i in range(1, args.size()):
		if args[i] == "perf":
			Weather.force("sunny", 0.0)
			clock.total_minutes = 12 * 60
			_main.hud.visible = false
			lv.select("none", -1)
			lv.frame_home()
			await _measure("home view (zoom %.0f), sunny (warm-up)" % lv._zoom_target)
			await _measure("home view (zoom %.0f), sunny" % lv._zoom_target)
			lv.set_zoom(46.0)
			await _measure("zoomed out (zoom 46), sunny")
			Weather.force("rain", 0.0)
			await _measure("zoomed out, rain")
			lv.frame_home()
			await _measure("home view, rain")
			continue
		var p: PackedStringArray = args[i].split(":")
		if p[0] in ["go", "min", "shells", "walk", "sel", "play"]:
			await _control(p, clock, lv)
			continue
		clock.total_minutes = int(float(p[2]) * 60.0)
		Weather.force(p[3], 0.0)
		_main.hud.visible = p.size() > 6 and p[6] == "1"
		var rot := int(p[5])
		while lv._yaw_step != posmod(rot, 4):
			lv.rotate_camera(1)
		lv.select("none", -1)
		if p[4] == "home":
			lv.frame_home()
		elif p[4].begins_with("lot="):
			lv.frame_home()
			Neighborhood.focus_lot(p[4].substr(4))
		elif p[4] == "follow":
			lv.frame_home()
			lv.select("folk", W.all_folk()[0].id)
		else:
			var xz: PackedStringArray = p[4].split(",")
			lv.frame_home()
			lv._target = Vector3(float(xz[0]), 0, float(xz[1]))
		if float(p[1]) > 0.0:
			lv.set_zoom(float(p[1]))
		lv._zoom = lv._zoom_target
		lv._update_daylight()
		await create_timer(1.6).timeout
		root.get_texture().get_image().save_png("%s_%s.png" % [prefix, p[0]])
		print("saved ", p[0], "  target ", lv._target, " zoom ", lv._zoom)
	quit(0)


func _control(p: PackedStringArray, clock, lv) -> void:
	match p[0]:
		"go":
			var ids: Array = []
			for f in SysUtil.residents():
				ids.append(int(f.id))
			var res: Dictionary = Neighborhood.travel(ids, p[1], {"fast": p.size() > 2 and p[2] == "fast", "free": true, "quiet": true})
			print("go ", p[1], " -> ", res)
			clock.set_speed(0)
			for _i in 120:
				clock.advance_minutes(1)
			print("  crowd by lot: ", Neighborhood.lot_ids().map(func(l): return "%s=%d/%d" % [l, Crowd.count(l), Crowd.staff_folk(l).size()]), " hour ", clock.hour_f())
		"min":
			for _i in int(p[1]):
				clock.advance_minutes(1)
			print("  crowd by lot: ", Neighborhood.lot_ids().map(func(l): return "%s=%d/%d" % [l, Crowd.count(l), Crowd.staff_folk(l).size()]), " hour ", clock.hour_f())
			for nf in Crowd.crowd_folk("cafe"):
				var fv = lv.get_folk_view(nf.id)
				print("   cafe npc ", nf.name, " tile ", nf.tile, " cur ", nf.current.def_id if nf.current != null else "-", " view ", fv != null, " vis ", fv.visible if fv != null else "-", " pos ", fv.position if fv != null else "-")
		"shells":
			lv.shells_enabled = p[1] == "1"
		"walk":
			var res2: Dictionary = Neighborhood.travel([SysUtil.residents()[0].id], p[1], {"free": true, "quiet": true})
			print("walk ", p[1], " -> ", res2)
			for _i in (int(p[2]) if p.size() > 2 else 12):
				clock.advance_minutes(1)
			var m0 = SysUtil.residents()[0]
			print("  walker at ", m0.tile, " lot '", Neighborhood.lot_of(m0), "' current ", m0.current.def_id if m0.current != null else "none")
		"sel":
			lv.select("folk", int(p[1]))
		"play":
			clock.set_speed(int(p[2]) if p.size() > 2 else 1)
			await create_timer(float(p[1])).timeout
			clock.set_speed(0)
	var wd = root.get_node("World")
	for fid in lv._folk_views:          # views walk at real speed: after a jump in game time put them where their folk stand
		var fo = wd.get_folk(fid)
		if fo != null and lv._folk_views[fid].position.distance_to(wd.tile_to_pos(fo.tile)) > 3.0:
			lv._folk_views[fid].position = wd.tile_to_pos(fo.tile)
	await _frames(10)
