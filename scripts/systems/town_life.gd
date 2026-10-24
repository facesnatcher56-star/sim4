class_name TownLife
extends RefCounted
## Task 66: the town runs on its own all day (data/director.json "town"). Every hour a few real things happen between real townies at real places,
## from the same causes as the street scenes (StreetScenes.cause: a feud, an affair, a debt, an arrest, a car alarm, someone collapsing ...).
## On the pawn's lot (and the pawn awake and free) it plays in front of them (StreetScenes.stage). Anywhere else it happens for real off-screen
## (tension and friendship, a hospital stay, an arrest, a petty case) and is remembered: it reaches the player only through people, as gossip
## when they talk to someone who knows the people involved, and as a ripple when a friend of theirs was in it (Involve picks those up).
##   TownLife.on_hour(h)   TownLife.on_social(pawn_id, other_id)   TownLife.ripple(pid) -> {tid, kind} or {}   recent   reset()

const PUBLIC := ["row", "arrest", "alarm", "collapse"]          # things people saw in the street; the rest (an affair, a debt, someone upset) only friends know

static var recent: Array = []          # [{kind, a, b, c, lot, day, told}] what happened, newest last
static var _rippled: Dictionary = {}   # index -> true: already reached the player as a ripple

static func reset() -> void:
	recent = []
	_rippled = {}

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
	if str(pick["kind"]) != "gathering" and Neighborhood.lot_of(f) == lot2 and not SysUtil.is_away(f) and not CrimePlace.is_asleep(f) and StreetScenes.pending.is_empty() and JusticePlayer.open == 0:
		StreetScenes.stage(f, lot2, pick)          # right here: the player sees it happen
		Involve.landed("scene: %s" % str(pick["kind"]), [int(pick["a"]), int(pick.get("b", -1))])
		return
	_offscreen(pick, lot2)

## Everyday causes the town has without any thread: two townies who already dislike each other run into each other (a row), or someone
## with friends has them round (a get-together at their home). Sampled, so it stays cheap. {} when none turned up this time.
static func _everyday(lots: Array) -> Dictionary:
	var pool: Array = Story.free_townies().filter(func(t): return Story.stage_of(t) in ["adult", "elder"] and StreetScenes._free(int(t["id"])))
	if pool.size() < 3 or lots.is_empty():
		return {}
	for _i in int(cfg().get("everyday_tries", 12)):
		var a: int = int(pool[SysUtil.rng.randi_range(0, pool.size() - 1)]["id"])
		var b: int = int(pool[SysUtil.rng.randi_range(0, pool.size() - 1)]["id"])
		if a == b:
			continue
		var fr: float = RelationshipService.value(a, b, "friendship")
		if (fr <= -10.0 or RelationshipService.value(a, b, "tension") >= 20.0) and not StreetScenes._recent("row|%d|%d" % [a, b]):
			return {"kind": "row", "a": a, "b": b, "lot": str(lots[0])}
		if fr >= 20.0 and not StreetScenes._recent("gathering|%d|-1" % a) and Neighborhood.home_of_townie(a) != "":
			return {"kind": "gathering", "a": a, "b": b, "lot": Neighborhood.home_of_townie(a)}
	return {}

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
	recent.append({"kind": kind, "a": a, "b": b, "c": int(s.get("c", -1)), "lot": lot, "day": SysUtil.day(), "told": false})
	while recent.size() > int(cfg().get("keep", 24)):
		recent.pop_front()
		_rippled.clear()

# ------------------------------------------------------------------ through people
## The pawn has just talked to `other`: if they know someone something happened to, they say so (one item per chat).
static func on_social(pid: int, other: int) -> void:
	if not Pawn.is_pawn_id(pid) or other < 0:
		return
	for i in range(recent.size() - 1, -1, -1):
		var e: Dictionary = recent[i]
		if bool(e["told"]) or SysUtil.day() - int(e["day"]) > 4:
			continue
		var near: bool = other in [int(e["a"]), int(e["b"]), int(e["c"])] or (str(e["kind"]) in PUBLIC and SysUtil.rng.randf() < 0.5)          # a public scene: anyone in town may have heard
		for who in [int(e["a"]), int(e["b"])]:
			if who >= 0 and RelationshipService.value(other, who, "friendship") >= 10.0:
				near = true
		if not near:
			continue
		e["told"] = true
		SysUtil.notify("%s: \"%s\"" % [Story.name_of(other).get_slice(" ", 0), _gossip(e, other)], "story")
		return

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
