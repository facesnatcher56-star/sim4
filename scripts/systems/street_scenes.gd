class_name StreetScenes
extends RefCounted
## Task 65: while the pawn is out, real things between real townies happen where it can see them (data/street_scenes.json). Never invented:
## each scene comes from a real state (a TownDrama thread: a feud, tension, a family rift, an affair, a debt, an addiction, a failing business;
## or somebody on the lot right now, who collapses). The people walk in from the gate (Crowd) and act it out; the player steps in, watches or
## walks away, and that feeds the normal systems (friendship, grudges, tension, history, a hospital stay). Task 66: no timer of its own; the town's
## events (TownLife) play here when the pawn is on their lot, and the involvement director (Involve) may pick one.
##   StreetScenes.play(f, lot) / party(f) -> landed   cause(kind, f, lot)   stage(f, lot, s)   StreetScenes.on_minute() (the cue)   reset()

const TITLE := "Out here"

static var last_people: Array = []     # the townies of the last scene staged (Involve counts them as in a pull)
static var _used: Dictionary = {}       # "kind|a|b" -> day: one scene per thread a day
static var pending: Dictionary = {}     # a scene on its way: {f, s, v, opts, text, since} until its people are in view of the pawn

static func reset() -> void:
	_used = {}
	pending = {}

static func cfg() -> Dictionary:
	return SysUtil.table("street_scenes")

static func _line(k: String, v: Dictionary) -> String:
	var lines: Array = (cfg().get("lines", {}) as Dictionary).get(k, [""])
	var t: String = str(lines[PlayerPrompt._pick("scene|" + k, lines.size())])
	for key in v:
		t = t.replace("{%s}" % key, str(v[key]))
	return t

static func _first(tid: int) -> String:
	return Story.name_of(tid).get_slice(" ", 0)

# ------------------------------------------------------------------ the clock
static func on_minute() -> void:
	if not pending.is_empty():
		_cue(SysUtil.now())

static func busy() -> bool:
	return not pending.is_empty()

## Pick a kind by weight among those that have a real cause here and now, and play it in front of the pawn.
static func play(f, lot: String) -> bool:
	var cands: Array = []
	var ws: Array = []
	for kind in (cfg().get("weights", {}) as Dictionary):
		var s: Dictionary = cause(str(kind), f, lot)
		if not s.is_empty():
			cands.append(s)
			ws.append(float(cfg()["weights"][kind]))
	var pick = SysUtil.pick_weighted(cands, ws)
	if pick == null:
		return false
	stage(f, lot, pick)
	return true

## A uniformed officer from the station walks in from the lot's gate (a real Folk on the map, like the station's own staff) and leaves again with the
## suspect: the crowd's normal walk out of the gate, never a vanishing.
static func _officer_walks_in(lot: String, near: Vector2i):
	var cop = Crowd._spawn_staff("police_officer", Crowd.free_near(NeighborhoodLots.gate_tile(lot)), lot)
	if cop == null:
		return null
	cop.remove_meta("staff")
	cop.remove_meta("staff_lot")
	cop.clear_queue()
	cop.cancel_current("on a call")
	cop.set_meta("crowd", lot)
	cop.set_meta("arrived_min", SimEnv.now_min())
	cop.set_meta("leave_min", SimEnv.now_min() + 30)
	cop.idle_until_min = CrowdDrive.NEVER
	cop.set_meta("next_act", SimEnv.now_min() + 30)
	var go := Interaction.create_goto(cop, Crowd.free_near(near), false)
	if go != null:
		go.def = go.def.duplicate(true)
		go.def["priority"] = "high"
		cop.enqueue(go)
	return cop

