extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/ui_scenes_shot.gd -- <scenario> out.png
## Scenarios: title | create | picker | game | pie_fridge | pie_folk | goals | career | offer | household | help | toasts | build | map | full
var _frames := 0
var _main: Node = null
var _out := "user://scene.png"
var _scn := "game"

func _careers():
	return load("res://scripts/systems/careers.gd")

func _notify(text: String, kind: String) -> void:
	root.get_node("Events").emit_signal("notification", text, kind)

func _find_obj(def_id: String) -> int:
	for o in root.get_node("World").objects.values():
		if str(o.def_id) == def_id:
			return int(o.id)
	return -1

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
		match _scn:
			"title":
				pass
			"create":
				_main.title.visible = false
				_main.start_picker.open()
				_main.start_picker.visible = true
				_main.start_picker.select("sandbox")
				_main.start_picker._open_creator(true)
			"picker":
				_main.title.visible = false
				_main.start_picker.open()
				_main.start_picker.visible = true
			_:
				load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
				_main.start_new_game(_main.default_household())
	if _frames == 30 and _main.playing:
		var f = root.get_node("World").all_folk()[0]
		var vp := root.get_visible_rect().size
		match _scn:
			"pie_fridge":
				hud.pie.open_for(f, "object", _find_obj("fridge"), vp * 0.5)
			"pie_folk":
				hud.pie.open_for(f, "folk", root.get_node("World").all_folk()[1].id, vp * 0.5)
			"goals":
				hud.goals_dialog.show_for(f.id)
			"career":
				_careers().make_offer(f, "cook", 1)
				hud.career_dialog.show_for(f.id)
			"offer":
				_careers().make_offer(f, "writer", 1)
			"household":
				hud.household_dialog.show_for(f.id)
			"help":
				hud.help_dialog.show_for(f.id)
			"toasts":
				_notify("Mira is hosting a party gathering.", "relationship")
				_notify("Bill overdue! Late fee 10 added (now 110 coins).", "warn")
				_notify("Tobin turned 21 and is now an adult.", "birthday")
				for i in 6:
					_notify("Wren fulfilled a whim: Eat something (+20)", "goal")
			"build":
				hud.build_panel.set_active(true)
				_notify("Can't place here", "warn")
			"map":
				hud.travel_panel.toggle()
			"full":
				hud.goals_dialog.show_for(f.id)
				_careers().make_offer(f, "cook", 1)
				_notify("Mira is hosting a party gathering.", "relationship")
				hud.tips.start(true)
				hud.build_panel.set_active(false)
	if _frames == 80:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
