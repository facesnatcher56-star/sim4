class_name JusticeOrders
extends RefCounted
## PROTECTIVE ORDERS (task 19.1). A data-driven legal state in JusticeState.orders: the offender must keep away from the victim's home for N days.
## - Issued when a domestic assault suspect is arrested (short, until the trial) and again on a conviction (longer, longer for repeat offenders);
##   lifted on an acquittal. Data: data/justice.json "domestic".
## - A cohabiting offender moves out (FamilyHousehold.move_out); townie guests are kept away from the household (`bars`, used by StoryVisits).
## - Breaking the order is a crime of its own (charge "order_violation"): a new case, arrest and trial; the order is extended.

static func cfg() -> Dictionary:
	return JusticeState.sect("domestic")

static func active() -> Array:
	return JusticeState.orders.filter(func(o): return int(o["until"]) >= SysUtil.day())

## The active order of this pair ({} when none).
static func between(offender: int, victim: int) -> Dictionary:
	for o in active():
		if int(o["offender"]) == offender and int(o["victim"]) == victim:
			return o
	return {}

## True when `offender` may not be at the home of `other` (the victim, or anybody who lives with the victim).
static func bars(offender: int, other: int) -> bool:
	for o in active():
		if int(o["offender"]) != offender:
			continue
		if int(o["victim"]) == other or (int(o["vhid"]) > 0 and CrimePerson.hid(other) == int(o["vhid"])):
			return true
	return false

static func orders_against(offender: int) -> Array:
	return active().filter(func(o): return int(o["offender"]) == offender)

static func orders_for(victim: int) -> Array:
	return active().filter(func(o): return int(o["victim"]) == victim)

static func days_for(offender: int) -> int:
	var k: Dictionary = cfg()
	var prior: int = 0
	for r in JusticeState.records.get(offender, []):
		if str(r.get("charge", "")) in ["assault", "domestic_violence", "order_violation"] and str(r.get("result", "")) in ["guilty", "plea"]:
			prior += 1
	return mini(int(k.get("order_days", 28)) + int(k.get("order_repeat_days", 28)) * maxi(prior - 1, 0), int(k.get("order_max_days", 112)))

## Issue (or extend) an order for `days` days from the case's accused towards the case's victim.
static func issue(c: Dictionary, days: int) -> Dictionary:
	var off: int = int(c.get("accused", -1))
	var vic: int = int(c.get("victim", -1))
	if off < 0 or vic < 0 or off == vic:
		return {}
	var until: int = SysUtil.day() + days
	var o: Dictionary = between(off, vic)
	if o.is_empty():
		o = {"id": JusticeState.next_order, "offender": off, "victim": vic, "vhid": CrimePerson.hid(vic), "home": CrimePerson.home_key(vic),
			"since": SysUtil.day(), "until": until, "case": int(c["id"]), "violations": 0}
		JusticeState.next_order += 1
		JusticeState.orders.append(o)
		JusticeState.count("orders")
		var text: String = "A protective order now keeps %s away from %s for %s." % [CrimePerson.name_of(off), CrimePerson.name_of(vic), SysUtil.count_text(days, "day")]
		CaseStore.note(c, text, "protective_order", 3)
		if CaseStore.household_involved(c):
			SysUtil.notify(text, "story")
	else:
		o["until"] = maxi(int(o["until"]), until)
		o["case"] = int(c["id"])
	enforce(o)
	return o

## An acquittal lifts the orders that came from the case.
static func lift(c: Dictionary) -> void:
	JusticeState.orders = JusticeState.orders.filter(func(o): return int(o["case"]) != int(c["id"]))

## A cohabiting offender who is free to move out does so. (Inmates move out when released: on_released.)
static func enforce(o: Dictionary) -> void:
	var off: int = int(o["offender"])
	var vic: int = int(o["victim"])
	if CrimePerson.in_custody(off) or CrimePerson.hid(off) <= 0 or CrimePerson.hid(off) != CrimePerson.hid(vic):
		return
	if CrimePerson.folk(off) != null and FamilyHousehold.move_out(off, 0.3):
		JusticeState.count("order_moveouts")
		var text: String = "%s moved out because of the protective order." % CrimePerson.name_of(off)
		ChronicleHook.note("protective_order", text, [off, vic], CrimePerson.home_key(vic), 3, true)

static func on_released(pid: int) -> void:
	for o in orders_against(pid):
		enforce(o)

static func on_day() -> void:
	var k: Dictionary = cfg()
	JusticeState.orders = JusticeState.orders.filter(func(o): return int(o["until"]) >= SysUtil.day() and CrimePerson.alive(int(o["offender"])) and CrimePerson.alive(int(o["victim"])))
	for o in JusticeState.orders.duplicate():
		var off: int = int(o["offender"])
		if CrimePerson.in_custody(off):
			continue
		enforce(o)
		if CrimePerson.is_player(off) or CrimePerson.folk(off) != null:
			continue                       # a folk the player controls is kept away by `bars`; they decide where to go
		var p: float = float(k.get("violation_daily", 0.012)) * (0.5 + CrimeMurder.anger(off, int(o["victim"])) + float(CrimePerson.has_trait(off, "hot_headed")))
		if JusticeState.chance(p):
			violate(o)

## The offender turns up at the victim's home: a new case, arrested at once, the order is extended.
static func violate(o: Dictionary) -> Dictionary:
	var off: int = int(o["offender"])
	var vic: int = int(o["victim"])
	var c: Dictionary = CaseStore.create("order_violation", off, vic, str(o["home"]), {"witnessed": true, "witnesses": [vic], "witness_clarity": 0.95, "trace": 0.5})
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	c["domestic"] = true
	o["violations"] = int(o["violations"]) + 1
	o["until"] = int(o["until"]) + int(cfg().get("violation_extend", 14))
	CaseStore.note(c, "%s came to %s's home despite the protective order." % [CrimePerson.name_of(off), CrimePerson.name_of(vic)], "protective_order", 3)
	JusticeProcess.arrest(c, off)
	return c
