class_name ShopStock
extends RefCounted
## Shop shelves (task 13, slice 2). Shops are DATA (data/shops.json) on existing lots: stock, prices, hours. Stock sells down with town demand
## and restocks daily; sales and holiday deals change prices; MarketEconomy.price_mult() moves everything with the economy.
## Tier: town-wide, DAILY (restock/demand/deals) + on player command. Active set: the ~9 shops x <=6 items (a few dozen counters).
## Caps: orders 40, inventory per household by item id. State: stock, deals, orders, inventory (bought items), parcels (furniture to place free).

static var stock: Dictionary = {}       # "shop/item" -> units on the shelf
static var deals: Dictionary = {}       # shop id -> {pct, until}
static var orders: Array = []           # online orders in transit {hid, shop, item, qty, due}
static var inventory: Dictionary = {}   # hid -> {item id -> count}
static var parcels: Dictionary = {}     # hid -> {object def id -> count}: bought furniture, placed in build mode at no further cost
static var sold_out: Array = []         # "shop/item" that ran out today (news / UI hint)
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	stock.clear()
	deals.clear()
	orders.clear()
	inventory.clear()
	parcels.clear()
	sold_out.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = 130021

static func cfg() -> Dictionary:
	return SysUtil.table("shops").get("stock", {})

static func shops() -> Dictionary:
	return SysUtil.table("shops").get("shops", {})

static func shop(sid: String) -> Dictionary:
	return shops().get(sid, {})

static func item(sid: String, iid: String) -> Dictionary:
	return (shop(sid).get("items", {}) as Dictionary).get(iid, {})

static func shop_ids() -> Array:
	var ids: Array = shops().keys()
	ids.sort()
	return ids

static func _key(sid: String, iid: String) -> String:
	return sid + "/" + iid

## Units on the shelf (fills a never-seen item to its starting stock).
static func units(sid: String, iid: String) -> int:
	var k: String = _key(sid, iid)
	if not stock.has(k):
		stock[k] = int(item(sid, iid).get("stock", 0))
	return int(stock[k])

static func take(sid: String, iid: String, n: int) -> bool:
	if units(sid, iid) < n:
		return false
	stock[_key(sid, iid)] = units(sid, iid) - n
	return true

# ------------------------------------------------------------------ prices & hours
static func deal_pct(sid: String) -> float:
	var pct: float = 0.0
	var d: Dictionary = deals.get(sid, {})
	if not d.is_empty() and SysUtil.day() <= int(d.get("until", -1)):
		pct = float(d.get("pct", 0.0))
	if not Holidays.today().is_empty():
		pct = maxf(pct, float(cfg().get("holiday_pct", 0.15)))
	return pct

static func on_sale(sid: String) -> bool:
	return deal_pct(sid) > 0.0

static func price(sid: String, iid: String) -> int:
	var it: Dictionary = item(sid, iid)
	if it.is_empty():
		return 0
	var p: float = float(it.get("base", 0)) * MarketEconomy.price_mult() * (1.0 - deal_pct(sid))
	var cap: float = maxf(float(it.get("stock", 1)), 1.0)
	if float(units(sid, iid)) / cap < float(cfg().get("scarce_below", 0.2)):
		p *= 1.0 + float(cfg().get("scarce_markup", 0.1))
	return maxi(int(round(p)), 1)

static func is_open(sid: String, at_hour: float = -1.0) -> bool:
	var h: float = SysUtil.hour_f() if at_hour < 0.0 else at_hour
	var hrs: Array = shop(sid).get("hours", [8, 20])
	return h >= float(hrs[0]) and h < float(hrs[1])

## Shops open now on a given lot ("market", "library", "office").
static func shops_at(lot_id: String) -> Array:
	var out: Array = []
	for sid in shop_ids():
		if str(shop(sid).get("lot", "")) == lot_id:
			out.append(sid)
	return out

static func online_shops() -> Array:
	var out: Array = []
	for sid in shop_ids():
		if bool(shop(sid).get("online", false)):
			out.append(sid)
	return out

# ------------------------------------------------------------------ the owned side
static func inv_count(hid: int, iid: String) -> int:
	return int((inventory.get(hid, {}) as Dictionary).get(iid, 0))

static func inv_add(hid: int, iid: String, n: int) -> void:
	if not inventory.has(hid):
		inventory[hid] = {}
	inventory[hid][iid] = inv_count(hid, iid) + n
	if int(inventory[hid][iid]) <= 0:
		(inventory[hid] as Dictionary).erase(iid)

