class_name HousingRent
extends RefCounted
## Rent, tenants, evictions and townie landlords (task 13, slice 4). Weekly (the bill cycle). A player TENANT gets an ordinary Economy bill
## (reason "rent"), so late fees, missed-bill counting and repossession are the existing machinery; the second missed rent also serves an
## eviction notice. Townie tenants pay from their coins; a landlord that is a household gets the rent deposited, a townie landlord's coins grow.
## Tier: WEEKLY. Active set: properties with a tenant (<= ~12). Data: data/housing.json "rent".

static var next_cycle: int = 0

static func reset() -> void:
	next_cycle = 0

static func rc() -> Dictionary:
	return HousingProps.cfg().get("rent", {})

static func pay_days() -> int:
	return maxi(int(HousingProps.cfg().get("pay_days", 7)), 1)

static func on_day(day: int) -> void:
	if not MarketEconomy.enabled:
		return
	HousingProps.ensure()
	if next_cycle <= 0:
		next_cycle = day + pay_days()
	if day < next_cycle:
		return
	next_cycle = day + pay_days()
	_credit_paid_rent_bills()
	for id in HousingProps.props.keys():
		var p: Dictionary = HousingProps.props[id]
		if str(p["tenant_kind"]) == "" or (str(p["tenant_kind"]) == str(p["owner_kind"]) and int(p["tenant"]) == int(p["owner"])):
			_vacant_or_owner(p)
			continue
		_charge(p, day)
	_townie_market(day)

static func _vacant_or_owner(p: Dictionary) -> void:
	if str(p["tenant_kind"]) == "" and bool(p["to_let"]) and str(p["owner_kind"]) != "bank":
		if HousingProps.rng.randf() < float(rc().get("tenant_find_chance", 0.35)):
			_find_tenant(p)

static func _find_tenant(p: Dictionary) -> void:
	var rent: int = int(p["rent"])
	var pool: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["adult", "elder"] and not t.has("home_prop") and int(t["coins"]) >= rent * 2:
			pool.append(t)
	if pool.is_empty():
		return
	var t2: Dictionary = _weighted_tenant(pool, p)
	t2["home_prop"] = str(p["id"])
	p["tenant_kind"] = "townie"
	p["tenant"] = int(t2["id"])
	p["missed"] = 0
	if str(p["owner_kind"]) == "player":
		SysUtil.notify("%s moved into %s and will pay %d coins a week." % [t2["name"], p["label"], rent], "info")
	SysUtil.game_event("tenant_moved_in", {"prop": str(p["id"]), "tenant": int(t2["id"])})

## A random tenant from the pool, each weighted by the soft pull of the district (relatives, friends, community shops there; Heritage.pull). Same draw as before
## when the pool has one person or no district.
static func _weighted_tenant(pool: Array, p: Dictionary) -> Dictionary:
	var did: String = SoloDistricts.district_of(str(p.get("lot", "")))
	if did == "" or pool.size() == 1 or not SoloHome.active:
		return pool[HousingProps.rng.randi_range(0, pool.size() - 1)]
	var w: Array = []
	var total: float = 0.0
	for t in pool:
		var x: float = Heritage.pull(int(t["id"]), str(t.get("heritage", "")), did)
		w.append(x)
		total += x
	var r: float = HousingProps.rng.randf() * total
	for i in pool.size():
		r -= float(w[i])
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

static func _charge(p: Dictionary, day: int) -> void:
	var rent: int = _rent_due(p)
	if rent <= 0:
		return
	if str(p["tenant_kind"]) == "player":
		_bill(p, rent, day)
		return
	var t: Dictionary = Story.townies.get(int(p["tenant"]), {})
	if t.is_empty() or not bool(t.get("alive", false)):
		_clear_tenant(p)
		return
	var default_p: float = float(rc().get("tenant_default_chance", 0.015))
	if int(t["coins"]) >= rent and HousingProps.rng.randf() >= default_p:
		t["coins"] = int(t["coins"]) - rent
		p["missed"] = 0
		_pay_landlord(p, rent)
	else:
		p["missed"] = int(p["missed"]) + 1
		p["arrears"] = int(p["arrears"]) + rent
		if int(p["missed"]) >= int(rc().get("evict_after_missed", 2)):
			_evict(p, "unpaid rent")

## Rent a tenant owes: the property's agreed rent, or the market rent when none was set (a lease-back or a bank-owned home).
static func _rent_due(p: Dictionary) -> int:
	if int(p["rent"]) > 0:
		return int(p["rent"])
	return HousingProps.market_rent(p) if str(p["owner_kind"]) != str(p["tenant_kind"]) or int(p["owner"]) != int(p["tenant"]) else 0

static func _pay_landlord(p: Dictionary, rent: int) -> void:
	p["paid"] = int(p["paid"]) + rent
	match str(p["owner_kind"]):
		"player":
			Economy.deposit(int(p["owner"]), rent, "rent: %s" % str(p["label"]))
		"townie":
			var o: Dictionary = Story.townies.get(int(p["owner"]), {})
			if not o.is_empty():
				o["coins"] = int(o["coins"]) + rent

static func _clear_tenant(p: Dictionary) -> void:
	var t: Dictionary = Story.townies.get(int(p["tenant"]), {})
	if not t.is_empty() and str(p["tenant_kind"]) == "townie":
		t.erase("home_prop")
	p["tenant_kind"] = ""
	p["tenant"] = 0
	p["missed"] = 0

