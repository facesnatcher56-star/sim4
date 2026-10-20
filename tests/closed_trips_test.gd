extends RefCounted
## No trip to a shut door (task fixes38): an outing of a person's own is not started when the place will be closed by the time they
## arrive.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	WorldIface.coins[1] = 3000
	# the gym is open until 22:00: a quiet (own) walk at 21:50 arrives too late / with no time left; the player's order is still allowed
	Kit.set_time(2, 21, 50)
	_check(Venues.is_open("gym") and not Venues.open_for("gym", SimEnv.now_min(), 30), "gym is open at 21:50 but not for another 30 minutes")
	var own: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true})
	_check(not bool(own["ok"]) and str(own["reason"]).find("closed by the time") >= 0, "own outing at 21:50 is not started: %s" % str(own.get("reason", "")))
	_check(Neighborhood.heading_to(mira.id) == "" and Neighborhood.where(mira.id) == "home", "nobody set off")
	var ordered: Dictionary = Neighborhood.travel([mira.id], "gym", {})
	_check(bool(ordered["ok"]), "a player order at 21:50 is still allowed: %s" % str(ordered.get("reason", "")))
	Neighborhood.go_home([], {"instant": true})
	Kit.set_time(2, 12)
	var noon: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true})
	_check(bool(noon["ok"]), "own outing at noon is fine: %s" % str(noon.get("reason", "")))
	Neighborhood.go_home([], {"instant": true})
	# hours maths
	var night: int = 2 * 1440 + 3 * 60
	_check(not Venues.open_for("cafe", night, 0), "cafe is shut at 03:00")
	_check(Venues.open_for("park", 1 * 1440 + 12 * 60, 60), "park is open for an hour at noon")
	Kit.teardown()
	return fails
