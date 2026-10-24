class_name ShopActs
extends RefCounted
## Task 53 shops: take anything off a shelf, pocket it, eat it in the aisle, pay at the till, or walk out. Nothing in the menu says it isn't paid for:
## the world tells you, through the cashier who is really there (data/shop_acts.json). Held goods that are not paid for are the trigger.
##   ShopActs.entries(f, obj) (added to an object's menu)   ShopActs.hides(f, obj) -> ids the pawn no longer gets here   ShopActs.on_minute() (the exit check)

static var carried: Dictionary = {}          # fid -> [{lot, id, what, price, kind, units, hidden}]
static var flagged: Dictionary = {}          # fid -> true: somebody saw them pocket something
static var asking: Dictionary = {}           # fid -> lot: the cashier asked, waiting for the answer
static var was_in: Dictionary = {}           # "fid|lot" -> true: has been inside that shop holding its goods (walking out = going from in to out)
static var resume: Dictionary = {}           # fid -> [Interaction]: the player's orders the door scene interrupted (task 63: given back after the answer)

static func reset() -> void:
	carried = {}
	flagged = {}
	asking = {}
	was_in = {}
	resume = {}

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
	for o in (cfg().get("objects", {}) as Dictionary).get(str(obj.def_id), {}).get("orders", []):
		var od: Dictionary = o
		var lbl: String = str(SimEnv.data().interaction_def(str(od["iid"])).get("label", od["what"]))
		var e: Dictionary = _entry("tab_" + str(od["iid"]), lbl, func(): order(f, lot, obj, od))
		e["enabled"] = _order_ir(f, obj, od) != null          # the menu says no when the order could not be served now (a round only in the evening)
		e["iid"] = str(od["iid"])          # InteractionQuery words the reason from this interaction's tests
		out.append(e)
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

## Task 63: a counter cafe takes the money when you order; only a sit-down restaurant or a bar (a round in the evening) runs a tab.
static func on_tab(lot: String, od: Dictionary) -> bool:
	return bool(od.get("tab", false)) or (cfg().get("tab_venues", []) as Array).has(Venues.type_of_lot(lot))

## A cafe or bar order: the real interaction, served now (no coins test, no coins taken on finish). Paid at the till first, or owed on the tab.
static func order(f, lot: String, obj, od: Dictionary) -> void:
	var ir: Interaction = _order_ir(f, obj, od)
	if ir == null:
		return          # nothing is served, so nothing is paid or owed
	if not on_tab(lot, od):
		var c = _cashier(lot)
		var nm: String = _nm(c) if c != null else "the cashier"
		var price: int = int(od["price"])
		var have: int = Economy.balance(int(f.household_id))
		if have < price:
			SysUtil.notify(_cap(_line("short", {"n": nm, "t": price, "s": price - have})), "warn")
			return
		Economy.spend(int(f.household_id), price, "shop: %s" % Neighborhood.label_of(lot))
		SysUtil.notify(_cap(_line("paid", {"n": nm, "t": price})), "story")
		f.enqueue(ir)
		return
	f.enqueue(ir)
	var list: Array = carried.get(int(f.id), [])
	list.append({"lot": lot, "id": str(od["iid"]), "what": str(od["what"]), "price": int(od["price"]), "kind": "eaten", "hidden": false, "tab": true})          # staff served it: they know
	carried[int(f.id)] = list

## The order as an interaction that goes on the tab (no coin test, no payment on finish), or null when it cannot be served now.
static func _order_ir(f, obj, od: Dictionary) -> Interaction:
	var ir: Interaction = Interaction.create(str(od["iid"]), f, int(obj.id), true)
	if ir == null:
		return null
	ir.def = ir.def.duplicate(true)
	ir.def["tests"] = (ir.def.get("tests", []) as Array).filter(func(t): return not (t is Dictionary and ((t as Dictionary).has("coins_at_least") or (t as Dictionary).has("stat_below"))))          # task 63: paid for, a coffee can be had at any energy; the need is what it does, not a gate
	ir.def["on_finish"] = (ir.def.get("on_finish", []) as Array).filter(func(e): return not (e is Dictionary and (e as Dictionary).has("coins_add")))
	return ir if ir.can_run(f, obj, false) else null

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

## Lines say "the cashier" mid-sentence when nobody is named; a line that starts with it gets a capital.
static func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)

