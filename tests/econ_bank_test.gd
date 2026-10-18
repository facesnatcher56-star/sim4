extends RefCounted
## Bank: savings interest, loans and the credit score from bill history, insurance payouts, wills, the lottery and addiction.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_savings(f)
	_loans(f)
	_credit(f)
	_insurance(f)
	_will(f)
	_lottery(f)
	_cards_and_addiction(f)
	return f

func _savings(f: Array) -> void:
	var w := E.setup(1000)
	K.expect(f, BankAccounts.deposit(1, 400) and Economy.balance(1) == 600 and BankAccounts.balance(1) == 400, "deposit moves coins into savings")
	K.expect(f, not BankAccounts.deposit(1, 5000), "cannot deposit what you do not have")
	for d in range(2, 30):
		E.day(d)
	K.expect(f, BankAccounts.balance(1) > 400, "savings earn interest (%d)" % BankAccounts.balance(1))
	var bal: int = BankAccounts.balance(1)
	var before: int = Economy.balance(1)
	K.expect(f, BankAccounts.withdraw(1, bal) and Economy.balance(1) == before + bal, "withdraw gives it back")
	K.expect(f, not BankAccounts.withdraw(1, 10), "nothing left to withdraw")
	K.teardown()

func _loans(f: Array) -> void:
	var w := E.setup(500)
	var lim: int = BankAccounts.loan_limit(1)
	K.expect(f, lim > 1000, "a new household can borrow a little (%d)" % lim)
	K.expect(f, not bool(BankAccounts.take_loan(1, lim + 500)["ok"]), "cannot borrow more than the limit")
	var r: Dictionary = BankAccounts.take_loan(1, 1000)
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == 1500, "the loan is paid out")
	var l: Dictionary = r["loan"]
	K.expect(f, int(l["payment"]) > 50 and int(l["payment"]) < 150, "weekly payment is reasonable (%d)" % int(l["payment"]))
	var score0: int = BankAccounts.credit_score(1)
	WorldIface.coins[1] = 3000
	for d in range(2, 30):
		E.day(d)
	K.expect(f, BankAccounts.loans_of(1).size() == 0 or float(BankAccounts.loans_of(1)[0]["balance"]) < 1000.0, "payments reduce the loan")
	WorldIface.coins[1] = 0
	BankAccounts.open_loan(1, 400, 10, 0.1, "loan", "")
	for d2 in range(30, 60):
		E.day(d2)
	K.expect(f, int(BankAccounts.record.get(1, {}).get("late_loan", 0)) >= 1, "missed payments are recorded")
	K.expect(f, BankAccounts.credit_score(1) < score0, "and lower the credit score (%d -> %d)" % [score0, BankAccounts.credit_score(1)])
	K.teardown()

func _credit(f: Array) -> void:
	var w := E.setup(5000)
	var s0: int = BankAccounts.credit_score(1)
	for i in 6:
		Economy.bills.append({"id": i + 1, "hid": 1, "amount": 100, "base": 100, "issued": 1, "due": 4, "paid": true, "late": false, "fee": 0})
	K.expect(f, BankAccounts.credit_score(1) > s0, "bills paid on time build the score (%d -> %d)" % [s0, BankAccounts.credit_score(1)])
	var s1: int = BankAccounts.credit_score(1)
	for i in 3:
		Economy.bills.append({"id": 20 + i, "hid": 1, "amount": 100, "base": 100, "issued": 1, "due": 4, "paid": false, "late": true, "fee": 10})
	K.expect(f, BankAccounts.credit_score(1) < s1 - 50, "late bills hurt it a lot")
	K.expect(f, BankAccounts.score_label(780) == "Excellent" and BankAccounts.score_label(500) == "Poor", "score labels")
	K.teardown()

func _insurance(f: Array) -> void:
	var w := E.setup(5000)
	Incidents.insurance_fn = Callable()
	MarketTick.install()
	K.expect(f, Incidents.insurance_cover(200, 1, "health") == 0, "no cover without a policy")
	BankInsurance.buy(1, "health")
	K.expect(f, Incidents.insurance_cover(200, 1, "health") == 160, "health insurance pays 80 percent of medical bills")
	K.expect(f, Incidents.insurance_cover(200, 1) == 0, "but not property losses")
	DisasterInsurance.set_level(1, "full")
	K.expect(f, Incidents.insurance_cover(1000, 1) > 0, "home cover still pays for the house")
	var b0: int = Economy.compute_bill(1)
	K.expect(f, BankInsurance.bill_extra(1) > 0, "premiums join the weekly bill")
	BankInsurance.cancel(1, "health")
	K.expect(f, Economy.compute_bill(1) < b0, "cancelling lowers the bill")
	BankInsurance.buy(1, "car")
	var bal: int = Economy.balance(1)
	BankInsurance.on_chronicle({"kind": "traffic_hit", "lot": "home:1", "subjects": [1]})
	K.expect(f, Economy.balance(1) == bal + 350, "car insurance pays after a traffic accident")
	K.expect(f, BankInsurance.paid_out.size() == 1, "payouts are remembered")
	K.teardown()

