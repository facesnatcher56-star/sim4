class_name BusinessSim
extends RefCounted
## The daily business model (task 13), the same for player and townie businesses. Customers come from the type's demand x location traffic x
## reputation x price (elasticity -1.5) x prosperity x competition x opening-hours fit; staff set the capacity and the quality; stock is used
## per customer. Result {customers, revenue, costs, profit, unserved}. Reputation drifts toward a target built from service, stock and price;
## customers leave stars-and-text reviews. Cash going below zero for `bankrupt_after_days` days closes the business.
## Tier: DAILY, one call per open business (<= 10). Seeded rng (BusinessSim.rng).

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 130051

static func _staff_n(b: Dictionary) -> int:
	return (b["staff"] as Array).size()

static func staff_skill(b: Dictionary) -> float:
	var total: float = float(b["owner_skill"])
	var n: int = 1
	for s in b["staff"]:
		total += float(s["skill"])
		n += 1
	return total / float(n)

static func competitors(b: Dictionary) -> float:
	var w: float = 0.0
	for id in BusinessState.list:
		var o: Dictionary = BusinessState.list[id]
		if int(o["id"]) == int(b["id"]) or str(o["type"]) != str(b["type"]) or not bool(o["open"]):
			continue
		var rep_w: float = 0.6 + float(o["rep"]) / 125.0
		w += (1.0 if str(o["lot"]) == str(b["lot"]) else 0.4) * rep_w
	return w

static func open_hours(b: Dictionary) -> int:
	return maxi(int(b["hours"][1]) - int(b["hours"][0]), 0)

## Hours inside the type's natural trading window count fully, the others at a quarter (a late cafe, an early gym).
static func effective_hours(b: Dictionary) -> float:
	var td: Dictionary = BusinessState.type_def(str(b["type"]))
	var th: Array = td.get("hours", [9, 18])
	var lo: int = maxi(int(b["hours"][0]), int(th[0]))
	var hi: int = mini(int(b["hours"][1]), int(th[1]))
	var inside: float = maxf(float(hi - lo), 0.0)
	return inside + 0.25 * (float(open_hours(b)) - inside)

static func capacity(b: Dictionary) -> float:
	var td: Dictionary = BusinessState.type_def(str(b["type"]))
	var per: float = float(td.get("cap_per_staff", 1.5))
	var lvl: float = pow(float(BusinessState.cfg().get("expand", {}).get("capacity_mult", 1.4)), float(int(b["level"]) - 1))
	return float(1 + _staff_n(b)) * per * float(open_hours(b)) * lvl

static func demand(b: Dictionary) -> float:
	var td: Dictionary = BusinessState.type_def(str(b["type"]))
	var traffic: float = float((BusinessState.cfg().get("traffic", {}) as Dictionary).get(str(b["lot"]), 1.0))
	var rep_mult: float = 0.4 + 1.2 * float(b["rep"]) / 100.0
	var prosp: float = MarketEconomy.prosperity if MarketEconomy.enabled else 0.0
	var lvl: float = pow(float(BusinessState.cfg().get("expand", {}).get("capacity_mult", 1.4)), float(int(b["level"]) - 1))
	var comp: float = 1.0 / (1.0 + 0.25 * competitors(b))
	return float(td.get("demand", 2.0)) * effective_hours(b) \
		* traffic * rep_mult * pow(float(b["price"]), -1.5) * (1.0 + 0.35 * prosp) * comp * lvl

static func unit_cost(b: Dictionary) -> float:
	return float(BusinessState.type_def(str(b["type"])).get("unit_cost", 3.0)) * MarketEconomy.price_mult()

static func daily_wages(b: Dictionary) -> float:
	var total: float = 0.0
	for s in b["staff"]:
		total += float(s["wage"]) * float(open_hours(b))
	return total

static func daily_rent(b: Dictionary) -> float:
	if str(b["mode"]) != "rent":
		return 0.0
	return float((BusinessState.cfg().get("lot_rent", {}) as Dictionary).get(str(b["lot"]), 40)) * MarketEconomy.rent_mult()

