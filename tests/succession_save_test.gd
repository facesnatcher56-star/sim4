extends RefCounted
## Task 15: head, picked heir and the waiting "nobody left" question save and load (the players block), old saves without them still load, and a
## loaded waiting household is settled by the day row.

const K := preload("res://tests/succession_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = K.new_game()
	var head = folk[0]
	Succession.pick_heir(1, int(folk[2].id))
	var snap := SaveLoad.snapshot("s")
	var block: Dictionary = JSON.parse_string(JSON.stringify(snap["systems"]["players"]))
	_check(int((block["table"]["1"] as Dictionary)["head"]) == int(head.id), "the head is in the saved players block")
	Players.reset()
	Players.from_dict(block)
	_check(Succession.head_of(1) == int(head.id) and Succession.heir_of(1) == int(folk[2].id), "head and picked heir survive a JSON round trip")
	var schema = JSON.parse_string(FileAccess.get_file_as_string("res://data/share_schema.json"))
	_check((schema["town_system_keys"] as Array).has("players"), "the players block is a valid town key (shared towns carry the heir facts)")
	# an old save (players block without the new fields) loads with defaults
	Players.from_dict({"table": {"1": {"household_id": 1, "name": "Old"}}})
	_check(int(Players.field(1, "heir")) == -1 and not Succession.is_pending(1) and Succession.head_of(1) == int(head.id), "an old save loads: no pick, not waiting, head found again")
	# a waiting household round trips and is settled after the load
	Aging.kill(int(folk[1].id), "old age")
	Aging.kill(int(folk[2].id), "old age")
	K.townie("Quill", "adult")
	Aging.kill(int(head.id), "old age")
	_check(Succession.is_pending(1), "waiting before the save")
	var since: int = int(Players.field(1, "since"))
	var block2: Dictionary = JSON.parse_string(JSON.stringify(Players.to_dict()))
	Players.reset()
	Players.from_dict(block2)
	_check(Succession.is_pending(1) and str(Players.field(1, "late")) == "Mira" and int(Players.field(1, "since")) == since, "the waiting question and the name of the late head survive")
	Succession.on_day(since + SuccessionNobody.AUTO_DAYS)
	_check(not Succession.is_pending(1) and K.household_count() == 1, "the loaded household is settled by the day row")
	K.teardown()
	return fails
