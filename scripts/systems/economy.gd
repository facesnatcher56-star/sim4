class_name Economy
extends RefCounted
## Household funds, weekly bills, late fees, repossession, buying/selling objects and grocery restock.
## Balances live in WorldIface.coins (the same numbers Cond `coins_at_least` / Loot `coins_add` use).

static var bills: Array = []            # {id, hid, amount, base, issued, due, paid, late, fee}
static var missed: Dictionary = {}      # hid -> consecutive bills that went late
static var ledger: Dictionary = {}      # hid -> Array of {day, amount, reason, balance}
static var owner: Dictionary = {}       # object_id -> household id
static var placed_day: Dictionary = {}  # object_id -> day it entered the lot
static var usage: Dictionary = {}       # hid -> utility units used this billing cycle
static var repossessed: Array = []      # {day, hid, def_id, value}
static var next_bill_day: int = 0
static var auto_pay: bool = true
static var _seq: int = 1

static func reset() -> void:
	bills.clear()
	missed.clear()
	ledger.clear()
	owner.clear()
	placed_day.clear()
	usage.clear()
	repossessed.clear()
	next_bill_day = 0
	auto_pay = true
	_seq = 1

static func cfg() -> Dictionary:
	return SysUtil.table("economy")

static func bill_cfg() -> Dictionary:
	return cfg().get("bills", {})

# ------------------------------------------------------------------ funds
static func balance(hid: int) -> int:
	return WorldIface.get_coins(hid)

static func can_afford(hid: int, n: int) -> bool:
	return balance(hid) >= n

static func _log(hid: int, amount: int, reason: String) -> void:
	if not ledger.has(hid):
		ledger[hid] = []
	var l: Array = ledger[hid]
	l.append({"day": SysUtil.day(), "amount": amount, "reason": reason, "balance": balance(hid)})
	var cap: int = int(cfg().get("ledger_size", 60))
	while l.size() > cap:
		l.pop_front()

static func deposit(hid: int, n: int, reason: String = "") -> void:
	if n == 0:
		return
	WorldIface.add_coins(hid, n)
	_log(hid, n, reason)

## Spend `n` coins if affordable. Emits coins_changed through WorldIface. Returns false when too poor.
static func spend(hid: int, n: int, reason: String = "") -> bool:
	if n < 0:
		return false
	if balance(hid) < n:
		return false
	WorldIface.add_coins(hid, -n)
	_log(hid, -n, reason)
	return true

## Callables for World.coin_spend / World.coin_refund.
static func spend_cb(hid: int, n: int) -> bool:
	return spend(hid, n, "build/buy")

static func refund_cb(hid: int, n: int) -> void:
	deposit(hid, n, "refund")

static func ledger_for(hid: int) -> Array:
	return (ledger.get(hid, []) as Array).duplicate(true)

static func start_funds(hid: int) -> void:
	WorldIface.coins[hid] = 0
	deposit(hid, int(cfg().get("starting_funds", 5000)), "starting funds")

# ------------------------------------------------------------------ households & objects
static func household_ids() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if int(f.household_id) > 0 and not out.has(int(f.household_id)):
			out.append(int(f.household_id))
	out.sort()
	return out

static func primary_household() -> int:
	var w = WorldIface.world()
	if w != null and "current_household_id" in w and int(w.current_household_id) > 0:
		return int(w.current_household_id)
	var ids: Array = household_ids()
	return int(ids[0]) if not ids.is_empty() else 1

static func object_price(obj) -> int:
	return price_of_def(str(obj.def_id))

static func price_of_def(def_id: String) -> int:
	return int(SimEnv.data().object_def(def_id).get("price", 0))

## Owner an unregistered object starts with: the primary household for objects in the home lot (or on a map without regions),
## community property (-1: never in bills / repossession) for every venue and townie lot.
static func default_owner(o) -> int:
	var w = WorldIface.world()
	if w != null and "regions" in w and w.regions.has_regions():
		return primary_household() if w.regions.region_at(o.tile) == w.regions.home_id else -1
	return primary_household()

