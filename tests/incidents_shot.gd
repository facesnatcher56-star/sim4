extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/incidents_shot.gd -- <scenario> out.png
## Scenarios: debug | grave | death | hospital      (read the PNG)
var _frames := 0
var _main: Node = null
var _out := "user://incidents.png"
var _scn := "debug"
var _grave_tile := Vector2i.ZERO

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
		var folk: Array = W.all_folk()
		var f = folk[0]
		match _scn:
			"debug":
				hud.select_folk(f.id) if hud.has_method("select_folk") else null
				hud.incident_debug.show_for(f.id)
			"grave":
				var victim = folk[1]
				Aging.kill(victim.id, "heart_attack")
				var gs: Array = W.objects_of_def("grave")
				if not gs.is_empty():
					_grave_tile = gs[0].tile
					Neighborhood.focus_camera(_grave_tile)
					print("grave at ", _grave_tile, " tooltip: ", Graves.hover_text(gs[0]).replace("\n", " / "))
			"death":
				Aging.kill(folk[1].id, "heart_attack")
			"hospital":
				Hospital.injure(f, 1, "a trip")
				Hospital.fall_ill(f, 1, "a bug")
				hud.folk_panel.show_folk(f)
				root.get_node("Events").emit_signal("notification", "%s was rushed to hospital with a heart attack." % f.name, "bad")
	if _frames == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
