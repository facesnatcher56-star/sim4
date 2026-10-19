class_name BankDialog
extends RefCounted
## The "Bank" tab of BankHub: savings, loans and credit score, insurance (home, health, car, life), your will, and the lottery / cards.

static func build(dlg: BankHub) -> void:
	var h: int = dlg.hid()
	var score: int = BankAccounts.credit_score(h)
	dlg.heading("Your accounts")
	dlg.line("Cash %d coins. Savings %d (earning %.1f%% a year). Debts %d." % [Economy.balance(h), BankAccounts.balance(h), BankAccounts.savings_rate() * 100.0, BankAccounts.debt(h)], 14)
	dlg.row_with("Move money to or from savings.", [
		dlg.button("Save 100", "", func(): dlg.act("bank_deposit", {"amount": 100}), Economy.balance(h) >= 100),
		dlg.button("Save 500", "", func(): dlg.act("bank_deposit", {"amount": 500}), Economy.balance(h) >= 500),
		dlg.button("Take 100", "", func(): dlg.act("bank_withdraw", {"amount": 100}), BankAccounts.balance(h) >= 100),
		dlg.button("Take all", "", func(): dlg.act("bank_withdraw", {"amount": BankAccounts.balance(h)}), BankAccounts.balance(h) > 0)])
	dlg.heading("Loans")
	var hist: Dictionary = BankAccounts.history(h)
	dlg.line("Credit score %d (%s): %d bills paid on time, %d late." % [score, BankAccounts.score_label(score), int(hist["on_time"]), int(hist["late"])], 13)
	for l in BankAccounts.loans_of(h):
		var lid: int = int(l["id"])
		dlg.row_with("%s: %d left, %d coins a week at %.1f%%." % [UIU.sentence(str(l["kind"])), int(l["balance"]), int(l["payment"]), float(l["rate"]) * 100.0],
			[dlg.button("Pay 200", "", func(): dlg.act("loan_repay", {"loan": lid, "amount": 200}), Economy.balance(h) >= 200),
			dlg.button("Pay off", "", func(): dlg.act("loan_repay", {"loan": lid, "amount": int(ceil(float(l["balance"])))}), Economy.balance(h) >= int(ceil(float(l["balance"]))))])
	var lim: int = BankAccounts.loan_limit(h)
	dlg.row_with("The bank would lend you up to %d coins at %.1f%% a year." % [lim, BankAccounts.loan_rate(h) * 100.0], [
		dlg.button("Borrow 500", "", func(): dlg.act("loan_take", {"amount": 500}), lim >= 500),
		dlg.button("Borrow 1000", "", func(): dlg.act("loan_take", {"amount": 1000}), lim >= 1000)])
	dlg.heading("Insurance")
	dlg.row_with(DisasterInsurance.describe(h), [dlg.button("Home cover", "Cycle none, basic and full", func(): dlg.act("home_insurance_cycle"))])
	var defs: Dictionary = BankInsurance.defs()
	for pid in defs:
		var d: Dictionary = defs[pid]
		var on: bool = BankInsurance.has(h, str(pid))
		var what: String = "pays %d%% of medical bills" % int(round(float(d.get("cover", 0.0)) * 100.0)) if d.has("cover") and pid != "car" else ("pays out after a road accident" if pid == "car" else "pays %d if someone dies" % int(d.get("payout", 0)))
		dlg.row_with("%s: %d a week, %s." % [str(d["label"]), BankInsurance.weekly(str(pid)), what], [dlg.button("Cancel" if on else "Buy", "", func(): dlg.act("insurance_toggle", {"policy": str(pid)}))])
	_will(dlg, h)
	_gamble(dlg, h)

static func _will(dlg: BankHub, h: int) -> void:
	dlg.heading("Your will")
	var fid: int = dlg.folk_id
	if BankWill.has_will(fid):
		dlg.line("%s leaves everything to %s." % [SysUtil.folk_name(fid), SysUtil.folk_name(BankWill.heir_of(fid))], 13)
	else:
		dlg.line("No will yet: without one, the closest family inherits. Use a desk or computer to write one, or choose below.", 13, UITheme.MUTED)
	var row := HFlowContainer.new()
	dlg.body.add_child(row)
	for c in BankWill.candidates(fid).slice(0, 6):
		var b := Button.new()
		b.text = str(c["name"])
		b.toggle_mode = true
		b.button_pressed = BankWill.heir_of(fid) == int(c["id"])
		b.pressed.connect(func(): dlg.act("will_write", {"heir": int(c["id"])}))
		row.add_child(b)

static func _gamble(dlg: BankHub, h: int) -> void:
	dlg.heading("Luck")
	dlg.line("Lottery: %d tickets for the next draw (day %d), jackpot %d. Tickets are sold at the market stalls." % [BankGamble.tickets_of(h), BankGamble.next_draw, BankGamble.current_jackpot()], 13)
	var fid: int = dlg.folk_id
	if BankGamble.is_hooked(fid):
		dlg.line("You can't stop thinking about the next bet. Money is slipping away.", 13, Color("#e5534b"))
	var stakes: Array = []
	for s in SysUtil.table("bank").get("gamble", {}).get("cards_stake", [5, 10, 25]):
		stakes.append(dlg.button("Cards %d" % int(s), "A hand of cards: win and get double back", func(): dlg.act("gamble_cards", {"stake": int(s)}), Economy.balance(h) >= int(s)))
	dlg.row_with("A hand of cards for money.", stakes)
