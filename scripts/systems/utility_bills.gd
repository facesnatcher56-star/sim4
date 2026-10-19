class_name UtilityBills
extends RefCounted
## Each bill is split by utility (task 12.1): electricity, water and sewage, phone and internet, council charges, plus the optional cover (insurance premiums).
## Fixed charges (base + lot value) are shared out by data/city.json utilities.fixed_share; use (Economy.usage, the weights of data/economy.json) goes to the
## utility the interaction used (utilities.usage shares). Solar panels, a water tank and a well cut their utility's part. The total is what Economy always charged.
##   UtilityBills.parts(hid) -> {power, water, internet, rates, cover}  (floats)     UtilityBills.describe(parts) -> "power 41, water 30, ..."
## Cadence: weekly (a bill) and on demand; per-use bookkeeping is one dictionary add per interaction a resident finishes.

static var used: Dictionary = {}          # str(hid) -> {power, water, internet} units since the last bill

static func reset() -> void:
	used.clear()

static func to_dict() -> Dictionary:
	return {"used": used.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	used = (d.get("used", {}) as Dictionary).duplicate(true)

static func note(hid: int, iid: String) -> void:
	var shares: Dictionary = (Utilities.cfg().get("usage", {}) as Dictionary).get(iid, {})
	var w: float = float((Economy.bill_cfg().get("utility_weights", {}) as Dictionary).get(iid, 0.0))
	if shares.is_empty() or w <= 0.0 or hid <= 0:
		return
	var total: float = 0.0
	for k in shares:
		total += float(shares[k])
	if total <= 0.0:
		return
	var rec: Dictionary = used.get(str(hid), {})
	for k2 in shares:
		rec[k2] = float(rec.get(k2, 0.0)) + w * float(shares[k2]) / total
	used[str(hid)] = rec

static func parts(hid: int) -> Dictionary:
	var b: Dictionary = Economy.bill_cfg()
	var fixed: float = float(b.get("base", 50)) + float(Economy.lot_value(hid)) * float(b.get("lot_value_rate", 0.015))
	var mult: float = Weather.bill_multiplier() * Scenario.bill_multiplier() * MarketEconomy.price_mult()
	var shares: Dictionary = Utilities.cfg().get("fixed_share", {})
	var rec: Dictionary = used.get(str(hid), {})
	var tracked: float = 0.0
	for k in rec:
		tracked += float(rec[k])
	var untracked: float = maxf(float(Economy.usage.get(hid, 0.0)) - tracked, 0.0)       # e.g. the heating of a blizzard: all power
	var rate: float = float(b.get("utility_rate", 0.8))
	var out: Dictionary = {}
	for u in ["power", "water", "internet", "rates"]:
		var v: float = fixed * float(shares.get(u, 0.0)) + float(rec.get(u, 0.0)) * rate
		if u == "power":
			v += untracked * rate
		out[u] = v * mult
	_savings(hid, out)
	out["cover"] = float(DisasterInsurance.bill_extra(hid)) + float(BankInsurance.bill_extra(hid)) + float(CrimeSecurityAlarm.bill_extra(hid))      # home insurance, health / car / life cover (13), alarm monitoring and a guard (21)
	return out

## Solar panels cut the electricity part, a water tank and a well the water part (each object, capped at 90 percent together).
static func _savings(hid: int, out: Dictionary) -> void:
	var objs: Dictionary = (Utilities.cfg().get("objects", {}) as Dictionary)
	var defs: Dictionary = UtilityHomes.defs_of(hid)
	var cut: Dictionary = {"power": 0.0, "water": 0.0}
	for oid in objs:
		var n: int = (defs.get(oid, []) as Array).size()
		if n == 0:
			continue
		var spec: Dictionary = objs[oid]
		for u in cut:
			cut[u] += float(spec.get(u + "_cut", 0.0)) * (1.0 if oid == "well" else float(n))
	for u2 in cut:
		out[u2] = float(out[u2]) * (1.0 - minf(float(cut[u2]), 0.9))

static func total(p: Dictionary) -> float:
	var t: float = 0.0
	for k in p:
		t += float(p[k])
	return t

## Whole numbers that add up to the bill total (the last part takes the rounding).
static func rounded(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var order: Array = ["power", "water", "internet", "rates", "cover"]
	var sum: int = 0
	var want: int = int(round(total(p)))
	for k in order:
		out[k] = int(round(float(p.get(k, 0.0))))
		sum += int(out[k])
	out["rates"] = int(out["rates"]) + (want - sum)
	return out

static func describe(p: Dictionary) -> String:
	var bits: Array = []
	for k in ["power", "water", "internet", "rates", "cover"]:
		var v: int = int(p.get(k, 0))
		if v <= 0:
			continue
		var name: String = {"power": "electricity", "water": "water", "internet": "phone and internet", "rates": "council charges", "cover": "insurance"}[k]
		bits.append("%s %d" % [name, v])
	return ", ".join(bits)
