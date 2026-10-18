class_name BusinessCmd
extends RefCounted
## The player's business commands (task 13): open (rent a slot or buy it), set prices and hours, hire and fire townies, restock, expand,
## sell up. Each returns {ok, reason, ...}. Money only through Economy. Optional: a household that never opens one is untouched.

static func _no(why: String) -> Dictionary:
	return {"ok": false, "reason": why}

static func _ok(extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"ok": true, "reason": ""}
	d.merge(extra, true)
	return d

static func _mine(hid: int, id: int) -> Dictionary:
	var b: Dictionary = BusinessState.get_biz(id)
	if b.is_empty() or str(b["owner_kind"]) != "player" or int(b["owner"]) != hid:
		return {}
	return b

static func fitout_cost(t: String) -> int:
	return int(round(float(BusinessState.type_def(t).get("fitout", 1000)) * MarketEconomy.price_mult()))

## Extra price of buying the slot outright (renting costs nothing up front).
static func slot_price(lot: String) -> int:
	return int(round(float((BusinessState.cfg().get("lot_rent", {}) as Dictionary).get(lot, 30)) * 40.0 * MarketEconomy.rent_mult()))

static func open_cost(t: String, lot: String, mode: String) -> int:
	return fitout_cost(t) + (slot_price(lot) if mode == "own" else 0)

static func open(hid: int, t: String, lot: String, mode: String, nm: String = "") -> Dictionary:
	var td: Dictionary = BusinessState.type_def(t)
	if td.is_empty():
		return _no("Unknown kind of business.")
	if not (td.get("lots", []) as Array).has(lot):
		return _no("That kind of business cannot trade there.")
	if BusinessState.free_slots(lot) <= 0:
		return _no("There is no free space there.")
	if mode != "rent" and mode != "own":
		return _no("Rent or buy the space.")
	var cost: int = open_cost(t, lot, mode)
	if not Economy.can_afford(hid, cost):
		return _no("You need %d coins to open." % cost)
	Economy.spend(hid, cost, "new business: %s" % str(td.get("label", t)))
	if nm == "":
		nm = "%s's %s" % [_founder(hid), str(td.get("label", t))]
	var b: Dictionary = BusinessState.make(t, lot, mode, "player", hid, nm)
	b["stock"] = int(BusinessState.stock_cap(b) * float(BusinessState.cfg().get("stock", {}).get("start_fraction", 0.5)))
	b["owner_skill"] = _owner_skill(hid, str(td.get("skill", "")))
	SysUtil.game_event("business_opened", {"household_id": hid, "business": int(b["id"]), "type": t})
	ChronicleHook.note("business", "%s opened %s." % [_founder(hid), nm], [], "home:%d" % hid, 1, true)
	return _ok({"id": int(b["id"]), "cost": cost})

static func _founder(hid: int) -> String:
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			return str(f.name).split(" ")[0]
	return "Town"

## The owner's own skill in the business's field (a skilled cook runs a better cafe).
static func _owner_skill(hid: int, skill: String) -> float:
	var best: float = 2.0
	for f in SysUtil.residents():
		if int(f.household_id) == hid and f.age_stage == "adult":
			best = maxf(best, 2.0 + float(f.skill_level(skill)))
	return minf(best, 9.0)

static func set_price(hid: int, id: int, level: float) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	var lv: Array = BusinessState.cfg().get("price_levels", [1.0])
	var best: float = float(lv[0])
	for x in lv:
		if absf(float(x) - level) < absf(best - level):
			best = float(x)
	b["price"] = best
	return _ok({"price": best})

static func set_hours(hid: int, id: int, h_open: int, h_close: int) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	if h_open < 0 or h_close > 24 or h_close - h_open < 3:
		return _no("Open for at least three hours, between midnight and midnight.")
	b["hours"] = [h_open, h_close]
	return _ok()

static func set_open(hid: int, id: int, is_open: bool) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	b["open"] = is_open
	return _ok()

static func set_auto_stock(hid: int, id: int, on: bool) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	b["auto_stock"] = on
	return _ok()

static func restock(hid: int, id: int, units: int) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	var room: int = BusinessState.stock_cap(b) - int(b["stock"])
	var n: int = mini(units, room)
	if n <= 0:
		return _no("The shelves are full.")
	var cost: int = int(ceil(float(n) * BusinessSim.unit_cost(b)))
	if not Economy.spend(hid, cost, "stock: %s" % str(b["name"])):
		return _no("Stock for %d units costs %d coins." % [n, cost])
	b["stock"] = int(b["stock"]) + n
	return _ok({"units": n, "cost": cost})

