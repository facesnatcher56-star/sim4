extends RefCounted
## Command log replay (24A tests): play a short session through Commands.run (an interaction, a build placement, a trip to the park and back),
## record the log, replay it on a FRESH game from the same seed => the same state hash (world + story + saved systems). Also: the log is
## bounded, numbered, carries the game minute, and a refused command is logged with ok = false.

const HoodKit := preload("res://tests/hood_kit.gd")
const Kit := preload("res://tests/coop_kit.gd")
const Det := preload("res://tests/determinism_test.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _hashes() -> String:
	return "%s|%s|%s" % [CoopHash.of_world(), Det.story_hash(), Det.systems_hash()]

func _free_tile(w: Node, def_id: String) -> Vector2i:
	var o: Vector2i = w.starter_spawn_tiles[0]
	for r in range(2, 14):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var t := o + Vector2i(dx, dy)
				if w.in_bounds(t) and w.can_place(def_id, t, 0, 0):
					return t
	return Vector2i(-1, -1)

func _session(replay_of: Array) -> Dictionary:
	HoodKit.teardown()
	SimSeed.apply(909)
	var folk: Array = HoodKit.new_game("classic", 909, 909)
	Commands.reset()
	var w: Node = HoodKit.world()
	var advance := func(n: int): HoodKit.run(n)
	if not replay_of.is_empty():
		var results: Array = Commands.replay(replay_of, advance)
		HoodKit.run(int(replay_of[-1]["game_minute"]) + 120 - SimEnv.now_min())
		return {"hash": _hashes(), "log": Commands.since(0), "results": results, "folk": folk}
	HoodKit.run(40)
	var cmd := Kit.find_command()
	var r1 := {"ok": false}
	if not cmd.is_empty():
		r1 = Commands.run({"folk_id": int(cmd["folk"].id), "action": "interact", "args": {"interaction_id": cmd["iid"], "target_id": cmd["tid"]}})
	HoodKit.run(25)
	var tile := _free_tile(w, "chair")
	var r2 := Commands.run({"folk_id": int(folk[0].id), "action": "build_place", "args": {"def_id": "chair", "tile": tile, "rot": 0, "level": 0}})
	HoodKit.run(15)
	var r3 := Commands.run({"folk_id": int(folk[2].id), "action": "travel", "args": {"folk_ids": [int(folk[2].id)], "lot_id": "park", "opts": {"quiet": true, "fast": true, "free": true}}})
	HoodKit.run(60)
	var r4 := Commands.run({"folk_id": int(folk[2].id), "action": "go_home", "args": {"folk_ids": [int(folk[2].id)], "opts": {"quiet": true, "fast": true, "free": true}}})
	var r5 := Commands.run({"folk_id": int(folk[1].id), "action": "nonsense"})
	HoodKit.run(120)
	return {"hash": _hashes(), "log": Commands.since(0), "results": [r1, r2, r3, r4, r5], "folk": folk}

func run() -> Array:
	fails = []
	var a := _session([])
	var log: Array = a["log"]
	_check(log.size() == 5, "five commands logged (%d)" % log.size())
	var seqs_ok := true
	for i in log.size():
		if int(log[i]["seq"]) != i + 1:
			seqs_ok = false
	_check(seqs_ok, "seq numbers run 1..n")
	_check(int(log[-1]["game_minute"]) > int(log[0]["game_minute"]) and bool(log[0].has("player_id")), "entries carry the game minute and the player id")
	_check(not bool(log[4]["ok"]) and not bool(a["results"][4]["ok"]), "an unknown action is refused and logged with ok = false")
	_check(bool(a["results"][1]["ok"]) and int(a["results"][1].get("id", -1)) >= 0, "the build placement worked (%s)" % str(a["results"][1]))
	_check(bool(a["results"][2]["ok"]), "the trip to the park worked (%s)" % str(a["results"][2]))
	var recorded: Array = []
	for e in log:
		recorded.append({"player_id": e["player_id"], "folk_id": e["folk_id"], "action": e["action"], "args": e["args"], "game_minute": e["game_minute"]})
	HoodKit.teardown()
	var b := _session(recorded)
	_check(a["hash"] == b["hash"], "replay on a fresh game from the same seed gives the same state hash: %s vs %s" % [a["hash"], b["hash"]])
	_check(b["log"].size() == log.size(), "the replay logged the same number of commands")
	for i in mini(b["results"].size(), a["results"].size()):
		_check(bool(b["results"][i]["ok"]) == bool(a["results"][i]["ok"]), "replayed command %d has the same outcome" % i)
	# bounded log
	Commands.reset()
	for i in Commands.LOG_CAP + 25:
		Commands.run({"action": "nonsense"})
	_check(Commands.log.size() == Commands.LOG_CAP and Commands.seq == Commands.LOG_CAP + 25, "the log is a bounded ring buffer (%d entries, seq %d)" % [Commands.log.size(), Commands.seq])
	HoodKit.teardown()
	return fails