## At home in the evening: the neighbour (a real townie next door) has real friends round at their house, and the music carries. Once a day at most.
static func party(f) -> bool:
	var h: float = SysUtil.hour_f()
	var nb: int = SoloOpening.neighbour
	if h < 19.0 or h >= 23.0 or nb < 0 or not _free(nb) or int(_used.get("party", -1)) == SysUtil.day() or Neighborhood.lot_of(f) != Neighborhood.HOME:
		return false
	var lot: String = Neighborhood.home_of_townie(nb)
	if lot == "" or lot == Neighborhood.HOME:
		return false
	var friends: Array = Story.free_townies().filter(func(t): return int(t["id"]) != nb and _free(int(t["id"])) and RelationshipService.value(nb, int(t["id"]), "friendship") >= 20.0)
	if friends.size() < 2:
		return false
	_used["party"] = SysUtil.day()
	var people: Array = [nb]
	for t2 in friends.slice(0, 3):
		people.append(int(t2["id"]))
	for tid in people:
		if SysUtil.folk(int(tid)) == null:
			Crowd.spawn_npc(Story.townies[int(tid)], lot, "townie_home", int(cfg().get("party_min", 150)), true)
	var v: Dictionary = {"a": _first(nb), "b": "", "c": "", "place": Neighborhood.label_of(lot)}
	JusticePlayer.ask(int(f.id), TITLE, _line("party", v),
		[{"id": "go", "label": "Go round"}, {"id": "wall", "label": "Bang on the wall"}, {"id": "walk", "label": "Put up with it"}],
		func(ch): _party_answer(f, nb, lot, v, str(ch)), "walk")
	return true

static func _party_answer(f, nb: int, lot: String, v: Dictionary, ch: String) -> void:
	match ch:
		"go":
			Commands.run({"player_id": Players.local_id, "folk_id": int(f.id), "action": "travel", "args": {"folk_ids": [int(f.id)], "lot_id": lot}})          # their front door: the normal door flow (DoorActs)
		"wall":
			SysUtil.notify(_line("party_wall", v), "story")
			RelationshipService.add_both(int(f.id), nb, "friendship", -4.0)
			RelationshipService.add_value(int(f.id), nb, "tension", 15.0)
		_:
			SysUtil.notify(_line("party_bear", v), "story")

## A townie who has gone home to rest: they leave the lot (walking out of the gate) and are out of town life for `days`.
static func _laid_up(tid: int, days: int) -> void:
	var p = SysUtil.folk(tid)
	if p != null and p.has_meta("crowd"):
		Crowd.start_leaving(p)
	if Story.townies.has(tid):
		Story.townies[tid]["missing_until"] = SysUtil.day() + days

## A free townie (alive, not held, not in hospital) who is not on the map somewhere else.
## The key a scene is remembered under (the same one cause() checks with _recent), whether it played in front of the pawn or off-screen.
static func key_of(s: Dictionary) -> String:
	match str(s["kind"]):
		"upset", "alarm":
			return "%s|%d" % [str(s["kind"]), int(s["a"])]
		"gathering":
			return "gathering|%d|-1" % int(s["a"])
		"theft", "break_in", "drunk":
			return "%s|%d" % ["theft" if str(s["kind"]) == "break_in" else str(s["kind"]), int(s["a"])]
		"arrest":
			return "arrest|%d" % int(s.get("case", -1))
		"collapse":
			return "collapse|%d|-1" % int(s["a"])
	return "%s|%d|%d" % [str(s["kind"]), int(s["a"]), int(s.get("b", -1))]

## A thread or pair already shown lately (task 66: not the same two people rowing every day).
static func _recent(key: String) -> bool:
	return SysUtil.day() - int(_used.get(key, -99)) < int(cfg().get("again_days", 3))

static func _free(tid: int) -> bool:
	if tid < 0 or not Story.townies.has(tid):
		return false
	var t: Dictionary = Story.townies[tid]
	if not bool(t["alive"]) or JusticeState.inmates.has(tid) or Hospital.is_in(tid) or Story.stage_of(t) not in ["adult", "elder", "teen"] or int(t.get("missing_until", 0)) > SysUtil.day():          # (resting at home after a collapse too)
		return false
	if not Involve.fresh(tid) or not TownLife.rested(tid):
		return false          # task 66c: just in a pull, or just in something in town: someone else this time
	var on = SysUtil.folk(tid)
	return on == null or on.has_meta("crowd")