## Register any object we have not seen yet (placed today, owned per default_owner).
static func refresh_objects() -> void:
	var seen: Dictionary = {}
	for o in SysUtil.all_world_objects():
		seen[int(o.id)] = true
		if not placed_day.has(int(o.id)):
			placed_day[int(o.id)] = SysUtil.day()
		if not owner.has(int(o.id)):
			owner[int(o.id)] = default_owner(o)
	for id in placed_day.keys():
		if not seen.has(id):
			placed_day.erase(id)
			owner.erase(id)

static func on_object_placed(object_id: int) -> void:
	placed_day[object_id] = SysUtil.day()
	if not owner.has(object_id):
		var o = WorldIface.get_object(object_id)
		owner[object_id] = default_owner(o) if o != null else primary_household()

static func on_object_removed(object_id: int) -> void:
	placed_day.erase(object_id)
	owner.erase(object_id)

static func objects_of(hid: int) -> Array:
	refresh_objects()
	var out: Array = []
	for o in SysUtil.all_world_objects():
		if int(owner.get(int(o.id), -1)) == hid:
			out.append(o)
	return out

## Value of everything the household owns (its home lot objects: venue and townie lot objects are community property).
static func lot_value(hid: int) -> int:
	var total: int = 0
	for o in objects_of(hid):
		total += object_price(o)
	return int(float(total) * CrimeRate.value_mult())       # a high crime rate lowers property values

# ------------------------------------------------------------------ buy / sell
static func sell_ratio(age_days: int) -> float:
	var m: Dictionary = cfg().get("market", {})
	var hi: float = float(m.get("sell_ratio_new", 0.8))
	var lo: float = float(m.get("sell_ratio_old", 0.5))
	var span: float = maxf(float(m.get("old_after_days", 30)), 1.0)
	return lerpf(hi, lo, clampf(float(age_days) / span, 0.0, 1.0))

static func value_of(object_id: int) -> int:
	var o = WorldIface.get_object(object_id)
	if o == null:
		return 0
	refresh_objects()
	var age: int = SysUtil.day() - int(placed_day.get(object_id, SysUtil.day()))
	return int(floor(float(object_price(o)) * sell_ratio(age)))

## Purchase and place a new object. Returns the object id or -1 (insufficient funds / blocked).
static func buy_object(hid: int, def_id: String, tile: Vector2i, rot: int = 0) -> int:
	var price: int = int(SimEnv.data().object_def(def_id).get("price", -1))
	if price < 0 or not can_afford(hid, price):
		return -1
	var w = WorldIface.world()
	if w == null or not w.has_method("place_object"):
		return -1
	var id: int = int(w.place_object(def_id, tile, rot))
	if id < 0:
		return -1
	spend(hid, price, "bought " + def_id)
	owner[id] = hid
	placed_day[id] = SysUtil.day()
	SysUtil.game_event("object_bought", {"object_id": id, "household_id": hid, "def_id": def_id})
	return id

## Sell an object back at 50-80% depending on age. Returns the coins received (0 = refused).
static func sell_object(hid: int, object_id: int) -> int:
	var o = WorldIface.get_object(object_id)
	if o == null:
		return 0
	refresh_objects()
	if int(owner.get(object_id, hid)) != hid:
		return 0
	var value: int = value_of(object_id)
	var w = WorldIface.world()
	if w == null or not w.has_method("remove_object"):
		return 0
	if not bool(w.remove_object(object_id)):
		return 0
	owner.erase(object_id)
	placed_day.erase(object_id)
	deposit(hid, value, "sold " + str(o.def_id))
	SysUtil.game_event("object_sold", {"object_id": object_id, "household_id": hid, "coins": value})
	return value

# ------------------------------------------------------------------ groceries
static func grocery_cost() -> int:
	return int(cfg().get("groceries", {}).get("cost_per_unit", 6))

