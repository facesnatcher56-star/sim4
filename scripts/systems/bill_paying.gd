class_name BillPaying
extends RefCounted
## Paying the household bills without the player (19i). Two ways, both for the same bills Economy issues:
##  - autopay: Economy.autopay_for(hid) - on for every household the player does not run (townies), the player's own choice for theirs (default off);
##  - the action "Pay Bills" at the mailbox: an adult who lives there does it by themself while the house has bills unpaid and the coins to settle them.
##    The marker buffs below tell the interaction when it may run (Cond has no bill knowledge): `bills_waiting` from the day a bill is issued
##    (the tidy and neat folk get round to it first: the action carries the "chore" tag), `bills_late` once it is past due (much more urgent).
## Called once a day from Economy.on_day and again after a payment. Data: data/content_sys.json (buffs, interaction pay_bills).

const WAITING := "bills_waiting"
const LATE := "bills_late"

## The bills that could be settled right now: owed > 0 and the household has the coins. late = any bill is past due.
static func state(hid: int) -> Dictionary:
	var owed: int = Economy.owed(hid)
	var late: bool = false
	for bl in Economy.outstanding(hid):
		if bool(bl.get("late", false)) or SysUtil.day() >= int(bl.get("due", 99999)):
			late = true
	return {"owed": owed, "late": late, "can_pay": owed > 0 and Economy.balance(hid) >= owed}

## Put or take the marker buffs on the household's adults. Cheap: O(residents).
static func refresh() -> void:
	var cache: Dictionary = {}
	for f in SysUtil.residents():
		var hid: int = int(f.household_id)
		if not cache.has(hid):
			cache[hid] = state(hid)
		var s: Dictionary = cache[hid]
		var adult: bool = str(f.age_stage) in ["adult", "elder"] and not SysUtil.is_away(f)
		var want_wait: bool = adult and bool(s["can_pay"]) and not bool(s["late"])
		var want_late: bool = adult and bool(s["can_pay"]) and bool(s["late"])
		_mark(f, WAITING, want_wait)
		_mark(f, LATE, want_late)

static func _mark(f, buff: String, want: bool) -> void:
	if want and not f.has_buff(buff):
		f.add_buff(buff)
	elif not want and f.has_buff(buff):
		f.remove_buff(buff)

## The action's end: this person settles every unpaid bill of their household (if it can still afford them).
static func on_pay_bills(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return 0
	var paid: int = Economy.pay_bill(int(f.household_id))     # Economy toasts "Paid bills: N coins."
	refresh()
	return paid
