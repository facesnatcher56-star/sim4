extends SceneTree
## Screenshot helper for one-character play (not a test): godot --path . --resolution 1600x900 --script res://tools/solo_shot.gd -- <scene> out.png
## scenes: start | myself | homes | picker
var _frames := 0
var _main: Node = null
var _out := "user://solo.png"
var _scn := "start"

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
		if _scn != "picker":
			sp.select("solo")
			sp._emit_chosen()
	if _frames == 60 and _scn == "myself":
		var hud = _main.hud
		var f = hud._resolve(hud.selected_folk_id)
		for c in hud.folk_row.get_children():
			if c.name == "myself_button":
				c.pressed.emit()
	if _frames == 60 and _scn == "selfdump":
		var hud3 = _main.hud
		var f3 = hud3._resolve(hud3.selected_folk_id)
		print("SELF selected=%d folk=%s" % [hud3.selected_folk_id, str(f3 != null)])
		var iq = load("res://scripts/ui/interaction_query.gd")
		for e in iq.self_entries(f3):
			print("SELF %s | %s | enabled=%s | %s" % [e["id"], e["label"], str(e["enabled"]), e["reason"]])
		quit(0)
	if _frames == 60 and _scn == "homes":
		var hud2 = _main.hud
		hud2.money_hub.tab = "homes"
		hud2.money_hub.show_for(hud2.selected_folk_id)
	if _frames == 100:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