# ------------------------------------------------------------------ staff
static func max_staff(b: Dictionary) -> int:
	var h: Dictionary = BusinessState.cfg().get("hire", {})
	return int(h.get("max_staff_base", 2)) + int(h.get("max_staff_per_level", 2)) * (int(b["level"]) - 1)

## A townie's skill for hiring: their career level plus a little from their traits.
static func townie_skill(t: Dictionary) -> int:
	return clampi(int(t.get("level", 1)) + 1 + (1 if (t.get("traits", []) as Array).has("hard_working") else 0), 1, 9)

static func candidates() -> Array:
	var out: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["adult", "teen"] and str(t.get("career", "")) == "" and not t.has("job_biz") and not t.has("owner_biz"):
			out.append({"tid": int(t["id"]), "name": str(t["name"]), "skill": townie_skill(t), "wage": BusinessSim.hire_wage(townie_skill(t))})
	return out

static func hire(hid: int, id: int, tid: int) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	if (b["staff"] as Array).size() >= max_staff(b):
		return _no("There is no room for more staff.")
	var t: Dictionary = Story.townies.get(tid, {})
	if t.is_empty() or not bool(t.get("alive", false)) or str(t.get("career", "")) != "" or t.has("job_biz") or t.has("owner_biz"):
		return _no("They are not looking for work.")
	var fee: int = int(BusinessState.cfg().get("hire", {}).get("hire_cost", 40))
	if not Economy.spend(hid, fee, "hiring fee: %s" % str(t["name"])):
		return _no("The hiring fee is %d coins." % fee)
	var skill: int = townie_skill(t)
	(b["staff"] as Array).append({"tid": tid, "wage": BusinessSim.hire_wage(skill), "skill": skill})
	t["job_biz"] = int(b["id"])
	return _ok({"wage": BusinessSim.hire_wage(skill)})

static func fire(hid: int, id: int, tid: int) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	var keep: Array = []
	var found: bool = false
	for s in b["staff"]:
		if int(s["tid"]) == tid:
			found = true
		else:
			keep.append(s)
	if not found:
		return _no("They do not work there.")
	b["staff"] = keep
	var t: Dictionary = Story.townies.get(tid, {})
	if not t.is_empty():
		t.erase("job_biz")
	return _ok()

# ------------------------------------------------------------------ growth
static func expand_cost(b: Dictionary) -> int:
	return int(round(float(fitout_cost(str(b["type"]))) * float(BusinessState.cfg().get("expand", {}).get("cost_mult", 0.8)) * float(b["level"])))

static func why_not_expand(b: Dictionary) -> String:
	var e: Dictionary = BusinessState.cfg().get("expand", {})
	if int(b["level"]) >= int(BusinessState.cfg().get("max_levels", 3)):
		return "It cannot grow any bigger."
	if float(b["rep"]) < float(e.get("min_reputation", 55)):
		return "Build a better reputation first (%d needed)." % int(e.get("min_reputation", 55))
	return ""

static func expand(hid: int, id: int) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	var why: String = why_not_expand(b)
	if why != "":
		return _no(why)
	var cost: int = expand_cost(b)
	if not Economy.spend(hid, cost, "expansion: %s" % str(b["name"])):
		return _no("Expanding costs %d coins." % cost)
	b["level"] = int(b["level"]) + 1
	return _ok({"cost": cost, "level": int(b["level"])})

static func sale_value(b: Dictionary) -> int:
	var s: Dictionary = BusinessState.cfg().get("sale", {})
	var v: float = float(BusinessState.type_def(str(b["type"])).get("fitout", 1000)) * MarketEconomy.price_mult() * float(s.get("fitout_fraction", 0.5)) * float(b["level"])
	var avg: float = 0.0
	for p in b["hist"]:
		avg += float(p)
	avg /= maxf(float((b["hist"] as Array).size()), 1.0)
	v += maxf(avg, 0.0) * float(s.get("profit_days", 5))
	if str(b["mode"]) == "own":
		v += slot_price(str(b["lot"])) * 0.6
	return int(round(v))

static func sell(hid: int, id: int) -> Dictionary:
	var b: Dictionary = _mine(hid, id)
	if b.is_empty():
		return _no("That is not your business.")
	var v: int = sale_value(b) + maxi(int(b["cash"]), 0)
	Economy.deposit(hid, v, "sold business: %s" % str(b["name"]))
	BusinessState.close(b, "sold")
	return _ok({"value": v})
