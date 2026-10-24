class_name StreetScenes
extends RefCounted
## Task 65: while the pawn is out, real things between real townies happen where it can see them (data/street_scenes.json). Never invented:
## each scene comes from a real state (a TownDrama thread: a feud, tension, a family rift, an affair, a debt, an addiction, a failing business;
## or somebody on the lot right now, who collapses). The people walk in from the gate (Crowd) and act it out; the player steps in, watches or
## walks away, and that feeds the normal systems (friendship, grudges, tension, history, a hospital stay). About one scene an hour out,
## sooner in a rough district and at night.   StreetScenes.on_minute()   StreetScenes.reset()

const TITLE := "Out here"

static var next_min: int = -1           # the earliest minute of the next scene on this outing
static var _last_check: int = -1
static var _used: Dictionary = {}       # "kind|a|b" -> day: one scene per thread a day
static var pending: Dictionary = {}     # a scene on its way: {f, s, v, opts, text, since} until its people are in view of the pawn

static func reset() -> void:
	next_min = -1
	_last_check = -1
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
	var now: int = SysUtil.now()
	if not pending.is_empty():
		_cue(now)
		return
	if now - _last_check < int(cfg().get("check_min", 10)):
		return
	_last_check = now
	var f = SysUtil.folk(Pawn.of()) if SoloHome.active and Pawn.of() >= 0 else null
	var lot: String = Neighborhood.lot_of(f) if f != null else ""
	if f != null and lot == Neighborhood.HOME and not SysUtil.is_away(f) and not CrimePlace.is_asleep(f):
		next_min = -1
		_party_next_door(f)          # at home in the evening: the neighbours may have people round
		return
	if f == null or lot == "" or lot == Neighborhood.HOME or SysUtil.is_away(f) or CrimePlace.is_asleep(f):
		next_min = -1          # away: the next outing starts its own clock
		return
	if next_min < 0:
		next_min = now + _gap(lot)
		return
	if now < next_min:
		return
	if _play(f, lot):
		next_min = now + _gap(lot)
	else:
		next_min = now + 15          # nothing real to show here right now: look again soon

static func _gap(lot: String) -> int:
	var g: Array = cfg().get("gap_min", [45, 75])
	var m: float = float(SysUtil.rng.randi_range(int(g[0]), int(g[1])))
	if SoloDistricts.rough_at(lot) > 0.5:
		m *= float(cfg().get("rough_mult", 0.6))
	if SysUtil.hour_f() >= 20.0 or SysUtil.hour_f() < 5.0:
		m *= float(cfg().get("night_mult", 0.75))
	return int(m)

## Pick a kind by weight among those that have a real cause here and now, and play it.
static func _play(f, lot: String) -> bool:
	var cands: Array = []
	var ws: Array = []
	for kind in (cfg().get("weights", {}) as Dictionary):
		var s: Dictionary = _cause(str(kind), f, lot)
		if not s.is_empty():
			cands.append(s)
			ws.append(float(cfg()["weights"][kind]))
	var pick = SysUtil.pick_weighted(cands, ws)
	if pick == null:
		return false
	_stage(f, lot, pick)
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
static func _party_next_door(f) -> void:
	var h: float = SysUtil.hour_f()
	var nb: int = SoloOpening.neighbour
	if h < 19.0 or h >= 23.0 or nb < 0 or not _free(nb) or int(_used.get("party", -1)) == SysUtil.day():
		return
	if SysUtil.rng.randf() >= float(cfg().get("party_chance", 0.15)):
		return
	var lot: String = Neighborhood.home_of_townie(nb)
	if lot == "" or lot == Neighborhood.HOME:
		return
	var friends: Array = Story.free_townies().filter(func(t): return int(t["id"]) != nb and _free(int(t["id"])) and RelationshipService.value(nb, int(t["id"]), "friendship") >= 20.0)
	if friends.size() < 2:
		return
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

## A free townie (alive, not held, not in hospital) who is not on the map somewhere else.
static func _free(tid: int) -> bool:
	if tid < 0 or not Story.townies.has(tid):
		return false
	var t: Dictionary = Story.townies[tid]
	if not bool(t["alive"]) or JusticeState.inmates.has(tid) or Hospital.is_in(tid) or Story.stage_of(t) not in ["adult", "elder", "teen"]:
		return false
	var on = SysUtil.folk(tid)
	return on == null or on.has_meta("crowd")

