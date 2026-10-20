extends SceneTree
## Screenshot helper (not a test), task 32d: godot --path . --resolution 1280x720 --script res://tests/pov32d_shot.gd -- <scenario> <out.png> [empty|furnished] [expand] [hours]
## Starts the game through the New Game screen's real config, optionally expands the folk panel, runs `hours` game hours, saves the window.
var _frames := 0
var _main: Node = null
var _scn := "solo"
var _out := "user://pov32d.png"
var _home := "empty"
var _expand := false
var _hours := 0
var _ran := false

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0: _scn = args[0]
		if args.size() > 1: _out = args[1]
		if args.size() > 2: _home = args[2]
		if args.size() > 3: _expand = args[3] == "expand"
		if args.size() > 4: _hours = int(args[4])
		GameSettings.path = "user://settings_shot.cfg"
		GameSettings.load_settings()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var sp = _main.start_picker
	if _frames == 5:
		UIPrefs.set_flag("tips_seen", false)
		UIPrefs.set_flag("folk_panel_expanded", false)
		_main.title.visible = false
		sp.open()
		sp.visible = true
		sp.select(_scn)
		if sp.has_method("set_home_state"):
			sp.set_home_state(_home)
		sp._emit_chosen()
	if _frames == 30 and _hours > 0:
		root.get_node("Clock").advance_minutes(_hours * 60)
	if _frames == 40 and _expand and _main.hud.folk_panel.has_method("set_expanded"):
		_main.hud.folk_panel.set_expanded(true)
	if _frames == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