static func pay(f, lot: String) -> void:
	var fid: int = int(f.id)
	var items: Array = unpaid(fid, lot)
	var c = _cashier(lot)
	var nm: String = _nm(c) if c != null else "the cashier"
	if items.is_empty():
		SysUtil.notify(_cap(_line("nothing_to_pay", {"n": nm})), "story")
		return
	var total: int = _total(items)
	var have: int = Economy.balance(int(f.household_id))
	if have < total:
		JusticePlayer.ask(fid, "At the till", _cap(_line("short", {"n": nm, "t": total, "s": total - have})),
			[{"id": "back", "label": "Put something back"}, {"id": "all", "label": "Leave it all"}, {"id": "walk", "label": "Walk out with it"}],
			func(ch): _short(f, lot, str(ch)), "back")
		return
	Economy.spend(int(f.household_id), total, "shop: %s" % Neighborhood.label_of(lot))
	SysUtil.notify(_cap(_line("paid", {"n": nm, "t": total})), "story")
	_own(f, items)
	_drop(fid, lot)
	_resume(f)

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
			else:
				_resume(f)
		"all":
			var keep2: Array = (carried.get(fid, []) as Array).filter(func(it): return str(it["lot"]) != lot or str(it["kind"]) == "eaten")
			carried[fid] = keep2
			SysUtil.notify(_line("put_back"), "story")
			_resume(f)
		_:
			resume.erase(fid)
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
			var k: String = "%d|%s" % [int(fid), lot]
			if Neighborhood.lot_of(f) != lot or (WeatherFolk.is_outside(f) and was_in.has(k)):
				was_in.erase(k)
				_exit(f, lot)
			elif not WeatherFolk.is_outside(f):
				was_in[k] = true

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
	var tab_only: bool = items.all(func(it): return bool(it.get("tab", false)))
	if not seen:
		if tab_only:          # task 63: an unnoticed walk-out on a tab is the character's own knowledge, never a shoplifting case
			SysUtil.notify("You walked out without paying the %d coins." % _total(items), "warn")
			_drop(fid, lot)
		else:
			_steal(f, lot, false)
		return
	var nm: String = _nm(c)
	var no_back: bool = items.all(func(it): return bool(it.get("tab", false)) or str(it["kind"]) == "eaten")          # nothing left to put back
	var line: String = Sexes.fill(_line("ask_tab" if no_back else "ask", {"n": nm}), int(c.id))
	SysUtil.notify(line, "bad")
	_keep_orders(f)
	f.cancel_current("stopped at the door")
	f.clear_queue()
	asking[fid] = lot          # still held until the answer
	JusticePlayer.ask(fid, "At the door", line,
		([{"id": "pay", "label": "Pay"}] + ([] if no_back else [{"id": "back", "label": "Put it back"}]) + [{"id": "lie", "label": "Say you already paid"}, {"id": "walk", "label": "Keep walking"}, {"id": "run", "label": "Run"}]),
		func(ch): _answer(f, lot, c, str(ch)), "pay")

static func _answer(f, lot: String, c, ch: String) -> void:
	var fid: int = int(f.id)
	var nm: String = _nm(c) if c != null else "the cashier"
	asking.erase(fid)
	match ch:
		"pay":
			pay(f, lot)
		"back":
			_drop(fid, lot)
			SysUtil.notify(_line("put_back"), "story")
			_resume(f)
		"lie":
			var r: Dictionary = SkillCheck.attempt(fid, "lie", {"opponent": int(c.id)} if c != null else {})
			if bool(r["ok"]):
				SysUtil.notify(_cap(_line("lie_ok", {"n": nm})), "story")
				_steal(f, lot, false)
				_resume(f)
			else:
				SysUtil.notify(_cap(_line("lie_fail", {"n": nm})), "bad")
				_steal(f, lot, true)
				resume.erase(fid)
		_:
			resume.erase(fid)
			SysUtil.notify(_cap(_line("shout", {"n": nm})), "bad")
			_steal(f, lot, true, ch == "run")
			if ch == "run":
				var away: Interaction = Interaction.create_goto(f, NeighborhoodLots.street_tile(lot) + Vector2i(0, 8), true, 0)
				if away != null:
					f.enqueue(away)

## Task 63: the walk (or whatever else the player ordered) the cashier interrupted, kept so it carries on after the answer.
static func _keep_orders(f) -> void:
	var keep: Array = []
	var cur: Interaction = f.current
	if cur != null and cur.player:
		var again: Interaction = Interaction.create(cur.def_id, f, cur.target_id, true)
		if again != null:
			again.def = cur.def
			again.params = cur.params.duplicate()
			again.goto_tile = cur.goto_tile
			again.goto_level = cur.goto_level
			keep.append(again)
	for q in f.queue:
		if (q as Interaction).player:
			keep.append(q)
	if not keep.is_empty():
		resume[int(f.id)] = keep

static func _resume(f) -> void:
	for ir in resume.get(int(f.id), []):
		(ir as Interaction).state = "queued"
		f.enqueue(ir)
	resume.erase(int(f.id))

## The shop's real security (CrimeSecurity business profile): camera footage of the exit, and a guard on post who is awake.
static func security(lot: String) -> Dictionary:
	var vt: String = Venues.type_of_lot(lot)
	var fx: Dictionary = CrimeSecurity.effects(CrimeSecurity.business_profile(vt), DoorActs.night())
	var guard: int = -1
	var day_guard = StaffPosts.guard_at(lot)          # a guard on a day post (data/staff_posts.json), else the night posts
	if day_guard != null:
		return {"footage": float(fx.get("footage", 0.0)), "guard": int(day_guard.id)}
	for g in CrimeSecurityGuards.guards_of("biz:" + vt):
		if not CrimeSecurityGuards.is_asleep(int(g)) and CrimeSecurityGuards.is_night():
			guard = int(g)
	return {"footage": float(fx.get("footage", 0.0)), "guard": guard}

static func _steal(f, lot: String, seen: bool, running: bool = false) -> void:
	var fid: int = int(f.id)
	var sec: Dictionary = security(lot)
	var held: bool = false
	if seen and int(sec["guard"]) >= 0:          # a guard at the door: walking past means being stopped, running means a chase
		held = not running or not bool(SkillCheck.attempt(fid, "outrun", {"opponent": int(sec["guard"])})["ok"])
		SysUtil.notify(("%s steps in front of you and takes your arm." if held else "%s gives chase, and falls behind.") % SysUtil.folk_name(int(sec["guard"])), "bad")
	if held:
		_drop(fid, lot)          # the goods go back on the shelf
		CrimePetty.commit("shoplifting", fid, "venue:" + lot, {"seen": true, "trace": 1.0})
		return
	_own(f, unpaid(fid, lot))
	_drop(fid, lot)
	CrimePetty.commit("shoplifting", fid, "venue:" + lot, {"seen": seen, "trace": float(sec["footage"])})
