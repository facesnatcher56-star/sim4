extends SceneTree
## Not a unit test: boots the real game, simulates N game days with the real World, prints a report, saves screenshots.
## godot --path . --resolution 1600x900 --script res://tests/play_smoke.gd -- out_prefix days [job|nojob]
## `job` (default): the first folk is hired as a coder, so the run exercises the real commute (walk to the office, shift, walk home).
const Watchdog := preload("res://tests/watchdog.gd")
var _wd = null
var _main: Node = null
var _frames := 0
var _days := 2
var _prefix := "user://smoke"
var _stage := 0
var _job := true
var _away_min := 0        # game minutes in which somebody was away / at work / walking to or from work
var _commuting_min := 0
var _coins0 := 0

func _process(_d: float) -> bool:
	var args := Watchdog.user_args()
	if _main == null:
		_wd = Watchdog.start(Watchdog.budget_from(OS.get_cmdline_user_args(), 300.0), "play_smoke")
		if args.size() > 0: _prefix = args[0]
		if args.size() > 1: _days = int(args[1])
		if args.size() > 2: _job = args[2] != "nojob"
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		_main.start_new_game(_main.default_household())
		if _job:
			var first = root.get_node("World").all_folk()[0]
			print("hired %s as coder: %s" % [first.name, str(Careers.hire(first, "coder", 1))])
		_coins0 = Economy.balance(1)
	if _frames == 30 and _stage == 0:
		_stage = 1
		var clock = root.get_node("Clock")
		var dir = root.get_node("SimDirector")
		var t0 := Time.get_ticks_msec()
		for m in range(_days * 1440):
			clock.advance_minutes(1)
			var someone_away := false
			for fk in root.get_node("World").all_folk():
				if fk.household_id == 1 and (Away.active.has(fk.id) or Commute.active(fk.id)):
					someone_away = true
			if someone_away:
				_away_min += 1
			if m % 720 == 360:
				_snap(m)
		print("simulated %d days in %d ms" % [_days, Time.get_ticks_msec() - t0])
		_report()
	if _frames == 60:
		var tex := root.get_texture()
		if tex != null and DisplayServer.get_name() != "headless":
			tex.get_image().save_png(_prefix + "_end.png")
		_wd.stop()
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
	print("coins hh1: ", eco.balance(1), " (started at %d, gained %d)" % [_coins0, eco.balance(1) - _coins0])
	print("minutes with a household folk away / at work / commuting: %d of %d (job=%s)" % [_away_min, _days * 1440, str(_job)])
