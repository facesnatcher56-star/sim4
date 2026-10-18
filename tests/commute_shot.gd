extends SceneTree
## Not a unit test: windowed screenshots of a morning commute (a Folk walks to the office along the sidewalk, enters).
## godot --path . --resolution 1600x900 --script res://tests/commute_shot.gd -- out_prefix [career]
var _main: Node = null

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://commute"
	var career: String = args[1] if args.size() > 1 else "coder"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7})
	await _frames(25)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	Weather.force("sunny", 0.0)
	var lv = _main.lot_view
	_main.hud.visible = false
	var me = SysUtil.residents()[0]
	for f in SysUtil.residents():
		f.idle_until_min = 1 << 30
	Careers.hire(me, career, 1)
	var lot: String = Workplace.lot_for(career)
	var door: Vector2i = NeighborhoodLots.entry_tile(lot)
	clock.total_minutes = 1 * 1440 + int((me.work_start - 1.2) * 60.0)
	lv.select("folk", me.id)
	lv.focus_tile(me.tile)
	lv.set_zoom(16.0)
	lv._zoom = lv._zoom_target
	var shots := {"start": false, "mid": false, "near": false}
	var guard := 0
	while guard < 240:
		guard += 1
		clock.advance_minutes(1)
		await create_timer(0.45).timeout
		var left: int = WorldIface.path_length(me.tile, door)
		var st: String = str(Commute.trips.get(me.id, {}).get("state", ""))
		if st == "out" and not shots["start"]:
			shots["start"] = true
			lv.focus_tile(me.tile)
			await create_timer(1.2).timeout
			root.get_texture().get_image().save_png("%s_1_leaving.png" % prefix)
			print("leaving: tile ", me.tile, " door ", door, " steps ", left)
		if st == "out" and left < 45 and not shots["mid"]:
			shots["mid"] = true
			lv.focus_tile(me.tile)
			await create_timer(1.2).timeout
			root.get_texture().get_image().save_png("%s_2_street.png" % prefix)
			print("street: tile ", me.tile, " lot '", NeighborhoodLots.lot_at(me.tile), "' steps ", left)
		if st == "out" and left < 6 and not shots["near"]:
			shots["near"] = true
			lv.focus_tile(me.tile)
			await create_timer(1.2).timeout
			root.get_texture().get_image().save_png("%s_3_door.png" % prefix)
			print("door: tile ", me.tile, " steps ", left)
		if st == "in":
			break
	await _frames(10)
	print("final state ", Commute.trips.get(me.id, {}), " away ", SysUtil.is_away(me), " tile ", me.tile, " lot ", NeighborhoodLots.lot_at(me.tile), " minutes ", guard)
	if Away.is_visible(me.id):
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("%s_4_working.png" % prefix)
	quit(0)
