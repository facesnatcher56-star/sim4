extends SceneTree
## Dev probe (not a test): boots the real game with a fixed seed, plays N game days and prints state hashes (CoopHash + one hash per
## save block). Used to prove a refactor keeps the simulation identical:  -- [days=2] [seed=4242]
const Watchdog := preload("res://tests/watchdog.gd")
var _wd = null
var _main: Node = null
var _frames := 0

static func digest(snap: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in snap:
		var v = snap[k]
		out[str(k)] = JSON.stringify(v, "", true).sha256_text().substr(0, 10)
		if v is Dictionary and str(k) == "systems":
			for sk in v:
				out["systems." + str(sk)] = JSON.stringify(v[sk], "", true).sha256_text().substr(0, 10)
	return out

func _process(_d: float) -> bool:
	var args := Watchdog.user_args()
	if _main == null:
		_wd = Watchdog.start(Watchdog.budget_from(OS.get_cmdline_user_args(), 600.0), "state_hash_probe")
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var sd := int(args[1]) if args.size() > 1 else 4242
		root.get_node("Clock").set_speed(0)          # real time must not move the game clock
		SimSeed.apply(sd)
		var hh: Dictionary = _main.default_household()
		for i in 3:
			hh["folk"][i]["name"] = ["Mira", "Tobin", "Wren"][i]      # default_household draws random names (setup UI, not sim)
		SimSeed.apply(sd)
		_main.start_new_game(hh, "classic", {"world_seed": sd})
		SimSeed.apply(sd)
		root.get_node("Clock").set_speed(0)
	if _frames == 30:
		var days := int(args[0]) if args.size() > 0 else 2
		var clock = root.get_node("Clock")
		for m in range(days * 1440):
			clock.advance_minutes(1)
		print("HASH coop=", CoopHash.of_world(), " minute=", clock.total_minutes)
		var d := digest(SaveLoad.snapshot("probe"))
		var keys: Array = d.keys()
		keys.sort()
		for k in keys:
			print("HASH ", k, " ", d[k])
		_wd.stop()
		quit(0)
	return false
