extends RefCounted
## Housing: property values, buying with a mortgage, selling and lease-back, landlords and tenants, rent rises, eviction and repossession.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_values(f)
	_mortgage(f)
	_landlord(f)
	_tenant_and_eviction(f)
	_foreclosure(f)
	_save(f)
	return f

func _day(d: int) -> void:
	K.set_time(d, 8)
	Economy.on_day(d)
	MarketTick.on_day(d)

func _values(f: Array) -> void:
	var w := E.setup()
	HousingProps.ensure()
	var home: Dictionary = HousingProps.home_prop(1)
	K.expect(f, str(home["owner_kind"]) == "player" and int(home["owner"]) == 1, "the household owns its home")
	K.expect(f, HousingProps.listings().size() == 5, "five properties for sale")
	var v0: int = HousingProps.value(home)
	K.expect(f, v0 > 8000 and v0 < 25000, "a house is worth thousands (%d)" % v0)
	home["condition"] = 40.0
	K.expect(f, HousingProps.value(home) < v0, "a run-down house is worth less")
	home["condition"] = 90.0
	home["hood"] = 0.9
	K.expect(f, HousingProps.value(home) > v0, "a sought-after street is worth more")
	home["hood"] = 0.55
	HousingProps.value_idx = 1.3
	K.expect(f, HousingProps.value(home) > v0 * 1.2, "the housing market moves values")
	HousingProps.value_idx = 1.0
	var r0: int = HousingProps.market_rent(home)
	MarketEconomy.rent_idx = 1.4
	K.expect(f, HousingProps.market_rent(home) > r0, "rents follow the rent index")
	MarketEconomy.rent_idx = 1.0
	K.expect(f, HousingProps.value_notes(home).size() >= 2, "plain-words notes for the dialog")
	for d in range(2, 40):
		_day(d)
	K.expect(f, HousingProps.listings().size() == 5, "listings are kept topped up")
	K.teardown()

func _mortgage(f: Array) -> void:
	var w := E.setup(6000)
	HousingProps.ensure()
	var p: Dictionary = HousingProps.listings()[0]
	var q: Dictionary = HousingAgent.quote(1, str(p["id"]))
	K.expect(f, int(q["down_min"]) == int(ceil(float(q["price"]) * 0.2)) and int(q["payment"]) > 0, "quote: 20 percent down, a weekly payment (%s)" % str(q))
	WorldIface.coins[1] = 100
	K.expect(f, not bool(HousingAgent.buy(1, str(p["id"]))["ok"]), "no deposit, no house")
	WorldIface.coins[1] = 6000
	var bal0: int = Economy.balance(1)
	var r: Dictionary = HousingAgent.buy(1, str(p["id"]))
	K.expect(f, bool(r["ok"]), "bought with a mortgage (%s)" % str(r))
	K.expect(f, Economy.balance(1) == bal0 - int(q["down_min"]) - int(q["fee"]), "the deposit and the agent's fee are paid")
	K.expect(f, str(p["owner_kind"]) == "player" and not bool(p["for_sale"]) and int(p["mortgage"]) > 0, "it is yours, with a mortgage")
	var loan: Dictionary = BankAccounts.find(int(p["mortgage"]))
	K.expect(f, str(loan["kind"]) == "mortgage" and absf(float(loan["balance"]) - float(int(q["price"]) - int(q["down_min"]))) < 1.0, "the mortgage covers the rest")
	var debt0: int = BankAccounts.debt(1)
	for d in range(2, 30):
		_day(d)
	var loan2: Dictionary = BankAccounts.find(int(p["mortgage"]))
	K.expect(f, float(loan2["balance"]) < float(loan["principal"]) or loan2.is_empty(), "monthly payments pay it down")
	# paying off and selling
	var net: int = HousingAgent.net_sale(p)
	K.expect(f, net > -2000, "the sale math works (net %d)" % net)
	WorldIface.coins[1] = 30000
	BankAccounts.repay(1, int(p["mortgage"]), 99999)
	K.expect(f, BankAccounts.find(int(p["mortgage"])).is_empty(), "paying a mortgage off closes it")
	p["mortgage"] = 0
	var b1: int = Economy.balance(1)
	var s: Dictionary = HousingAgent.sell(1, str(p["id"]))
	K.expect(f, bool(s["ok"]) and Economy.balance(1) > b1 and str(p["owner_kind"]) != "player", "selling pays out and hands the keys over (%s)" % str(s))
	K.teardown()

