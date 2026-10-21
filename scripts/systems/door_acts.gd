class_name DoorActs
extends RefCounted
## Tasks 49 / 53: the doors of private homes. Walking to somebody else's home ends at their front door; the player is offered Knock, Wait, Try the door, Leave, and
## once they have found the door locked BY TRYING IT: Pick the lock, Force it, Break a window. Nothing tells them whether anyone is home or whether the door is
## locked: not answering looks the same as nobody home, and a locked door is only known after trying it. A resident who is home and awake answers by how they feel about
## the visitor, the hour and their nature. Getting in uninvited is trespassing: a resident who is home and awake notices after a minute or two and reacts (scream, order
## you out, grab something, flee, call the police), and the player answers (leave, run, hide, fight). Every way in makes its own noise. Numbers and lines: data/doors.json.
##   DoorActs.private_lot(lot, f)    DoorActs.arrive(f, lot)    DoorActs.entries(f, lot)    DoorActs.notice(p)  (queued: a resident notices an intruder)

static var known_locked: Dictionary = {}          # "fid|lot" -> true once the door was tried
static var forced: Dictionary = {}                # lot -> day the door was forced / picked open (stays open that day)
static var intruders: Dictionary = {}             # fid -> lot id they are in without being invited
static var working: Dictionary = {}               # fid -> {lot, act, r}: an attempt under way (it takes the minutes the skill says)

static func reset() -> void:
	known_locked = {}
	forced = {}
	intruders = {}
	working = {}

static func cfg() -> Dictionary:
	return SysUtil.table("doors")

## Somebody else's home (a townie home that is not the player's own).
static func private_lot(lot_id: String, f = null) -> bool:
	if str(Neighborhood.lot(lot_id).get("type", "")) != "townie_home":
		return false
	return f == null or lot_id != PlayerLots.home_of(f)

## A lot whose door the player's person has to deal with: somebody else's home, or a place that is shut now (a closed shop has a locked door).
static func door_lot(lot_id: String, f = null) -> bool:
	if private_lot(lot_id, f):
		return true
	return lot_id != Neighborhood.HOME and str(Neighborhood.lot(lot_id).get("type", "")) != "townie_home" and not Venues.is_open(lot_id) and Venues.type_of_lot(lot_id) not in ["park", "home"]

static func _frac(lot_id: String, salt: String) -> float:
	return float(absi(hash("%s|%d|%s" % [lot_id, SysUtil.day(), salt])) % 1000) / 1000.0

static func night() -> bool:
	var h: float = SysUtil.hour_f()
	return h >= float(cfg().get("awake_to", 23)) - 2.0 or h < float(cfg().get("awake_from", 7))

static func is_locked(lot_id: String) -> bool:
	if int(forced.get(lot_id, -1)) == SysUtil.day():
		return false
	if str(Neighborhood.lot(lot_id).get("type", "")) != "townie_home":
		return true          # a closed shop or office is locked
	var lc: Dictionary = cfg().get("lock_chance", {})
	return _frac(lot_id, "lock") < float(lc.get("night" if night() else "day", 0.3))

## Townies who live here, are not at work and are up (the ones who could hear the door).
static func awake_residents(lot_id: String) -> Array:
	var out: Array = []
	var h: float = SysUtil.hour_f()
	if h < float(cfg().get("awake_from", 7)) or h >= float(cfg().get("awake_to", 23)):
		return out
	for t in Neighborhood.residents_of(lot_id):
		if Story.stage_of(t) in ["adult", "elder", "teen"] and CommuteTownies.lot_now(int(t["id"])) == "":
			out.append(t)
	return out

static func _line(key: String, who: String = "", extra: Dictionary = {}) -> String:
	var lines: Array = cfg().get("lines", {}).get(key, [""])
	var text: String = str(lines[PlayerPrompt._pick("door|" + key, lines.size())])
	return text.replace("{r}", who)

static func _say(f, text: String) -> void:
	SysUtil.notify(text, "story")

