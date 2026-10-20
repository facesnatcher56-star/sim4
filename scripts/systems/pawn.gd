class_name Pawn
extends RefCounted
## One-character play (docs/ONE_CHARACTER_PLAN.md): the PAWN is the head of a player's household (the Players table). It has NO autonomy: nothing
## happens to it unless the player ordered it, or the body / the world forces it (priority high or urgent: toilet accident, collapse, fire, the
## away hold of a shift or a hospital stay). Everybody else is an ordinary autonomous NPC. Without a Players entry (test kits) nobody is a pawn.
## Standing orders that stay: the job's commute (accepting a job is the order), bills and rent (autopay).

static func of(player_id: int = -1) -> int:
	var pid: int = Players.local_id if player_id < 0 else player_id
	if not Players.table.has(pid):
		return -1
	return Succession.head_of(pid)

static func is_pawn(f) -> bool:
	if f == null or Players.table.is_empty():
		return false
	var hid: int = int(f.household_id)
	if hid <= 0:
		return false
	for pid in Players.table:
		if int((Players.table[pid] as Dictionary)["household_id"]) == hid:
			return Succession.head_of(int(pid)) == int(f.id)
	return false

static func is_pawn_id(folk_id: int) -> bool:
	return is_pawn(SysUtil.folk(folk_id))

## May this interaction be queued on `f`? Pawns accept only the player's orders and forced ones (body, hazard, hold).
static func allows(f, ir) -> bool:
	if ir.player or ir.effective_priority() >= Interaction.PRIORITY["high"]:
		return true
	return not is_pawn(f)
