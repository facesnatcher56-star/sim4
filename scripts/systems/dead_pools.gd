class_name DeadPools
extends RefCounted
## The dead (and townies who moved away) leave every social pool: gossip they hold or are the subject of, undiscovered affairs, open invites
## and visit lists. `is_dead` is the one test the social toasts / gossip / backfire code asks before it names anybody as an actor.

static func is_dead(id: int) -> bool:
	if id < 0 or SysUtil.folk(id) != null:
		return false
	if Story.townies.has(id):
		return not bool(Story.townies[id]["alive"])
	return int((Family.people.get(id, {}) as Dictionary).get("died_day", -1)) >= 0

static func any_dead(ids: Array) -> bool:
	for id in ids:
		if is_dead(int(id)):
			return true
	return false

## Called from both death paths (Aging.kill for folk on the map, DeathCauses.kill_townie for far townies) once the person is gone.
static func purge(id: int) -> void:
	RelationshipService.gossip_items.erase(id)
	for holder in RelationshipService.gossip_items.keys():
		var kept: Array = []
		for it in RelationshipService.gossip_items[holder]:
			if int(it.get("about", -1)) == id or int(it.get("other", -1)) == id:
				continue
			(it.get("told", []) as Array).erase(id)
			kept.append(it)
		RelationshipService.gossip_items[holder] = kept
	RelationshipService.affairs = RelationshipService.affairs.filter(func(a): return int(a.get("cheater", -1)) != id and int(a.get("other", -1)) != id and int(a.get("victim", -1)) != id)
	for inv in Story.invites:
		if str(inv["state"]) == "open" and (int(inv["townie_id"]) == id or int(inv["folk_id"]) == id):
			inv["state"] = "expired"
	for sit in Story.situations:
		(sit["guest_ids"] as Array).erase(id)