## Fill a fridge up to its max stock, paying per unit. Buys as many units as the household can afford.
## Returns the units added.
static func restock_fridge(hid: int, fridge_id: int) -> int:
	var o = WorldIface.get_object(fridge_id)
	if o == null:
		return 0
	var spec: Dictionary = SimEnv.data().object_def(str(o.def_id)).get("state", {}).get("stock", {})
	var cap: int = int(spec.get("max", cfg().get("groceries", {}).get("max_units", 10)))
	var cur: int = int(float(WorldIface.state_get(o, "stock", 0.0)))
	var missing: int = cap - cur
	if missing <= 0:
		return 0
	var cost: int = grocery_cost()
	var units: int = mini(missing, int(floor(float(balance(hid)) / float(maxi(cost, 1)))))
	if units <= 0:
		SysUtil.notify("Can't afford groceries.", "warn")
		return 0
	spend(hid, units * cost, "groceries x%d" % units)
	WorldIface.state_add(o, "stock", float(units))
	SysUtil.game_event("groceries_bought", {"household_id": hid, "object_id": fridge_id, "units": units})
	return units

# ------------------------------------------------------------------ bills
static func note_usage(hid: int, interaction_id: String) -> void:
	var w: Dictionary = bill_cfg().get("utility_weights", {})
	if w.has(interaction_id) and hid > 0:
		usage[hid] = float(usage.get(hid, 0.0)) + float(w[interaction_id])

static func compute_bill(hid: int) -> int:
	var b: Dictionary = bill_cfg()
	var amount: float = float(b.get("base", 50)) + float(lot_value(hid)) * float(b.get("lot_value_rate", 0.015))
	amount += float(usage.get(hid, 0.0)) * float(b.get("utility_rate", 0.8))
	amount *= Weather.bill_multiplier()    # heating / cooling over the billing cycle (1.0 when mild)
	amount *= Scenario.bill_multiplier()   # new-game difficulty (1.0 on Normal)
	amount += float(DisasterInsurance.bill_extra(hid))   # optional home insurance premium (task 06)
	return int(round(amount))

static func outstanding(hid: int) -> Array:
	var out: Array = []
	for bl in bills:
		if int(bl["hid"]) == hid and not bool(bl["paid"]):
			out.append(bl)
	return out

static func owed(hid: int) -> int:
	var total: int = 0
	for bl in outstanding(hid):
		total += int(bl["amount"])
	return total

static func issue_bill(hid: int) -> Dictionary:
	var b: Dictionary = bill_cfg()
	var amount: int = compute_bill(hid)
	var bill: Dictionary = {"id": _seq, "hid": hid, "amount": amount, "base": amount, "issued": SysUtil.day(),
		"due": SysUtil.day() + int(b.get("due_after_days", 3)), "paid": false, "late": false, "fee": 0}
	_seq += 1
	bills.append(bill)
	usage[hid] = 0.0
	SysUtil.notify("Household bills: %d coins, due on day %d." % [amount, int(bill["due"])], "bill")
	SysUtil.game_event("bill_issued", {"household_id": hid, "amount": amount, "due": bill["due"]})
	return bill

## Pay every outstanding bill of the household if it can afford all of them. Returns coins paid.
static func pay_bill(hid: int) -> int:
	var total: int = owed(hid)
	if total <= 0:
		return 0
	if not spend(hid, total, "bills"):
		return 0
	for bl in outstanding(hid):
		bl["paid"] = true
	missed[hid] = 0
	SysUtil.notify("Paid bills: %d coins." % total, "bill")
	SysUtil.game_event("bill_paid", {"household_id": hid, "amount": total})
	return total

