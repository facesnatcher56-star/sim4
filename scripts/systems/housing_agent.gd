class_name HousingAgent
extends RefCounted
## The real estate agent (task 13): the player's housing commands. Buy a listing (cash or a mortgage), sell a property, sell-and-lease-back
## the home, buy it back, let a second property to a townie, set the rent, repair, evict. Each returns {ok, reason}. Money only through Economy
## / BankAccounts. The agent's fee is `value.agent_fee` of the price on both buying and selling.

static func _ok(extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"ok": true, "reason": ""}
	d.merge(extra, true)
	return d

static func _no(why: String) -> Dictionary:
	return {"ok": false, "reason": why}

static func fee_of(price: int) -> int:
	return int(round(float(price) * float(HousingProps.cfg().get("value", {}).get("agent_fee", 0.03))))

static func mortgage_rate(hid: int) -> float:
	var m: Dictionary = HousingProps.cfg().get("mortgage", {})
	var p: float = MarketEconomy.prosperity if MarketEconomy.enabled else 0.0
	return float(m.get("rate_year", 0.05)) + 0.04 * float(850 - BankAccounts.credit_score(hid)) / 550.0 + 0.015 * p

static func min_down(price: int) -> int:
	return int(ceil(float(price) * float(HousingProps.cfg().get("mortgage", {}).get("down_min", 0.2))))

## What a purchase would cost: {price, fee, down_min, rate, payment_for_min_down}.
static func quote(hid: int, prop_id: String, down: int = -1) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if p.is_empty():
		return {}
	var price: int = HousingProps.ask_price(p)
	var d: int = min_down(price) if down < 0 else clampi(down, 0, price)
	var rate: float = mortgage_rate(hid)
	var term: int = int(HousingProps.cfg().get("mortgage", {}).get("term_payments", 40))
	return {"price": price, "fee": fee_of(price), "down_min": min_down(price), "down": d, "rate": rate, "term": term,
		"payment": BankAccounts.payment_for(float(price - d), rate, term) if price > d else 0}

static func can_buy(p: Dictionary, hid: int) -> bool:
	if p.is_empty():
		return false
	if bool(p["for_sale"]):
		return true
	return str(p["tenant_kind"]) == "player" and int(p["tenant"]) == hid and not (str(p["owner_kind"]) == "player" and int(p["owner"]) == hid)

## down < 0: the smallest down payment; down >= price: all cash (no mortgage).
static func buy(hid: int, prop_id: String, down: int = -1) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if not can_buy(p, hid):
		return _no("That property is not for sale.")
	var q: Dictionary = quote(hid, prop_id, down)
	var price: int = int(q["price"])
	var d: int = int(q["down"])
	if d < int(q["down_min"]) and d < price:
		return _no("The bank wants at least %d coins down." % int(q["down_min"]))
	var loan_amount: int = price - d
	if loan_amount > 0 and BankAccounts.credit_score(hid) < int(HousingProps.cfg().get("mortgage", {}).get("max_credit_floor", 520)):
		return _no("Your credit score is too low for a mortgage.")
	if not Economy.can_afford(hid, d + int(q["fee"])):
		return _no("Not enough coins for the deposit and the agent's fee.")
	Economy.spend(hid, d, "house deposit: %s" % str(p["label"]))
	Economy.spend(hid, int(q["fee"]), "estate agent fee")
	_pay_seller(p, d)
	if loan_amount > 0:
		var l: Dictionary = BankAccounts.open_loan(hid, loan_amount, int(q["term"]), float(q["rate"]), "mortgage", str(p["id"]))
		p["mortgage"] = int(l["id"])
		_pay_seller(p, loan_amount)         # the bank pays the seller the rest
	p["owner_kind"] = "player"
	p["owner"] = hid
	p["for_sale"] = false
	p["bought_day"] = SysUtil.day()
	p["paid"] = 0
	if str(p["tenant_kind"]) != "player" or int(p["tenant"]) != hid:
		HousingRent._clear_tenant(p)
		p["rent"] = 0
	SysUtil.notify("You bought %s." % str(p["label"]), "good")
	SysUtil.game_event("property_bought", {"household_id": hid, "prop": str(p["id"]), "price": price})
	ChronicleHook.note("housing", "A household bought %s." % str(p["label"]), [], "home:%d" % hid, 1, true)
	return _ok({"price": price})

static func _pay_seller(p: Dictionary, amount: int) -> void:
	if str(p["owner_kind"]) == "townie":
		var t: Dictionary = Story.townies.get(int(p["owner"]), {})
		if not t.is_empty():
			t["coins"] = int(t["coins"]) + amount
	elif str(p["owner_kind"]) == "player" and int(p["owner"]) > 0:
		Economy.deposit(int(p["owner"]), amount, "sale of %s" % str(p["label"]))

static func why_not_sell(hid: int, p: Dictionary) -> String:
	if p.is_empty() or str(p["owner_kind"]) != "player" or int(p["owner"]) != hid:
		return "You do not own that."
	var net: int = net_sale(p)
	if net < 0:
		return "The mortgage is bigger than the sale price."
	return ""

static func net_sale(p: Dictionary) -> int:
	var v: Dictionary = HousingProps.cfg().get("value", {})
	var price: int = int(round(float(HousingProps.value(p)) * (1.0 - float(v.get("sale_spread", 0.04)))))
	var owed: int = 0
	var l: Dictionary = BankAccounts.find(int(p["mortgage"]))
	if not l.is_empty():
		owed = int(ceil(float(l["balance"])))
	return price - fee_of(price) - owed

