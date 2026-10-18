class_name BankInsurance
extends RefCounted
## Insurance policies (task 13): health, car and life next to the existing home cover (DisasterInsurance). Premiums are added to the weekly
## household bill (Economy.compute_bill -> bill_extra). `cover(amount, hid)` is THE Incidents.insurance_fn: Incidents.cover_kind says what is
## being paid ("" = property: fire, disasters, theft; "health" = hospital and doctor). Car and life pay out on events from the chronicle.
## Tier: event driven (no polling). Data: data/bank.json "insurance".

static var policies: Dictionary = {}    # hid -> {policy id -> day it started}
static var paid_out: Array = []         # [{day, hid, policy, amount}] last 20

static func reset() -> void:
	policies.clear()
	paid_out.clear()

static func defs() -> Dictionary:
	return SysUtil.table("bank").get("insurance", {}).get("policies", {})

static func has(hid: int, pid: String) -> bool:
	return (policies.get(hid, {}) as Dictionary).has(pid)

static func buy(hid: int, pid: String) -> bool:
	if not defs().has(pid) or has(hid, pid):
		return false
	if not policies.has(hid):
		policies[hid] = {}
	policies[hid][pid] = SysUtil.day()
	return true

static func cancel(hid: int, pid: String) -> void:
	if policies.has(hid):
		(policies[hid] as Dictionary).erase(pid)

static func toggle(hid: int, pid: String) -> bool:
	if has(hid, pid):
		cancel(hid, pid)
		return false
	return buy(hid, pid)

static func weekly(pid: String) -> int:
	return int(round(float((defs().get(pid, {}) as Dictionary).get("weekly", 0)) * MarketEconomy.price_mult()))

## Economy.compute_bill hook.
static func bill_extra(hid: int) -> int:
	var total: int = 0
	for pid in (policies.get(hid, {}) as Dictionary):
		total += weekly(str(pid))
	return total

# ------------------------------------------------------------------ cover
static func ratio(hid: int, kind: String) -> float:
	var keep: float = 1.0 - DisasterInsurance.ratio(hid)     # the home policy pays toward everything it always did
	for pid in (policies.get(hid, {}) as Dictionary):
		var d: Dictionary = defs().get(pid, {})
		if (d.get("kinds", []) as Array).has(kind):
			keep *= 1.0 - float(d.get("cover", 0.0))
	return 1.0 - keep

## Incidents.insurance_fn(amount, hid).
static func cover(amount: int, hid: int) -> int:
	return int(floor(float(amount) * ratio(hid, Incidents.cover_kind)))

static func install() -> void:
	Incidents.insurance_fn = Callable(BankInsurance, "cover")

# ------------------------------------------------------------------ payouts
static func _pay(hid: int, pid: String, amount: int, why: String) -> void:
	if amount <= 0 or hid <= 0:
		return
	Economy.deposit(hid, amount, why)
	paid_out.append({"day": SysUtil.day(), "hid": hid, "policy": pid, "amount": amount})
	while paid_out.size() > 20:
		paid_out.pop_front()
	SysUtil.notify("%s paid out %d coins." % [str((defs().get(pid, {}) as Dictionary).get("label", "Insurance")), amount], "good")
	SysUtil.game_event("insurance_paid", {"household_id": hid, "policy": pid, "amount": amount})

## "chronicle" events: a car crash pays the car policy, a death pays the life policy of the household it happened in.
static func on_chronicle(p: Dictionary) -> void:
	var kind: String = str(p.get("kind", ""))
	var lot: String = str(p.get("lot", ""))
	var hid: int = int(lot.get_slice(":", 1)) if lot.begins_with("home:") else 0
	if hid <= 0:
		return
	for pid in (policies.get(hid, {}) as Dictionary):
		var d: Dictionary = defs().get(pid, {})
		var ev: Dictionary = d.get("payout_events", {})
		if ev.has(kind):
			_pay(hid, str(pid), int(round(float(ev[kind]) * MarketEconomy.price_mult())), "%s claim" % str(d.get("label", pid)))
		if str(pid) == "life" and kind == "death" and SysUtil.day() > int(policies[hid][pid]):
			var who: int = int((p.get("subjects", [0]) as Array)[0])
			BankWill.queue_life_payout(hid, who, int(round(float(d.get("payout", 0)) * MarketEconomy.price_mult())))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"policies": SysUtil.str_keys(policies).duplicate(true), "paid_out": paid_out.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	policies = SysUtil.int_keys((d.get("policies", {}) as Dictionary).duplicate(true))
	for hid in policies:
		for pid in policies[hid]:
			policies[hid][pid] = int(policies[hid][pid])
	paid_out = (d.get("paid_out", []) as Array).duplicate(true)
	for p in paid_out:
		SysUtil.ints_in(p, ["day", "hid", "amount"])
