extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1600x900 --script res://tests/ui_settings_shot.gd -- <scenario> out.png [ui_scale]
## Scenarios: display | gameplay | access | audio | controls | pause | title | confirm
var _frames := 0
var _main: Node = null
var _out := "user://settings.png"
var _scn := "display"

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0: _scn = args[0]
		if args.size() > 1: _out = args[1]
		GameSettings.path = "user://settings_shot.cfg"
		GameSettings.load_settings()
		if args.size() > 2: GameSettings.set_value("ui_scale", int(args[2]))
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var hud = _main.hud
	if _frames == 5:
		if _scn == "title":
			_main.title.settings_dialog.show_for(-1)
		else:
			load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
			_main.start_new_game(_main.default_household())
	if _frames == 30 and _main.playing:
		match _scn:
			"pause": hud.pause_menu.show_for(-1)
			"confirm": hud.request_quit_to_title()
			_:
				hud.settings_dialog.tab = _scn
				hud.settings_dialog.show_for(-1)
	if _frames == 70:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
