extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/life_shot.gd -- <tab> <kind> <place> out.png
## Tabs: places | study | health | pets | phone | news | jobs.  Example: -- places food restaurant out.png
var _frames := 0
var _main: Node = null
var _out := "user://life.png"
var _tab := "places"
var _kind := ""
var _place := ""

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_tab = args[0]
		if args.size() > 1:
			_kind = "" if args[1] == "-" else args[1]
		if args.size() > 2:
			_place = "" if args[2] == "-" else args[2]
		if args.size() > 3:
			_out = args[3]
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
		var hid: int = int(f.household_id)
		WorldIface.coins[hid] = 3000
		root.get_node("Clock").total_minutes = 2 * 1440 + 13 * 60
		for t in Story.alive_townies().slice(0, 4):
			RelationshipService.add_both(f.id, int(t["id"]), "friendship", 45.0)
		if _tab == "pets":
			PetState.add_pet(hid, "dog", "Rex", 20.0)
			PetState.add_pet(hid, "cat", "Mittens", 20.0)
		hud.life_hub.tab = _tab
		hud.life_hub.kind = _kind
		hud.life_hub.place_id = _place
		hud.life_hub.show_for(f.id)
	if _frames == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