static func cause(kind: String, f, lot: String) -> Dictionary:
	match kind:
		"row":
			for th in TownDrama.threads:
				if str(th["kind"]) in ["feud", "tension", "family"] and _free(int(th["a"])) and _free(int(th["b"])) and not _recent("row|%d|%d" % [th["a"], th["b"]]):
					return {"kind": "row", "a": int(th["a"]), "b": int(th["b"])}
			var here: Array = Crowd.crowd_folk(lot)          # or two people on this lot right now who really can't stand each other
			for i in here.size():
				for j in range(i + 1, here.size()):
					var x: int = int(here[i].get_meta("townie_id", -1))
					var y: int = int(here[j].get_meta("townie_id", -1))
					if x >= 0 and y >= 0 and _free(x) and _free(y) and (RelationshipService.value(x, y, "friendship") <= -15.0 or RelationshipService.value(x, y, "tension") >= 30.0) and not _recent("row|%d|%d" % [x, y]):
						return {"kind": "row", "a": x, "b": y}
		"affair":
			for af in RelationshipService.affairs:
				var a: int = int(af.get("cheater", -1))
				var b: int = int(af.get("other", -1))
				var c: int = int(af.get("victim", -1))
				if _free(a) and _free(b) and _free(c) and not _recent("affair|%d|%d" % [a, b]):
					return {"kind": "affair", "a": a, "b": b, "c": c}
		"debt":
			for th2 in TownDrama.threads:
				if str(th2["kind"]) == "debt" and _free(int(th2["a"])) and _free(int(th2["b"])) and (SysUtil.hour_f() >= 19.0 or SoloDistricts.rough_at(lot) > 0.4) and not _recent("debt|%d|%d" % [th2["a"], th2["b"]]):
					return {"kind": "debt", "a": int(th2["a"]), "b": int(th2["b"])}
		"upset":
			for th3 in TownDrama.threads:
				if str(th3["kind"]) in ["family", "addiction", "business"] and _free(int(th3["a"])) and not _recent("upset|%d" % int(th3["a"])):
					return {"kind": "upset", "a": int(th3["a"]), "b": -1}
		"arrest":
			for c in CaseStore.open_cases():          # the police are about to pick someone up: their top suspect, well into the case
				var sus: Array = c.get("suspect_ids", [])
				if str(c["state"]) != "open" or sus.is_empty() or not _free(int(sus[0])) or _recent("arrest|%d" % int(c["id"])):
					continue
				if float(c.get("progress", 0.0)) >= float(cfg().get("arrest_progress", 0.5)):
					return {"kind": "arrest", "a": int(sus[0]), "b": -1, "case": int(c["id"])}
		"alarm":
			if VehicleBays.of(lot).is_empty() or (SysUtil.hour_f() >= 6.0 and SysUtil.hour_f() < 19.0 and SoloDistricts.rough_at(lot) <= 0.4):
				return {}          # parked cars here, and dark or a rough block
			for th4 in TownDrama.threads:
				if str(th4["kind"]) == "crew" and _free(int(th4["a"])) and not _recent("alarm|%d" % int(th4["a"])):
					return {"kind": "alarm", "a": int(th4["a"]), "b": -1}
			for t5 in Story.free_townies():          # or anyone with a record for it
				var tid5: int = int(t5["id"])
				if not JusticeRecords.convictions(tid5).is_empty() and _free(tid5) and not _recent("alarm|%d" % tid5):
					return {"kind": "alarm", "a": tid5, "b": -1}
		"collapse":
			for p in Crowd.crowd_folk(lot):
				if not p.has_meta("leaving") and (p.tile - f.tile).length() < 14.0 and Story.stage_of(Story.townies.get(int(p.get_meta("townie_id", -1)), {})) == "elder" and not _recent("collapse|%d|-1" % int(p.get_meta("townie_id", -1))):
					return {"kind": "collapse", "a": int(p.get_meta("townie_id", -1)), "b": -1}
	return {}

