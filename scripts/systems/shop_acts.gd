class_name ShopActs
extends RefCounted
## Task 53 shops: take anything off a shelf, pocket it, eat it in the aisle, pay at the till, or walk out. Nothing in the menu says it isn't paid for:
## the world tells you, through the cashier who is really there (data/shop_acts.json). Held goods that are not paid for are the trigger.
##   ShopActs.entries(f, obj) (added to an object's menu)   ShopActs.hides(f, obj) -> ids the pawn no longer gets here   ShopActs.on_minute() (the exit check)

static var carried: Dictionary = {}          # fid -> [{lot, id, what, price, kind, units, hidden}]
static var flagged: Dictionary = {}          # fid -> true: somebody saw them pocket something
static var asking: Dictionary = {}           # fid -> lot: the cashier asked, waiting for the answer

static func reset() -> void:
	carried = {}
	flagged = {}
	asking = {}

static func busy() -> bool:
	return not carried.is_empty()

static func cfg() -> Dictionary:
	return SysUtil.table("shop_acts")

static func _line(k: String, vars: Dictionary = {}) -> String:
	var lines: Array = cfg().get("lines", {}).get(k, [""])
	var t: String = str(lines[PlayerPrompt._pick("shop|" + k, lines.size())])
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

static func _shop_lot(f) -> String:
	var lot: String = Neighborhood.lot_of(f)
	return lot if lot != "" and Venues.type_of_lot(lot) not in ["home", "park", ""] else ""

static func hides(f, obj) -> Array:
	if not Pawn.is_pawn(f) or _shop_lot(f) == "":
		return []
	return (cfg().get("objects", {}) as Dictionary).get(str(obj.def_id), {}).get("replaces", [])

static func _entry(id: String, label: String, fn: Callable) -> Dictionary:
	return {"id": id, "label": label, "category": "Shop", "enabled": true, "reason": "", "action": fn}

static func entries(f, obj) -> Array:
	var lot: String = _shop_lot(f)
	if obj == null or not Pawn.is_pawn(f) or lot == "":
		return []
	var out: Array = []
	var spot: Vector2i = WalkThen.near(obj.tile)
	for g in (cfg().get("objects", {}) as Dictionary).get(str(obj.def_id), {}).get("goods", []):
		var good: Dictionary = g
		out.append(_entry("take_" + str(good["id"]), str(good["take"]), func(): WalkThen.go(f, spot, func(): take(f, lot, good, false))))
		out.append(_entry("pocket_" + str(good["id"]), "Slip %s into a pocket" % str(good["what"]), func(): WalkThen.go(f, spot, func(): take(f, lot, good, true))))
		if good.has("eat"):
			out.append(_entry("eat_" + str(good["id"]), "Eat %s here" % str(good["what"]), func(): WalkThen.go(f, spot, func(): eat_here(f, lot, good))))
	if (cfg().get("till_objects", []) as Array).has(str(obj.def_id)) and not unpaid(int(f.id), lot).is_empty():
		out.append(_entry("pay_till", "Pay", func(): WalkThen.go(f, spot, func(): pay(f, lot))))
	return out

static func unpaid(fid: int, lot: String) -> Array:
	return (carried.get(fid, []) as Array).filter(func(it): return str(it["lot"]) == lot)

static func _total(items: Array) -> int:
	var t: int = 0
	for it in items:
		t += int(it["price"])
	return t

