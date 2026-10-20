extends RefCounted
## "Didn't make it to the bathroom" names who and what kind of place (a toast with no name tells the player nothing).

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var mira: Folk = Kit.new_game("classic")[0]
	var line: String = Loot.fill_text("{name} didn't make it to the bathroom ({where}).", mira)
	_check(line == "Mira didn't make it to the bathroom (at home).", "bathroom text names the folk and place: %s" % line)
	Neighborhood.travel([mira.id], "cafe", {"instant": true, "free": true})
	_check(Loot.where_text(mira) == "at " + Neighborhood.label_of("cafe"), "where text for a venue: %s" % Loot.where_text(mira))
	_check(str(SimEnv.data().interaction_def("have_accident")["on_finish"]).find("{name}") >= 0, "accident toast uses the name placeholder")
	Kit.teardown()
	return fails
