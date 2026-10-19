class_name TierSets
extends RefCounted
## The incrementally maintained tier sets (task 17.3). One Dictionary per tier: person id -> Folk (or null for townie records without a Folk).
## A set only changes through put() / drop(): systems loop `set_of(tier)` instead of scanning the world, and nothing recomputes these by scanning.

var sets: Array = [{}, {}, {}, {}]
var tier_of: Dictionary = {}          # id -> tier

func put(id: int, tier: int, folk) -> int:
	## Returns the previous tier (-1 = new).
	var old: int = int(tier_of.get(id, -1))
	if old == tier:
		(sets[tier] as Dictionary)[id] = folk
		return old
	if old >= 0:
		(sets[old] as Dictionary).erase(id)
	(sets[tier] as Dictionary)[id] = folk
	tier_of[id] = tier
	return old

func drop(id: int) -> int:
	var old: int = int(tier_of.get(id, -1))
	if old >= 0:
		(sets[old] as Dictionary).erase(id)
		tier_of.erase(id)
	return old

func has(id: int) -> bool:
	return tier_of.has(id)

func clear() -> void:
	for s in sets:
		(s as Dictionary).clear()
	tier_of.clear()

func count(tier: int) -> int:
	return (sets[tier] as Dictionary).size()
