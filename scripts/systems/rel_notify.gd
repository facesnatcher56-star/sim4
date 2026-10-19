class_name RelNotify
extends RefCounted
## Relationship news (dating, made up, cheating, gossip) is a toast only when it concerns the household or somebody they know well
## (friendship 25+); strangers, crew and passengers' own dramas stay out of the feed (task 22, cruise report: crew drama flooded the log).

static func concerns_household(ids: Array) -> bool:
	for id in ids:
		var f = SysUtil.folk(int(id))
		if SysUtil.is_resident(f):
			return true
	for r in SysUtil.residents():
		for id2 in ids:
			if RelationshipService.knows(int(r.id), int(id2)) and RelationshipService.value(int(r.id), int(id2), "friendship") >= 25.0:
				return true
	return false

static func say(ids: Array, text: String, kind: String) -> void:
	if DeadPools.any_dead(ids):
		return          # the dead take no part in relationship news
	if concerns_household(ids):
		SysUtil.notify(text, kind)