# ------------------------------------------------------------------ on the shelf
static func take(f, lot: String, good: Dictionary, hide: bool) -> void:
	var fid: int = int(f.id)
	var it: Dictionary = good.duplicate()
	it["lot"] = lot
	it["hidden"] = false
	if hide:
		var cashier = _cashier(lot)
		var r: Dictionary = SkillCheck.attempt(fid, "shoplift", {"opponent": int(cashier.id)} if cashier != null else {})
		it["hidden"] = bool(r["ok"])
		var who: Array = Notice.who(fid, f.tile, {"visibility": 0.25 if bool(r["ok"]) else 0.9, "unseen": true, "ignore": [int(cashier.id)] if cashier != null else []})
		if not who.is_empty() or str(r["grade"]) in ["loud_fail", "catastrophic"]:
			flagged[fid] = true          # a shopper or the staff saw it go into the pocket
			if not who.is_empty():
				SysUtil.notify(_line("pocket_seen", {"n": SysUtil.folk_name(int(who[0]["id"]))}), "story")
	var list: Array = carried.get(fid, [])
	list.append(it)
	carried[fid] = list

static func eat_here(f, lot: String, good: Dictionary) -> void:
	f.add_to_stat("hunger", float(good.get("eat", 20)))
	SysUtil.notify(_line("eat"), "story")
	var it: Dictionary = good.duplicate()
	it["lot"] = lot
	it["hidden"] = true          # nothing to see in your hands; the wrapper is the only trace
	it["kind"] = "eaten"
	var list: Array = carried.get(int(f.id), [])
	list.append(it)
	carried[int(f.id)] = list
	if not Notice.who(int(f.id), f.tile, {"visibility": 0.6}).is_empty():
		flagged[int(f.id)] = true

# ------------------------------------------------------------------ the till
static func _cashier(lot: String):
	var roles: Array = cfg().get("cashier_roles", [])
	for s in Crowd.staff_folk(lot):
		if roles.has(str(s.get_meta("staff", ""))) and not SysUtil.is_away(s):
			return s
	return null

## A person's name as said in a line (staff carry their role in brackets on the name tag).
static func _nm(p) -> String:
	return str(p.name).get_slice(" (", 0)

static func pay(f, lot: String) -> void:
	var fid: int = int(f.id)
	var items: Array = unpaid(fid, lot)
	var c = _cashier(lot)
	var nm: String = _nm(c) if c != null else "The cashier"
	if items.is_empty():
		SysUtil.notify(_line("nothing_to_pay", {"n": nm}), "story")
		return
	var total: int = _total(items)
	var have: int = Economy.balance(int(f.household_id))
	if have < total:
		JusticePlayer.ask(fid, "At the till", _line("short", {"n": nm, "t": total, "s": total - have}),
			[{"id": "back", "label": "Put something back"}, {"id": "all", "label": "Leave it all"}, {"id": "walk", "label": "Walk out with it"}],
			func(ch): _short(f, lot, str(ch)), "back")
		return
	Economy.spend(int(f.household_id), total, "shop: %s" % Neighborhood.label_of(lot))
	SysUtil.notify(_line("paid", {"n": nm, "t": total}), "story")
	_own(f, items)
	_drop(fid, lot)

static func _short(f, lot: String, ch: String) -> void:
	var fid: int = int(f.id)
	match ch:
		"back":
			var items: Array = unpaid(fid, lot)
			items.sort_custom(func(a, b): return int(a["price"]) > int(b["price"]))
			var keep: Array = []
			for it in carried.get(fid, []):
				if it != items[0] or str(it["kind"]) == "eaten":
					keep.append(it)
			carried[fid] = keep
			SysUtil.notify(_line("put_back"), "story")
			if not unpaid(fid, lot).is_empty():
				pay(f, lot)
		"all":
			var keep2: Array = (carried.get(fid, []) as Array).filter(func(it): return str(it["lot"]) != lot or str(it["kind"]) == "eaten")
			carried[fid] = keep2
			SysUtil.notify(_line("put_back"), "story")
		_:
			flagged[fid] = true          # walking off from the till with it: the cashier is looking right at you

static func _own(f, items: Array) -> void:
	for it in items:
		if str(it["kind"]) == "pantry":
			Neighborhood.add_pantry(int(it.get("units", 1)))

static func _drop(fid: int, lot: String) -> void:
	carried[fid] = (carried.get(fid, []) as Array).filter(func(it): return str(it["lot"]) != lot)
	if (carried[fid] as Array).is_empty():
		carried.erase(fid)
		flagged.erase(fid)

