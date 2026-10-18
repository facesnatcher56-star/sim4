class_name BusinessDay
extends RefCounted
## The daily business tick (task 13): run every open business, settle money (player: Economy ledger; townie: owner's coins), pay staff,
## close the bankrupt, and let townies found new businesses (competition for yours). Tier: DAILY, <= 10 businesses. No per-minute work.

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 130061
	BusinessSim.reset()

static func on_day(day: int) -> void:
	if not MarketEconomy.enabled:
		return
	for id in BusinessState.ids_sorted():
		var b: Dictionary = BusinessState.get_biz(int(id))
		if b.is_empty():
			continue
		if str(b["owner_kind"]) == "townie" and not bool(Story.townies.get(int(b["owner"]), {}).get("alive", false)):
			BusinessState.close(b, "the owner is gone")
			continue
		_staff_check(b)
		var res: Dictionary = BusinessSim.run_day(b)
		_pay_staff(b)
		_settle(b, res)
	_found_townie_business(day)

# ------------------------------------------------------------------ staff
static func _staff_check(b: Dictionary) -> void:
	var keep: Array = []
	for s in b["staff"]:
		var t: Dictionary = Story.townies.get(int(s["tid"]), {})
		if t.is_empty() or not bool(t.get("alive", false)):
			continue
		keep.append(s)
	b["staff"] = keep

static func _pay_staff(b: Dictionary) -> void:
	if not bool(b["open"]):
		return
	for s in b["staff"]:
		var t: Dictionary = Story.townies.get(int(s["tid"]), {})
		if not t.is_empty():
			t["coins"] = int(t["coins"]) + int(s["wage"]) * BusinessSim.open_hours(b)

# ------------------------------------------------------------------ money
static func _settle(b: Dictionary, res: Dictionary) -> void:
	var cash: float = float(b["cash"])
	var is_player: bool = str(b["owner_kind"]) == "player"
	if cash < 0.0:
		var need: int = int(ceil(-cash))
		if _owner_pay(b, need):
			b["cash"] = 0.0
			b["neg_days"] = 0
		else:
			b["neg_days"] = int(b["neg_days"]) + 1
			if int(b["neg_days"]) >= int(BusinessState.cfg().get("bankrupt_after_days", 7)):
				bankrupt(b)
		return
	b["neg_days"] = 0
	if bool(b["auto_sweep"]) and cash >= 1.0:
		var keep: float = 0.0
		var take: int = int(floor(cash - keep))
		if take > 0:
			b["cash"] = cash - float(take)
			if is_player:
				Economy.deposit(int(b["owner"]), take, "profit: %s" % str(b["name"]))
			else:
				var o: Dictionary = Story.townies.get(int(b["owner"]), {})
				if not o.is_empty():
					o["coins"] = int(o["coins"]) + int(float(take) * float(BusinessState.cfg().get("townies", {}).get("coin_share", 0.6)))

## The owner covers a loss. Player: household funds. Townie: their coins.
static func _owner_pay(b: Dictionary, n: int) -> bool:
	if str(b["owner_kind"]) == "player":
		return Economy.spend(int(b["owner"]), n, "business loss: %s" % str(b["name"]))
	var o: Dictionary = Story.townies.get(int(b["owner"]), {})
	if o.is_empty() or int(o["coins"]) < n:
		return false
	o["coins"] = int(o["coins"]) - n
	return true

static func bankrupt(b: Dictionary) -> void:
	var text: String = "%s (%s) went out of business." % [str(b["name"]), str(BusinessState.type_def(str(b["type"])).get("label", b["type"])).to_lower()]
	if str(b["owner_kind"]) == "player":
		SysUtil.notify("%s has gone bankrupt and is closed." % str(b["name"]), "bad")
		SysUtil.game_event("business_bankrupt", {"household_id": int(b["owner"]), "business": int(b["id"])})
	else:
		var o: Dictionary = Story.townies.get(int(b["owner"]), {})
		if not o.is_empty():
			o["coins"] = int(int(o["coins"]) * 0.4)
	ChronicleHook.note("business", text, [], "town:0", 2, true)
	BusinessState.close(b, "bankrupt")

# ------------------------------------------------------------------ townies found businesses
static func _found_townie_business(day: int) -> void:
	var tc: Dictionary = BusinessState.cfg().get("townies", {})
	var mine: int = 0
	for id in BusinessState.list:
		if str(BusinessState.list[id]["owner_kind"]) == "townie":
			mine += 1
	if mine >= int(tc.get("max_businesses", 5)):
		return
	var prosp: float = MarketEconomy.prosperity
	if rng.randf() >= float(tc.get("found_chance", 0.1)) * clampf(1.0 + prosp, 0.2, 2.0):
		return
	var cands: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) == "adult" and int(t["coins"]) >= int(tc.get("min_coins", 150)) and not t.has("owner_biz") and not t.has("job_biz"):
			cands.append(t)
	if cands.is_empty():
		return
	cands.sort_custom(func(a, c): return int(a["id"]) < int(c["id"]))
	var t2: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var tid: String = _pick_type(prosp)
	if tid == "":
		return
	var lots: Array = BusinessState.open_lots_for(tid)
	if lots.is_empty():
		return
	var lot: String = str(lots[rng.randi_range(0, lots.size() - 1)])
	var fitout: int = int(round(float(BusinessState.type_def(tid).get("fitout", 1000)) * MarketEconomy.price_mult()))
	# the townie puts in what they can and the bank covers the rest: statistical, no ledger needed
	t2["coins"] = int(int(t2["coins"]) * 0.5)
	var last: String = str(t2["name"]).split(" ")[-1]
	var label: String = str(BusinessState.type_def(tid).get("label", tid))
	var nm: String = "%s's %s" % [last, label]
	for id2 in BusinessState.list:
		if str(BusinessState.list[id2]["name"]) == nm:
			nm = "%s %s" % [last, label]
	var b: Dictionary = BusinessState.make(tid, lot, "rent", "townie", int(t2["id"]), nm)
	b["owner_skill"] = float(rng.randi_range(2, 6))
	b["price"] = [0.85, 1.0, 1.0, 1.15][rng.randi_range(0, 3)]
	if fitout > 0:
		b["cash"] = float(fitout) * 0.05
	t2["owner_biz"] = true
	ChronicleHook.note("business", "%s opened %s at %s." % [str(t2["name"]), nm, Neighborhood.label_of(lot) if Neighborhood.lot(lot).size() > 0 else lot], [int(t2["id"])], "town:0", 1, true)

## Prefer types the town does not have yet (the gap in the market), and cheap ones in a recession.
static func _pick_type(prosp: float) -> String:
	var ids: Array = BusinessState.type_ids()
	var weights: Array = []
	for t in ids:
		var have: int = 0
		for id in BusinessState.list:
			if str(BusinessState.list[id]["type"]) == str(t):
				have += 1
		var w: float = 1.0 / float(1 + have)
		if prosp < -0.2 and int(BusinessState.type_def(str(t)).get("fitout", 1000)) > 1800:
			w *= 0.4
		weights.append(w)
	var total: float = 0.0
	for w2 in weights:
		total += float(w2)
	var roll: float = rng.randf() * total
	for i in ids.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return str(ids[i])
	return str(ids[0]) if not ids.is_empty() else ""