static func on_day(day: int) -> void:
	refresh_objects()
	var b: Dictionary = bill_cfg()
	if next_bill_day <= 0:
		next_bill_day = int(b.get("first_day", 7))
	var every: int = maxi(int(b.get("every_days", 7)), 1)
	# 1) due / late handling for existing bills
	for bl in bills:
		if bool(bl["paid"]):
			continue
		var hid: int = int(bl["hid"])
		if day < int(bl["due"]):
			continue
		if auto_pay and balance(hid) >= int(bl["amount"]):
			pay_bill(hid)
			continue
		if not bool(bl["late"]):
			bl["late"] = true
			var fee: int = maxi(int(b.get("late_fee_min", 10)), int(round(float(bl["amount"]) * float(b.get("late_fee_rate", 0.1)))))
			bl["fee"] = fee
			bl["amount"] = int(bl["amount"]) + fee
			missed[hid] = int(missed.get(hid, 0)) + 1
			SysUtil.notify("Bill overdue! Late fee %d added (now %d coins)." % [fee, int(bl["amount"])], "warn")
			SysUtil.game_event("bill_late", {"household_id": hid, "amount": bl["amount"], "missed": missed[hid]})
			if int(missed[hid]) >= int(b.get("repossess_after_cycles", 3)):
				_repossess(hid)
	# 2) a new billing cycle (after processing, so a fresh bill is not instantly due)
	# One bill per call, even if the clock skipped several cycles: missed cycles are merged, never stacked.
	if day >= next_bill_day:
		for hid2 in household_ids():
			issue_bill(int(hid2))
		Weather.reset_bill_period()
		next_bill_day += every * (1 + (day - next_bill_day) / every)
	# issued bills with due == today are handled tomorrow

static func _repossess(hid: int) -> void:
	var protected_tags: Array = bill_cfg().get("protected_tags", [])
	var best = null
	var best_price: int = -1
	for o in objects_of(hid):
		var od: Dictionary = SimEnv.data().object_def(str(o.def_id))
		var skip: bool = false
		for t in od.get("tags", []):
			if protected_tags.has(t):
				skip = true
		if skip:
			continue
		var p: int = object_price(o)
		if p > best_price:
			best_price = p
			best = o
	if best == null:
		return
	var def_id: String = str(best.def_id)
	var oid: int = int(best.id)
	var w = WorldIface.world()
	if w != null and w.has_method("remove_object"):
		w.remove_object(oid)
	owner.erase(oid)
	placed_day.erase(oid)
	repossessed.append({"day": SysUtil.day(), "hid": hid, "def_id": def_id, "value": best_price})
	var label: String = str(SimEnv.data().object_def(def_id).get("label", def_id))
	SysUtil.notify("Repossessed: your %s was taken for unpaid bills!" % label, "bad")
	SysUtil.game_event("repossessed", {"household_id": hid, "def_id": def_id, "object_id": oid})

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {
		"bills": bills.duplicate(true), "missed": SysUtil.str_keys(missed), "ledger": SysUtil.str_keys(ledger).duplicate(true),
		"owner": SysUtil.str_keys(owner), "placed_day": SysUtil.str_keys(placed_day), "usage": SysUtil.str_keys(usage),
		"repossessed": repossessed.duplicate(true), "next_bill_day": next_bill_day, "auto_pay": auto_pay, "seq": _seq,
		"funds": SysUtil.str_keys(_funds_without_npcs()),
	}

## Household balances only: the pocket money of ambient NPCs (household -1) is not saved.
static func _funds_without_npcs() -> Dictionary:
	var out: Dictionary = WorldIface.coins.duplicate()
	out.erase(-1)
	return out

static func from_dict(d: Dictionary) -> void:
	reset()
	bills = (d.get("bills", []) as Array).duplicate(true)
	missed = SysUtil.int_keys(d.get("missed", {}))
	ledger = SysUtil.int_keys((d.get("ledger", {}) as Dictionary).duplicate(true))
	owner = SysUtil.int_keys(d.get("owner", {}))
	placed_day = SysUtil.int_keys(d.get("placed_day", {}))
	usage = SysUtil.int_keys(d.get("usage", {}))
	repossessed = (d.get("repossessed", []) as Array).duplicate(true)
	next_bill_day = int(d.get("next_bill_day", 0))
	auto_pay = bool(d.get("auto_pay", true))
	_seq = int(d.get("seq", 1))
	if d.has("funds"):
		WorldIface.coins.clear()
		var fd: Dictionary = SysUtil.int_keys(d["funds"])
		for k in fd:
			WorldIface.coins[k] = int(fd[k])
	for bl in bills:
		SysUtil.ints_in(bl, ["id", "hid", "amount", "base", "issued", "due", "fee"])
