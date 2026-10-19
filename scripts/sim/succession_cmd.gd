class_name SuccessionCmd
extends RefCounted
## Command handlers of task 15 (called from command_actions.gd): the player picks the heir, or chooses who to play when nobody is left.
##   set_heir {heir_id}                      heir_id -1 clears the pick
##   choose_successor {choice, household?}   choice: "relative:<id>" | "townie:<id>" | "town" | "new" | "later" (SuccessionNobody); household = a HouseholdSetup dict for "new"

static func set_heir(e: Dictionary) -> Dictionary:
	return Succession.pick_heir(int(e["player_id"]), int(e["args"].get("heir_id", -1)))

static func choose_successor(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	return SuccessionNobody.choose(int(e["player_id"]), str(a.get("choice", "")), a.get("household", {}))
