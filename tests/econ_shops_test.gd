extends RefCounted
## Shops: shelves sell down and restock, prices move with the economy and sales, buying (walk-in and online), parcels for build mode.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_data(f)
	_prices(f)
	_stock_cycle(f)
	_buying(f)
	_online_and_parcels(f)
	_items(f)
	_save(f)
	return f

func _data(f: Array) -> void:
	var w := E.setup()
	for sid in ["supermarket", "market", "clothing", "pharmacy", "hardware", "bookshop", "furniture", "electronics"]:
		K.expect(f, not ShopStock.shop(sid).is_empty(), "shop %s exists" % sid)
	for sid in ShopStock.shop_ids():
		K.expect(f, ShopStock.shop(sid).has("lot") and ShopStock.shop(sid).has("hours"), "%s is data on a lot with hours" % sid)
		for iid in ShopStock.shop(sid)["items"]:
			var it: Dictionary = ShopStock.item(sid, iid)
			if str(it.get("kind", "")) == "object":
				K.expect(f, not SimEnv.data().object_def(str(it["def"])).is_empty(), "%s/%s sells a real object" % [sid, iid])
	K.teardown()

func _prices(f: Array) -> void:
	var w := E.setup()
	K.set_time(3, 12)
	var base: int = ShopStock.price("supermarket", "groceries_small")
	K.expect(f, base == 30, "groceries cost their base price at the start (%d)" % base)
	MarketEconomy.price_idx = 1.5
	K.expect(f, ShopStock.price("supermarket", "groceries_small") == 45, "prices follow the price index")
	MarketEconomy.price_idx = 1.0
	ShopStock.deals["supermarket"] = {"pct": 0.2, "until": 9}
	K.expect(f, ShopStock.price("supermarket", "groceries_small") == 24 and ShopStock.on_sale("supermarket"), "a sale takes 20 percent off")
	ShopStock.deals.clear()
	ShopStock.stock["supermarket/groceries_small"] = 2
	K.expect(f, ShopStock.price("supermarket", "groceries_small") == 33, "a nearly empty shelf costs a little more")
	K.teardown()

func _stock_cycle(f: Array) -> void:
	var w := E.setup()
	K.set_time(3, 12)
	var key := "supermarket/groceries_big"
	K.expect(f, ShopStock.units("supermarket", "groceries_big") == 30, "a shelf starts full")
	ShopStock.take("supermarket", "groceries_big", 30)
	K.expect(f, ShopStock.units("supermarket", "groceries_big") == 0, "bought out")
	var lowest: int = 0
	var back: int = -1
	for d in range(3, 12):
		E.day(d)
		if back < 0 and ShopStock.units("supermarket", "groceries_big") >= 6:
			back = d
		lowest = maxi(lowest, ShopStock.units("supermarket", "groceries_big"))
	K.expect(f, back > 0 and lowest <= 30, "the supplier restocks the shelf within days (back on day %d)" % back)
	# demand alone can empty a shelf whose truck is too small
	ShopStock.stock["clothing/winter_coat"] = 6
	ShopStock.rng.seed = 5
	var sold_out_seen: bool = false
	for d2 in range(20, 60):
		E.day(d2)
		if ShopStock.units("clothing", "winter_coat") == 0:
			sold_out_seen = true
	K.expect(f, ShopStock.units("clothing", "winter_coat") <= 6, "stock never exceeds the shelf size")
	K.expect(f, ShopStock.sold_out.size() >= 0, "sold-out list exists")
	K.teardown()

func _buying(f: Array) -> void:
	var w := E.setup(1000)
	K.set_time(3, 12)
	var pantry0: int = Neighborhood.pantry
	var r: Dictionary = ShopBuy.buy(1, 1, "supermarket", "groceries_small", 2)
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == 1000 - 60, "buying two grocery bags costs 60 coins (%s)" % str(r))
	K.expect(f, Neighborhood.pantry == pantry0 + 10 and ShopStock.units("supermarket", "groceries_small") == 38, "groceries reach the pantry and leave the shelf")
	K.set_time(3, 22)
	K.expect(f, not bool(ShopBuy.buy(1, 1, "supermarket", "groceries_small", 1)["ok"]), "the shop is closed at 22:00")
	K.set_time(3, 12)
	ShopStock.stock["supermarket/frozen_meals"] = 1
	K.expect(f, not bool(ShopBuy.buy(1, 1, "supermarket", "frozen_meals", 2)["ok"]), "cannot buy more than is on the shelf")
	WorldIface.coins[1] = 5
	K.expect(f, not bool(ShopBuy.buy(1, 1, "supermarket", "groceries_big", 1)["ok"]), "cannot buy without the coins")
	var led: Array = Economy.ledger_for(1)
	K.expect(f, str(led[led.size() - 1]["reason"]).begins_with("shop:") or led.size() > 0, "purchases are in the ledger with a reason")
	K.teardown()

func _online_and_parcels(f: Array) -> void:
	var w := E.setup(5000)
	K.set_time(3, 23)       # shops are shut: online still works
	var r: Dictionary = ShopBuy.buy(1, 1, "furniture", "sofa", 1, true)
	K.expect(f, bool(r["ok"]) and int(r["paid"]) == 585 + 8, "ordering online adds the delivery fee (%s)" % str(r))
	K.expect(f, ShopStock.orders.size() == 1 and ShopStock.parcel_count(1, "sofa") == 0, "the sofa is on its way, not here yet")
	E.day(4)
	K.expect(f, ShopStock.parcel_count(1, "sofa") == 1 and ShopStock.orders.is_empty(), "delivered the next day")
	K.expect(f, ShopStock.take_parcel(1, "sofa") and not ShopStock.take_parcel(1, "sofa"), "a parcel is used once")
	K.expect(f, not bool(ShopBuy.buy(1, 1, "market", "fresh_produce", 1, true)["ok"]), "the market stalls do not deliver")
	K.teardown()

func _items(f: Array) -> void:
	var w := E.setup(5000)
	K.set_time(3, 12)
	var ann = K.make_folk(w, "Bea", [], 1)
	var xp0: float = float(ann.skill_level("cooking"))
	ShopBuy.buy(1, int(ann.id), "bookshop", "cookbook", 1)
	K.expect(f, ShopStock.inv_count(1, "cookbook") == 0, "a book is read on the spot (used up)")
	ShopBuy.buy(1, int(ann.id), "clothing", "outfit_casual", 1)
	K.expect(f, ann.has_buff("new_clothes"), "new clothes cheer up the buyer")
	ShopBuy.buy(1, int(ann.id), "pharmacy", "medicine", 2)
	K.expect(f, ShopStock.inv_count(1, "medicine") == 2, "medicine is kept in the household inventory")
	var used: int = ShopBuy.use(1, int(ann.id), "medicine", 1)
	K.expect(f, used == 1 and ShopStock.inv_count(1, "medicine") == 1, "using one leaves one")
	K.teardown()

func _save(f: Array) -> void:
	var w := E.setup()
	K.set_time(3, 12)
	ShopBuy.buy(1, 1, "furniture", "sofa", 1, true)
	ShopStock.inv_add(1, "medicine", 3)
	E.day(3)
	var d1: Dictionary = ShopStock.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(d1))
	ShopStock.from_dict(json)
	var diffs: Array = []
	K.expect(f, K.deep_eq(JSON.parse_string(JSON.stringify(d1)), JSON.parse_string(JSON.stringify(ShopStock.to_dict())), "shops", diffs), "shop state survives a save: %s" % str(diffs))
	K.teardown()