# ------------------------------------------------------------------ arriving at the door
## The pawn reached the street in front of somebody's home: it stops there and the door options come up (no "closed", no walking home by itself).
static func arrive(f, lot_id: String) -> void:
	if str(f.get_meta("door_walk", "")) == lot_id or (str(f.get_meta("at_door", "")) == lot_id and f.tile == doorstep(lot_id)):
		return          # already on the way up the path to this door, or already standing on its step
	f.cancel_current("at_the_door")
	f.clear_queue()
	f.set_meta("at_door", lot_id)
	var step: Vector2i = doorstep(lot_id)
	if f.tile == step or not NeighborhoodLots.walk_to(f, step, ""):
		SysUtil.game_event("doorstep", {"folk_id": int(f.id), "lot_id": lot_id})
		return
	f.set_meta("door_walk", lot_id)          # the door options come up once the pawn stands on the step (on_interaction_finished)

## The step outside the lot's front door: the outdoor walkable tile next to a ground-floor door of the lot, the one nearest the street.
## Falls back to the lot's street tile when the lot has no door object (an unbuilt plot).
static func doorstep(lot_id: String) -> Vector2i:
	var street: Vector2i = NeighborhoodLots.street_tile(lot_id)
	var w = WorldIface.world()
	if w == null:
		return street
	var rc: Rect2i = NeighborhoodLots.rect_of(lot_id)
	var best: Vector2i = street
	var best_d: int = 1 << 30
	for o in w.objects_of_def("door"):
		if ("level" in o and int(o.level) != 0) or not rc.has_point(o.tile):
			continue
		for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var t: Vector2i = o.tile + dv
			if rc.has_point(t) and w.is_walkable(t) and w.is_outdoor(t):
				var d: int = (t - street).length_squared()
				if d < best_d:
					best_d = d
					best = t
	return best

static func entries(f, lot_id: String) -> Array:
	var fid: int = int(f.id)
	var out: Array = []
	var known: bool = bool(known_locked.get("%d|%s" % [fid, lot_id], false))
	out.append({"id": "knock", "label": "Knock", "category": "Door", "enabled": true, "reason": "", "action": func(): knock(f, lot_id)})
	out.append({"id": "try_door", "label": "Try the door", "category": "Door", "enabled": true, "reason": "", "action": func(): try_door(f, lot_id)})
	if known:
		out.append({"id": "pick_lock", "label": "Pick the lock", "category": "Door", "enabled": true, "reason": "", "action": func(): pick(f, lot_id)})
		out.append({"id": "force_door", "label": "Force the door", "category": "Door", "enabled": true, "reason": "", "action": func(): force(f, lot_id)})
		out.append({"id": "break_window", "label": "Break a window", "category": "Door", "enabled": true, "reason": "", "action": func(): window(f, lot_id)})
	out.append({"id": "wait_door", "label": "Wait", "category": "Door", "enabled": true, "reason": "", "action": func(): _wait(f, lot_id)})
	out.append({"id": "leave_door", "label": "Leave", "category": "Door", "enabled": true, "reason": "", "action": func(): _leave(f, lot_id)})
	return out

## The door options come back up after an attempt that did not get the pawn in.
static func _again(f, lot_id: String) -> void:
	if str(f.get_meta("at_door", "")) == lot_id:
		SysUtil.game_event("doorstep", {"folk_id": int(f.id), "lot_id": lot_id})

static func _wait(f, lot_id: String) -> void:
	var ir: Interaction = Interaction.create("wait_here", f, -1, true)
	if ir == null:
		return
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = 10.0
	f.enqueue(ir)

static func _leave(f, lot_id: String) -> void:
	f.remove_meta("at_door")
	var away: Interaction = Interaction.create_goto(f, NeighborhoodLots.street_tile(lot_id) + Vector2i(0, 4), true, 0)
	if away != null:
		f.enqueue(away)

