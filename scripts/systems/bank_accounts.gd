class_name BankAccounts
extends RefCounted
## The bank (task 13, slice 5): savings with interest, loans (and mortgages, same book) with a credit score built from the household's bill
## history, and debt. Money moves only through Economy.deposit / spend with reasons.
## Tier: town-wide, DAILY. Active set: households with a savings balance or a loan. Caps: 2 loans per household (+ mortgages), score 300..850.
## Data: data/bank.json.

static var savings: Dictionary = {}     # hid -> float coins in the bank
static var loans: Array = []            # {id, hid, kind loan|mortgage, prop, principal, balance, rate, payment, left, missed, next_due, taken}
static var record: Dictionary = {}      # hid -> {repaid, defaults, late_loan}
static var _seq: int = 1

static func reset() -> void:
	savings.clear()
	loans.clear()
	record.clear()
	_seq = 1

static func cfg() -> Dictionary:
	return SysUtil.table("bank")

static func _pay_days() -> int:
	return maxi(int(cfg().get("pay_days", 7)), 1)

static func _year_days() -> float:
	return maxf(float(MarketEconomy.cfg().get("year_days", 28)), 1.0)

# ------------------------------------------------------------------ savings
static func balance(hid: int) -> int:
	return int(floor(float(savings.get(hid, 0.0))))

static func deposit(hid: int, n: int) -> bool:
	if n <= 0 or not Economy.spend(hid, n, "savings deposit"):
		return false
	savings[hid] = float(savings.get(hid, 0.0)) + float(n)
	return true

static func withdraw(hid: int, n: int) -> bool:
	if n <= 0 or float(savings.get(hid, 0.0)) < float(n):
		return false
	savings[hid] = float(savings[hid]) - float(n)
	Economy.deposit(hid, n, "savings withdrawal")
	return true

static func savings_rate() -> float:
	var s: Dictionary = cfg().get("savings", {})
	var p: float = MarketEconomy.prosperity if MarketEconomy.enabled else 0.0
	return maxf(float(s.get("rate_year", 0.03)) + float(s.get("prosperity_rate", 0.02)) * p, float(s.get("min_rate", 0.005)))

# ------------------------------------------------------------------ credit score
## Counted from the Economy's bill book: paid on time / late (the "bill history"), plus loans repaid and defaulted.
static func history(hid: int) -> Dictionary:
	var on_time: int = 0
	var late: int = 0
	for b in Economy.bills:
		if int(b["hid"]) != hid:
			continue
		if bool(b["late"]):
			late += 1
		elif bool(b["paid"]):
			on_time += 1
	var r: Dictionary = record.get(hid, {})
	return {"on_time": on_time, "late": late, "repaid": int(r.get("repaid", 0)), "defaults": int(r.get("defaults", 0)), "late_loan": int(r.get("late_loan", 0))}

static func credit_score(hid: int) -> int:
	var c: Dictionary = cfg().get("credit", {})
	var h: Dictionary = history(hid)
	var s: float = float(c.get("start", 600))
	s += float(mini(int(h["on_time"]), int(c.get("on_time_cap", 40)))) * float(c.get("on_time", 4))
	s += float(int(h["late"]) + int(h["late_loan"])) * float(c.get("late", -35))
	s += float(h["defaults"]) * float(c.get("default", -90))
	s += float(h["repaid"]) * float(c.get("repaid_loan", 25))
	s += float(debt(hid)) / 1000.0 * float(c.get("debt_penalty_per_1000", -6))
	s += float(balance(hid)) / 1000.0 * float(c.get("savings_bonus_per_1000", 5))
	return clampi(int(round(s)), int(c.get("min", 300)), int(c.get("max", 850)))

static func score_label(score: int) -> String:
	if score >= 740:
		return "Excellent"
	if score >= 670:
		return "Good"
	if score >= 580:
		return "Fair"
	return "Poor"

# ------------------------------------------------------------------ loans
static func loans_of(hid: int, kind: String = "") -> Array:
	var out: Array = []
	for l in loans:
		if int(l["hid"]) == hid and (kind == "" or str(l["kind"]) == kind):
			out.append(l)
	return out

static func debt(hid: int) -> int:
	var total: int = Economy.owed(hid)
	for l in loans_of(hid):
		total += int(ceil(float(l["balance"])))
	return total

static func loan_rate(hid: int) -> float:
	var c: Dictionary = cfg().get("loans", {})
	var score: int = credit_score(hid)
	var p: float = MarketEconomy.prosperity if MarketEconomy.enabled else 0.0
	return float(c.get("base_rate_year", 0.08)) + float(c.get("spread_low_score", 0.1)) * float(850 - score) / 550.0 + 0.02 * p

static func loan_limit(hid: int) -> int:
	var c: Dictionary = cfg().get("loans", {})
	var score: int = credit_score(hid)
	var room: int = maxi(score - int(c.get("limit_floor_score", 450)), 0) * int(c.get("limit_per_point", 12))
	var owing: int = 0
	for l in loans_of(hid, "loan"):
		owing += int(l["balance"])
	return maxi(room - owing, 0)

static func payment_for(amount: float, rate_year: float, n: int) -> int:
	var r: float = rate_year * float(_pay_days()) / _year_days()
	if r <= 0.0001:
		return int(ceil(amount / float(maxi(n, 1))))
	return int(ceil(amount * r / (1.0 - pow(1.0 + r, -float(n)))))

static func why_not_loan(hid: int, amount: int) -> String:
	var c: Dictionary = cfg().get("loans", {})
	if amount < int(c.get("min_amount", 200)):
		return "The smallest loan is %d coins." % int(c.get("min_amount", 200))
	if loans_of(hid, "loan").size() >= int(c.get("max_loans", 2)):
		return "You already have as many loans as the bank allows."
	if amount > loan_limit(hid):
		return "The bank will lend you up to %d coins." % loan_limit(hid)
	return ""

