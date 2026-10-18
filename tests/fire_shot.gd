extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/fire_shot.gd -- <scenario> out.png
## Scenarios: fire | big | after | people      (read the PNG)
var _frames := 0
var _main: Node = null
var _out := "user://fire.png"
var _scn := "fire"

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
	if _frames == 5:
		load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
		_main.start_new_game(_main.default_household())
	if _frames == 30 and _main.playing:
		var W = root.get_node("World")
		var stoves: Array = W.objects_of_def("stove")
		var st = stoves[0]
		for cand in stoves:
			if FireRules.lot_of(cand.tile) == Neighborhood.HOME:
				st = cand
		print("stove at ", st.tile, " objects ", W.all_objects().size())
		Neighborhood.focus_camera(st.tile)
		root.get_node("Clock").set_speed(0)
		var lv = root.get_tree().get_first_node_in_group("lot_view")
		if lv != null:
			lv._zoom_target = 7.0
			lv._zoom = 7.0
		match _scn:
			"fire":
				Fire.ignite(st, "cooking", {"stage": 2})
			"big":
				Fire.ignite(st, "cooking", {"stage": 3})
				for o in W.objects_in_radius(st.tile, 3.5):
					if not o.is_wall_mounted():
						Fire.ignite(o, "cooking", {"stage": 3})
				root.get_node("Clock").advance_minutes(2)
			"after":
				Fire.ignite(st, "cooking")
				for o in W.objects_in_radius(st.tile, 2.5):
					if not o.is_wall_mounted():
						Fire.ignite(o, "cooking")
				for fi in Fire.active():
					FireSpread._consume(fi)
				Fire.extinguish_lot("home", "brigade")
			"people":
				Fire.ignite(st, "cooking", {"stage": 2})
				root.get_node("Clock").advance_minutes(3)
				root.get_node("Clock").set_speed(1)
	if _frames == 120:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		var lv2 = root.get_tree().get_first_node_in_group("lot_view")
		var fvn = lv2.get_node_or_null("FireView") if lv2 != null else null
		print("FireView ", fvn, " scorch ", Fire.scorch.size(), " drawn ", fvn.scorch_count() if fvn != null else -1, " emitters ", fvn.emitter_count() if fvn != null else -1)
		print("saved ", _out, " ", img.get_size(), " fires=", Fire.fires.size(), " smoke=", Fire.smoke_of("home"))
		quit(0)
	return false