func _will(f: Array) -> void:
	var w := E.setup(2000)
	var ann: Folk = SysUtil.folk(1)
	var bea: Folk = K.make_folk(w, "Bea", [], 2, Vector2i(14, 14))
	WorldIface.coins[2] = 100
	K.expect(f, BankWill.write(int(ann.id), int(bea.id)) and BankWill.heir_of(int(ann.id)) == int(bea.id), "a will names an heir")
	BankAccounts.deposit(1, 500)
	var res: Dictionary = BankWill.apply(ann, [])
	K.expect(f, int(res.get("heir", -1)) == int(bea.id) and int(res.get("to", -1)) == 2, "apply() sends the estate to the heir household: %s" % str(res))
	K.expect(f, Economy.balance(2) == 100 + 2000 and BankAccounts.balance(1) == 0, "coins and savings moved (%d)" % Economy.balance(2))
	K.expect(f, not BankWill.has_will(int(ann.id)), "the will is spent")
	K.expect(f, BankWill.apply(bea, []).is_empty(), "no will, the old inheritance rules decide")
	K.teardown()
	# the real thing through Aging.kill: debts are paid out of the estate first
	var w2 := E.setup(2000)
	var a2: Folk = SysUtil.folk(1)
	var c2: Folk = K.make_folk(w2, "Cleo", [], 3, Vector2i(16, 16))
	WorldIface.coins[3] = 0
	BankAccounts.open_loan(1, 600, 10, 0.1, "loan", "")
	BankWill.write(int(a2.id), int(c2.id))
	Aging.kill(int(a2.id), "old age")
	K.expect(f, Economy.balance(3) > 1000 and Economy.balance(3) <= 1500, "the heir gets the estate after the debt (%d)" % Economy.balance(3))
	K.teardown()

func _lottery(f: Array) -> void:
	var w := E.setup(5000)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var counts: Dictionary = {}
	var n: int = 40000
	for _i in n:
		var id: String = BankGamble.roll_ticket(r)
		counts[id] = int(counts.get(id, 0)) + 1
	var small: float = float(counts.get("small", 0)) / float(n)
	var med: float = float(counts.get("medium", 0)) / float(n)
	K.expect(f, small > 0.10 and small < 0.14, "small prizes land about 12 percent (%.3f)" % small)
	K.expect(f, med > 0.007 and med < 0.018, "medium prizes about 1.2 percent (%.4f)" % med)
	K.expect(f, int(counts.get("jackpot", 0)) < 60, "the jackpot is rare (%d in %d)" % [int(counts.get("jackpot", 0)), n])
	K.set_time(3, 12)
	K.expect(f, bool(ShopBuy.buy(1, 1, "market", "lottery_ticket", 4)["ok"]) and BankGamble.tickets_of(1) == 4, "tickets are sold at the market")
	var bal: int = Economy.balance(1)
	BankGamble.rng.seed = 7
	BankGamble.draw(3)
	K.expect(f, BankGamble.tickets_of(1) == 0 and int(BankGamble.last_draw.get("day", 0)) == 3, "a draw settles and clears the tickets")
	K.expect(f, Economy.balance(1) >= bal, "prizes only add")
	K.teardown()

func _cards_and_addiction(f: Array) -> void:
	var w := E.setup(5000)
	var wins: int = 0
	var rounds: int = 400
	for _i in rounds:
		WorldIface.coins[1] = 100
		var r: Dictionary = BankGamble.play_cards(1, 1, 10)
		if bool(r["won"]):
			wins += 1
	var p: float = float(wins) / float(rounds)
	K.expect(f, p > 0.40 and p < 0.54, "cards pay a little worse than even odds (%.2f)" % p)
	K.expect(f, BankGamble.is_hooked(1), "playing a lot gets you hooked (%.1f)" % BankGamble.level_of(1))
	K.expect(f, K.count_events("gambling_addiction") == 1, "the addiction event fires once for the Health track")
	WorldIface.coins[1] = 500
	BankGamble.rng.seed = 3
	var tix: int = 0
	for d in range(2, 12):
		E.day(d)
		tix += BankGamble.tickets_of(1)
	K.expect(f, tix > 0, "a hooked person buys tickets without being asked")
	K.teardown()
