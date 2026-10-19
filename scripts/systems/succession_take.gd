class_name SuccessionTake
extends RefCounted
## Hands the household to somebody (task 15): a housemate simply becomes the head; a moved-out child, a relative or a townie moves (back) into the
## family home first, bringing their partner and young children with them when those are townies too. Then the head is set, the heir pick is cleared
## and the player is told in plain words who they play now ("head_changed" makes the HUD select that person and move the camera).

## `cand` = a HeirLine candidate {id, kind, in_household ...}. Returns true when the person now plays.
static func take(pid: int, hid: int, cand: Dictionary, late_name: String) -> bool:
	var id: int = int(cand["id"])
	var moved: bool = not bool(cand.get("in_household", false))
	var names: Array = []
	if moved:
		if not FamilyHousehold.invite_to_household(id, hid):
			return false
		names = _bring_family(id, hid)
	var f = SysUtil.folk(id)
	if f == null:
		return false
	Succession.set_head(pid, id)
	Players.set_field(pid, "pending", false)
	var text: String = SuccessionText.took_over(late_name, str(f.name), str(cand.get("kind", "")), moved)
	if not names.is_empty():
		text += " %s came along." % " and ".join(names)
	_announce(pid, id, text)
	return true

## Partner and young children who are townies follow the new head into the home.
static func _bring_family(id: int, hid: int) -> Array:
	var names: Array = []
	var pr: Dictionary = FamilyTree.partner_of(id)
	if not pr.is_empty() and str(pr.get("status", "")) in ["spouse", "partner", "fiance"]:
		_move_townie(int(pr["id"]), hid, names)
	for c in FamilyTree.children_of(id):
		if Story.townies.has(int(c)) and str(Family.person_info(int(c))["stage"]) in ["baby", "toddler", "child", "teen"]:
			_move_townie(int(c), hid, names)
	return names

static func _move_townie(tid: int, hid: int, names: Array) -> void:
	if Story.townies.has(tid) and bool(Story.townies[tid]["alive"]) and FamilyHousehold.invite_to_household(tid, hid):
		names.append(Family.name_of(tid))

static func _announce(pid: int, folk_id: int, text: String) -> void:
	SysUtil.notify(text, "story")
	ChronicleHook.note("succession", text, [folk_id], "home:%d" % Players.household_of(pid), 3, true)
	SysUtil.game_event("head_changed", {"player_id": pid, "folk_id": folk_id, "household_id": Players.household_of(pid)})