# ------------------------------------------------------------------ knocking
static func knock(f, lot_id: String) -> void:
	var c: Dictionary = cfg().get("answer", {})
	var hosts: Array = awake_residents(lot_id)
	if hosts.is_empty() and str(Neighborhood.lot(lot_id).get("type", "")) != "townie_home":
		var staff: Array = Crowd.staff_folk(lot_id)          # a shop that is shut: somebody still inside may answer through the door
		if not staff.is_empty() and SysUtil.rng.randf() < 0.6:
			_say(f, "%s calls through the door: \"We are closed. %s.\"" % [str(staff[0].name), Venues.status_text(lot_id)])
			_again(f, lot_id)
			return
	if hosts.is_empty():
		_say(f, _line("knock_none"))
		_again(f, lot_id)
		return
	var host: Dictionary = hosts[SysUtil.rng.randi_range(0, hosts.size() - 1)]
	var hid: int = int(host["id"])
	var fid: int = int(f.id)
	var friendship: float = RelationshipService.value(hid, fid, "friendship")
	var w_open: float = float(c.get("open", 0.35)) + friendship * float(c.get("friend_open_bonus", 0.0045)) - (float(c.get("stranger_open_malus", 0.25)) if not RelationshipService.knows(hid, fid) else 0.0)
	if SysUtil.hour_f() >= float(c.get("late_hour", 21)):
		w_open *= float(c.get("late_open_factor", 0.4))
	var w_ignore: float = float(c.get("ignore", 0.35))
	for tr in (c.get("traits_open", {}) as Dictionary):
		if SocialDynamics.has_t(hid, str(tr)):
			w_open *= float(c["traits_open"][tr])
	for tr2 in (c.get("traits_closed", {}) as Dictionary):
		if SocialDynamics.has_t(hid, str(tr2)):
			w_ignore *= float(c["traits_closed"][tr2])
	var pick = SysUtil.pick_weighted(["open", "through", "ignore"], [maxf(w_open, 0.02), float(c.get("through_door", 0.3)), w_ignore])
	var who: String = str(host.get("name", "Somebody"))
	match str(pick):
		"open":
			_say(f, _line("knock_open", who))
			RelationshipService.add_both(fid, hid, "friendship", 0.5)
			if SysUtil.rng.randf() < 0.5 + friendship * 0.004:
				_say(f, _line("invited_in", who))
				_enter(f, lot_id, true)
		"through":
			_say(f, _line("knock_through", who))
			_again(f, lot_id)
		_:
			_say(f, _line("knock_none"))          # the same words as for an empty house: you cannot tell the difference
			_again(f, lot_id)

# ------------------------------------------------------------------ the ways in
static func try_door(f, lot_id: String) -> void:
	if is_locked(lot_id):
		known_locked["%d|%s" % [int(f.id), lot_id]] = true
		_say(f, _line("locked"))
		_again(f, lot_id)
		return
	_enter(f, lot_id, false)

## The crime scene key of a lot (a townie home is "town:<n>", so its real alarm, cameras and dog apply).
static func scene_of(lot_id: String) -> String:
	for t in Neighborhood.residents_of(lot_id):
		return "town:%d" % int(t.get("lot", 0))
	return "venue:" + lot_id

static func _ctx(lot_id: String) -> Dictionary:
	return {"scene": scene_of(lot_id), "wants": "unseen"}

const WORK_LABEL := {"pick_lock": "Picking the lock", "force_door": "Forcing the door", "break_window": "Breaking a window"}