static func hire_wage(skill: int) -> int:
	var h: Dictionary = BusinessState.cfg().get("hire", {})
	return int(round((float(h.get("base_wage", 9)) + float(h.get("skill_wage", 1.2)) * float(skill)) * MarketEconomy.wage_mult()))

# ------------------------------------------------------------------ one day
static func run_day(b: Dictionary) -> Dictionary:
	var td: Dictionary = BusinessState.type_def(str(b["type"]))
	var res: Dictionary = {"customers": 0, "revenue": 0.0, "costs": 0.0, "profit": 0.0, "unserved": 0, "demand": 0.0}
	var rent: float = daily_rent(b)
	var utils: float = 6.0 * MarketEconomy.price_mult()
	if not bool(b["open"]) or open_hours(b) <= 0:
		res["costs"] = rent
		res["profit"] = -rent
		return _apply(b, res)
	var dem: float = demand(b)
	dem *= 1.0 + rng.randf_range(-0.2, 0.2)
	var cap: float = capacity(b)
	var want: float = minf(dem, cap)
	var use: float = float(td.get("stock_use", 1.0))
	var served: float = want
	var out_of_stock: bool = false
	if not bool(b["auto_stock"]):
		var can: float = float(b["stock"]) / maxf(use, 0.01)
		if can < served:
			served = can
			out_of_stock = true
	var customers: int = int(floor(served)) + (1 if rng.randf() < served - floor(served) else 0)
	var units: int = int(ceil(float(customers) * use))
	if not bool(b["auto_stock"]):
		b["stock"] = maxi(int(b["stock"]) - units, 0)
	var price_f: float = float(td.get("avg_spend", 10)) * float(b["price"]) * MarketEconomy.price_mult()
	res["customers"] = customers
	res["demand"] = dem
	res["unserved"] = int(maxf(dem - float(customers), 0.0))
	res["revenue"] = float(customers) * price_f
	res["costs"] = float(units) * unit_cost(b) + daily_wages(b) + rent + utils
	res["profit"] = float(res["revenue"]) - float(res["costs"])
	_reputation(b, td, dem, customers, out_of_stock)
	_review(b, customers)
	return _apply(b, res)

static func _apply(b: Dictionary, res: Dictionary) -> Dictionary:
	b["cash"] = float(b["cash"]) + float(res["profit"])
	b["profit_total"] = float(b["profit_total"]) + float(res["profit"])
	(b["hist"] as Array).append(snappedf(float(res["profit"]), 0.1))
	while (b["hist"] as Array).size() > 7:
		(b["hist"] as Array).pop_front()
	b["last"] = res
	return res

static func _reputation(b: Dictionary, td: Dictionary, dem: float, customers: int, out_of_stock: bool) -> void:
	var unserved_ratio: float = clampf((dem - float(customers)) / maxf(dem, 1.0), 0.0, 1.0)
	var target: float = 48.0 + 3.0 * (staff_skill(b) - 3.0) + 5.0 * float(mini(_staff_n(b), 3)) - 22.0 * (float(b["price"]) - 1.0) \
		- 30.0 * unserved_ratio - (14.0 if out_of_stock else 0.0)
	target += 4.0 * float(int(b["level"]) - 1)
	b["rep"] = clampf(float(b["rep"]) + (clampf(target, 5.0, 98.0) - float(b["rep"])) * 0.08, 0.0, 100.0)

static func _review(b: Dictionary, customers: int) -> void:
	var rv: Dictionary = BusinessState.cfg().get("reviews", {})
	if customers <= 0 or rng.randf() >= float(rv.get("chance", 0.5)):
		return
	var stars: int = clampi(int(round(1.0 + float(b["rep"]) / 25.0 + rng.randf_range(-0.9, 0.9))), 1, 5)
	var texts: Array = (BusinessState.cfg().get("review_text", {}) as Dictionary).get(str(stars), ["..."])
	var arr: Array = b["reviews"]
	arr.append({"day": SysUtil.day(), "stars": stars, "text": str(texts[rng.randi_range(0, texts.size() - 1)])})
	while arr.size() > int(rv.get("keep", 8)):
		arr.pop_front()
	var sum: float = 0.0
	for r in arr:
		sum += float(r["stars"])
	b["stars"] = sum / float(arr.size())
