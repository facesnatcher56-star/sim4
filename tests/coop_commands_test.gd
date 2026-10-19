extends RefCounted
## CoopCommands adapter against the real sim: allowlist, validation and that apply() reaches SimDirector.command.

const HoodKit := preload("res://tests/hood_kit.gd")
const Kit := preload("res://tests/coop_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	HoodKit.new_game("classic")
	HoodKit.set_time(2, 9)
	HoodKit.run(5)
	var cmd := Kit.find_command()
	_check(not cmd.is_empty(), "the test world offers a runnable interaction")
	if cmd.is_empty():
		HoodKit.teardown()
		return fails
	var f: Folk = cmd["folk"]
	var env := {"player_id": 2, "folk_id": f.id, "action": "interact", "args": {"interaction_id": cmd["iid"], "target_id": cmd["tid"]}, "game_minute": 0, "seq": 1}
	_check(CoopCommands.allowed(2, f.id), "player 2 may command household 1")
	_check(not CoopCommands.allowed(1, f.id) and not CoopCommands.allowed(9, f.id), "unlisted players may not")
	var stranger := -1
	for g in WorldIface.all_folk():
		if int(g.household_id) <= 0:
			stranger = g.id
			break
	_check(stranger < 0 or not CoopCommands.allowed(2, stranger), "player 2 may not command a townie / stranger")
	_check(not CoopCommands.allowed(2, 987654), "unknown folk")
	_check(CoopCommands.check(env) == "", "valid envelope passes")
	var bad := env.duplicate(true)
	bad["action"] = "teleport"
	_check(CoopCommands.check(bad) != "", "unknown action refused")
	bad = env.duplicate(true)
	bad["args"] = {"interaction_id": "no_such_thing", "target_id": 1}
	_check(CoopCommands.check(bad) != "", "unknown interaction refused")
	bad = env.duplicate(true)
	bad["args"] = {"interaction_id": cmd["iid"], "target_id": "x"}
	_check(CoopCommands.check(bad) != "", "bad target type refused")
	bad = env.duplicate(true)
	bad["player_id"] = 1
	var q0 := f.queue.size()
	_check(not CoopCommands.apply(bad)["ok"] and f.queue.size() == q0, "a refused envelope changes nothing")
	var r := CoopCommands.apply(env)
	_check(r["ok"], "apply ok (%s)" % str(r.get("msg", "")))
	_check(f.current != null or f.queue.size() > q0, "the folk has the order (current or queued)")
	CoopCommands.set_allowlist({2: [77]})
	_check(not CoopCommands.allowed(2, f.id), "custom allowlist replaces the default")
	CoopCommands.set_allowlist({2: [1], 3: [1], 4: [1]})
	HoodKit.teardown()
	return fails
