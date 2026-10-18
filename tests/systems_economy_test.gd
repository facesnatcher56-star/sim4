extends RefCounted
## Economy: funds, spend, bills / late fees / repossession, buy & sell with depreciation, grocery restock.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_funds(f)
	_buy_sell(f)
	_bills_paid(f)
	_bills_unpaid(f)
	_groceries(f)
	_roundtrip(f)
	return f

func _funds(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	WorldIface.coins[1] = 0
	Economy.deposit(1, 100, "gift")
	K.expect(f, Economy.balance(1) == 100, "deposit should give 100 coins")
	K.expect(f, Economy.spend(1, 40, "snack"), "spend 40 should succeed")
	K.expect(f, not Economy.spend(1, 500, "yacht"), "spend 500 with 60 must fail")
	K.expect(f, Economy.balance(1) == 60, "balance should be 60, got %d" % Economy.balance(1))
	K.expect(f, Cond.check([{"coins_at_least": 60}], {"folk": a}), "Cond coins_at_least must see Economy funds")
	K.expect(f, not Cond.check([{"coins_at_least": 61}], {"folk": a}), "Cond coins_at_least 61 must fail")
	Loot.apply([{"coins_add": 25}], {"folk": a})
	K.expect(f, Economy.balance(1) == 85, "Loot coins_add must change Economy balance")
	K.expect(f, Economy.ledger_for(1).size() >= 2, "ledger should record transactions")
	K.expect(f, not Economy.spend(1, -5, "neg"), "negative spend must be refused")
	K.teardown()

func _buy_sell(f: Array) -> void:
	var w := K.setup()
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = 1000
	var id: int = Economy.buy_object(1, "sofa", Vector2i(5, 5))
	K.expect(f, id > 0, "buy_object should place a sofa")
	K.expect(f, Economy.balance(1) == 1000 - 650, "sofa costs 650, balance %d" % Economy.balance(1))
	K.expect(f, Economy.buy_object(1, "tv", Vector2i(7, 5)) < 0, "cannot afford a tv with 350 coins")
	K.expect(f, Economy.sell_ratio(0) > 0.79 and Economy.sell_ratio(0) <= 0.8, "new items sell for 80 percent")
	K.expect(f, absf(Economy.sell_ratio(30) - 0.5) < 0.001, "30-day-old items sell for 50 percent")
	K.expect(f, Economy.value_of(id) == 520, "fresh sofa value 520, got %d" % Economy.value_of(id))
	K.set_time(21, 8)   # 20 days later
	var v: int = Economy.value_of(id)
	K.expect(f, v < 520 and v > 325, "20-day-old sofa value should be between 325 and 520, got %d" % v)
	var before: int = Economy.balance(1)
	var got: int = Economy.sell_object(1, id)
	K.expect(f, got == v and Economy.balance(1) == before + v, "sell should pay value_of")
	K.expect(f, w.get_object(id) == null, "sold object must be removed from the world")
	K.expect(f, Economy.sell_object(1, 9999) == 0, "selling a missing object returns 0")
	K.teardown()

func _bills_paid(f: Array) -> void:
	var w := K.setup()
	K.make_folk(w, "Ann")
	Kit_furnish(w)
	WorldIface.coins[1] = 3000
	K.set_time(7, 8)
	Economy.note_usage(1, "take_shower")
	Economy.on_day(7)
	var out: Array = Economy.outstanding(1)
	K.expect(f, out.size() == 1, "a bill should be issued on day 7")
	if out.size() == 1:
		var amt: int = int(out[0]["amount"])
		K.expect(f, amt > 50, "bill must exceed the base fee (lot value + utilities), got %d" % amt)
		K.expect(f, int(out[0]["due"]) == 10, "bill due 3 days after issue")
		K.set_time(10, 8)
		Economy.on_day(10)
		K.expect(f, Economy.outstanding(1).is_empty(), "funded household auto-pays on the due date")
		K.expect(f, Economy.balance(1) == 3000 - amt, "balance should drop by the bill")
	K.expect(f, K.has_note("bills"), "a bill notification must be sent")
	K.expect(f, Economy.next_bill_day == 14, "next bill cycle is day 14")
	K.teardown()

func Kit_furnish(w: StubWorld) -> void:
	var kit = load("res://tests/sim_testkit.gd")
	kit.furnish(w)

func _bills_unpaid(f: Array) -> void:
	var w := K.setup()
	K.make_folk(w, "Ann")
	Kit_furnish(w)
	WorldIface.coins[1] = 0
	var start_objects: int = w.objects.size()
	for d in range(1, 31):
		K.set_time(d, 8)
		Economy.on_day(d)
	K.expect(f, int(Economy.missed.get(1, 0)) >= 3, "three late bills expected, got %s" % str(Economy.missed.get(1, 0)))
	K.expect(f, Economy.repossessed.size() >= 1, "unpaid for 3 cycles must repossess an object")
	K.expect(f, w.objects.size() < start_objects, "repossession removes an object from the world")
	if not Economy.repossessed.is_empty():
		K.expect(f, str(Economy.repossessed[0]["def_id"]) == "computer", "the most valuable object (computer 900) goes first, got %s" % str(Economy.repossessed[0]["def_id"]))
	var late_fee_seen: bool = false
	for bl in Economy.bills:
		if int(bl["fee"]) > 0:
			late_fee_seen = true
	K.expect(f, late_fee_seen, "late fee must be applied")
	K.expect(f, K.has_note("overdue"), "overdue notification expected")
	K.expect(f, K.has_note("Repossessed"), "repossession notification expected")
	# paying later clears everything
	WorldIface.coins[1] = 5000
	var paid: int = Economy.pay_bill(1)
	K.expect(f, paid > 0 and Economy.outstanding(1).is_empty() and int(Economy.missed.get(1, 0)) == 0, "pay_bill clears outstanding bills and the missed counter")
	K.teardown()

func _groceries(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var fridge = w.add_object("fridge", Vector2i(10, 10))
	fridge.state["stock"] = 0
	WorldIface.coins[1] = 25
	var units: int = Economy.restock_fridge(1, fridge.id)
	K.expect(f, units == 4 and fridge.state["stock"] == 4, "25 coins buy 4 units at 6 each, got %d" % units)
	WorldIface.coins[1] = 500
	units = Economy.restock_fridge(1, fridge.id)
	K.expect(f, units == 6 and fridge.state["stock"] == 10 and Economy.balance(1) == 500 - 36, "restock fills to max")
	K.expect(f, Economy.restock_fridge(1, fridge.id) == 0, "full fridge buys nothing")
	# the pie-menu action: order_groceries -> game_event -> Economy
	fridge.state["stock"] = 1
	a.tile = Vector2i(10, 11)
	var dir = K.director()
	var ir := Interaction.create("order_groceries", a, fridge.id, true)
	K.expect(f, ir != null and ir.can_run(a), "order_groceries is available with low stock and enough coins")
	a.enqueue(ir)
	K.run(dir, 12)
	K.expect(f, fridge.state["stock"] >= 9, "ordering groceries via the interaction refills the fridge, stock=%s" % str(fridge.state["stock"]))
	K.expect(f, (SimEnv.data().object_def("fridge")["interactions"] as Array).has("order_groceries"), "fridge advertises order_groceries")
	K.teardown()

func _roundtrip(f: Array) -> void:
	var w := K.setup()
	K.make_folk(w, "Ann")
	Kit_furnish(w)
	WorldIface.coins[1] = 100
	for d in range(1, 12):
		K.set_time(d, 8)
		Economy.on_day(d)
	var d1: Dictionary = Economy.to_dict()
	var text: String = JSON.stringify(d1)
	var parsed: Variant = JSON.parse_string(text)
	Economy.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1, Economy.to_dict(), "economy", diffs), "economy save roundtrip differs: %s" % str(diffs.slice(0, 5)))
	K.teardown()