static func _cause(kind: String, f, lot: String) -> Dictionary:
	var day: int = SysUtil.day()
	match kind:
		"row":
			for th in TownDrama.threads:
				if str(th["kind"]) in ["feud", "tension", "family"] and _free(int(th["a"])) and _free(int(th["b"])) and int(_used.get("row|%d|%d" % [th["a"], th["b"]], -1)) != day:
					return {"kind": "row", "a": int(th["a"]), "b": int(th["b"])}
			var here: Array = Crowd.crowd_folk(lot)          # or two people on this lot right now who really can't stand each other
			for i in here.size():
				for j in range(i + 1, here.size()):
					var x: int = int(here[i].get_meta("townie_id", -1))
					var y: int = int(here[j].get_meta("townie_id", -1))
					if x >= 0 and y >= 0 and (RelationshipService.value(x, y, "friendship") <= -15.0 or RelationshipService.value(x, y, "tension") >= 30.0) and int(_used.get("row|%d|%d" % [x, y], -1)) != day:
						return {"kind": "row", "a": x, "b": y}
		"affair":
			for af in RelationshipService.affairs:
				var a: int = int(af.get("cheater", -1))
				var b: int = int(af.get("other", -1))
				var c: int = int(af.get("victim", -1))
				if _free(a) and _free(b) and _free(c) and int(_used.get("affair|%d|%d" % [a, b], -1)) != day:
					return {"kind": "affair", "a": a, "b": b, "c": c}
		"debt":
			for th2 in TownDrama.threads:
				if str(th2["kind"]) == "debt" and _free(int(th2["a"])) and _free(int(th2["b"])) and (SysUtil.hour_f() >= 19.0 or SoloDistricts.rough_at(lot) > 0.4) and int(_used.get("debt|%d|%d" % [th2["a"], th2["b"]], -1)) != day:
					return {"kind": "debt", "a": int(th2["a"]), "b": int(th2["b"])}
		"upset":
			for th3 in TownDrama.threads:
				if str(th3["kind"]) in ["family", "addiction", "business"] and _free(int(th3["a"])) and int(_used.get("upset|%d" % int(th3["a"]), -1)) != day:
					return {"kind": "upset", "a": int(th3["a"]), "b": -1}
		"arrest":
			for c in CaseStore.open_cases():          # the police are about to pick someone up: their top suspect, well into the case
				var sus: Array = c.get("suspect_ids", [])
				if str(c["state"]) != "open" or sus.is_empty() or not _free(int(sus[0])) or int(_used.get("arrest|%d" % int(c["id"]), -1)) == day:
					continue
				if float(c.get("progress", 0.0)) >= float(cfg().get("arrest_progress", 0.5)):
					return {"kind": "arrest", "a": int(sus[0]), "b": -1, "case": int(c["id"])}
		"alarm":
			if VehicleBays.of(lot).is_empty() or (SysUtil.hour_f() >= 6.0 and SysUtil.hour_f() < 19.0 and SoloDistricts.rough_at(lot) <= 0.4):
				return {}          # parked cars here, and dark or a rough block
			for th4 in TownDrama.threads:
				if str(th4["kind"]) == "crew" and _free(int(th4["a"])) and int(_used.get("alarm|%d" % int(th4["a"]), -1)) != day:
					return {"kind": "alarm", "a": int(th4["a"]), "b": -1}
			for t5 in Story.free_townies():          # or anyone with a record for it
				var tid5: int = int(t5["id"])
				if not JusticeRecords.convictions(tid5).is_empty() and _free(tid5) and int(_used.get("alarm|%d" % tid5, -1)) != day:
					return {"kind": "alarm", "a": tid5, "b": -1}
		"collapse":
			for p in Crowd.crowd_folk(lot):
				if not p.has_meta("leaving") and (p.tile - f.tile).length() < 14.0 and Story.stage_of(Story.townies.get(int(p.get_meta("townie_id", -1)), {})) == "elder":
					return {"kind": "collapse", "a": int(p.get_meta("townie_id", -1)), "b": -1}
	return {}

# ------------------------------------------------------------------ on stage
static func _stage(f, lot: String, s: Dictionary) -> void:
	var kind: String = str(s["kind"])
	_used["%s|%d|%d" % [kind, int(s["a"]), int(s["b"])] if kind != "upset" else "upset|%d" % int(s["a"])] = SysUtil.day()
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
			else:
				SysUtil.notify(_line("comfort_no", v), "story")
				_friend(pid, a, "brushed_off")
		"ambulance":
			SysUtil.notify(_line("ambulance", v), "story")
			_friend(pid, a, "ambulance")
			var p = SysUtil.folk(a)
			if p != null and p.has_meta("crowd"):
				Crowd.dismiss(p)
			Hospital.admit(a, 2, "collapsed in the street")
		"help":
			SysUtil.notify(_line("helped_up", v), "story")
			_friend(pid, a, "helped")
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
