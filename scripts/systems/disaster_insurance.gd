class_name DisasterInsurance
extends RefCounted
## Optional home insurance (task 06). Two levels in config.disasters.insurance: weekly premium added to the household bill
## (Economy.compute_bill calls bill_extra) and a share of every disaster loss, hospital bill and doctor visit paid back
## (Incidents.insurance_fn -> cover()). The player changes the level on the mailbox ("Home insurance").

static func levels() -> Dictionary:
	return DisasterState.cfg("insurance")

static func level(hid: int) -> String:
	return str(DisasterState.insurance.get(hid, ""))

static func label(hid: int) -> String:
	var l: String = level(hid)
	return str((levels().get(l, {}) as Dictionary).get("label", "No cover")) if l != "" else "No cover"

static func set_level(hid: int, id: String) -> void:
	if id == "" or not levels().has(id):
		DisasterState.insurance.erase(hid)
	else:
		DisasterState.insurance[hid] = id

## none -> basic -> full -> none. Returns the new level id.
static func cycle(hid: int) -> String:
	var order: Array = [""]
	order.append_array(levels().keys())
	var i: int = order.find(level(hid))
	var nxt: String = str(order[(i + 1) % order.size()])
	set_level(hid, nxt)
	return nxt

static func ratio(hid: int) -> float:
	var l: String = level(hid)
	return float((levels().get(l, {}) as Dictionary).get("cover", 0.0)) if l != "" else 0.0

static func premium(hid: int) -> int:
	var l: String = level(hid)
	return int(round(float((levels().get(l, {}) as Dictionary).get("weekly", 0)) * CrimeSecurityAlarm.insurance_mult(hid))) if l != "" else 0       # alarms and cameras earn a discount (task 21)

## Economy.compute_bill hook: the weekly premium.
static func bill_extra(hid: int) -> int:
	return premium(hid)

## Coins an insurer pays toward `amount` for household `hid` (Incidents.insurance_fn signature).
static func cover(amount: int, hid: int) -> int:
	return int(floor(float(amount) * ratio(hid)))

static func install() -> void:
	Incidents.insurance_fn = Callable(BankInsurance, "cover")      # task 13: the bank wraps the home cover and adds health / car

static func ensure() -> void:
	if not Incidents.insurance_fn.is_valid():
		install()

## What the household chose, as one friendly sentence.
static func describe(hid: int) -> String:
	var l: String = level(hid)
	if l == "":
		return "Your home is not insured."
	var d: Dictionary = levels().get(l, {})
	return "%s: %d coins a week, pays back %d%% of damage and medical bills." % [str(d.get("label", l)), int(d.get("weekly", 0)), int(round(float(d.get("cover", 0.0)) * 100.0))]
