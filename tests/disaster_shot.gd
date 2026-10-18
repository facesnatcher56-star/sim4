extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/disaster_shot.gd -- <scenario> out.png
## Scenarios: siren | tornado | flood | quake | blizzard | blackout | wildfire | hail | meteor        (read the PNG)
var _frames := 0
var _main: Node = null
var _out := "user://disaster.png"
var _scn := "tornado"

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
	if _frames == 40 and _main.playing:
		var hid: int = Economy.primary_household()
		match _scn:
			"siren":
				DisasterState.siren_when_forced = true
				Incidents.force("tornado", {"lot": "home:%d" % hid, "outcome": 1})
			"tornado":
				Incidents.force("tornado", {"lot": "home:%d" % hid, "outcome": 1})
			"flood":
				Incidents.force("flood", {"lot": "home:%d" % hid, "outcome": 1})
			"quake":
				Incidents.force("earthquake", {"lot": "home:%d" % hid, "outcome": 1})
			"blizzard":
				Weather.force("snow", 0.8)
				Incidents.force("blizzard", {"lot": "home:%d" % hid, "outcome": 1})
			"blackout":
				SimEnv.clock().total_minutes = 21 * 60
				Incidents.force("power_outage", {"lot": "home:%d" % hid})
			"wildfire":
				Weather.force("heatwave")
				Incidents.force("wildfire", {"lot": "home:%d" % hid, "outcome": 0})
			"hail":
				Incidents.force("hailstorm", {"lot": "home:%d" % hid, "outcome": 1})
			"meteor":
				Incidents.force("meteor_strike", {"lot": "home:%d" % hid})
	if _frames == 42 and _scn == "tornado":
		SimEnv.events().emit_signal("game_event", "disaster", {"kind": "tornado", "phase": "impact", "minutes": 30, "folk_id": -1})
	if _frames == 95:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size(), " notes: ", ChronicleHook.recent.size())
		quit(0)
	return false
