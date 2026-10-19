class_name ChaosPests
extends RefCounted
## Roaches that spread next door (task 07b). A house that is overrun (level at the swarm mark) has a small daily chance to send them to a
## neighbour: another household on the map gets a first sighting; otherwise a neighbouring townie lot complains and the friendship with them
## suffers a little. Cleaning up (or an exterminator) before the swarm mark stops it. Numbers: config.chaos.spread (chance, penalty).

static func spread(hid: int) -> void:
	var c: Dictionary = ChaosState.cfg("pests")
	var sp: Dictionary = ChaosState.cfg("spread")
	if ChaosState.pest_level(hid) < float(c.get("swarm", 0.85)) or Incidents.rng.randf() >= float(sp.get("chance", 0.04)):
		return
	var others: Array = Economy.household_ids().filter(func(h): return int(h) != hid)
	others.sort()
	if not others.is_empty():
		var other: int = int(others[Incidents.rng.randi_range(0, others.size() - 1)])
		if ChaosState.pest_level(other) < float(c.get("start", 0.25)) and int((ChaosState.pests.get(str(other), {}) as Dictionary).get("free_until", -1)) <= SysUtil.day():
			ChaosState.pest_rec(other)["level"] = float(c.get("start", 0.25))
			ChaosState.count("pests_spread")
			SysUtil.notify("Roaches from the house next door have found their way in: a first sighting.", "warn")
			ChaosClock.sync_markers(other)
		return
	var lots: Array = []
	for t in Story.alive_townies():
		if int(t.get("lot", 0)) > 0 and not lots.has(int(t["lot"])):
			lots.append(int(t["lot"]))
	if lots.is_empty():
		return
	lots.sort()
	var lot: int = int(lots[Incidents.rng.randi_range(0, lots.size() - 1)])
	var mine: Array = SysUtil.residents().filter(func(f): return int(f.household_id) == hid)
	for t2 in Story.alive_townies():
		if int(t2.get("lot", 0)) == lot:
			for f2 in mine:
				RelationshipService.add_both(int(f2.id), int(t2["id"]), "friendship", -float(sp.get("penalty", 6.0)))
	ChaosState.count("pests_spread_town")
	SysUtil.notify("A neighbour complains: the roaches from your house have spread next door. Clean up and call the exterminator before more people notice.", "warn")