# ------------------------------------------------------------------ walking out
## Every minute, only while someone holds unpaid goods: stepping outside the shop (or leaving the lot) with them is the moment the cashier may ask.
static func on_minute() -> void:
	if carried.is_empty():
		return
	for fid in carried.keys():
		var f = SysUtil.folk(int(fid))
		if f == null:
			carried.erase(fid)
			continue
		if asking.has(fid):
			continue
		for lot in _lots_of(int(fid)):
			if Neighborhood.lot_of(f) != lot or WeatherFolk.is_outside(f):
				_exit(f, lot)

static func _lots_of(fid: int) -> Array:
	var out: Array = []
	for it in carried.get(fid, []):
		if not out.has(str(it["lot"])):
			out.append(str(it["lot"]))
	return out

static func _exit(f, lot: String) -> void:
	var fid: int = int(f.id)
	var items: Array = unpaid(fid, lot)
	var c = _cashier(lot)
	var seen: bool = false
	if c != null:
		var visible: bool = bool(flagged.get(fid, false)) or items.any(func(it): return not bool(it["hidden"]))
		var busy: float = float(cfg().get("busy_per_customer", 0.06)) * float(Crowd.count(lot))
		var p: float = float(cfg().get("watch", 0.85)) * clampf(1.0 - busy, 0.2, 1.0) * (0.7 + SkillCheck.level(int(c.id), "perception") * 0.05)
		seen = visible and (bool(flagged.get(fid, false)) or SysUtil.rng.randf() < p)
	if not seen:
		_own(f, items)
		_drop(fid, lot)
		CrimePetty.commit("shoplifting", fid, "venue:" + lot, {"seen": false})
		return
	var nm: String = _nm(c)
	var line: String = Sexes.fill(_line("ask", {"n": nm}), int(c.id))
	SysUtil.notify(line, "bad")
	f.cancel_current("stopped at the door")
	f.clear_queue()
	asking[fid] = lot          # still held until the answer
	JusticePlayer.ask(fid, "At the door", line,
		[{"id": "pay", "label": "Pay"}, {"id": "back", "label": "Put it back"}, {"id": "lie", "label": "Say you already paid"}, {"id": "walk", "label": "Keep walking"}, {"id": "run", "label": "Run"}],
		func(ch): _answer(f, lot, c, str(ch)), "pay")

static func _answer(f, lot: String, c, ch: String) -> void:
	var fid: int = int(f.id)
	var nm: String = _nm(c) if c != null else "The cashier"
	asking.erase(fid)
	match ch:
		"pay":
			pay(f, lot)
		"back":
			_drop(fid, lot)
			SysUtil.notify(_line("put_back"), "story")
		"lie":
			var r: Dictionary = SkillCheck.attempt(fid, "lie", {"opponent": int(c.id)} if c != null else {})
			if bool(r["ok"]):
				SysUtil.notify(_line("lie_ok", {"n": nm}), "story")
				_own(f, unpaid(fid, lot))
				_drop(fid, lot)
				CrimePetty.commit("shoplifting", fid, "venue:" + lot, {"seen": false})
			else:
				SysUtil.notify(_line("lie_fail", {"n": nm}), "bad")
				_steal(f, lot, true)
		_:
			SysUtil.notify(_line("shout", {"n": nm}), "bad")
			_steal(f, lot, true)
			if ch == "run":
				var away: Interaction = Interaction.create_goto(f, NeighborhoodLots.street_tile(lot) + Vector2i(0, 8), true, 0)
				if away != null:
					f.enqueue(away)

static func _steal(f, lot: String, seen: bool) -> void:
	var fid: int = int(f.id)
	_own(f, unpaid(fid, lot))
	_drop(fid, lot)
	CrimePetty.commit("shoplifting", fid, "venue:" + lot, {"seen": seen})
