extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/health_shot.gd -- <scenario> out.png
## Scenarios: collapse | ill       (read the PNG)
var _frames := 0
var _main: Node = null
var _out := "user://health.png"
var _scn := "collapse"

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_scn = args[0]
		if args.size() > 1:
			_out = args[1]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var hud = _main.hud
	if _frames == 5:
		load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
		_main.start_new_game(_main.default_household())
	if _frames == 30 and _main.playing:
		var W = root.get_node("World")
		var f = W.all_folk()[0]
		match _scn:
			"collapse":
				f.needs["hunger"].set_value(-100.0)
				Health.collapse(f, "hunger")
				hud.folk_panel.show_folk(f)
			"ill":
				Incidents.force("catch_flu", {"folk_id": f.id})
				Health.injure(f, 1, "a trip")
				f.add_buff("shivering")
				hud.folk_panel.show_folk(f)
	if _frames == 100:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
