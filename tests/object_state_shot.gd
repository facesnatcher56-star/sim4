extends SceneTree
## Not a unit test: windowed screenshots of task 33.3 (objects show their state) and 33.4 (progress rings). Family seed 101 home; test objects are placed in a free row near the household.
## godot --path . --resolution 1280x720 --script res://tests/object_state_shot.gd -- docs/act33 [case,case,...]
## cases: plants, toilets, sinks, broken, stove, tv, beds, easel, garden, fridge, lamps, rings
var _out := "user://act33"
var _main: Node = null
var _home := Vector2i.ZERO
var _cap: Label = null


var _beat: Thread = null


func _heartbeat() -> void:
	while true:
		OS.delay_msec(5000)
		print("beat frames=", Engine.get_frames_drawn())


func _initialize() -> void:
	_beat = Thread.new()
	_beat.start(_heartbeat)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _W() -> Node:
	return root.get_node("World")


## Place `defs` side by side (2 tiles apart) in a free row near the home; returns [ids, centre tile] or [[], home].
func _row(defs: Array, rot: int = 0) -> Array:
	var W := _W()
	for r in range(2, 16):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var o := Vector2i(_home.x + dx, _home.y + dy)
				var ids: Array = []
				print("try ", o)
				var ok := true
				for i in defs.size():
					var id: int = W.place_object(str(defs[i]), Vector2i(o.x + i * 2, o.y), rot)
					if id < 0:
						ok = false
						break
					ids.append(id)
				if ok:
					return [ids, Vector2i(o.x + defs.size() - 1, o.y)]
				for id in ids:
					W.remove_object(id)
	return [[], _home]


func _shot(name: String, caption: String, tile: Vector2i, zoom: float = 4.0) -> void:
	var lv = _main.lot_view
	lv.set_zoom(zoom)
	lv.focus_tile(tile + Vector2i(-1, -1))        # objects stand above the ground point the camera aims at
	print("shot ", name)
	_cap.text = caption
	_cap.position = Vector2(400, 80) if _main.hud.visible else Vector2(20, 20)
	await _secs(1.4)
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [_out, name]
	root.get_texture().get_image().save_png(p)
	print("saved ", p)


func _st(id: int, key: String, v: Variant) -> void:
	_W().set_object_state(id, key, v)


func _case_plants() -> void:
	var r := await _row(["plant", "plant", "plant"])
	var ids: Array = r[0]
	if ids.is_empty():
		print("no room for plants")
		return
	_st(ids[0], "water", 3.0)
	_st(ids[1], "water", 9.5)
	_st(ids[2], "water", 0.5)
	await _shot("plants_dry_watered_wilting", "plant: dry (left), watered (middle), wilting (right)", r[1], 3.6)


func _case_pair(defs: String, name: String, caption: String, key: String, a: float, b: float) -> void:
	var r := await _row([defs, defs])
	var ids: Array = r[0]
	if ids.is_empty():
		return
	_st(ids[0], key, a)
	_st(ids[1], key, b)
	await _shot(name, caption, r[1], 3.2)


func _cmd(fid: int, iid: String, target: int) -> bool:
	var f = _W().get_folk(fid)
	for n in ["energy", "hygiene", "bladder", "social", "hunger", "fun"]:
		if f.needs.has(n):
			f.needs[n].set_value(10.0)
	var ir := Interaction.create(iid, f, target, true)
	if ir == null:
		return false
	f.idle_until_min = 0
	f.enqueue(ir)
	root.get_node("SimDirector")._fill(f)
	return true


func _until_running(fid: int) -> void:
	var f = _W().get_folk(fid)
	for i in 80:
		if f.current != null and str(f.current.state) == "running":
			return
		root.get_node("Clock").advance_minutes(1)