static func parcel_count(hid: int, def_id: String) -> int:
	return int((parcels.get(hid, {}) as Dictionary).get(def_id, 0))

static func parcel_add(hid: int, def_id: String, n: int) -> void:
	if not parcels.has(hid):
		parcels[hid] = {}
	parcels[hid][def_id] = parcel_count(hid, def_id) + n

## World build hook: a bought piece of furniture is placed for free (returns true and uses one parcel).
static func take_parcel(hid: int, def_id: String) -> bool:
	if parcel_count(hid, def_id) <= 0:
		return false
	parcels[hid][def_id] = parcel_count(hid, def_id) - 1
	if int(parcels[hid][def_id]) <= 0:
		(parcels[hid] as Dictionary).erase(def_id)
	return true

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	var c: Dictionary = cfg()
	sold_out.clear()
	_rotate_sale(day, c)
	var prosp: float = MarketEconomy.prosperity if MarketEconomy.enabled else 0.0
	var noise: float = float(c.get("demand_noise", 0.4))
	for sid in shop_ids():
		var items: Dictionary = shop(sid).get("items", {})
		var iids: Array = items.keys()
		iids.sort()
		for iid in iids:
			var it: Dictionary = items[iid]
			var k: String = _key(sid, iid)
			var have: int = units(sid, iid)
			var demand: float = float(it.get("demand", 0.0)) * (1.0 + 0.3 * prosp) * (1.0 + deal_pct(sid)) * (1.0 + rng.randf_range(-noise, noise))
			var sold: int = mini(have, int(floor(demand)) + (1 if rng.randf() < demand - floor(demand) else 0))
			have -= sold
			if have <= 0 and sold > 0:
				sold_out.append(k)
			# the supplier's truck: restock per day, a little slower in a recession
			var truck: float = float(it.get("restock", 0)) * (1.0 + 0.2 * prosp)
			var add: int = int(floor(truck)) + (1 if rng.randf() < truck - floor(truck) else 0)
			stock[k] = clampi(have + add, 0, int(it.get("stock", 0)))
	_deliver(day)

static func _rotate_sale(day: int, c: Dictionary) -> void:
	for sid in deals.keys():
		if day > int((deals[sid] as Dictionary).get("until", 0)):
			deals.erase(sid)
	var every: int = maxi(int(c.get("sale_days", 7)), 1)
	if day % every != 0:
		return
	var ids: Array = shop_ids()
	if ids.is_empty():
		return
	var sid2: String = str(ids[rng.randi_range(0, ids.size() - 1)])
	deals[sid2] = {"pct": float(c.get("sale_pct", 0.2)), "until": day + int(c.get("sale_length", 3)) - 1}
	ChronicleHook.note("sale", "%s has a sale on for a few days." % str(shop(sid2).get("label", sid2)), [], "town:0", 1, true)

static func _deliver(day: int) -> void:
	var keep: Array = []
	for o in orders:
		if day >= int(o["due"]):
			ShopBuy.receive(int(o["hid"]), str(o["shop"]), str(o["item"]), int(o["qty"]), -1)
			SysUtil.notify("A delivery arrived: %s." % str(item(str(o["shop"]), str(o["item"])).get("label", o["item"])), "info")
		else:
			keep.append(o)
	orders = keep

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"stock": stock.duplicate(), "deals": deals.duplicate(true), "orders": orders.duplicate(true), "inventory": SysUtil.str_keys(inventory).duplicate(true),
		"parcels": SysUtil.str_keys(parcels).duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for k in (d.get("stock", {}) as Dictionary):
		stock[str(k)] = int(d["stock"][k])
	deals = (d.get("deals", {}) as Dictionary).duplicate(true)
	for sid in deals:
		SysUtil.ints_in(deals[sid], ["until"])
	orders = (d.get("orders", []) as Array).duplicate(true)
	for o in orders:
		SysUtil.ints_in(o, ["hid", "qty", "due"])
	inventory = _int_counts(SysUtil.int_keys((d.get("inventory", {}) as Dictionary).duplicate(true)))
	parcels = _int_counts(SysUtil.int_keys((d.get("parcels", {}) as Dictionary).duplicate(true)))
	rng.seed = int(str(d.get("rng_seed", "130021")))
	rng.state = int(str(d.get("rng_state", str(rng.state))))

static func _int_counts(by_hid: Dictionary) -> Dictionary:
	for hid in by_hid:
		for k in by_hid[hid]:
			by_hid[hid][k] = int(by_hid[hid][k])
	return by_hid