## Sell. A home you live in becomes a lease-back: you stay as tenants of the buyer at the market rent.
static func sell(hid: int, prop_id: String) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	var why: String = why_not_sell(hid, p)
	if why != "":
		return _no(why)
	var net: int = net_sale(p)
	var l: Dictionary = BankAccounts.find(int(p["mortgage"]))
	if not l.is_empty():
		BankAccounts._close(l, true)
	p["mortgage"] = 0
	Economy.deposit(hid, net, "sale of %s" % str(p["label"]))
	var buyer: Dictionary = _richest_townie()
	if buyer.is_empty():
		p["owner_kind"] = "bank"
		p["owner"] = 0
	else:
		p["owner_kind"] = "townie"
		p["owner"] = int(buyer["id"])
		buyer["coins"] = maxi(int(buyer["coins"]) - HousingProps.value(p) / 4, 0)
	p["to_let"] = false
	var lease_back: bool = str(p["tenant_kind"]) == "player" and int(p["tenant"]) == hid
	if lease_back:
		p["rent"] = HousingProps.market_rent(p)
		p["last_rent_change"] = SysUtil.day()
	elif str(p["owner_kind"]) == "bank" and str(p["lot"]) == "":
		p["for_sale"] = true
		p["listed_day"] = SysUtil.day()
		p["ask"] = HousingProps.ask_price(p)
	SysUtil.notify("Sold %s for %d coins after fees%s." % [str(p["label"]), net, ". You stay on as tenants" if lease_back else ""], "good")
	SysUtil.game_event("property_sold", {"household_id": hid, "prop": str(p["id"]), "net": net})
	return _ok({"net": net, "lease_back": lease_back})

static func _richest_townie() -> Dictionary:
	var best: Dictionary = {}
	for t in Story.alive_townies():
		if Story.stage_of(t) == "adult" and (best.is_empty() or int(t["coins"]) > int(best["coins"])):
			best = t
	return best if int(best.get("coins", 0)) >= 500 else {}

# ------------------------------------------------------------------ landlord
static func rent_out(hid: int, prop_id: String, rent: int = -1) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if p.is_empty() or str(p["owner_kind"]) != "player" or int(p["owner"]) != hid:
		return _no("You do not own that.")
	if str(p["tenant_kind"]) == "player":
		return _no("You live there.")
	p["to_let"] = true
	p["rent"] = HousingProps.market_rent(p) if rent <= 0 else rent
	p["last_rent_change"] = SysUtil.day()
	return _ok({"rent": int(p["rent"])})

static func stop_letting(hid: int, prop_id: String) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if p.is_empty() or str(p["owner_kind"]) != "player" or int(p["owner"]) != hid:
		return _no("You do not own that.")
	p["to_let"] = false
	return _ok()

## Raise or lower the rent of a property you let. A tenant in place can be charged at most `increase_cap` more per review period.
static func set_rent(hid: int, prop_id: String, rent: int) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if p.is_empty() or str(p["owner_kind"]) != "player" or int(p["owner"]) != hid or rent <= 0:
		return _no("You cannot change that rent.")
	var cur: int = int(p["rent"])
	var occupied: bool = str(p["tenant_kind"]) != ""
	if occupied and rent > cur:
		var review: int = int(HousingProps.cfg().get("townies", {}).get("rent_review_days", 28))
		if SysUtil.day() - int(p["last_rent_change"]) < review:
			return _no("Rent can only go up once every %d days." % review)
		var cap: int = int(floor(float(cur) * (1.0 + float(HousingRent.rc().get("increase_cap", 0.08)))))
		if rent > cap:
			return _no("A rise of more than %d%% is not allowed." % int(float(HousingRent.rc().get("increase_cap", 0.08)) * 100.0))
	p["rent"] = rent
	p["last_rent_change"] = SysUtil.day()
	# a tenant who is asked for much more than the going rate may leave
	if occupied and str(p["tenant_kind"]) == "townie" and rent > int(float(HousingProps.market_rent(p)) * 1.2):
		HousingRent._evict(p, "a rent they could not afford")
	return _ok({"rent": rent})

static func repair(hid: int, prop_id: String) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if p.is_empty() or str(p["owner_kind"]) != "player" or int(p["owner"]) != hid:
		return _no("You do not own that.")
	var pts: float = 95.0 - float(p["condition"])
	if pts < 5.0:
		return _no("It is in good shape already.")
	var cost: int = int(round(pts * float(HousingProps.cfg().get("condition", {}).get("repair_cost_per_point", 8)) * MarketEconomy.price_mult()))
	if not Economy.spend(hid, cost, "repairs: %s" % str(p["label"])):
		return _no("Repairs would cost %d coins." % cost)
	p["condition"] = 95.0
	return _ok({"cost": cost})

static func evict_tenant(hid: int, prop_id: String) -> Dictionary:
	var p: Dictionary = HousingProps.get_prop(prop_id)
	if p.is_empty() or str(p["owner_kind"]) != "player" or int(p["owner"]) != hid or str(p["tenant_kind"]) != "townie":
		return _no("There is nobody to evict.")
	HousingRent._evict(p, "notice from the landlord")
	return _ok()