## Objects in a row, folk `hh[i]` doing `cmds[i] = [def, object index, fraction]` (the action is set to that fraction done), shown with the HUD when `hud`.
func _scene(name: String, caption: String, defs: Array, cmds: Array, hh: Array, hud: bool, zoom: float) -> void:
	var r := await _row(defs)
	if (r[0] as Array).is_empty():
		print("no room for ", name)
		return
	for i in cmds.size():
		var fid: int = hh[i]
		var fvw = _main.lot_view.get_folk_view(fid)
		if fvw != null:
			fvw.remove_meta("level_hidden")
		if not _cmd(fid, str(cmds[i][0]), r[0][int(cmds[i][1])]):
			print("could not command ", cmds[i])
	for i in cmds.size():
		_until_running(hh[i])
	root.get_node("Clock").speed = 1
	await _secs(7.0)            # the views walk to the objects (they only move while time runs)
	root.get_node("Clock").speed = 0
	for i in cmds.size():
		var f = _W().get_folk(hh[i])
		if f.current != null:
			f.current.elapsed_min = float(cmds[i][2]) * f.current.duration()
	if hud:
		_main.hud.visible = true
		_main.hud.tips.visible = false
		_main.hud.tracker.visible = false
		_main.hud.toasts.visible = false
		_main.hud.select_folk(hh[0])
		_main.lot_view._set_selected("folk", hh[0])
	var t0: Vector2i = _W().get_folk(hh[0]).tile
	var t1: Vector2i = _W().get_folk(hh[maxi(cmds.size() - 1, 0)]).tile
	await _shot(name, caption, Vector2i((t0.x + t1.x) / 2 - 1, (t0.y + t1.y) / 2 - 1), zoom)      # aim between the acting folk, a little up-left so they are not at the top edge
	_main.hud.visible = false
	for i in cmds.size():
		var f2 = _W().get_folk(hh[i])
		f2.queue.clear()
		if f2.current != null:
			f2.current.finish(false)
		f2.current = null
		var fvw2 = _main.lot_view.get_folk_view(hh[i])
		if fvw2 != null:
			fvw2.set_meta("level_hidden", true)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") or _out.begins_with("user://") else _out)
	var only: Array = (args[1] as String).split(",") if args.size() > 1 else []
	print("booting")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var rr := RandomNumberGenerator.new()
	rr.seed = 101
	_main.start_new_game(HouseholdSetup.make_household("family", rr), str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	await _frames(20)
	print("started")
	var W := _W()
	_main.hud.visible = false
	var hh: Array = []
	for f in W.all_folk():
		if int(f.household_id) == 1:
			hh.append(f.id)
			f.idle_until_min = 1 << 30
	for fid in hh:
		var fvw = _main.lot_view.get_folk_view(fid)
		if fvw != null:
			fvw.set_meta("level_hidden", true)       # keep the household out of the close-ups
	_home = W.get_folk(hh[0]).tile
	print("home ", _home)
	_main.lot_view._set_selected("none", -1)
	_cap = Label.new()
	_cap.position = Vector2(20, 20)
	_cap.add_theme_font_size_override("font_size", 26)
	_cap.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_cap.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_cap.add_theme_constant_override("outline_size", 8)
	var cl := CanvasLayer.new()
	cl.add_child(_cap)
	root.add_child(cl)
	if only.is_empty() or "plants" in only:
		await _case_plants()
	if only.is_empty() or "toilets" in only:
		await _case_pair("toilet", "toilet_clean_vs_dirty", "toilet: clean (left), dirty (right)", "dirtiness", 0.0, 9.0)
	if only.is_empty() or "sinks" in only:
		await _case_pair("sink", "sink_clean_vs_dirty", "sink: clean (left), dirty (right)", "dirtiness", 0.0, 9.0)
	if only.is_empty() or "broken" in only:
		var r := await _row(["tv", "stove"])
		if not (r[0] as Array).is_empty():
			_st(r[0][0], "broken", true)
			_st(r[0][1], "broken", true)
			await _shot("broken_sparks", "broken TV and stove: dark tint, sparks and smoke", r[1], 3.2)
	if only.is_empty() or "tv" in only:
		var r2 := await _row(["tv", "tv", "computer"])
		if not (r2[0] as Array).is_empty():
			_st(r2[0][1], "on", true)
			_st(r2[0][2], "on", true)
			await _shot("tv_on", "TV off (left), TV on (middle), computer on (right)", r2[1], 3.2)
	if only.is_empty() or "beds" in only:
		var r3 := await _row(["bed", "bed"])
		if not (r3[0] as Array).is_empty():
			_st(r3[0][1], "made", false)
			await _shot("bed_made_vs_unmade", "bed: made (left), unmade (right)", r3[1], 3.6)
	if only.is_empty() or "easel" in only:
		var r4 := await _row(["easel", "easel", "easel"])
		if not (r4[0] as Array).is_empty():
			_st(r4[0][1], "progress", 30.0)
			_st(r4[0][2], "progress", 80.0)
			await _shot("easel_progress", "easel: blank, 30%, 80%", r4[1], 3.2)
	if only.is_empty() or "garden" in only:
		var r5 := await _row(["garden_plot", "garden_plot", "garden_plot", "garden_plot"])
		if not (r5[0] as Array).is_empty():
			var g: Array = r5[0]
			_st(g[0], "growth", 0.0)
			_st(g[1], "growth", 2.0)
			_st(g[2], "growth", 3.6)
			_st(g[3], "growth", 9.0)
			await _shot("garden_stages", "garden: bare, sprouts, growing, ripe", r5[1], 5.0)
	if only.is_empty() or "lamps" in only:
		var r6 := await _row(["lamp", "lamp", "pendant_light"])
		if not (r6[0] as Array).is_empty():
			_st(r6[0][1], "on", false)
			await _shot("lamps", "lamp on (left), lamp off (middle), pendant on", r6[1], 3.2)
	if only.is_empty() or "use" in only:
		await _scene("stove_fridge_tv_in_use", "stove burners glow, fridge door open, TV on while used", ["stove", "fridge", "tv"], [["cook_meal", 0, 0.3], ["grab_snack", 1, 0.3], ["watch_tv", 2, 0.3]], hh, false, 3.4)
	if only.is_empty() or "rings" in only:
		await _scene("progress_ring_30_and_80", "progress rings: cooking 30%, painting 80% (selected + household)", ["stove", "easel"], [["cook_meal", 0, 0.3], ["paint_canvas", 1, 0.8]], hh, true, 5.5)
	print("done")
	quit(0)
	await _secs(3.0)
	OS.kill(OS.get_process_id())        # a windowed quit can hang; this is our own process
