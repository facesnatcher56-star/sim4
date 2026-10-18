extends RefCounted
## Economy slice 1: prosperity drives prices, rents, wages and unemployment; booms and recessions come and go; the chronicle hears of it.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_off_by_default(f)
	_recession_and_boom(f)
	_unemployment(f)
	_stats(f)
	_determinism(f)
	return f

func _off_by_default(f: Array) -> void:
	var w := K.setup()
	K.expect(f, not MarketEconomy.enabled and MarketEconomy.price_mult() == 1.0 and MarketEconomy.wage_mult() == 1.0, "economy is off (all multipliers 1.0) until a game starts")
	MarketTick.on_day(5)
	K.expect(f, MarketEconomy.history.is_empty() and MarketEconomy.prosperity == 0.0, "a day tick does nothing while the economy is off")
	K.teardown()

func _recession_and_boom(f: Array) -> void:
	var w := E.setup()
	MarketEconomy.phase = "recession"
	MarketEconomy.phase_left = 45
	E.days(2, 40)
	var p_low: float = MarketEconomy.prosperity
	var price_rel_low: float = MarketEconomy.price_idx / MarketEconomy.base_level
	var wage_rel_low: float = MarketEconomy.wage_idx / MarketEconomy.base_level
	K.expect(f, p_low < -0.4, "a recession drags prosperity down (%.2f)" % p_low)
	K.expect(f, price_rel_low < 0.97, "prices sit below trend in a recession (%.3f)" % price_rel_low)
	MarketEconomy.phase = "boom"
	MarketEconomy.phase_left = 60
	E.days(41, 90)
	var p_hi: float = MarketEconomy.prosperity
	K.expect(f, p_hi > 0.4, "a boom lifts prosperity (%.2f)" % p_hi)
	K.expect(f, MarketEconomy.price_idx / MarketEconomy.base_level > price_rel_low + 0.08, "prices recover above trend in a boom")
	K.expect(f, MarketEconomy.wage_idx / MarketEconomy.base_level > wage_rel_low + 0.04, "wages follow prosperity")
	K.expect(f, MarketEconomy.rent_idx > 0.8 and MarketEconomy.base_level > 1.0, "slow inflation raises the general level (%.3f)" % MarketEconomy.base_level)
	K.expect(f, MarketEconomy.history.size() >= 2, "a monthly report is kept")
	var chron: int = 0
	for c in ChronicleHook.recent:
		if str(c["kind"]).begins_with("economy"):
			chron += 1
	K.expect(f, chron >= 2, "the chronicle hears of the economy (%d notes)" % chron)
	K.teardown()

func _unemployment(f: Array) -> void:
	var w := E.setup()
	for t in Story.alive_townies():
		if Story.stage_of(t) == "adult":
			t["career"] = "barista"
	MarketEconomy.phase = "recession"
	MarketEconomy.phase_left = 200
	E.days(2, 70)
	var u_rec: float = MarketEconomy.unemployment
	K.expect(f, u_rec > 0.2, "a long recession lays people off (unemployment %.2f)" % u_rec)
	MarketEconomy.phase = "boom"
	MarketEconomy.phase_left = 200
	E.days(71, 170)
	K.expect(f, MarketEconomy.unemployment < u_rec - 0.1, "a boom hires them again (%.2f -> %.2f)" % [u_rec, MarketEconomy.unemployment])
	K.teardown()

func _stats(f: Array) -> void:
	var w := E.setup()
	E.days(2, 30)
	var s: Dictionary = MarketEconomy.stats()
	for k in ["phase", "prosperity", "price_index", "inflation", "unemployment", "budget"]:
		K.expect(f, s.has(k), "town stats carry %s" % k)
	K.expect(f, MarketEconomy.lines().size() >= 3 and MarketEconomy.headline().find("unemployment") >= 0, "readable stat lines for the paper")
	K.teardown()

func _determinism(f: Array) -> void:
	var states: Array = []
	for _i in 2:
		var w := E.setup()
		E.days(2, 60)
		states.append(JSON.stringify(MarketEconomy.to_dict()))
		K.teardown()
	K.expect(f, states[0] == states[1], "same seed, same economy after 60 days")
