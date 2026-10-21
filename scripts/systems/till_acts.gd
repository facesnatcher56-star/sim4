class_name TillActs
extends RefCounted
## Task 53: the till behind a shop or cafe counter. "Open the till" is always offered at one; how much is in it is hidden until opened (stable per
## lot and day, emptier early and after closing: the takings go to the bank at night). Whoever is really there notices (the staff at the post almost
## always, shoppers through Notice) and reacts; the player answers. Taking the cash is theft (a case: seen at once, or found at closing).
##   TillActs.entries(f, obj)   numbers and lines: data/shop_acts.json "till"

static func cfg() -> Dictionary:
	return SysUtil.table("shop_acts").get("till", {})

static func _line(k: String, vars: Dictionary = {}) -> String:
	var lines: Array = cfg().get("lines", {}).get(k, [""])
	var t: String = str(lines[PlayerPrompt._pick("till|" + k, lines.size())])
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

static var emptied: Dictionary = {}          # lot -> day the till was taken

static func reset() -> void:
	emptied = {}

## The cash in it now: grows through the opening hours, nothing once it was taken today or after closing.
static func cash(lot: String) -> int:
	if int(emptied.get(lot, -1)) == SysUtil.day() or not Venues.is_open(lot):
		return 0
	var c: Dictionary = cfg()
	var h: float = SysUtil.hour_f()
	var frac: float = float(absi(hash("%s|%d|till" % [lot, SysUtil.day()])) % 1000) / 1000.0
	return int(float(c.get("float", 20)) + float(c.get("per_hour", 12)) * clampf(h - 8.0, 0.0, 14.0) * (0.5 + frac))

static func entries(f, obj) -> Array:
	var lot: String = Neighborhood.lot_of(f)
	if obj == null or not Pawn.is_pawn(f) or lot == "" or Venues.type_of_lot(lot) in ["home", "park", ""]:
		return []
	if not (SysUtil.table("shop_acts").get("till_objects", []) as Array).has(str(obj.def_id)):
		return []
	return [{"id": "open_till", "label": "Open the till", "category": "Shop", "enabled": true, "reason": "",
		"action": func(): WalkThen.go(f, WalkThen.near(obj.tile), func(): open_till(f, lot))}]

static func open_till(f, lot: String) -> void:
	var fid: int = int(f.id)
	var staff = ShopActs._cashier(lot)
	var nid: int = -1
	if staff != null and SysUtil.rng.randf() < float(cfg().get("staff_sees", 0.95)):
		nid = int(staff.id)
	else:
		var who: Array = Notice.who(fid, f.tile, {"visibility": 0.8, "noise": 0.2, "unseen": true})
		if not who.is_empty():
			nid = int(who[0]["id"])
	var n: int = cash(lot)
	if nid < 0:
		_take(f, lot, n, -1)
		return
	var nm: String = SysUtil.folk_name(nid).get_slice(" (", 0)
	var line: String = Sexes.fill(_line("caught", {"n": nm}), nid)
	SysUtil.notify(line, "bad")
	JusticePlayer.ask(fid, "At the till", line,
		[{"id": "back", "label": "Step back"}, {"id": "lie", "label": "Say you were looking for change"}, {"id": "grab", "label": "Grab the cash"}],
		func(ch): _answer(f, lot, nid, n, str(ch)), "back")

static func _answer(f, lot: String, nid: int, n: int, ch: String) -> void:
	var fid: int = int(f.id)
	var nm: String = SysUtil.folk_name(nid).get_slice(" (", 0)
	match ch:
		"back":
			SysUtil.notify(_line("back_off", {"n": nm}), "story")
			RelationshipService.add_value(nid, fid, "friendship", -3.0)
		"lie":
			var r: Dictionary = SkillCheck.attempt(fid, "lie", {"opponent": nid})
			SysUtil.notify(_line("lie_ok" if bool(r["ok"]) else "lie_fail", {"n": nm}), "story" if bool(r["ok"]) else "bad")
			if not bool(r["ok"]):
				CrimePetty.commit("disturbance", fid, "venue:" + lot, {"seen": true})
		_:
			_take(f, lot, n, nid)

static func _take(f, lot: String, n: int, witness: int) -> void:
	var fid: int = int(f.id)
	emptied[lot] = SysUtil.day()
	if n <= 0:
		SysUtil.notify(_line("empty"), "story")
	else:
		Economy.deposit(int(f.household_id), n, "cash from a till")
		SysUtil.notify(_line("took", {"c": n}), "story")
	if n <= 0 and witness < 0:
		return
	var cs: Dictionary = CaseStore.create("theft", fid, -1, "venue:" + lot, {"witnessed": witness >= 0, "witnesses": [witness] if witness >= 0 else [],
		"witness_clarity": 0.8 if witness >= 0 else 0.0, "trace": 0.3, "stolen_coins": n, "loot_value": n})
	CrimePlace.place_at_scene(fid, "venue:" + lot)
	if witness >= 0:
		CaseDiscovery.report(cs, witness, "saw")
	else:
		CarActs.reports.append({"case": int(cs["id"]), "due_min": SysUtil.now() + 60 * SysUtil.rng.randi_range(1, 5)})          # found when the till is counted
