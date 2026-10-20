extends RefCounted
## Task 32e: starting household members know each other (family-level relationships), and the Getting Started fridge goal
## reads "Buy a fridge and stock it" while the home has no fridge.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var c: Array = Kit.new_game("couple")
	var a: int = c[0].id
	var b: int = c[1].id
	_check(RelationshipBits.bit_for(a, b) in ["partner", "spouse"], "couple: partner/spouse bit (%s)" % RelationshipBits.bit_for(a, b))
	_check(RelationshipService.value(a, b, "friendship") > 55.0 and RelationshipService.value(b, a, "romance") >= 55.0, "couple: friendship above the get-to-know gate and high romance")
	var fa: Array = Kit.new_game("family")
	var p1: int = fa[0].id
	var p2: int = fa[1].id
	var kid: int = fa[2].id
	for p in [p1, p2]:
		_check(RelationshipService.value(p, kid, "friendship") >= 60.0 and RelationshipService.value(kid, p, "friendship") >= 60.0, "family: parent<->child friendship high")
		_check(RelationshipService.value(p, kid, "romance") == 0.0 and not RomanceRules.allowed(p, kid), "family: no romance with the child (RomanceRules respected)")
		_check(RelationshipBits.bit_for(kid, p) != "stranger", "family: child is not a stranger to a parent")
	_check(RelationshipService.value(p1, p2, "friendship") > 55.0, "family: spouses high friendship")
	var rm: Array = Kit.new_game("roommates")
	for i in 3:
		for j in 3:
			if i != j:
				var fr := RelationshipService.value(rm[i].id, rm[j].id, "friendship")
				_check(fr >= 15.0 and fr < 30.0, "roommates: acquaintance-level friendship (%s)" % fr)
				_check(RelationshipBits.bit_for(rm[i].id, rm[j].id) == "acquaintance", "roommates: acquaintance bit (%s)" % RelationshipBits.bit_for(rm[i].id, rm[j].id))
	# fridge goal text
	var goal: Dictionary = {}
	for g in Scenario.def("family")["goals"]:
		if g["id"] == "fridge":
			goal = g
	Kit.new_game("family", "normal", {}, -1, {"home_state": "empty", "world_seed": 5})
	_check(str(Scenario.goal_text(goal)["label"]) == "Buy a fridge and stock it", "empty home: goal says buy a fridge")
	Kit.new_game("family", "normal", {}, -1, {"home_state": "furnished", "world_seed": 5})
	_check(str(Scenario.goal_text(goal)["label"]) == "Stock the fridge", "furnished home: goal says stock the fridge")
	Kit.teardown()
	return fails
