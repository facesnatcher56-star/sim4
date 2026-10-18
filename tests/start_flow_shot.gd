extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1600x900 --script res://tests/start_flow_shot.gd -- <scenario> out.png
## Scenarios: picker | picker_hard | creator | creator_family | game_<id> (solo couple family roommates) | tracker | nudge
var _frames := 0
var _main: Node = null
var _out := "user://start.png"
var _scn := "picker"

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0: _scn = args[0]
		if args.size() > 1: _out = args[1]
		GameSettings.path = "user://settings_shot.cfg"
		GameSettings.load_settings()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var sp = _main.start_picker
	if _frames == 5:
		UIPrefs.set_flag("tips_seen", false)
		_main.title.visible = false
		sp.open()
		sp.visible = true
		match _scn:
			"picker_hard": sp.set_difficulty("hard")
			"creator":
				sp.select("sandbox")
				sp._open_creator(true)
			"creator_family":
				sp.select("family")
				sp._open_creator(false)
			"flow":      # the real buttons: title New Game -> Start
				_main.title.visible = true
				sp.visible = false
				_main.title.main_box.get_child(2).pressed.emit()
				sp.start_btn.pressed.emit()
			"tracker", "nudge":
				sp.select("solo")
				sp._emit_chosen()
			_:
				if _scn.begins_with("game_"):
					sp.select(_scn.substr(5))
					sp._emit_chosen()
	if _frames == 40 and _scn == "tracker":
		var f = root.get_node("World").all_folk()[0]
		Careers.hire(f, Careers.career_ids()[0], 1)
	if _frames == 40 and _scn == "nudge":
		for g in Scenario.goals():
			ScenarioGoals.complete(str(g["id"]))
	if _frames == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
