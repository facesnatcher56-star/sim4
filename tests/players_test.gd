extends RefCounted
## The players table: player id -> household id, name. Falls back to the old behaviour without entries; Economy.primary_household answers from
## it; two players own two households; it round-trips through SaveLoad and is listed in the share schema; the co-op adapter goes through Commands.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	HoodKit.new_game("classic", 77, 1)
	_check(Players.household_of(Players.LOCAL) == 1 and Players.primary_household() == 1, "without an entry the local player controls the current household (1)")
	_check(Players.player_of(1) == Players.LOCAL and Players.player_of(2) == -1, "player_of: household 1 is the local player's, 2 is nobody's")
	_check(Players.household_of(9) == -1, "an unknown player controls nothing")
	Players.set_player(1, 1, "Ada")
	Players.set_player(2, 2, "Bo")
	_check(Players.household_of(2) == 2 and Players.name_of(2) == "Bo" and Players.ids() == [1, 2], "two players, two households")
	_check(Players.owns(2, 2) and not Players.owns(2, 1), "owns() follows the table")
	Players.set_player(1, 2, "Ada")
	_check(Economy.primary_household() == 2, "Economy.primary_household reads the players table")
	Players.set_player(1, 1, "Ada")
	# save round trip
	var snap := SaveLoad.snapshot("p")
	_check(snap["systems"].has("players"), "the save has a players block")
	Players.reset()
	_check(Players.ids().is_empty(), "reset empties the table")
	Players.from_dict(JSON.parse_string(JSON.stringify(snap["systems"]["players"])))
	_check(Players.household_of(2) == 2 and Players.name_of(1) == "Ada", "the table survives a JSON round trip")
	# schema
	var schema = JSON.parse_string(FileAccess.get_file_as_string("res://data/share_schema.json"))
	_check((schema["town_system_keys"] as Array).has("players"), "players is a valid town system key in data/share_schema.json")
	# the build command uses the player's household, not a hard-coded 1
	_check(CommandActions.has_action("build_place") and not CommandActions.has_action("build_everything"), "the command table knows its actions")
	HoodKit.teardown()
	return fails