static func _evict(p: Dictionary, why: String) -> void:
	var name: String = Story.name_of(int(p["tenant"]))
	_clear_tenant(p)
	p["arrears"] = 0
	if str(p["owner_kind"]) == "player":
		SysUtil.notify("%s left %s (%s). The place is empty again." % [name, p["label"], why], "warn")
	ChronicleHook.note("eviction", "%s was evicted from %s for %s." % [name, p["label"], why], [], "town:0", 2, true)
	SysUtil.game_event("evicted", {"prop": str(p["id"]), "why": why})

## A player tenant: one rent bill per cycle in the Economy's bill book.
static func _bill(p: Dictionary, rent: int, day: int) -> void:
	var hid: int = int(p["tenant"])
	var late: int = _late_rent_bills(p)
	if late >= SoloRules.evict_after(p) and not bool(p.get("notice", false)):
		p["notice"] = true
		SysUtil.notify("EVICTION NOTICE: rent on %s is overdue. Pay your bills or belongings will be taken." % str(p["label"]), "bad")
		ChronicleHook.note("eviction", "An eviction notice was served on %s." % str(p["label"]), [], "home:%d" % hid, 3, true)
		SysUtil.game_event("eviction_notice", {"household_id": hid, "prop": str(p["id"])})
	elif late == 0:
		p["notice"] = false
	var bill: Dictionary = {"id": Economy._seq, "hid": hid, "amount": rent, "base": rent, "issued": day, "due": day + 3, "paid": false,
		"late": false, "fee": 0, "reason": "rent", "prop": str(p["id"]), "credited": false}
	Economy._seq += 1
	Economy.bills.append(bill)
	SysUtil.notify("Rent due for %s: %d coins." % [str(p["label"]), rent], "bill")

static func _late_rent_bills(p: Dictionary) -> int:
	var n: int = 0
	for b in Economy.bills:
		if str(b.get("reason", "")) == "rent" and str(b.get("prop", "")) == str(p["id"]) and not bool(b["paid"]) and bool(b["late"]):
			n += 1
	return n

## Rent paid by a player tenant reaches the landlord one cycle later (the bill book pays it).
static func _credit_paid_rent_bills() -> void:
	for b in Economy.bills:
		if str(b.get("reason", "")) == "rent" and bool(b["paid"]) and not bool(b.get("credited", true)):
			b["credited"] = true
			var p: Dictionary = HousingProps.get_prop(str(b.get("prop", "")))
			if not p.is_empty():
				_pay_landlord(p, int(b["amount"]))
				p["missed"] = 0

# ------------------------------------------------------------------ townie side
## Townies sell and buy houses, set rents to the market and sometimes lose a tenant. A handful of dice per week.
static func _townie_market(day: int) -> void:
	var tc: Dictionary = HousingProps.cfg().get("townies", {})
	var review: int = int(tc.get("rent_review_days", 28))
	for id in HousingProps.props.keys():
		var p: Dictionary = HousingProps.props[id]
		if str(p["owner_kind"]) == "townie" and str(p["tenant_kind"]) != "":
			if int(p["tenant"]) != int(p["owner"]) and day - int(p["last_rent_change"]) >= review:
				p["rent"] = raise_toward_market(p, int(p["rent"]))
				p["last_rent_change"] = day
		if bool(p["for_sale"]) and str(p["owner_kind"]) == "townie":
			if HousingProps.rng.randf() < float(tc.get("buy_chance", 0.03)) * 4.0:
				_townie_buys(p)

## A landlord can raise the rent by at most rent.increase_cap per review. 0 = start at the market rent.
static func raise_toward_market(p: Dictionary, current: int) -> int:
	var m: int = HousingProps.market_rent(p)
	if current <= 0:
		return m
	var cap: float = float(rc().get("increase_cap", 0.08))
	return clampi(m, int(floor(float(current) * (1.0 - cap))), int(ceil(float(current) * (1.0 + cap))))

static func _townie_buys(p: Dictionary) -> void:
	for t in Story.alive_townies():
		if Story.stage_of(t) == "adult" and int(t["coins"]) >= HousingProps.ask_price(p) / 3:
			p["owner_kind"] = "townie"
			p["owner"] = int(t["id"])
			p["for_sale"] = false
			return

## Mortgage default: the property goes back to the bank. A player's own home stays occupied: they become the bank's tenant.
static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev != "loan_default" or str(payload.get("kind", "")) != "mortgage":
		return
	var p: Dictionary = HousingProps.get_prop(str(payload.get("prop", "")))
	if p.is_empty():
		return
	var hid: int = int(payload.get("household_id", 0))
	p["owner_kind"] = "bank"
	p["owner"] = 0
	p["mortgage"] = 0
	ChronicleHook.note("foreclosure", "The bank took back %s after missed mortgage payments." % str(p["label"]), [], "home:%d" % hid, 3, true)
	if str(p["lot"]) == "home":
		p["tenant_kind"] = "player"
		p["tenant"] = hid
		p["rent"] = HousingProps.market_rent(p)
		SysUtil.notify("The bank took the house, but you may stay as tenants for %d coins a week." % int(p["rent"]), "bad")
	else:
		p["tenant_kind"] = ""
		p["tenant"] = 0
		p["for_sale"] = true
		p["ask"] = HousingProps.ask_price(p)
		p["listed_day"] = SysUtil.day()

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"next_cycle": next_cycle}

static func from_dict(d: Dictionary) -> void:
	reset()
	next_cycle = int(d.get("next_cycle", 0))