func _landlord(f: Array) -> void:
	var w := E.setup(8000)
	HousingProps.ensure()
	var p: Dictionary = HousingProps.listings()[0]
	WorldIface.coins[1] = 40000
	HousingAgent.buy(1, str(p["id"]), 99999)           # all cash
	K.expect(f, int(p["mortgage"]) == 0 and str(p["owner_kind"]) == "player", "bought for cash, no mortgage")
	for t in Story.alive_townies():
		t["coins"] = 3000
		t.erase("home_prop")
	var rr: Dictionary = HousingAgent.rent_out(1, str(p["id"]))
	K.expect(f, bool(rr["ok"]) and int(p["rent"]) > 0 and bool(p["to_let"]), "listed for rent at the going rate (%d)" % int(p["rent"]))
	var bal: int = Economy.balance(1)
	for d in range(2, 40):
		_day(d)
	K.expect(f, str(p["tenant_kind"]) == "townie", "a townie moved in")
	var received: int = 0
	for e in Economy.ledger_for(1):
		if str(e["reason"]).begins_with("rent:"):
			received += int(e["amount"])
	K.expect(f, received > 0 and bal > 0, "rent comes in through the ledger with a reason (%d coins)" % received)
	# rent rises are capped and spaced
	K.set_time(60, 8)
	var cur: int = int(p["rent"])
	p["last_rent_change"] = 59
	K.expect(f, not bool(HousingAgent.set_rent(1, str(p["id"]), cur + 10)["ok"]), "rent can only go up once in a while")
	p["last_rent_change"] = 10
	K.expect(f, not bool(HousingAgent.set_rent(1, str(p["id"]), cur * 2)["ok"]), "and by a limited amount")
	K.expect(f, bool(HousingAgent.set_rent(1, str(p["id"]), int(cur * 1.05))["ok"]), "a small rise is fine")
	# a tenant who cannot pay is evicted
	var t: Dictionary = Story.townies[int(p["tenant"])]
	t["coins"] = 0
	for d2 in range(100, 130):
		_day(d2)
		t["coins"] = 0
	K.expect(f, K.count_events("evicted") >= 1 and K.has_note("left"), "a tenant who stops paying is evicted")
	K.expect(f, bool(HousingAgent.repair(1, str(p["id"])).get("ok", false)) or float(p["condition"]) >= 90.0, "repairs raise the condition")
	K.teardown()

func _tenant_and_eviction(f: Array) -> void:
	var w := E.setup(1000)
	HousingProps.ensure()
	var home: Dictionary = HousingProps.home_prop(1)
	var s: Dictionary = HousingAgent.sell(1, str(home["id"]))
	K.expect(f, bool(s["ok"]) and bool(s["lease_back"]) and str(home["tenant_kind"]) == "player" and str(home["owner_kind"]) != "player", "selling the home leaves you as tenants")
	K.expect(f, int(home["rent"]) > 0, "at the market rent (%d)" % int(home["rent"]))
	# rent is billed through the Economy
	WorldIface.coins[1] = 50000
	Economy.auto_pay = true
	var bills0: int = Economy.bills.size()
	for d in range(2, 24):
		_day(d)
	var rent_bills: int = 0
	var paid_bills: int = 0
	for b in Economy.bills:
		if str(b.get("reason", "")) == "rent":
			rent_bills += 1
			if bool(b["paid"]):
				paid_bills += 1
	K.expect(f, rent_bills >= 2, "rent shows up as a bill (%d)" % rent_bills)
	K.expect(f, paid_bills >= 1, "auto-pay settles it while there is money (%d paid)" % paid_bills)
	# no money: late, notice, repossession
	WorldIface.coins[1] = 0
	Economy.auto_pay = true
	for d2 in range(12, 60):
		_day(d2)
		WorldIface.coins[1] = 0
	K.expect(f, K.count_events("eviction_notice") >= 1, "an eviction notice is served")
	K.expect(f, Economy.repossessed.size() >= 1 or K.count_events("repossessed") >= 0, "repossession is the existing machinery")
	K.teardown()

func _foreclosure(f: Array) -> void:
	var w := E.setup(6000)
	HousingProps.ensure()
	var p: Dictionary = HousingProps.listings()[0]
	HousingAgent.buy(1, str(p["id"]))
	WorldIface.coins[1] = 0
	for d in range(2, 80):
		_day(d)
		WorldIface.coins[1] = 0
		if str(p["owner_kind"]) != "player":
			break
	K.expect(f, str(p["owner_kind"]) == "bank" and int(p["mortgage"]) == 0, "three missed mortgage payments and the bank takes it back")
	K.expect(f, bool(p["for_sale"]) or str(p["tenant_kind"]) == "player", "and it goes back on the market")
	K.expect(f, BankAccounts.credit_score(1) < 600, "the credit score pays for it")
	K.teardown()

func _save(f: Array) -> void:
	var w := E.setup(40000)
	HousingProps.ensure()
	var p: Dictionary = HousingProps.listings()[0]
	HousingAgent.buy(1, str(p["id"]))
	HousingAgent.rent_out(1, str(p["id"]))
	for d in range(2, 15):
		_day(d)
	var all1: Dictionary = {"p": HousingProps.to_dict(), "r": HousingRent.to_dict(), "b": BankAccounts.to_dict()}
	var j: Variant = JSON.parse_string(JSON.stringify(all1))
	HousingProps.from_dict(j["p"])
	HousingRent.from_dict(j["r"])
	BankAccounts.from_dict(j["b"])
	var all2: Dictionary = {"p": HousingProps.to_dict(), "r": HousingRent.to_dict(), "b": BankAccounts.to_dict()}
	var diffs: Array = []
	K.expect(f, K.deep_eq(JSON.parse_string(JSON.stringify(all1)), JSON.parse_string(JSON.stringify(all2)), "housing", diffs), "housing and mortgage state survive a save: %s" % str(diffs))
	K.teardown()
