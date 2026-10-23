class_name SoloGrey
extends RefCounted
## Task 61c: temptation reaches anyone who is broke, not only in the rough districts. Away from them (SoloPressure keeps the crew offers there),
## somebody the pawn already knows (the creation contact, the neighbour, a coworker, anyone they are on speaking terms with) offers quick money
## once the pawn is short or behind on a bill: cash-in-hand moving work that skips the tax, or a box of goods that "fell off a truck" to sell on.
## Always the player's choice (JusticePlayer.ask, Esc = no). Taking it pays at once; it can come back as a fine and a record. Rarer than the crews:
## the first offer after first_days of trouble, then at most one every repeat_days. Numbers and lines: data/solo.json "pressure.grey".

static var last_offer: int = -99
static var waiting: bool = false
static var pending_fine: Dictionary = {}          # {day, amount, charge, line} when a grey job will come back as a letter
static var due: int = -1                           # the day an offer is ready; it is made in the afternoon (on_hour), when people are about

static func reset() -> void:
	last_offer = -99
	waiting = false
	pending_fine = {}

static func cfg() -> Dictionary:
	return (SoloPressure.cfg().get("grey", {}) as Dictionary)

## Called daily by SoloPressure for a pawn in trouble outside a rough district.
static func on_day(f, day: int, trouble_since: int) -> void:
	var c: Dictionary = cfg()
	if waiting or c.is_empty() or day - trouble_since < int(SoloCfg.by_diff("pressure", "grey_first_days")) or day - last_offer < int(c.get("repeat_days", 7)):
		return
	if _someone(int(f.id)) >= 0:
		due = day

## The afternoon of a day an offer is ready: the person who knows the pawn makes it.
static func on_hour(h: int) -> void:
	if due != SysUtil.day() or h < 13 or h > 18 or waiting:
		return
	var f = SysUtil.folk(Pawn.of())
	if f == null or SysUtil.is_away(f):
		return
	due = -1
	var c: Dictionary = cfg()
	var day: int = SysUtil.day()
	var who: int = _someone(int(f.id))
	if who < 0:
		return
	var offers: Array = c.get("offers", [])
	var o: Dictionary = offers[SysUtil.rng.randi_range(0, offers.size() - 1)]
	last_offer = day
	waiting = true
	var txt: String = str(o["line"]).replace("{who}", Story.name_of(who).get_slice(" ", 0)).replace("{pay}", str(int(o["pay"])))
	JusticePlayer.ask(int(f.id), str(o["title"]), txt, [{"id": "yes", "label": str(o["yes"]).replace("{pay}", str(int(o["pay"])))}, {"id": "no", "label": "No thanks"}], _answer.bind(int(f.id), o), "no")
	if not JusticePlayer.ask_fn.is_valid():
		waiting = false

## Somebody the pawn knows (friendship above grey.min_friendship), the closest first.
static func _someone(fid: int) -> int:
	var best: int = -1
	var best_v: float = float(cfg().get("min_friendship", 5))
	for t in Story.alive_townies():
		if Story.stage_of(t) not in ["adult", "elder"]:
			continue
		var v: float = RelationshipService.value(fid, int(t["id"]), "friendship")
		if v >= best_v:
			best_v = v
			best = int(t["id"])
	return best

static func _answer(choice, pid: int, o: Dictionary) -> void:
	waiting = false
	var f = SysUtil.folk(pid)
	if f == null or str(choice) != "yes":
		return
	Economy.deposit(int(f.household_id), int(o["pay"]), str(o.get("ledger", "cash in hand")))
	if float(o.get("minutes", 0)) > 0.0:
		Away.send(f, float(o["minutes"]), "errand", {"label": str(o.get("away", "Out on a job"))})
	if SysUtil.chance(float(o.get("caught", 0.1))):
		pending_fine = {"day": SysUtil.day() + SysUtil.rng.randi_range(2, 5), "amount": int(o.get("fine", 40)), "charge": str(o.get("charge", "undeclared work")),
			"line": str(o.get("caught_line", ""))}

## The grey job comes back: a letter with a fine, and a petty record that closes some jobs until it is expunged.
static func fine_due(f, day: int) -> void:
	if pending_fine.is_empty() or day < int(pending_fine["day"]):
		return
	var amt: int = int(pending_fine["amount"])
	Economy.record(int(f.household_id), -mini(amt, Economy.balance(int(f.household_id))), "fine: " + str(pending_fine["charge"]))
	var recs: Array = JusticeState.records.get(int(f.id), [])
	recs.append({"day": day, "charge": str(pending_fine["charge"]), "case": -1, "result": "fined"})
	JusticeState.records[int(f.id)] = recs
	SysUtil.notify(str(pending_fine["line"]).replace("{fine}", str(amt)), "bad")
	pending_fine = {}

static func to_dict() -> Dictionary:
	return {"last": last_offer, "fine": pending_fine.duplicate()}

static func from_dict(d: Dictionary) -> void:
	reset()
	last_offer = int(d.get("last", -99))
	pending_fine = (d.get("fine", {}) as Dictionary).duplicate()
