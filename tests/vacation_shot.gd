extends SceneTree
## Not a unit test: windowed screenshots of the cruise ship (outside, each deck) and of a holiday destination, plus the booking dialog.
## godot --path . --resolution 1600x900 --script res://tests/vacation_shot.gd -- out_prefix [shots...]
## shots (default all): ship, deck0, deck1, deck2, deck3, deckm1, port, beach, mountain, city, camping, dialog, tripdialog
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, prefix: String, wait: float = 1.0) -> void:
	await create_timer(wait).timeout
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://vacation"
	var want: Array = Array(args).slice(1) if args.size() > 1 else ["ship", "deck0", "deck1", "deck2", "deck3", "deckm1", "port", "beach", "mountain", "city", "camping", "dialog", "tripdialog"]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W: WorldGrid = root.get_node("World")
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 1})
	await _frames(20)
	var clock = root.get_node("Clock")
	var hud = _main.hud
	var lv = _main.lot_view
	Weather.force("sunny", 0.0)
	var folk: Array = W.all_folk().filter(func(x): return int(x.household_id) > 0 and not x.has_meta("visitor"))
	WorldIface.coins[int(folk[0].household_id)] = 20000
	var hid: int = int(folk[0].household_id)
	if want.has("dialog"):
		clock.set_speed(0)
		hud.vacation_dialog.show_for(int(folk[0].id))
		await _shot("dialog", prefix, 0.8)
		hud.vacation_dialog.dest = "cruise"
		hud.vacation_dialog.days = 5
		hud.vacation_dialog.refresh()
		await _shot("dialog_cruise", prefix, 0.8)
		hud.vacation_dialog.hide_dialog()
	# a Saturday morning: nobody is on the way to work
	clock.total_minutes = 5 * 1440 + 8 * 60
	clock.set_speed(0)
	var dests: Array = ["beach", "mountain", "city", "camping"].filter(func(d): return want.has(d))
	if not dests.is_empty():
		await _destination(String(dests[0]), hid, folk, prefix, W, lv, clock)
		quit()
		return
	var res: Dictionary = Vacation.book_and_go(hid, "cruise", {"length_days": 5, "cabin_class": "ocean", "seed": 3, "travel_min": 20})
	print("booked: ", res.get("ok", false), " ", res.get("reason", ""))
	clock.advance_minutes(45)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var t: Dictionary = Vacation.trip(int(res["trip"]))
	var rc: Rect2i = DestLoader.zone_rect(int(t["zone"]))
	var f0: Folk = SysUtil.folk(int(t["folk"][0]))
	print("on the ship: ", t["state"], " lot ", NeighborhoodLots.lot_at(f0.tile))
	await _frames(40)
	lv.select("folk", f0.id)
	if want.has("tripdialog"):
		hud.vacation_dialog.show_for(int(f0.id))
		await _shot("tripdialog", prefix, 0.8)
		hud.vacation_dialog.hide_dialog()
	hud.visible = true
	if want.has("ship"):
		lv.select("none", -1)
		lv.focus_tile(rc.position + Vector2i(16, 11))
		lv.set_zoom(40.0)
		lv._zoom = lv._zoom_target
		await _frames(30)
		await _shot("ship", prefix, 1.5)
		lv.select("folk", f0.id)
	lv.set_zoom(26.0)
	lv._zoom = lv._zoom_target
	var decks := {"deckm1": [-1, 13, 14], "deck0": [0, 16, 8], "deck1": [1, 16, 8], "deck2": [2, 12, 14], "deck3": [3, 8, 8]}
	for k in ["deckm1", "deck0", "deck1", "deck2", "deck3"]:
		if not want.has(k):
			continue
		f0.level = int(decks[k][0])
		f0.tile = rc.position + Vector2i(int(decks[k][1]), int(decks[k][2]))
		lv.focus_tile(f0.tile)
		await _frames(45)
		await _shot(k, prefix, 1.0)
	if want.has("port"):
		var dock_min: int = -1
		for e in t["cruise"]["timeline"]:
			if str(e["kind"]) == "dock":
				dock_min = int(e["min"])
		clock.advance_minutes(dock_min - clock.total_minutes + 130)
		await _frames(30)
		if int(t["cruise"]["port_zone"]) >= 0:
			var f1: Folk = SysUtil.folk(int(t["folk"][0]))
			lv.select("folk", f1.id)
			lv.focus_tile(f1.tile)
			lv.set_zoom(24.0)
			lv._zoom = lv._zoom_target
			await _frames(40)
			await _shot("port", prefix, 1.0)
	quit()


func _destination(dest: String, hid: int, folk: Array, prefix: String, W: WorldGrid, lv, clock) -> void:
	var r2: Dictionary = Vacation.book_and_go(hid, dest, {"length_days": 3, "seed": 5, "travel_min": 10})
	if not bool(r2["ok"]):
		print("booking failed: ", r2.get("reason", ""))
		return
	clock.advance_minutes(30)
	var t2: Dictionary = Vacation.trip(int(r2["trip"]))
	var rc2 := DestLoader.zone_rect(int(t2["zone"]))
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	var f2: Folk = SysUtil.folk(int(t2["folk"][0]))
	lv.select("folk", f2.id)
	lv.focus_tile(rc2.position + Vector2i(16, 11))
	lv.set_zoom(28.0)
	lv._zoom = lv._zoom_target
	await _frames(40)
	await _shot(dest, prefix, 1.2)