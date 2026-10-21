class_name BankBranch
extends RefCounted
## Task 46: the bank is a real place (lot "bank", template "bank": the hall, the teller counter, the loans office, the back office and the vault).
## Putting money in or taking it out of savings and borrowing are done at the counter with a teller there; the phone keeps the balance, repayments and
## insurance (like a real banking app). Its guards, cameras and vault come from the posts (staff_posts.json) and the business profile "bank".
##   BankBranch.entries(f, obj) (the counter's menu)   BankBranch.at_counter(f)   BankBranch.needs_branch(f)

const LOT := "bank"
static var served: Dictionary = {}          # fid -> minute a teller last served them (the counter visit lasts a while)

static func reset() -> void:
	served = {}

static func is_bank(lot: String) -> bool:
	return Venues.type_of_lot(lot) == "bank"

static func teller(lot: String):
	for s in Crowd.staff_folk(lot):
		if str(s.get_meta("staff", "")) in ["teller", "cashier"]:
			return s
	return null

## One-character play: the counter rules apply to the pawn. Classic households keep banking from the money screen.
static func needs_branch(f) -> bool:
	return f != null and SocialFit.player_controlled(f) and not Neighborhood.lot(LOT).is_empty()

static func at_counter(f) -> bool:
	return f != null and SysUtil.now() - int(served.get(int(f.id), -100000)) <= 30

static func entries(f, obj) -> Array:
	var lot: String = Neighborhood.lot_of(f)
	if obj == null or not Pawn.is_pawn(f) or not is_bank(lot) or str(obj.def_id) != "counter":
		return []
	return [{"id": "bank_counter", "label": "Bank at the counter", "category": "Bank", "enabled": true, "reason": "",
		"action": func(): WalkThen.go(f, WalkThen.near(obj.tile + Vector2i(0, 1)), func(): visit(f, lot))}]

static func visit(f, lot: String) -> void:
	var t = teller(lot)
	if t == null:
		SysUtil.notify("Nobody is at the counter.", "story")
		return
	served[int(f.id)] = SysUtil.now()
	SysUtil.notify("%s looks up from the counter. \"How can I help?\"" % str(t.name).get_slice(" (", 0), "story")
	SysUtil.game_event("open_money", {"folk_id": int(f.id)})
