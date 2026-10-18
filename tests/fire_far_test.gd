extends RefCounted
## Fire for the whole town: far lots and townies use the same rates and risk entries with the statistical outcomes ("The Ashby house had a
## kitchen fire, no one hurt"), their houses carry smoke alarms / fireplaces / sprinklers (so those matter), holiday candles roll for them too,
## burnt-out lots lose things and recover, and none of it toasts the player.

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")

func run() -> Array:
	var f: Array = []
	_town_objects(f)
	_outcomes(f)
	_deaths(f)
	_aftermath(f)
	_holiday_marker(f)
	return f

func _setup() -> StubWorld:
	var w := FK.setup()
	K.make_folk(w, "Home", [], 1, Vector2i(5, 5))
	Story.generate_townies()
	Fire.on_minute()
	return w

func _lot_with(object_id: String, present: bool) -> int:
	var lots: Array = []
	for t in Story.alive_townies():
		var n: int = int(t.get("lot", 0))
		if n > 0 and not lots.has(n):
			lots.append(n)
	lots.sort()
	for n2 in lots:
		var has: bool = false
		for t2 in Story.alive_townies():
			if int(t2.get("lot", 0)) == n2 and (t2.get("town_objects", []) as Array).has(object_id):
				has = true
		if has == present:
			return int(n2)
	return -1

func _town_objects(f: Array) -> void:
	var w := _setup()
	var with_alarm: int = 0
	var lots: Dictionary = {}
	for t in Story.alive_townies():
		K.expect(f, t.has("town_objects"), "every townie lot has a fire-relevant object list")
		lots[int(t["lot"])] = t["town_objects"]
	for n in lots:
		if (lots[n] as Array).has("smoke_alarm"):
			with_alarm += 1
		K.expect(f, (lots[n] as Array).has("stove"), "every far lot has a stove")
	K.expect(f, lots.size() >= 4 and with_alarm >= 0, "%d far lots, %d with a smoke alarm" % [lots.size(), with_alarm])
	var again: Array = FireTown.objects_for_lot(7)
	K.expect(f, again == FireTown.objects_for_lot(7), "deterministic per lot")
	# the conditions see them
	var n_alarm: int = _lot_with("smoke_alarm", true)
	var n_none: int = _lot_with("smoke_alarm", false)
	if n_alarm > 0:
		K.expect(f, IncidentCond.check([{"has_object": "smoke_alarm"}], IncidentSubject.of_town_lot(n_alarm)), "has_object sees the far lot's smoke alarm")
	if n_none > 0:
		K.expect(f, IncidentCond.check([{"lacks_object": "smoke_alarm"}], IncidentSubject.of_town_lot(n_none)), "and its absence")
	var rate: float = Incidents.effective_rate("kitchen_fire", IncidentSubject.of_town_lot(n_none if n_none > 0 else n_alarm))
	K.expect(f, rate > 0.0 and rate <= 0.3 + 0.0001, "far lots roll the same kitchen fire rate (%.3f)" % rate)
	FK.teardown()

func _outcomes(f: Array) -> void:
	var w := _setup()
	var n: int = _lot_with("sprinkler", false)
	K.notes.clear()
	var r: Dictionary = Incidents.resolve_statistical("kitchen_fire", IncidentSubject.of_town_lot(n), 0)
	K.expect(f, bool(r["ok"]) and str(r["mode"]) == "statistical", "statistical resolution")
	K.expect(f, str(r["summary"]).begins_with("The ") and str(r["summary"]).find("house had a kitchen fire, no one hurt") >= 0, "summary reads like news: %s" % str(r["summary"]))
	K.expect(f, K.notes.is_empty(), "a far lot fire does not toast the player")
	K.expect(f, ChronicleHook.recent.size() >= 1 and str(ChronicleHook.recent[ChronicleHook.recent.size() - 1]["kind"]) == "kitchen_fire", "it goes to the chronicle")
	for id in ["fireplace_fire", "electrical_fire", "candle_fire", "lightning_fire"]:
		var res: Dictionary = Incidents.resolve_statistical(id, IncidentSubject.of_town_lot(n), 0)
		K.expect(f, bool(res["ok"]) and str(res["summary"]) != "", "%s has a statistical line: %s" % [id, str(res["summary"])])
	var weights: float = 0.0
	for oc in IncidentDefs.defs["kitchen_fire"]["statistical"]["outcomes"]:
		weights += float(oc["weight"])
	K.expect(f, weights > 99.0 and weights < 101.0, "kitchen outcome weights sum to ~100 (%.1f)" % weights)
	# a house with a sprinkler can never have the big-fire outcomes
	FK.teardown()

func _deaths(f: Array) -> void:
	var w := _setup()
	var n: int = _lot_with("smoke_alarm", false)
	if n < 0:
		n = _lot_with("sprinkler", false)
	var before: int = Story.alive_townies().size()
	var res: Dictionary = Incidents.resolve_statistical("kitchen_fire", IncidentSubject.of_town_lot(n), 3)
	K.expect(f, bool(res["ok"]) and str(res["summary"]).find("did not get out") >= 0, "the worst outcome is told plainly and gently: %s" % str(res["summary"]))
	K.expect(f, Story.alive_townies().size() == before - 1, "one townie of that lot died")
	var ch: Dictionary = ChronicleHook.recent[ChronicleHook.recent.size() - 1]
	K.expect(f, int(ch["severity"]) >= 3, "chronicle severity")
	var dead_fire: bool = false
	for tid in Story.townies:
		if str(Story.townies[tid].get("cause", "")) == "fire":
			dead_fire = true
	K.expect(f, dead_fire, "recorded with the cause: fire")
	FK.teardown()

func _aftermath(f: Array) -> void:
	var w := _setup()
	var n: int = _lot_with("sprinkler", false)
	var before: int = 0
	for t in Story.alive_townies():
		if int(t["lot"]) == n:
			before = (t["town_objects"] as Array).size()
			break
	Incidents.resolve_statistical("kitchen_fire", IncidentSubject.of_town_lot(n), 1)
	var after: int = 0
	var rec: Dictionary = {}
	for t2 in Story.alive_townies():
		if int(t2["lot"]) == n:
			after = (t2["town_objects"] as Array).size()
			rec = t2
			break
	K.expect(f, after < before and rec.has("fire_day"), "a burnt far lot loses things (%d -> %d)" % [before, after])
	Fire.on_day(SysUtil.day() + 11)
	K.expect(f, not rec.has("fire_day") and (rec["town_objects"] as Array).size() >= after, "and gets them back after 10 days")
	FK.teardown()

func _holiday_marker(f: Array) -> void:
	var w := _setup()
	var day: int = -1
	for d in range(1, 200):
		if not Holidays.today(d).is_empty():
			day = d
			break
	K.expect(f, day > 0, "the calendar has a holiday")
	FireTown.on_day(day)
	var marked: int = 0
	for t in Story.alive_townies():
		if (t.get("buffs", []) as Array).has("holiday_today"):
			marked += 1
	K.expect(f, marked == Story.alive_townies().size() and marked > 0, "townies carry the holiday marker on a holiday (%d)" % marked)
	var n: int = _lot_with("sprinkler", false)
	K.expect(f, Incidents.effective_rate("candle_fire", IncidentSubject.of_town_lot(n)) > 0.0, "so candle fires roll for far lots")
	FireTown.on_day(day + 1 if Holidays.today(day + 1).is_empty() else day + 2)
	K.expect(f, not (Story.alive_townies()[0].get("buffs", []) as Array).has("holiday_today"), "and the marker goes again")
	FK.teardown()
