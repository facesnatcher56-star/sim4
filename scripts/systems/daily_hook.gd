class_name DailyHook
extends RefCounted
## Task 65/66: personal hooks reaching the pawn through real systems (data/daily_hook.json), picked by the involvement director (Involve), never
## on a clock: someone it knows asks for a loan (a real relationship; repaid or not, later), a home problem (a StorytellerTilt on a real incident's
## own roll), or a wallet a real customer left behind. One plain line and a choice; never a list.
##   DailyHook.favour(f, tid, key) / wallet(f) / problem(f) -> landed   DailyHook.on_day(day) (loans paid back)   reset() / to_dict() / from_dict()

static var loans: Array = []           # [{tid, coins, due}] money lent, to be paid back (or not)
static var last_tid: int = -1          # the person in the last hook (Involve: the person gap)

static func reset() -> void:
	loans = []

static func cfg() -> Dictionary:
	return SysUtil.table("daily_hook")

static func _line(k: String, n: String, c: int = 0) -> String:
	var lines: Array = (cfg().get("lines", {}) as Dictionary).get(k, [""])
	return str(lines[PlayerPrompt._pick("hook|" + k, lines.size())]).replace("{n}", n).replace("{c}", str(c))

static func _friend(pid: int, tid: int, key: String) -> void:
	RelationshipService.add_both(pid, tid, "friendship", float((cfg().get("friendship", {}) as Dictionary).get(key, 0.0)))

static func on_day(day: int) -> void:
	var keep: Array = []
	for l in loans:
		if day < int(l["due"]):
			keep.append(l)
			continue
		var pid: int = Pawn.of()
		var n: String = Story.name_of(int(l["tid"])).get_slice(" ", 0)
		if Story.townies.has(int(l["tid"])) and bool(Story.townies[int(l["tid"])]["alive"]) and SysUtil.rng.randf() < float(cfg().get("repay_chance", 0.7)):
			Economy.deposit(Economy.primary_household(), int(l["coins"]), "paid back")
			SysUtil.notify(_line("repaid", n, int(l["coins"])), "relationship")
			_friend(pid, int(l["tid"]), "repaid")
		else:
			SysUtil.notify(_line("stiffed", n, int(l["coins"])), "story")
			_friend(pid, int(l["tid"]), "stiffed")
	loans = keep

# ------------------------------------------------------------------ the hooks
## Someone the pawn knows is short and asks (a phone call, or in person when they are standing there). `tid` >= 0: that person (a ripple: the
## friend the debt collector leaned on, the one whose affair came out), with its own line `key`.
static func favour(f, tid: int = -1, key: String = "favour") -> bool:
	var best: int = tid
	var best_v: float = float(cfg().get("favour_min", 10.0))
	for t in (Story.free_townies() if tid < 0 else []):
		var v: float = RelationshipService.value(int(f.id), int(t["id"]), "friendship")
		if v >= best_v and Story.stage_of(t) in ["adult", "elder"] and Involve.fresh(int(t["id"])) and not loans.any(func(l): return int(l["tid"]) == int(t["id"])):
			best_v = v
			best = int(t["id"])
	if loans.any(func(l): return int(l["tid"]) == best):
		return false
	if best < 0 or (PhoneOwn.block(int(f.id)) != "" and SysUtil.folk(best) == null):
		return false
	var amounts: Array = cfg().get("favour_amounts", [10, 20, 30])
	var c: int = int(amounts[SysUtil.rng.randi_range(0, amounts.size() - 1)])
	var n: String = Story.name_of(best).get_slice(" ", 0)
	last_tid = best
	var opts: Array = [{"id": "lend", "label": "Lend %d coins" % c}, {"id": "no", "label": "Can't right now"}]
	JusticePlayer.ask(int(f.id), "A favour", _line(key, n, c), opts, func(ch): _favour_answer(f, best, c, str(ch)), "no")
	return true

static func _favour_answer(f, tid: int, c: int, ch: String) -> void:
	var n: String = Story.name_of(tid).get_slice(" ", 0)
	if ch == "lend" and Economy.spend(int(f.household_id), c, "lent to " + n):
		var rd: Array = cfg().get("repay_days", [3, 7])
		loans.append({"tid": tid, "coins": c, "due": SysUtil.day() + SysUtil.rng.randi_range(int(rd[0]), int(rd[1]))})
		SysUtil.notify(_line("lent", n, c), "relationship")
		_friend(int(f.id), tid, "lent")
	else:
		SysUtil.notify(_line("refused", n, c), "story")
		_friend(int(f.id), tid, "refused")

## A home problem: only raises the odds of a real incident's own roll on the pawn's home (it may still not happen). Nothing is announced.
static func problem(f) -> bool:
	var ids: Array = cfg().get("problem_incidents", [])
	if ids.is_empty():
		return false
	StorytellerTilt.add(str(ids[SysUtil.rng.randi_range(0, ids.size() - 1)]), "home:%d" % int(f.household_id), "small")
	return true

## A real customer on the same lot leaves their wallet behind.
static func wallet(f) -> bool:
	var lot: String = Neighborhood.lot_of(f)
	if lot == "" or lot == Neighborhood.HOME:
		return false
	var owner = null
	for p in Crowd.crowd_folk(lot):
		if (p.tile - f.tile).length() < 12.0 and p.has_meta("townie_id") and Involve.fresh(int(p.get_meta("townie_id"))):
			owner = p
			break
	if owner == null:
		return false
	var tid: int = int(owner.get_meta("townie_id"))
	last_tid = tid
	var wc: Array = cfg().get("wallet_coins", [15, 60])
	var c: int = SysUtil.rng.randi_range(int(wc[0]), int(wc[1]))
	var n: String = str(owner.name).get_slice(" ", 0)
	Crowd.start_leaving(owner)
	JusticePlayer.ask(int(f.id), "Left behind", _line("wallet", n),
		[{"id": "return", "label": "Run after them with it"}, {"id": "keep", "label": "Pocket it"}, {"id": "leave", "label": "Leave it"}],
		func(ch): _wallet_answer(f, tid, n, c, lot, str(ch)), "leave")
	return true

static func _wallet_answer(f, tid: int, n: String, c: int, _lot: String, ch: String) -> void:
	match ch:
		"return":
			SysUtil.notify(_line("returned", n), "relationship")
			_friend(int(f.id), tid, "returned")
		"keep":
			Economy.deposit(int(f.household_id), c, "a found wallet")
			SysUtil.notify(_line("kept", n, c), "story")
			if SysUtil.rng.randf() < float(cfg().get("wallet_caught", 0.15)):          # they come back for it and see it in your hand
				SysUtil.notify(_line("kept_seen", n, c), "bad")
				_friend(int(f.id), tid, "kept_seen")
		_:
			SysUtil.notify(_line("left", n), "story")

static func to_dict() -> Dictionary:
	return {"loans": loans.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	loans = (d.get("loans", []) as Array).duplicate(true)
