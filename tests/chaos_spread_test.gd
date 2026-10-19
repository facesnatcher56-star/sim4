extends RefCounted
## Household chaos (task 07b), roaches spreading next door: only from an overrun house, to another household on the map or (when there is none) as a
## neighbour's complaint that costs a little friendship; protected (exterminated) houses are skipped; below the swarm mark nothing spreads.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_to_household(f)
	_to_townie_lot(f)
	return f

func _to_household(f: Array) -> void:
	var h: Dictionary = C.setup()
	var cy := K.make_folk(h["w"], "Cy Ward", [], 2, Vector2i(20, 12))
	WorldIface.coins[2] = 500
	ChaosState.cfg("spread")["chance"] = 1.0
	ChaosState.pest_rec(1)["level"] = 0.6
	ChaosPests.spread(1)
	K.expect(f, ChaosState.pest_level(2) == 0.0, "a house that is merely infested does not spread them yet")
	ChaosState.pest_rec(1)["level"] = 0.9
	ChaosPests.spread(1)
	K.expect(f, absf(ChaosState.pest_level(2) - 0.25) < 0.001 and cy.has_buff("roaches_seen"), "an overrun house sends them next door: a first sighting")
	K.expect(f, K.has_note("next door"), "in plain words")
	ChaosState.pests.erase("2")
	ChaosState.pest_rec(2)["free_until"] = SysUtil.day() + 10
	ChaosPests.spread(1)
	K.expect(f, ChaosState.pest_level(2) == 0.0, "a house the exterminator protects is skipped")
	K.teardown()

func _to_townie_lot(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var ada: Folk = h["ada"]
	ChaosState.cfg("spread")["chance"] = 1.0
	ChaosState.pest_rec(1)["level"] = 0.95
	var lot := -1
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) > 0:
			lot = int(t["lot"])
			break
	var neighbours: Array = Story.alive_townies().filter(func(t): return int(t.get("lot", 0)) > 0)
	for t2 in neighbours:
		RelationshipService.add_both(int(ada.id), int(t2["id"]), "friendship", 30.0)
	var before: float = 0.0
	for t3 in neighbours:
		before += RelationshipService.value(int(ada.id), int(t3["id"]), "friendship")
	ChaosPests.spread(1)
	var after: float = 0.0
	for t4 in neighbours:
		after += RelationshipService.value(int(ada.id), int(t4["id"]), "friendship")
	K.expect(f, after < before and K.has_note("neighbour complains"), "with no other household, a neighbour complains and is a little less friendly (%.0f -> %.0f)" % [before, after])
	K.expect(f, lot > 0 and int(ChaosState.stats.get("pests_spread_town", 0)) == 1, "counted")
	K.teardown()
