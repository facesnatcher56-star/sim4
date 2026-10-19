extends RefCounted
## Businesses: the player opens, prices, hires, stocks, expands and sells; townie businesses are founded, compete, thrive or go bankrupt.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_opening(f)
	_daily_model(f)
	_staff_and_growth(f)
	_bankruptcy(f)
	_townie_statistics(f)
	_save(f)
	return f

func _opening(f: Array) -> void:
	var w := E.setup(4000)
	K.expect(f, BusinessState.type_ids().size() == 7, "seven kinds of business")
	K.expect(f, not bool(BusinessCmd.open(1, "gym", "cafe", "rent")["ok"]), "a gym cannot trade in the cafe lot")
	var r: Dictionary = BusinessCmd.open(1, "cafe", "cafe", "rent", "Ann's Cafe")
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == 4000 - 1400, "renting a cafe slot costs the fit-out (%s)" % str(r))
	var id: int = int(r["id"])
	K.expect(f, BusinessState.free_slots("cafe") == 2, "a slot is used")
	K.expect(f, not bool(BusinessCmd.open(1, "cafe", "gym", "rent")["ok"]), "no cafe in the gym lot")
	var own: Dictionary = BusinessCmd.open(1, "gym", "gym", "own")
	K.expect(f, not bool(own["ok"]), "not enough coins for an owned gym (%s)" % str(own.get("reason", "")))
	K.expect(f, BusinessCmd.slot_price("gym") > 0 and BusinessCmd.open_cost("gym", "gym", "own") > BusinessCmd.open_cost("gym", "gym", "rent"), "owning the space costs more up front")
	K.teardown()

func _daily_model(f: Array) -> void:
	var w := E.setup(6000)
	var id: int = int(BusinessCmd.open(1, "cafe", "cafe", "rent")["id"])
	var b: Dictionary = BusinessState.get_biz(id)
	var bal0: int = Economy.balance(1)
	var res: Dictionary = BusinessSim.run_day(b)
	K.expect(f, int(res["customers"]) > 5 and float(res["revenue"]) > 80.0, "a fresh cafe has customers (%d, %.0f coins)" % [int(res["customers"]), float(res["revenue"])])
	var d0: float = BusinessSim.demand(b)
	BusinessCmd.set_price(1, id, 1.5)
	K.expect(f, BusinessSim.demand(b) < d0 * 0.7, "higher prices cost customers")
	BusinessCmd.set_price(1, id, 1.0)
	b["rep"] = 90.0
	K.expect(f, BusinessSim.demand(b) > d0 * 1.3, "reputation brings customers")
	b["rep"] = 50.0
	BusinessCmd.set_hours(1, id, 0, 24)
	K.expect(f, BusinessSim.demand(b) < d0 * 2.0, "opening at night adds only a little")
	BusinessCmd.set_hours(1, id, 7, 18)
	var other: Dictionary = BusinessState.make("cafe", "cafe", "rent", "townie", 1000, "Rival Cafe")
	K.expect(f, BusinessSim.demand(b) < d0 * 0.9, "a rival in the same lot shares the customers")
	BusinessState.close(other, "test")
	K.expect(f, not bool(BusinessCmd.set_hours(1, id, 10, 11)["ok"]), "hours must be at least three")
	BusinessCmd.set_open(1, id, false)
	var closed: Dictionary = BusinessSim.run_day(b)
	K.expect(f, int(closed["customers"]) == 0 and float(closed["profit"]) < 0.0, "a closed shop earns nothing and still pays rent")
	BusinessCmd.set_open(1, id, true)
	# reviews
	for i in 12:
		BusinessSim.run_day(b)
	K.expect(f, (b["reviews"] as Array).size() > 0 and (b["reviews"] as Array).size() <= 8, "customers leave reviews (%d)" % (b["reviews"] as Array).size())
	K.expect(f, float(b["stars"]) >= 1.0 and float(b["stars"]) <= 5.0, "a star rating")
	# profits reach the household through the ledger
	b["cash"] = 0.0
	var before: int = Economy.balance(1)
	E.day(2)
	var last: Dictionary = b["last"]
	K.expect(f, (float(last["profit"]) > 0.0 and Economy.balance(1) > before) or float(last["profit"]) <= 0.0, "profit is swept into the household funds")
	K.teardown()