## An attempt takes the time the skill says (an expert picks a lock in a minute, a novice in ten, and every minute at the door is a minute to be seen).
## The roll is made now; what happens lands when the work is done. Cancelling it means giving up (nothing happens).
static func _attempt(f, lot_id: String, act: String) -> void:
	var r: Dictionary = SkillCheck.attempt(int(f.id), act, _ctx(lot_id))
	var ir: Interaction = Interaction.create("wait_here", f, -1, true)
	if ir == null:
		_resolve(f, lot_id, act, r)
		return
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = maxf(float(r["minutes"]), 1.0)
	ir.def["label"] = str(WORK_LABEL.get(act, "Working at the door"))
	ir.def.erase("thought")
	working[int(f.id)] = {"lot": lot_id, "act": act, "r": r}
	f.enqueue(ir)

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if iid == "go_here":
		var g = SysUtil.folk(folk_id)
		if g != null and g.has_meta("door_walk"):
			var lot: String = str(g.get_meta("door_walk"))
			g.remove_meta("door_walk")
			if str(g.get_meta("at_door", "")) == lot:
				SysUtil.game_event("doorstep", {"folk_id": folk_id, "lot_id": lot})
		return
	if iid != "wait_here" or not working.has(folk_id):
		return
	var w: Dictionary = working[folk_id]
	working.erase(folk_id)
	var f = SysUtil.folk(folk_id)
	if success and f != null and str(f.get_meta("at_door", "")) == str(w["lot"]):
		_resolve(f, str(w["lot"]), str(w["act"]), w["r"])

static func pick(f, lot_id: String) -> void:
	_attempt(f, lot_id, "pick_lock")

static func force(f, lot_id: String) -> void:
	_attempt(f, lot_id, "force_door")

static func window(f, lot_id: String) -> void:
	_attempt(f, lot_id, "break_window")

static func _resolve(f, lot_id: String, act: String, r: Dictionary) -> void:
	var cat: bool = str(r["grade"]) == "catastrophic"
	var act_min: float = float((SysUtil.table("skills").get("acts", {}) as Dictionary).get(act, {}).get("minutes", 5))
	_noise(lot_id, 1.0 - pow(1.0 - float(r["noise"]), maxf(float(r["minutes"]) / act_min, 0.5)))
	if act == "break_window":
		CrimePetty.commit("vandalism", int(f.id), "venue:" + lot_id, {"seen": bool(r["alarm"]), "trace": float(r["trace"])})
	elif cat:
		CrimePetty.commit("vandalism", int(f.id), "venue:" + lot_id, {"seen": bool(r["alarm"]), "trace": float(r["trace"])})
	if bool(r["ok"]):
		if act != "break_window":
			forced[lot_id] = SysUtil.day()
		_say(f, {"pick_lock": "The lock clicks.", "force_door": "The door gives way with a crack.", "break_window": "Glass breaks. You climb in."}[act])
		_enter(f, lot_id, false)
		return
	if not cat:
		_say(f, {"pick_lock": "The lock will not give.", "force_door": "The door holds. That hurt.", "break_window": "Glass breaks, but the frame is too small."}[act])
	if act == "force_door":
		f.add_buff("embarrassed")
	_again(f, lot_id)

## Noise: a resident who is up may hear it (and the more noise, the likelier). Nobody is told that they did; the effect shows later (a light, a voice, a call).
static func _noise(lot_id: String, loudness: float) -> void:
	for t in awake_residents(lot_id):
		if SysUtil.rng.randf() < loudness:
			JusticeState.queue({"kind": "door_notice", "lot": lot_id, "tid": int(t["id"]), "why": "noise", "due_min": SysUtil.now() + SysUtil.rng.randi_range(1, 3)})
			return

static func _enter(f, lot_id: String, invited: bool) -> void:
	f.remove_meta("at_door")
	var r: Dictionary = Neighborhood.travel([int(f.id)], lot_id, {"instant": true, "free": true, "silent": true, "quiet": true})
	if not bool(r.get("ok", false)):
		return
	if invited:
		return
	intruders[int(f.id)] = lot_id
	CrimePetty.commit("trespassing", int(f.id), "venue:" + lot_id, {"seen": false})
	for t in awake_residents(lot_id):
		JusticeState.queue({"kind": "door_notice", "lot": lot_id, "tid": int(t["id"]), "why": "inside", "due_min": SysUtil.now() + SysUtil.rng.randi_range(1, 4)})
		break

