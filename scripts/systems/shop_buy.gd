class_name ShopBuy
extends RefCounted
## Buying from the shelves (task 13). `buy` = walk in (the folk must be at the shop's lot when `folk_id` >= 0) or `order` = online with a
## delivery fee and a day's wait. Every coin goes through Economy.spend with a reason. `use` consumes a bought item.

static func why_not(hid: int, folk_id: int, sid: String, iid: String, qty: int, online: bool) -> String:
	var it: Dictionary = ShopStock.item(sid, iid)
	if it.is_empty() or qty <= 0:
		return "That is not for sale."
	var sh: Dictionary = ShopStock.shop(sid)
	if str(it.get("kind", "")) == "lottery" and folk_id >= 0:
		var gf = SysUtil.folk(folk_id)
		if gf != null and Places.stage_reason(str(gf.age_stage), {"adult_only": true}) != "":
			return "Only adults can play the lottery."          # task 14: gambling is adult-only
	if online:
		if not bool(sh.get("online", false)):
			return "This shop does not deliver."
	else:
		if not ShopStock.is_open(sid):
			return "The shop is closed."
		if folk_id >= 0 and not _at_shop(folk_id, str(sh.get("lot", ""))):
			return "You have to go to the shop first."
	if ShopStock.units(sid, iid) < qty:
		return "Sold out." if ShopStock.units(sid, iid) <= 0 else "Not enough in stock."
	var total: int = ShopStock.price(sid, iid) * qty + (_fee() if online else 0)
	if not Economy.can_afford(hid, total):
		return "Not enough coins."
	return ""

static func _fee() -> int:
	return int(ShopStock.cfg().get("delivery_fee", 8))

## No map (tests / stub worlds) or the folk is at the lot.
static func _at_shop(folk_id: int, lot_id: String) -> bool:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return false
	var w = WorldIface.world()
	if w == null or not ("regions" in w) or not w.regions.has_regions():
		return true
	return Neighborhood.lot_of(f) == lot_id

## Returns {ok, reason, paid}.
static func buy(hid: int, folk_id: int, sid: String, iid: String, qty: int = 1, online: bool = false) -> Dictionary:
	var why: String = why_not(hid, folk_id, sid, iid, qty, online)
	if why != "":
		return {"ok": false, "reason": why, "paid": 0}
	var unit: int = ShopStock.price(sid, iid)
	var total: int = unit * qty + (_fee() if online else 0)
	var label: String = str(ShopStock.item(sid, iid).get("label", iid))
	if not Economy.spend(hid, total, "shop: %s x%d" % [label, qty]):
		return {"ok": false, "reason": "Not enough coins.", "paid": 0}
	ShopStock.take(sid, iid, qty)
	if online:
		ShopStock.orders.append({"hid": hid, "shop": sid, "item": iid, "qty": qty, "due": SysUtil.day() + int(ShopStock.cfg().get("delivery_days", 1))})
		if ShopStock.orders.size() > 40:
			ShopStock.orders.pop_front()
		SysUtil.notify("Ordered %s. It will be delivered tomorrow." % label, "info")
	else:
		receive(hid, sid, iid, qty, folk_id)
	SysUtil.game_event("shop_bought", {"household_id": hid, "shop": sid, "item": iid, "qty": qty, "paid": total, "online": online})
	return {"ok": true, "reason": "", "paid": total}

## The goods arrive (at once in a shop, a day later online). `folk_id` >= 0 = the buyer who uses buff / skill items on the spot.
static func receive(hid: int, sid: String, iid: String, qty: int, folk_id: int) -> void:
	var it: Dictionary = ShopStock.item(sid, iid)
	match str(it.get("kind", "item")):
		"food":
			Neighborhood.add_pantry(int(it.get("units", 1)) * qty)
		"lottery":
			BankGamble.add_tickets(hid, qty, folk_id)
		"object":
			ShopStock.parcel_add(hid, str(it.get("def", iid)), qty)
		_:
			ShopStock.inv_add(hid, iid, qty)
			if folk_id >= 0 and str(it.get("kind", "")) in ["buff", "skill"]:
				use(hid, folk_id, iid, qty)

## Use up bought items on a folk. Returns the number used.
static func use(hid: int, folk_id: int, iid: String, qty: int = 1) -> int:
	var f = SysUtil.folk(folk_id)
	var sid: String = _shop_of(iid)
	var it: Dictionary = ShopStock.item(sid, iid)
	if f == null or it.is_empty():
		return 0
	var n: int = mini(qty, ShopStock.inv_count(hid, iid))
	for _i in n:
		match str(it.get("kind", "")):
			"buff":
				f.add_buff(str(it.get("buff", "")))
			"skill":
				f.add_skill_xp(str(it.get("skill", "logic")), float(it.get("xp", 20)))
			_:
				match str(it.get("use", "")):
					"medicine":
						SysUtil.game_event("health_medicine", {"folk_id": folk_id})
					"first_aid":
						SysUtil.game_event("health_first_aid", {"folk_id": folk_id, "target_id": folk_id})
					"repair":
						if not _repair_one(hid):
							return _used(hid, iid, _i)
					_:
						return _used(hid, iid, _i)
	return _used(hid, iid, n)

static func _used(hid: int, iid: String, n: int) -> int:
	ShopStock.inv_add(hid, iid, -n)
	return n

static func _shop_of(iid: String) -> String:
	for sid in ShopStock.shop_ids():
		if (ShopStock.shop(sid).get("items", {}) as Dictionary).has(iid):
			return sid
	return ""

static func _repair_one(hid: int) -> bool:
	for o in Economy.objects_of(hid):
		if bool(WorldIface.state_get(o, "broken", false)):
			WorldIface.state_set(o, "broken", false)
			return true
	return false
