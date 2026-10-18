extends SceneTree
## Not a unit test: boots the real game, simulates N game days with the real World, prints a report, saves screenshots.
## godot --path . --resolution 1600x900 --script res://tests/play_smoke.gd -- out_prefix days
var _main: Node = null
var _frames := 0
var _days := 2
var _prefix := "user://smoke"
var _stage := 0

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0: _prefix = args[0]
		if args.size() > 1: _days = int(args[1])
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		_main.start_new_game(_main.default_household())
	if _frames == 30 and _stage == 0:
		_stage = 1
		var clock = root.get_node("Clock")
		var dir = root.get_node("SimDirector")
		var t0 := Time.get_ticks_msec()
		for m in range(_days * 1440):
			clock.advance_minutes(1)
			if m % 720 == 360:
				_snap(m)
		print("simulated %d days in %d ms" % [_days, Time.get_ticks_msec() - t0])
		_report()
	if _frames == 60:
		var tex := root.get_texture()
		if tex != null and DisplayServer.get_name() != "headless":
			tex.get_image().save_png(_prefix + "_end.png")
		quit(0)
	return false

func _snap(m: int) -> void:
	pass

func _report() -> void:
	var w = root.get_node("World")
	for f in w.all_folk():
		var cur = f.current.def_id if f.current != null else "-"
		var needs := []
		for n in f.needs: needs.append("%s:%d" % [n, int(f.needs[n].value)])
		print("%s [%s] now=%s mood=%s away=%s | %s" % [f.name, ",".join(f.traits), cur, str(f.get_mood()), str(f.has_meta("away")), " ".join(needs)])
	var eco = load("res://scripts/systems/economy.gd")
	print("coins hh1: ", eco.balance(1))