# ------------------------------------------------------------------ on stage
static func stage(f, lot: String, s: Dictionary) -> void:
	last_people = [int(s["a"]), int(s.get("b", -1)), int(s.get("c", -1))].filter(func(x): return x >= 0)
	var kind: String = str(s["kind"])
	_used[key_of(s)] = SysUtil.day()
	var people: Array = []
	for key in ["a", "b", "c"]:
		if int(s.get(key, -1)) >= 0:
			people.append(_bring(int(s[key]), lot, f.tile + Vector2i(3 + people.size(), 2)))
	var v: Dictionary = {"a": _first(int(s["a"])), "b": _first(int(s.get("b", -1))) if int(s.get("b", -1)) >= 0 else "", "c": _first(int(s.get("c", -1))) if int(s.get("c", -1)) >= 0 else "", "place": Neighborhood.label_of(lot)}
	if kind == "arrest":
		var cop = _officer_walks_in(lot, f.tile + Vector2i(4, 2))
		s["cop"] = int(cop.id) if cop != null else -1
		v["b"] = str(cop.name).get_slice(" ", 0) if cop != null else "A police officer"
	var opts: Array = []
	var text: String = ""
	match kind:
		"row", "affair", "debt":
			var fight: bool = kind == "row" and (SysUtil.hour_f() >= 21.0 or SoloDistricts.rough_at(lot) > 0.5)
			text = _line("row_fight" if fight else kind, v)
			if people.size() >= 2 and people[0] != null and people[1] != null:
				var ir := Interaction.create("yell_at" if fight else "argue", people[0], int(people[1].id), false)
				if ir != null:
					ir.def = ir.def.duplicate(true)
					ir.def["priority"] = "high"
					people[0].enqueue(ir)
			opts = [{"id": "step", "label": "Step in"}, {"id": "watch", "label": "Watch"}, {"id": "walk", "label": "Walk away"}]
		"upset":
			text = _line("upset", v)
			opts = [{"id": "comfort", "label": "Sit with them"}, {"id": "walk", "label": "Leave them be"}]
		"arrest":
			text = _line("arrest", v)
			opts = [{"id": "watch", "label": "Watch"}, {"id": "vouch", "label": "Speak up for %s" % v["a"]}, {"id": "walk", "label": "Walk away"}]
		"alarm":
			text = _line("alarm", v)
			opts = [{"id": "shout", "label": "Shout at them"}, {"id": "police", "label": "Call the police"}, {"id": "walk", "label": "Keep out of it"}]
		"collapse":
			var p0 = SysUtil.folk(int(s["a"]))
			if p0 != null:
				p0.cancel_current("collapsed")
				p0.clear_queue()
			text = _line("collapse", v)
			opts = [{"id": "ambulance", "label": "Call an ambulance"}, {"id": "help", "label": "Help them up"}, {"id": "walk", "label": "Walk on"}]
	pending = {"f": f, "s": s, "v": v, "opts": opts, "text": text, "since": SysUtil.now(), "lot": lot}          # the line comes when they are in view (_cue)

## The scene's people have walked over (within a few tiles of the pawn), or a quarter of an hour has passed: now the player sees it happen.
static func _cue(now: int) -> void:
	var p: Dictionary = pending
	var f = p["f"]
	var s: Dictionary = p["s"]
	var a = SysUtil.folk(int(s["a"]))
	var near: bool = a != null and f != null and (a.tile - f.tile).length() <= 5.0
	if not near and now < int(p["since"]) + 15:
		return
	pending = {}
	if f == null or Neighborhood.lot_of(f) != str(p["lot"]):
		return          # the pawn has gone: the scene plays out without them
	if str(s["kind"]) == "arrest":
		var c: Dictionary = CaseStore.get_case(int(s.get("case", -1)))
		if not c.is_empty() and str(c["state"]) == "open":
			JusticeProcess.arrest(c, int(s["a"]))          # the real arrest, in front of the pawn
			for who in [int(s["a"]), int(s.get("cop", -1))]:          # the officer walks them off the lot
				var sf = SysUtil.folk(who)
				if sf != null and sf.has_meta("crowd"):
					Crowd.start_leaving(sf)
	SysUtil.game_event("street_scene", {"kind": str(s["kind"]), "a": int(s["a"]), "b": int(s.get("b", -1)), "lot": str(p["lot"])})
	JusticePlayer.ask(int(f.id), TITLE, str(p["text"]), p["opts"], func(ch): _choose(f, s, p["v"], str(ch)), "walk")

## The townie on the map at the pawn's lot: already there as a customer, or walking in from the gate now (never popping up beside the pawn).
static func _bring(tid: int, lot: String, near: Vector2i):
	var on = SysUtil.folk(tid)
	if on == null:
		var vt: String = Venues.type_of_lot(lot)
		on = Crowd.spawn_npc(Story.townies[tid], lot, vt if vt != "" else "park", int(cfg().get("stay_min", 40)), true)
	if on != null:
		on.clear_queue()
		var go := Interaction.create_goto(on, Crowd.free_near(near), false)
		if go != null:
			go.def = go.def.duplicate(true)
			go.def["priority"] = "high"
			on.enqueue(go)
	return on

static func _friend(a: int, b: int, key: String) -> void:
	var d: float = float((cfg().get("friendship", {}) as Dictionary).get(key, 0.0))
	if d != 0.0 and a >= 0 and b >= 0:
		RelationshipService.add_both(a, b, "friendship", d)