## {ok, reason, loan}
static func take_loan(hid: int, amount: int, term: int = -1) -> Dictionary:
	var why: String = why_not_loan(hid, amount)
	if why != "":
		return {"ok": false, "reason": why, "loan": {}}
	var c: Dictionary = cfg().get("loans", {})
	if term <= 0:
		term = int(c.get("term_payments", 20))
	var l: Dictionary = open_loan(hid, amount, term, loan_rate(hid), "loan", "")
	Economy.deposit(hid, amount, "bank loan")
	return {"ok": true, "reason": "", "loan": l}

## Writes a loan into the book without paying out (mortgages pay the seller themselves).
static func open_loan(hid: int, amount: int, term: int, rate: float, kind: String, prop: String) -> Dictionary:
	var l: Dictionary = {"id": _seq, "hid": hid, "kind": kind, "prop": prop, "principal": amount, "balance": float(amount), "rate": rate,
		"payment": payment_for(float(amount), rate, term), "left": term, "missed": 0, "next_due": SysUtil.day() + _pay_days(), "taken": SysUtil.day()}
	_seq += 1
	loans.append(l)
	return l

static func find(loan_id: int) -> Dictionary:
	for l in loans:
		if int(l["id"]) == loan_id:
			return l
	return {}

## Pay extra (or all) of a loan early. Returns coins paid.
static func repay(hid: int, loan_id: int, amount: int) -> int:
	var l: Dictionary = find(loan_id)
	if l.is_empty() or int(l["hid"]) != hid:
		return 0
	var n: int = mini(amount, int(ceil(float(l["balance"]))))
	if n <= 0 or not Economy.spend(hid, n, "loan repayment"):
		return 0
	l["balance"] = float(l["balance"]) - float(n)
	if float(l["balance"]) <= 0.5:
		_close(l, true)
	return n

static func _close(l: Dictionary, paid_off: bool) -> void:
	loans.erase(l)
	if paid_off:
		var r: Dictionary = record.get(int(l["hid"]), {})
		r["repaid"] = int(r.get("repaid", 0)) + 1
		record[int(l["hid"])] = r
		SysUtil.game_event("loan_repaid", {"household_id": int(l["hid"]), "kind": str(l["kind"]), "prop": str(l["prop"])})

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	var rate: float = savings_rate() / _year_days()
	for hid in savings.keys():
		savings[hid] = float(savings[hid]) * (1.0 + rate)
		if float(savings[hid]) <= 0.0:
			savings.erase(hid)
	for l in loans.duplicate():
		if day >= int(l["next_due"]):
			_installment(l)

static func _installment(l: Dictionary) -> void:
	var hid: int = int(l["hid"])
	var c: Dictionary = cfg().get("loans", {})
	var step: float = float(l["rate"]) * float(_pay_days()) / _year_days()
	var interest: float = float(l["balance"]) * step
	var due: int = mini(int(l["payment"]), int(ceil(float(l["balance"]) + interest)))
	l["next_due"] = int(l["next_due"]) + _pay_days()
	if Economy.spend(hid, due, "%s payment" % str(l["kind"])):
		l["balance"] = float(l["balance"]) + interest - float(due)
		l["left"] = int(l["left"]) - 1
		l["missed"] = 0
		if float(l["balance"]) <= 0.5 or int(l["left"]) <= 0:
			if float(l["balance"]) > 0.5 and int(l["left"]) <= 0:
				l["balance"] = 0.0
			_close(l, true)
		return
	l["missed"] = int(l["missed"]) + 1
	l["balance"] = float(l["balance"]) + interest + float(c.get("late_fee", 20))
	var r: Dictionary = record.get(hid, {})
	r["late_loan"] = int(r.get("late_loan", 0)) + 1
	record[hid] = r
	SysUtil.notify("A %s payment of %d coins was missed. A late fee was added." % [str(l["kind"]), due], "warn")
	SysUtil.game_event("loan_missed", {"household_id": hid, "kind": str(l["kind"]), "prop": str(l["prop"]), "missed": int(l["missed"])})
	if int(l["missed"]) >= int(c.get("default_after_missed", 3)):
		_default(l)

static func _default(l: Dictionary) -> void:
	var hid: int = int(l["hid"])
	var r: Dictionary = record.get(hid, {})
	r["defaults"] = int(r.get("defaults", 0)) + 1
	record[hid] = r
	SysUtil.game_event("loan_default", {"household_id": hid, "kind": str(l["kind"]), "prop": str(l["prop"]), "balance": int(l["balance"])})
	if str(l["kind"]) == "mortgage":
		_close(l, false)          # the property goes back to the bank (HousingRent.on_game_event)
		return
	l["missed"] = 0
	Economy._repossess(hid)       # collections take the most valuable belongings
	l["balance"] = float(l["balance"]) * 0.7

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"savings": SysUtil.str_keys(savings), "loans": loans.duplicate(true), "record": SysUtil.str_keys(record).duplicate(true), "seq": _seq}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	savings = SysUtil.int_keys(d.get("savings", {}))
	for k in savings:
		savings[k] = float(savings[k])
	loans = (d.get("loans", []) as Array).duplicate(true)
	for l in loans:
		SysUtil.ints_in(l, ["id", "hid", "principal", "payment", "left", "missed", "next_due", "taken"])
		l["balance"] = float(l["balance"])
		l["rate"] = float(l["rate"])
	record = SysUtil.int_keys((d.get("record", {}) as Dictionary).duplicate(true))
	for hid in record:
		SysUtil.ints_in(record[hid], ["repaid", "defaults", "late_loan"])
	_seq = int(d.get("seq", 1))
