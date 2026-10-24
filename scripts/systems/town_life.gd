class_name TownLife
extends RefCounted
## Task 66: the town runs on its own all day (data/director.json "town"). Every hour a few real things happen between real townies at real places,
## from the same causes as the street scenes (StreetScenes.cause: a feud, an affair, a debt, an arrest, a car alarm, someone collapsing ...).
## On the pawn's lot (and the pawn awake and free) it plays in front of them (StreetScenes.stage). Anywhere else it happens for real off-screen
## (tension and friendship, a hospital stay, an arrest, a petty case) and is remembered: it reaches the player only through people, as gossip
## when they talk to someone who knows the people involved, and as a ripple when a friend of theirs was in it (Involve picks those up).
##   TownLife.on_hour(h)   TownLife.on_social(pawn_id, other_id)   TownLife.ripple(pid) -> {tid, kind} or {}   recent   reset()

const PUBLIC := ["row", "arrest", "alarm", "collapse", "drunk", "break_in"]
const STAGED := ["row", "affair", "debt", "upset", "collapse", "arrest", "alarm"]          # the kinds StreetScenes can play in front of the pawn          # things people saw in the street; the rest (an affair, a debt, someone upset) only friends know

static var recent: Array = []          # [{kind, a, b, c, lot, day, told}] what happened, newest last
static var _rippled: Dictionary = {}   # index -> true: already reached the player as a ripple
static var _in_at: Dictionary = {}     # townie id -> minute they were last in a town event (rest_h: spread it across the town)

static func reset() -> void:
	recent = []
	_rippled = {}
	_in_at = {}

static func cfg() -> Dictionary:
	return (SysUtil.table("director").get("town", {}) as Dictionary)

static func on_hour(h: int) -> void:
	if not SoloHome.active:
		return
	var per_hour: float = float(cfg().get("per_day", 10)) / 24.0 * float((cfg().get("hour_mult", {}) as Dictionary).get(str(h), 1.0))
	var n: int = int(per_hour) + (1 if SysUtil.rng.randf() < per_hour - float(int(per_hour)) else 0)
	for _i in n:
		_one()

## One real event somewhere in town: a kind with a real cause at some lot, picked by weight.
static func _one() -> void:
	var f = SysUtil.folk(Pawn.of()) if Pawn.of() >= 0 else null
	if f == null:
		return
	var lots: Array = Neighborhood.lot_ids().filter(func(l): return Venues.type_of_lot(str(l)) not in ["home", ""])
	lots.shuffle()
	var weights: Dictionary = StreetScenes.cfg().get("weights", {})
	var cands: Array = []
	var ws: Array = []
	for lot in lots.slice(0, int(cfg().get("lots_per_try", 4))):
		for kind in weights:
			var s: Dictionary = StreetScenes.cause(str(kind), f, str(lot))
			if not s.is_empty():
				s["lot"] = str(lot)
				cands.append(s)
				ws.append(float(weights[kind]))
	var every: Dictionary = _everyday(lots)          # the town's ordinary friction and fun, from real relationships
	if not every.is_empty():
		cands.append(every)
		ws.append(float(cfg().get("everyday_weight", 3.0)))
	var pick = SysUtil.pick_weighted(cands, ws)
	if pick == null:
		return
	var lot2: String = str(pick["lot"])
	if str(pick["kind"]) in STAGED and Neighborhood.lot_of(f) == lot2 and not SysUtil.is_away(f) and not CrimePlace.is_asleep(f) and StreetScenes.pending.is_empty() and JusticePlayer.open == 0:
		StreetScenes.stage(f, lot2, pick)          # right here: the player sees it happen
		for who2 in StreetScenes.last_people:
			_in_at[int(who2)] = SysUtil.now()
		Involve.landed("scene: %s" % str(pick["kind"]), [int(pick["a"]), int(pick.get("b", -1))])
		return
	_offscreen(pick, lot2)

## Not in a town event for rest_h hours (the same few names should not run through everything).
static func rested(tid: int) -> bool:
	return SysUtil.now() - int(_in_at.get(tid, -100000)) >= int(float(cfg().get("rest_h", 12)) * 60.0)