static func _choose(f, s: Dictionary, v: Dictionary, ch: String) -> void:
	var pid: int = int(f.id)
	var a: int = int(s["a"])
	var b: int = int(s.get("b", -1))
	match ch:
		"step":
			var r: Dictionary = SkillCheck.attempt(pid, "calm_down" if str(s["kind"]) != "debt" else "threaten", {"opponent": b} if str(s["kind"]) == "debt" else {})
			if bool(r["ok"]):
				SysUtil.notify(_line("debt_ok" if str(s["kind"]) == "debt" else "calm_ok", v), "story")
				_friend(pid, a, "helped")
				if str(s["kind"]) != "debt":
					_friend(pid, b, "helped")
					RelationshipService.add_value(a, b, "tension", -20.0)
				else:
					RelationshipService.add_both(pid, b, "friendship", -6.0)          # the collector remembers you
			else:
				SysUtil.notify(_line("debt_fail" if str(s["kind"]) == "debt" else "calm_fail", v), "bad")
				_friend(pid, b if str(s["kind"]) == "debt" else a, "dragged_in")
			RelationshipService.add_history(pid, a, "stepped_in", 0.4 if bool(r["ok"]) else -0.2, pid)
		"watch":
			SysUtil.notify(_line("watched", v), "story")
			RelationshipService.add_history(pid, a, "saw_scene", 0.0, a)          # a witness: they know what happened (gossip, a case)
			if b >= 0:
				RelationshipService.add_history(pid, b, "saw_scene", 0.0, b)
			if str(s["kind"]) == "affair":
				RelationshipBits.set_flag(pid, a, "knows_affair", true, false)
		"comfort":
			if SysUtil.rng.randf() < 0.75:
				SysUtil.notify(_line("comfort", v), "relationship")
				_friend(pid, a, "comforted")
				RelationshipService.add_history(pid, a, "stepped_in", 0.5, pid)
			else:
				SysUtil.notify(_line("comfort_no", v), "story")
				_friend(pid, a, "brushed_off")
		"ambulance":
			SysUtil.notify(_line("ambulance", v), "story")
			_friend(pid, a, "ambulance")
			RelationshipService.add_history(pid, a, "stepped_in", 0.6, pid)
			var p = SysUtil.folk(a)
			if p != null and p.has_meta("crowd"):
				Crowd.dismiss(p)
			Hospital.admit(a, 2, "collapsed in the street")
		"help":
			SysUtil.notify(_line("helped_up", v), "story")
			_friend(pid, a, "helped")
			RelationshipService.add_history(pid, a, "stepped_in", 0.5, pid)
			_laid_up(a, int(cfg().get("rest_days", 2)))          # they go home to rest: out of things for a while
		"vouch":
			SysUtil.notify(_line("vouch", v), "story")
			_friend(pid, a, "helped")
			var c2: Dictionary = CaseStore.get_case(int(s.get("case", -1)))
			if not c2.is_empty():
				CaseStore.note(c2, "%s spoke up for %s at the arrest." % [str(f.name), Story.name_of(a)], "", 1, false)
		"shout":
			var r2: Dictionary = SkillCheck.attempt(pid, "threaten", {"opponent": a})
			SysUtil.notify(_line("alarm_ok" if bool(r2["ok"]) else "alarm_fail", v), "story" if bool(r2["ok"]) else "bad")
			RelationshipService.add_both(pid, a, "friendship", -5.0)
			RelationshipService.add_history(pid, a, "saw_scene", -0.3, a)
		"police":
			SysUtil.notify(_line("alarm_police", v), "story")
			RelationshipService.add_history(pid, a, "saw_scene", -0.3, a)
			CrimePetty.commit("vandalism", a, "venue:" + Neighborhood.lot_of(f), {"seen": true, "trace": 0.5})          # a witness on the phone: a real case
		_:
			SysUtil.notify(_line("walked", v), "story")
			if str(s["kind"]) == "collapse":          # somebody else calls it in
				SysUtil.notify(_line("someone_called", v), "story")
				var p2 = SysUtil.folk(a)
				if p2 != null and p2.has_meta("crowd"):
					Crowd.dismiss(p2)
				Hospital.admit(a, 2, "collapsed in the street")
