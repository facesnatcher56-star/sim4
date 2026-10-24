class_name RelationshipToasts
extends RefCounted
## Who gets a "X now sees Y as: Friend" toast. Household members always (when they are the one who changes); people the household
## knows well (a resident is at least a friend of x or y) too; everybody else goes quietly to the Chronicle (big steps only).

const QUIET_BITS := ["best_friend", "sweetheart", "partner", "spouse", "enemy"]

static func announce(x: int, y: int, bit: String) -> void:
	if DeadPools.any_dead([x, y]):
		return
	var text: String = "%s now sees %s as: %s" % [SysUtil.folk_name(x), SysUtil.folk_name(y), RelationshipBits.bit_label(bit)]
	if _household_involved(x, y) or (_known_well(x, y) and not SoloHome.active):          # task 66: in solo play the townies' own changes reach the player through people
		SysUtil.notify(text, "relationship")
	elif bit in QUIET_BITS:
		ChronicleHook.note("relationship", text, [x, y], "", 1, false)

static func _is_household(id: int) -> bool:
	var f = SysUtil.folk(id)
	return SysUtil.is_resident(f)

static func _household_involved(x: int, y: int) -> bool:
	return _is_household(x) or _is_household(y)

static func _known_well(x: int, y: int) -> bool:
	for r in SysUtil.residents():
		for o in [x, y]:
			if RelationshipService.knows(int(r.id), int(o)) and RelationshipBits._bit_rank(RelationshipBits.bit_for(int(r.id), int(o))) >= 2 \
					and RelationshipBits.bit_for(int(r.id), int(o)) != "enemy":
				return true
	return false