## Everyday causes the town has without any thread: two townies who already dislike each other run into each other (a row), or someone
## with friends has them round (a get-together at their home). Sampled, so it stays cheap. {} when none turned up this time.
static func _everyday(lots: Array) -> Dictionary:
	var pool: Array = Story.free_townies().filter(func(t): return Story.stage_of(t) in ["adult", "elder"] and StreetScenes._free(int(t["id"])))          # (_free: rested and not just in a pull)
	if pool.size() < 3 or lots.is_empty():
		return {}
	var friendly: Dictionary = {}          # a get-together only when nothing rougher turned up this time (66b: they were most of the town's events)
	for _i in int(cfg().get("everyday_tries", 12)):
		var a: int = int(pool[SysUtil.rng.randi_range(0, pool.size() - 1)]["id"])
		var b: int = int(pool[SysUtil.rng.randi_range(0, pool.size() - 1)]["id"])
		if a == b:
			continue
		var fr: float = RelationshipService.value(a, b, "friendship")
		if (fr <= -10.0 or RelationshipService.value(a, b, "tension") >= 20.0) and not StreetScenes._recent("row|%d|%d" % [a, b]):
			return {"kind": "row", "a": a, "b": b, "lot": str(lots[0])}
		var crook: bool = not JusticeRecords.convictions(a).is_empty() or TownDrama.threads.any(func(t): return str(t["kind"]) in ["crew", "addiction", "debt"] and int(t["a"]) == a)
		if crook and not StreetScenes._recent("theft|%d" % a):          # someone with a record, a crew, a habit or a debt: they take what isn't theirs
			var home_b: String = Neighborhood.home_of_townie(b)
			if home_b != "" and SysUtil.rng.randf() < 0.4:
				return {"kind": "break_in", "a": a, "b": b, "lot": home_b}
			return {"kind": "theft", "a": a, "b": b, "lot": str(lots[0])}
		if TownDrama.threads.any(func(t): return str(t["kind"]) == "addiction" and int(t["a"]) == a) and SysUtil.hour_f() >= 18.0 and not StreetScenes._recent("drunk|%d" % a):
			return {"kind": "drunk", "a": a, "b": -1, "lot": str(lots[0])}
		if friendly.is_empty() and fr >= 20.0 and not StreetScenes._recent("gathering|%d|-1" % a) and Neighborhood.home_of_townie(a) != "":
			friendly = {"kind": "gathering", "a": a, "b": b, "lot": Neighborhood.home_of_townie(a)}
	return friendly if SysUtil.rng.randf() < float(cfg().get("gathering_share", 0.2)) else {}

## It happens for real where the pawn is not: the same consequences the townies would get in a scene nobody stepped into.
static func _offscreen(s: Dictionary, lot: String) -> void:
	var kind: String = str(s["kind"])
	var a: int = int(s["a"])
	var b: int = int(s.get("b", -1))
	StreetScenes._used[StreetScenes.key_of(s)] = SysUtil.day()
	match kind:
		"row":
			RelationshipService.add_both(a, b, "friendship", -6.0)
			RelationshipService.add_value(a, b, "tension", 20.0)
		"affair":
			var c: int = int(s.get("c", -1))
			RelationshipService.add_both(c, a, "friendship", -35.0)
			RelationshipService.add_value(c, a, "tension", 50.0)
		"debt":
			RelationshipService.add_both(a, b, "friendship", -8.0)
		"arrest":
			var cs: Dictionary = CaseStore.get_case(int(s.get("case", -1)))
			if not cs.is_empty() and str(cs["state"]) == "open":
				JusticeProcess.arrest(cs, a)
		"collapse":
			var p = SysUtil.folk(a)
			if p != null and p.has_meta("crowd"):
				Crowd.dismiss(p)
			Hospital.admit(a, 2, "collapsed in the street")
		"alarm":
			CrimePetty.commit("vandalism", a, "venue:" + lot, {"seen": false, "trace": 0.3})
		"gathering":
			RelationshipService.add_both(a, b, "friendship", 5.0)
		"theft", "break_in":          # a real case: the police may work it, and an arrest may follow (another scene, another ripple)
			var c2: Dictionary = CaseStore.create("theft" if kind == "theft" else "burglary", a, b, "venue:" + lot, {"witnessed": SysUtil.rng.randf() < 0.4, "trace": 0.4})
			c2["state"] = "open"
			c2["disc_day"] = SysUtil.day()
			RelationshipService.add_value(b, a, "tension", 10.0)
		"drunk":
			CrimePetty.commit("disturbance", a, "venue:" + lot, {"seen": true})
	recent.append({"kind": kind, "a": a, "b": b, "c": int(s.get("c", -1)), "lot": lot, "day": SysUtil.day(), "told": false})
	for who in [a, b, int(s.get("c", -1))]:
		if who >= 0:
			_in_at[who] = SysUtil.now()
	while recent.size() > int(cfg().get("keep", 24)):
		recent.pop_front()
		_rippled.clear()

