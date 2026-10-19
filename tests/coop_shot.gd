extends SceneTree
## Screenshot helper (not a test), WINDOWED (needs a display): godot --path . --resolution 1280x720 --script res://tests/coop_shot.gd -- <scenario> out.png
## Scenarios: lobby_host | lobby_join | pick | hud | alert | waiting | waiting_guest
##   lobby_*: the title menu's Co-op screen; pick: the household pick a joining player sees; hud: pace bar + name tags of two households;
##   alert: a loud alert on the HUD; waiting: the host is idle (asleep) while a guest plays -> the waiting panel (town stories + watch);
##   waiting_guest: the same moment seen from the guest's seat (_P.local_id = 2; in-process stand-in for a second window).
var _frames := 0
var _main: Node = null
var _out := "user://coop.png"
var _scn := "hud"
var _ses = null
var _guest := {}
var _P = load("res://scripts/systems/players.gd")

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
	var needs_game := not _scn.begins_with("lobby") and _scn != "pick"
	if _frames == 5:
		load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
		match _scn:
			"lobby_host", "lobby_join":
				_main.title.visible = false
				var l = load("res://scripts/ui/coop_lobby.gd").new()
				l.theme = _main.title.theme
				_main.add_child(l)
				if _scn == "lobby_join":
					l._show_tab(false)
			"pick":
				_main.title.visible = false
				var p = load("res://scripts/ui/coop_household_pick.gd").new()
				p.theme = _main.title.theme
				_main.add_child(p)
			_:
				_main.start_new_game(_main.default_household())
	if _frames == 30 and needs_game and _main.playing:
		_setup_game()
	if _frames == 60 and needs_game:
		_after()
	if _frames == (100 if needs_game else 40):
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		if _ses != null:
			_ses.stop()
		quit(0)
	return false

func _setup_game() -> void:
	_ses = load("res://scripts/net/coop_session.gd").ensure(self)
	var err = _ses.start_host(24680 + randi() % 200, "Host", 4, "normal", 180.0)
	if err != "":
		print("host failed: ", err)
	_P.set_player(1, _P.household_of(1), "Host")
	var folk: Array = []
	for i in 2:
		var f = load("res://scripts/systems/household_setup.gd").random_folk("adult", "none", ["Zed", "Zoe"])
		f["name"] = ["Zed", "Zoe"][i]
		folk.append(f)
	_guest = load("res://scripts/net/coop_households.gd").join(2, "Ann", {"name": "Newcomers", "folk": folk}, "")
	_ses.time.players_fn = func(): return [1, 2]          # the guest is not a real peer in this single-window shot: pretend it is connected
	print("guest joined: ", _guest.get("ok"), " lot ", _guest.get("lot"))
	load("res://scripts/systems/story.gd")._log("The bakery opened on Elm Street.")
	load("res://scripts/systems/chronicle_hook.gd").note("birth", "A baby was born on Elm Street.", [], "", 2, true)
	load("res://scripts/systems/chronicle_hook.gd").note("wedding", "Mira and Tobin got married.", [], "", 2, true)

func _after() -> void:
	var hud = _main.hud
	match _scn:
		"alert":
			_ses.host.local_alert.emit("A fire has broken out at your home!", -1, {"x": 5, "y": 5, "loud": true})
		"waiting", "waiting_guest":
			var mine := 1 if _scn == "waiting" else 2
			_P.local_id = mine
			for g in root.get_node("World").all_folk():
				var pid = _P.player_of(int(g.household_id))
				if pid == mine:
					g.set_meta("away", "work")             # my household is away: nothing for me to do
			hud.rebuild_folk_row()