# ------------------------------------------------------------------ somebody notices
## A queued notice: the resident saw or heard the intruder. They react; the player answers.
static func notice(p: Dictionary) -> void:
	var lot_id: String = str(p.get("lot", ""))
	var tid: int = int(p.get("tid", -1))
	var t: Dictionary = Story.townies.get(tid, {})
	var pawn = SysUtil.folk(Pawn.of())
	if t.is_empty() or pawn == null:
		return
	var inside: bool = str(intruders.get(int(pawn.id), "")) == lot_id and Neighborhood.lot_of(pawn) == lot_id
	var who: String = str(t.get("name", "Somebody"))
	if str(p.get("why", "")) == "noise" and not inside:
		SysUtil.notify(_line("heard", who), "story")          # a light comes on: the world tells you, nothing else
		return
	if not inside:
		return
	var reactions: Dictionary = cfg().get("lines", {}).get("intruder", {})
	var weights: Dictionary = {"scream": 1.0, "order_out": 1.2, "grab": 0.5, "flee": 0.5, "call": 0.7}
	if SocialDynamics.has_t(tid, "hot_headed") or SocialDynamics.has_t(tid, "brave"):
		weights["grab"] *= 3.0
		weights["order_out"] *= 1.5
	if SocialDynamics.has_t(tid, "shy") or SocialDynamics.has_t(tid, "anxious"):
		weights["flee"] *= 3.0
		weights["scream"] *= 2.0
	if RelationshipService.knows(tid, int(pawn.id)):
		weights["call"] *= 0.4          # someone who knows you talks first
	var keys: Array = weights.keys()
	var pick = SysUtil.pick_weighted(keys, keys.map(func(k): return float(weights[k])))
	var lines: Array = reactions.get(str(pick), [""])
	var line: String = str(lines[PlayerPrompt._pick("door|intruder|" + str(pick), lines.size())]).replace("{r}", who).replace("{a}", str(pawn.name))
	line = Sexes.fill(line, tid)
	SysUtil.notify(line, "bad")
	SimEnv.emit("thought", tid, line)
	if str(pick) == "call":
		CrimePetty.commit("trespassing", int(pawn.id), CrimePlace.where_now(int(pawn.id)), {"seen": true})
	JusticePlayer.ask(int(pawn.id), "Caught in %s's home" % who, line,
		[{"id": "leave", "label": "Get out now"}, {"id": "run", "label": "Run for the door"}, {"id": "hide", "label": "Hide"}, {"id": "fight", "label": "Push past"}],
		func(ch): _answer(pawn, lot_id, tid, str(ch)), "leave")

static func _answer(pawn, lot_id: String, tid: int, ch: String) -> void:
	var who: String = str(Story.townies.get(tid, {}).get("name", "them"))
	match ch:
		"leave", "run":
			intruders.erase(int(pawn.id))
			var out := NeighborhoodLots.street_tile(lot_id) + Vector2i(0, 3)
			var go: Interaction = Interaction.create_goto(pawn, out, true, 0)
			if go != null:
				pawn.enqueue(go)
			if ch == "run":
				RelationshipService.add_value(tid, int(pawn.id), "friendship", -2.0)
		"hide":
			if SysUtil.rng.randf() < 0.45:
				SysUtil.notify("%s looks around, and gives up for now." % who, "story")
			else:
				SysUtil.notify("%s finds you." % who, "bad")
				CrimePetty.commit("trespassing", int(pawn.id), CrimePlace.where_now(int(pawn.id)), {"seen": true})
		"fight":
			RelationshipService.add_value(tid, int(pawn.id), "friendship", -8.0)
			CrimeAssault.report(int(pawn.id), tid, 2, "%s shoved %s aside on the way out." % [pawn.name, who], false, "shove")
			intruders.erase(int(pawn.id))
			var out2 := NeighborhoodLots.street_tile(lot_id) + Vector2i(0, 3)
			var go2: Interaction = Interaction.create_goto(pawn, out2, true, 0)
			if go2 != null:
				pawn.enqueue(go2)
