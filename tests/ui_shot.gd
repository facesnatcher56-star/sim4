extends SceneTree
## Windowed screenshot helper (not a test): godot --path . --script res://tests/ui_shot.gd -- out.png [build]
## Boots main.tscn with --autostart semantics and saves the viewport after a short warm-up.
var _frames := 0
var _main: Node = null
var _out := "user://shot.png"
var _build := false

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0 and args[0].ends_with(".png"):
			_out = args[0]
		_build = "build" in args
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5 and _main.has_method("start_new_game"):
		_main.start_new_game(_main.default_household())
	if _frames == 60 and _build:
		_main.hud.build_panel.set_active(true)
	if _frames == 150:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
