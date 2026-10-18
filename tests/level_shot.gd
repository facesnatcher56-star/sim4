extends SceneTree
## Not a unit test: windowed screenshots of the multi-floor demo (the office tower) and of building up the home.
## godot --path . --resolution 1600x900 --script res://tests/level_shot.gd -- out_prefix [shots...]
## shots (default all): tower, floor0, floor1, floor2, base, roof, stairs, lift, build, home
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, prefix: String, wait: float = 1.2) -> void:
	await create_timer(wait).timeout
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved ", name)


func _measure(label: String, n: int = 240) -> void:
	await _frames(60)
	var t0 := Time.get_ticks_usec()
	var draws := 0.0
	var proc := 0.0
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	print("%-44s %.2f ms/frame (%.0f fps)  script %.2f ms  draw calls %.0f" % [label, ms, 1000.0 / ms, proc / n * 1000.0, draws / n])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://level"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var want: Array = Array(args).slice(1) if args.size() > 1 else ["tower", "floor0", "floor1", "floor2", "base", "roof", "stairs", "lift", "build", "home"]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W: WorldGrid = root.get_node("World")
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 1})
	await _frames(20)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	clock.total_minutes = 12 * 60
	Weather.force("sunny", 0.0)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	var hud = _main.hud
	var office: Dictionary = W.regions.by_lot("office")
	var rc: Rect2i = office["rect"]
	var org := rc.position
	var folk: Array = W.all_folk()
	var f0: Folk = folk[0]
	var centre := Vector2i(org.x + 16, org.y + 11)
	hud.visible = true
	if want.has("tower"):
		lv.select("none", -1)
		lv.focus_tile(centre)
		lv.set_zoom(46.0)
		lv._zoom = lv._zoom_target
		while lv._yaw_step != 1:
			lv.rotate_camera(1)
		await _shot("tower", prefix, 1.5)
	# a folk in the office, on each floor
	f0.tile = Vector2i(org.x + 14, org.y + 8)
	f0.level = 0
	f0.remove_meta("away") if f0.has_meta("away") else null
	lv.select("folk", f0.id)
	lv.focus_tile(centre)
	lv.set_zoom(24.0)
	lv._zoom = lv._zoom_target
	await _frames(30)
	if want.has("floor0"):
		await _shot("floor0", prefix, 1.0)
	f0.level = 1
	f0.tile = Vector2i(org.x + 14, org.y + 8)
	await _frames(40)
	if want.has("floor1"):
		await _shot("floor1", prefix, 1.0)
	f0.level = 2
	f0.tile = Vector2i(org.x + 17, org.y + 9)
	await _frames(40)
	if want.has("floor2"):
		await _shot("floor2", prefix, 1.0)
	if want.has("roof"):
		lv.set_wall_mode(0)
		await _frames(30)
		await _shot("roof", prefix, 1.0)
		lv.set_wall_mode(1)
	if want.has("base"):
		f0.level = -1
		f0.tile = Vector2i(org.x + 16, org.y + 9)
		await _frames(40)
		await _shot("base", prefix, 1.0)
	if want.has("stairs") or want.has("lift"):
		f0.level = 0
		f0.tile = Vector2i(org.x + 6, org.y + 7)
		await _frames(20)
		var dest := Vector2i(org.x + 14, org.y + 8)
		var ir := Interaction.create_goto(f0, dest, true, 2)
		if want.has("lift"):
			W.set_object_state(W.objects_of_def("elevator")[0].id, "out_of_order", false)
		else:
			W.set_object_state(W.objects_of_def("elevator")[0].id, "out_of_order", true)
		f0.enqueue(ir)
		lv.level_view.set_follow(true)
		var shots := 0
		clock.set_speed(1)          # folk views only move while the clock runs
		for step in 900:
			await _frames(6)
			var fv = lv.get_folk_view(f0.id)
			if fv != null and fv.visible and fv.position.y > 0.8 and fv.position.y < 5.5 and shots < 3:
				await _shot("stairs_%d" % shots if want.has("stairs") else "lift_%d" % shots, prefix, 0.0)
				shots += 1
				await _frames(20)
			if f0.level == 2 and f0.current == null and step > 60:
				break
		clock.set_speed(0)
		print("walker ended on level ", f0.level, " y ", lv.get_folk_view(f0.id).position.y, " shots ", shots)
	if want.has("perf"):
		# a 15-storey tower on the park lot, full map
		var park: Dictionary = W.regions.by_lot("park")
		var pb: Vector2i = (park["rect"] as Rect2i).position
		var foot := Rect2i(pb.x + 8, pb.y + 4, 16, 12)
		W.regions.enforce = false
		var kit := load("res://tests/level_kit.gd")
		var tb: int = kit.add_tower(W, foot, 15, true)
		W.regions.enforce = true
		for lvl in range(1, 15):
			for p in [Vector2i(foot.position.x + 6, foot.position.y + 7), Vector2i(foot.position.x + 9, foot.position.y + 8)]:
				W.place_object("computer", p + Vector2i(lvl % 3, 0), 0, lvl)
		var tc := foot.position + foot.size / 2
		f0.tile = tc
		f0.level = 0
		lv.select("folk", f0.id)
		lv.focus_tile(tc)
		lv.set_zoom(46.0)
		lv._zoom = lv._zoom_target
		clock.set_speed(1)
		await _measure("map, tower of 15 floors outside (warm-up)")
		await _measure("map, tower of 15 floors outside (zoom 46)")
		await _shot("tower15", prefix, 0.2)
		lv.set_zoom(26.0)
		lv._zoom = lv._zoom_target
		f0.tile = tc
		f0.level = 14
		await _frames(60)
		await _measure("floor 14 of 15 viewed (zoom 26)")
		await _shot("tower15_top", prefix, 0.2)
		f0.level = 7
		await _frames(60)
		await _measure("floor 7 of 15 viewed (zoom 26)")
		lv.level_view.set_process(false)
		await _measure("floor 7 viewed, LevelView._process off")
		lv.level_view.set_process(true)
		f0.level = 0
		lv.level_view.set_follow(true)
		await _frames(60)
		await _measure("ground floor of the tower (zoom 26)")
		clock.set_speed(0)
	if want.has("build") or want.has("home"):
		# the player's own home: two storeys, built through the same API as the build panel
		f0.level = 0
		var hr: Rect2i = W.regions.home()["rect"]
		var home := Vector2i(hr.position.x + 14, hr.position.y + 12)
		f0.tile = home
		lv.select("folk", f0.id)
		lv.focus_tile(home)
		lv.set_zoom(22.0)
		lv._zoom = lv._zoom_target
		await _frames(40)
		W.current_household_id = Economy.primary_household()
		Economy.deposit(Economy.primary_household(), 20000, "shot")
		var bid: int = W.lbuild.ensure_building(home)
		# stairs somewhere free inside the house
		var placed := -1
		for dy in range(-5, 6):
			for dx in range(-6, 7):
				var t := home + Vector2i(dx, dy)
				if placed < 0 and W.can_place("stairs", t, 0, 0):
					placed = W.buy_place("stairs", t, 0, -1, 0)
		print("stairs placed ", placed, " ", W.last_error)
		var lvl: int = W.lbuild.add_level(bid, true)
		print("added level ", lvl, " ", W.last_error)
		if want.has("home"):
			f0.level = 1
			lv.level_view.set_viewed(1)
			await _frames(40)
			await _shot("home", prefix, 1.0)
		if want.has("build"):
			hud.build_panel.set_active(true)
			await _frames(30)
			lv.level_view.set_viewed(1)
			lv.select("none", -1)
			lv.set_tool("place", "sofa")
			var mp := Vector2(900, 480)
			Input.warp_mouse(mp)
			await _frames(40)
			await _shot("build", prefix, 1.0)
	quit(0)
