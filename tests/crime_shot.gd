extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/crime_shot.gd -- <scenario> out.png
## Scenarios: prompt | board | jail
var _frames := 0
var _main: Node = null
var _out := "user://crime.png"
var _scn := "prompt"

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
		var ids: Array = Story.townies.keys()
		ids.sort()
		match _scn:
			"prompt":
				JusticePlayer.ask(f.id, "A dangerous grudge", "%s is consumed by rage at %s. This could end very badly." % [f.name, Story.name_of(int(ids[2]))],
					[{"id": "step_in", "label": "Step in and calm things down"}, {"id": "ignore", "label": "Let it be"}], func(_c): pass, "step_in")
			"board":
				var c: Dictionary = CaseStore.create("burglary", int(ids[2]), -1, "town:2", {})
				CaseDiscovery.report(c, int(ids[3]), "noticed")
				var m: Dictionary = CaseStore.create("murder", int(ids[4]), int(ids[5]), "street", {})
				m["state"] = "closed"
				m["verdict"] = "guilty"
				var r: Dictionary = CaseStore.create("robbery", int(ids[6]), -1, "street", {})
				Prison.admit(int(ids[6]), r, 20, "prison")
				RelationshipService.add_both(f.id, int(ids[6]), "friendship", 50.0)
				JusticeState.rate_now = 47.0
				hud.case_board.show_for(f.id)
			"jail":
				var c2: Dictionary = CaseStore.create("assault", f.id, int(ids[2]), "street", {})
				c2["charge"] = "assault"
				JusticeSentence._apply(c2, f.id, {"type": "jail", "days": 4, "fine": 0})
				hud.folk_panel.show_folk(f)
	if _frames == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