func _staff_and_growth(f: Array) -> void:
	var w := E.setup(9000)
	var id: int = int(BusinessCmd.open(1, "cafe", "cafe", "rent")["id"])
	var b: Dictionary = BusinessState.get_biz(id)
	var cands: Array = BusinessCmd.candidates()
	K.expect(f, cands.size() > 0, "unemployed townies look for work")
	var c: Dictionary = {}
	for x in cands:
		c = x
		break
	var cap0: float = BusinessSim.capacity(b)
	var hr: Dictionary = BusinessCmd.hire(1, id, int(c["tid"]))
	K.expect(f, bool(hr["ok"]) and (b["staff"] as Array).size() == 1, "hired a townie (%s)" % str(hr))
	K.expect(f, BusinessSim.capacity(b) > cap0 * 1.8, "staff add capacity")
	K.expect(f, Story.townies[int(c["tid"])].has("job_biz"), "the townie now has a job")
	var coins0: int = int(Story.townies[int(c["tid"])]["coins"])
	E.day(2)
	K.expect(f, int(Story.townies[int(c["tid"])]["coins"]) > coins0, "and is paid")
	K.expect(f, BusinessCmd.hire(1, id, int(c["tid"]))["ok"] == false, "cannot hire the same person twice")
	K.expect(f, bool(BusinessCmd.fire(1, id, int(c["tid"]))["ok"]) and not Story.townies[int(c["tid"])].has("job_biz"), "firing frees them")
	# expansion needs reputation
	K.expect(f, not bool(BusinessCmd.expand(1, id)["ok"]), "no expansion while the reputation is low")
	b["rep"] = 70.0
	var bal: int = Economy.balance(1)
	var ex: Dictionary = BusinessCmd.expand(1, id)
	K.expect(f, bool(ex["ok"]) and int(b["level"]) == 2 and Economy.balance(1) < bal, "a good name pays for a bigger shop")
	# stock
	BusinessCmd.set_auto_stock(1, id, false)
	b["stock"] = 5
	var res: Dictionary = BusinessSim.run_day(b)
	K.expect(f, int(res["customers"]) <= 5 and int(b["stock"]) == 0, "without stock there are no sales (%d customers)" % int(res["customers"]))
	var rs: Dictionary = BusinessCmd.restock(1, id, 50)
	K.expect(f, bool(rs["ok"]) and int(b["stock"]) == 50, "restocking buys shelves full")
	var sold: Dictionary = BusinessCmd.sell(1, id)
	K.expect(f, bool(sold["ok"]) and int(sold["value"]) > 300 and BusinessState.get_biz(id).is_empty(), "selling the business pays out")
	K.teardown()

func _bankruptcy(f: Array) -> void:
	var w := E.setup(300)
	WorldIface.coins[1] = 1600
	var id: int = int(BusinessCmd.open(1, "cafe", "cafe", "rent")["id"])
	var b: Dictionary = BusinessState.get_biz(id)
	b["price"] = 1.5
	b["rep"] = 5.0
	BusinessCmd.set_hours(1, id, 0, 6)       # opens in the dead of night: no customers
	BusinessCmd.set_auto_stock(1, id, true)
	WorldIface.coins[1] = 0
	for d in range(2, 30):
		E.day(d)
		if BusinessState.get_biz(id).is_empty():
			break
	K.expect(f, BusinessState.get_biz(id).is_empty(), "a business that loses money with no funds goes bankrupt")
	K.expect(f, K.count_events("business_bankrupt") == 1 and K.has_note("bankrupt"), "the player is told")
	K.teardown()

func _townie_statistics(f: Array) -> void:
	var w := E.setup()
	for t in Story.alive_townies():
		t["coins"] = 900
	BusinessDay.rng.seed = 11
	var founded: int = 0
	var peak: int = 0
	for d in range(2, 120):
		E.day(d)
		peak = maxi(peak, BusinessState.list.size())
	for entry in ChronicleHook.recent:
		if str(entry["kind"]) == "business":
			founded += 1
	K.expect(f, peak >= 2, "townies open businesses (peak %d)" % peak)
	K.expect(f, founded >= 2, "the chronicle hears about them")
	K.expect(f, BusinessState.closed_log.size() + BusinessState.list.size() >= 2, "some thrive or fail")
	var comp: int = 0
	for id in BusinessState.list:
		if BusinessSim.competitors(BusinessState.list[id]) > 0.0:
			comp += 1
	K.expect(f, BusinessState.list.size() <= 10, "never more businesses than slots")
	K.teardown()
	# a recession kills weak businesses, a boom does not
	var fails: Array = []
	for phase in ["recession", "boom"]:
		var w2 := E.setup()
		for t in Story.alive_townies():
			t["coins"] = 400
		MarketEconomy.phase = phase
		MarketEconomy.phase_left = 400
		for i in 4:
			var b: Dictionary = BusinessState.make(BusinessState.type_ids()[i], str(BusinessState.type_def(BusinessState.type_ids()[i])["lots"][0]), "rent", "townie", 1000 + i, "Test %d" % i)
			b["cash"] = 200.0
			var t2: Dictionary = Story.townies.get(1000 + i, {})
			if not t2.is_empty():
				t2["owner_biz"] = true
		BusinessDay.rng.seed = 5
		var total: float = 0.0
		for d2 in range(2, 80):
			E.day(d2)
		for id2 in BusinessState.list:
			total += float(BusinessState.list[id2]["profit_total"])
		fails.append(total)
		K.teardown()
	K.expect(f, float(fails[1]) > float(fails[0]), "businesses make more in a boom than a recession (%.0f vs %.0f)" % [float(fails[1]), float(fails[0])])

func _save(f: Array) -> void:
	var w := E.setup(4000)
	var id: int = int(BusinessCmd.open(1, "bakery", "market", "own")["id"])
	BusinessCmd.hire(1, id, int(BusinessCmd.candidates()[0]["tid"]))
	E.days(2, 12)
	var d1: Dictionary = BusinessState.to_dict()
	var j1: Variant = JSON.parse_string(JSON.stringify(d1))
	BusinessState.from_dict(j1)
	var diffs: Array = []
	K.expect(f, K.deep_eq(JSON.parse_string(JSON.stringify(d1)), JSON.parse_string(JSON.stringify(BusinessState.to_dict())), "biz", diffs), "business state survives a save: %s" % str(diffs))
	K.expect(f, BusinessState.get_biz(id).get("name", "") != "" and typeof(BusinessState.get_biz(id)["id"]) == TYPE_INT, "ids come back as ints")
	K.teardown()
