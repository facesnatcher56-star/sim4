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
	if f == null or lot == "" or lot == Neighborhood.HOME or SysUtil.is_away(f) or CrimePlace.is_asleep(f):
		next_min = -1          # at home or away: the next outing starts its own clock
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
	SysUtil.notify(str(p["text"]), "story")
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
		_:
			SysUtil.notify(_line("walked", v), "story")