# ------------------------------------------------------------------ through people
## The pawn has just talked to `other`: if they were stood up by the pawn they say so, else if they know someone something happened to,
## they tell it (one item per chat).
static func on_social(pid: int, other: int) -> void:
	if not Pawn.is_pawn_id(pid) or other < 0:
		return
	if Involve.stood.has(other):
		Involve.stood.erase(other)
		SysUtil.notify("%s: \"%s\"" % [Story.name_of(other).get_slice(" ", 0), str(cfg().get("stood_line", "You stood me up the other day. I waited an hour."))], "story")
		return
	var i: int = news_for(pid, other)
	if i >= 0:
		SysUtil.notify("%s: \"%s\"" % [Story.name_of(other).get_slice(" ", 0), tell(i, other)], "story")

## The newest untold thing `other` would know and tell the pawn: they were in it, they are close to someone who was, or it was public
## (a scene in the street) and the pawn knows someone in it. -1 when they have nothing.
static func news_for(pid: int, other: int) -> int:
	for i in range(recent.size() - 1, -1, -1):
		var e: Dictionary = recent[i]
		if bool(e["told"]) or SysUtil.day() - int(e["day"]) > 4:
			continue
		var near: bool = other in [int(e["a"]), int(e["b"]), int(e["c"])]
		if str(e["kind"]) == "gathering" and not near:
			continue          # a get-together is only news from someone who was there
		for who in [int(e["a"]), int(e["b"])]:
			if who >= 0 and RelationshipService.value(other, who, "friendship") >= 10.0:
				near = true
			if who >= 0 and str(e["kind"]) in PUBLIC and RelationshipService.knows(pid, who):
				near = true
		if near:
			return i
	return -1

## Say item `i` as `teller` would, and mark it told.
static func tell(i: int, teller: int) -> String:
	if i < 0 or i >= recent.size():
		return ""
	recent[i]["told"] = true
	return _gossip(recent[i], teller)

static func _gossip(e: Dictionary, teller: int) -> String:
	var lines: Dictionary = cfg().get("gossip", {})
	var own: bool = teller in [int(e["a"]), int(e["b"]), int(e["c"])]          # they were in it: they tell it their way
	var other: int = int(e["b"]) if teller == int(e["a"]) else int(e["a"])
	var ls: Array = (cfg().get("gossip_own", {}) as Dictionary).get(str(e["kind"]), []) if own else []
	if ls.is_empty():
		ls = lines.get(str(e["kind"]), lines.get("default", ["Did you hear about {a}?"]))
		own = false
	var t: String = str(ls[PlayerPrompt._pick("gossip|" + str(e["kind"]), ls.size())])
	var nm := func(id: int) -> String: return Story.name_of(id).get_slice(" ", 0) if id >= 0 else ""
	if own:
		return t.replace("{o}", nm.call(other)).replace("{place}", Neighborhood.label_of(str(e["lot"])))
	return t.replace("{a}", nm.call(int(e["a"]))).replace("{b}", nm.call(int(e["b"]))).replace("{c}", nm.call(int(e["c"]))).replace("{place}", Neighborhood.label_of(str(e["lot"])))

## A friend of the pawn's was in something lately: {tid, kind} (the director turns it into them asking for help), else {}.
static func ripple(pid: int) -> Dictionary:
	for i in range(recent.size() - 1, -1, -1):
		if _rippled.has(i):
			continue
		var e: Dictionary = recent[i]
		if SysUtil.day() - int(e["day"]) > 3 or str(e["kind"]) not in ["affair", "debt", "row", "arrest"]:
			continue
		for who in [int(e["a"]), int(e["c"])]:
			if who >= 0 and RelationshipService.value(pid, who, "friendship") >= float(cfg().get("ripple_friendship", 15.0)) and not JusticeState.inmates.has(who):
				_rippled[i] = true
				return {"tid": who, "kind": str(e["kind"])}
	return {}

static func to_dict() -> Dictionary:
	return {"recent": recent.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	recent = (d.get("recent", []) as Array).duplicate(true)
