extends SceneTree
## Not a unit test: task 41 part C UI screenshots under a look (default grounded). Windowed, Forward+. One screen per process.
## godot --path . --rendering-method forward_plus --script res://tests/art41c_ui_shot.gd -- <out dir> <WxH> <look> <screen>
## screens: title picker creator hud pie goals career household help toasts build map town council money settings
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _notify(text: String, kind: String) -> void:
	root.get_node("Events").emit_signal("notification", text, kind)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var res := args[1].split("x")
	var look := args[2]
	var scr: String = args[3]
	var size := Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	Looks.set_look(look)
	await _frames(5)
	if scr in ["title"]:
		pass
	elif scr in ["picker", "creator"]:
		_main.title.visible = false
		_main.start_picker.open()
		_main.start_picker.visible = true
		if scr == "creator":
			_main.start_picker.select("sandbox")
			_main.start_picker._open_creator(true)
	else:
		load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
		_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7, "home_state": "furnished"})
		await _frames(30)
		Looks.set_look(look)
		await _frames(10)
		var hud = _main.hud
		var W = root.get_node("World")
		var f = W.all_folk()[0]
		var vp := root.get_visible_rect().size
		root.get_node("Clock").set_speed(0)
		var cars = load("res://scripts/systems/careers.gd")
		match scr:
			"pie":
				hud.pie.open_for(f, "folk", W.all_folk()[1].id, vp * 0.5)
			"goals":
				hud.goals_dialog.show_for(f.id)
			"career":
				cars.make_offer(f, "cook", 1)
				hud.career_dialog.show_for(f.id)
			"household":
				hud.household_dialog.show_for(f.id)
			"help":
				hud.help_dialog.show_for(f.id)
			"toasts":
				_notify("Mira is hosting a party gathering.", "relationship")
				_notify("Bill overdue! Late fee 10 added (now 110 coins).", "warn")
				_notify("Tobin turned 21 and is now an adult.", "birthday")
				_notify("Fell asleep at the table. They are in hospital.", "bad")
				_notify("It is going to snow tonight.", "weather")
			"build":
				hud.build_panel.set_active(true)
				_notify("Can't place here", "warn")
			"map":
				hud.travel_panel.toggle()
			"town":
				hud.life_hub.toggle_for(f.id)
			"council":
				hud.town_dialog.toggle_for(f.id)
			"money":
				hud.money_hub.toggle_for(f.id)
			"settings":
				hud.settings_dialog.show_for(-1)
			"hud":
				hud.tips.visible = false
	await create_timer(1.5).timeout
	await _frames(5)
	var img: Image = root.get_texture().get_image()
	if img.get_size() != size:
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var p := "%s/art41c_ui_%s_%dx%d.png" % [out, scr, size.x, size.y]
	img.save_png(p)
	print("saved ", p)
	OS.kill(OS.get_process_id())
