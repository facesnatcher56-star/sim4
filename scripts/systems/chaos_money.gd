class_name ChaosMoney
extends RefCounted
## Money trouble (task 07b): identity theft and an eviction notice. Numbers: config.chaos.money. State: ChaosState.theft.
##  - Identity theft: someone uses an adult's name at the bank and coins vanish (a share of the balance), a little more every day until it is
##    reported (`report_identity_theft` at the computer or mailbox). The police take a few days, then the bank pays most of it back. Never reported:
##    the bank reviews it after three weeks and returns less. Adults and elders only; children never.
##  - Eviction notice: overdue bills AND something already repossessed lately. A warning with two days to pay everything off; if the household is still
##    behind the bailiffs take up to three more things and the bills are settled with them. Counterplay: pay the bills (mailbox) in time.

static func cfg() -> Dictionary:
	return ChaosState.cfg("money")

## Overdue bills and a repossession in the last weeks.
static func behind(hid: int) -> bool:
	var late := false
	for bl in Economy.outstanding(hid):
		if bool(bl["late"]):
			late = true
	if not late:
		return false
	var from: int = SysUtil.day() - int(cfg().get("repossessed_within_days", 56))
	for r in Economy.repossessed:
		if int(r["hid"]) == hid and int(r["day"]) >= from:
			return true
	return false

# ------------------------------------------------------------------ identity theft
static func theft(f) -> Dictionary:
	if f == null or int(f.household_id) <= 0 or ChaosState.theft.has(int(f.household_id)):
		return {"text": ""}
	var hid: int = int(f.household_id)
	var c: Dictionary = cfg()
	var bal: int = Economy.balance(hid)
	var taken: int = clampi(int(float(bal) * float(c.get("theft_share", 0.25))), int(c.get("theft_min", 40)), int(c.get("theft_max", 600)))
	taken = mini(taken, bal)
	if taken <= 0 or not Economy.spend(hid, taken, "identity theft"):
		return {"text": ""}
	ChaosState.theft[hid] = {"taken": taken, "since": SysUtil.now(), "reported": false, "fix_day": -1, "victim": int(f.id)}
	f.add_buff("identity_theft")
	ChaosState.count("theft")
	return {"text": "Someone has been using %s's name at the bank and %d coins are gone. Report it at the computer or the mailbox so the police can sort it out." % [f.name, taken], "kind": "bad"}

static func report(f, hid: int) -> void:
	var rec: Dictionary = ChaosState.theft.get(hid, {})
	if rec.is_empty() or bool(rec["reported"]):
		SysUtil.notify("There is nothing left to report.", "info")
		return
	var span: Array = cfg().get("police_days", [3, 6])
	rec["reported"] = true
	rec["fix_day"] = SysUtil.day() + Incidents.rng.randi_range(int(span[0]), int(span[1]))
	SysUtil.notify("%s reported the theft to the police. It will take a few days to sort out." % f.name, "info")

static func on_day() -> void:
	for hid in ChaosState.theft.keys():
		_theft_day(int(hid))

static func _theft_day(hid: int) -> void:
	var rec: Dictionary = ChaosState.theft[hid]
	var c: Dictionary = cfg()
	if not Economy.household_ids().has(hid):
		ChaosState.theft.erase(hid)
		return
	var today: int = SysUtil.day()
	if not bool(rec["reported"]):
		var drain: int = mini(int(c.get("theft_drain_per_day", 15)), maxi(Economy.balance(hid), 0))
		if drain > 0 and int(rec["taken"]) < int(c.get("theft_cap", 900)) and Economy.spend(hid, drain, "identity theft"):
			rec["taken"] = int(rec["taken"]) + drain
		if (SysUtil.now() - int(rec["since"])) / 1440 >= int(c.get("bank_review_days", 21)):
			_refund(hid, rec, float(c.get("refund_unreported", 0.4)), "The bank reviewed the odd payments and paid back part of it.")
		return
	if today >= int(rec["fix_day"]):
		_refund(hid, rec, float(c.get("refund_share", 0.85)), "The police sorted out the identity theft.")

static func _refund(hid: int, rec: Dictionary, share: float, lead: String) -> void:
	var back: int = int(float(rec["taken"]) * share)
	Economy.deposit(hid, back, "identity theft paid back")
	ChaosState.theft.erase(hid)
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			f.remove_buff("identity_theft")
	ChaosState.count("theft_sorted")
	SysUtil.notify("%s The bank returned %d coins." % [lead, back], "good")

# ------------------------------------------------------------------ eviction
## The bailiffs: up to three things taken (most valuable first, the ones the bill rules protect stay), the overdue bills settled with them.
static func eviction(hid: int) -> Dictionary:
	if not behind(hid):
		return {"text": ""}
	var before: int = Economy.repossessed.size()
	for _i in int(cfg().get("bailiff_items", 3)):
		Economy._repossess(hid)
	var taken: int = Economy.repossessed.size() - before
	for bl in Economy.outstanding(hid):
		bl["paid"] = true
	Economy.missed[hid] = 0
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			f.add_buff("eviction_scare")
	ChaosState.count("eviction")
	ChronicleHook.note("eviction", "The bailiffs cleared out part of a home over unpaid bills.", [], "home:%d" % hid, 3, false)
	return {"text": "The eviction notice ran out. The bailiffs came and took %d thing%s to settle the unpaid bills. Keep up with the bills so it does not come to this again." % [taken, "" if taken == 1 else "s"], "kind": "bad"}
