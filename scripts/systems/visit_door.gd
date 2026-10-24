class_name VisitDoor
extends RefCounted
## Task 65: visitors to the player's home come to the front door and knock (data/visit_door.json). Nobody walks in uninvited.
##   A visit (StoryVisits situation) for the pawn at its own home is held in state "door": the guests walk to DoorActs.doorstep and knock.
##   The player answers (Let them in / Talk on the doorstep / Send them away), looks through the window first, or ignores it (they knock
##   again, then go; they may text later and the snub is felt). Only "Let them in" lets the visit go on inside (state "arrive").
##   Guests inside ask before using the bathroom and keep out of the fridge and the beds; the host can ask them to leave (person menu).
##   VisitDoor.applies(sit)   VisitDoor.to_door(sit)   VisitDoor.on_minute()   VisitDoor.person_entries(f, target)

const TITLE := "At your door"

static func cfg() -> Dictionary:
	return SysUtil.table("visit_door")

static func _line(k: String, n: String = "") -> String:
	var lines: Array = (cfg().get("lines", {}) as Dictionary).get(k, [""])
	return str(lines[PlayerPrompt._pick("visit|" + k, lines.size())]).replace("{n}", n)

## A visit to the pawn at its own home (the player's household): the door flow applies.
static func applies(sit: Dictionary) -> bool:
	var hid: int = int((sit["host_ids"] as Array)[0]) if not (sit["host_ids"] as Array).is_empty() else -1
	var host = SysUtil.folk(hid)
	return host != null and Pawn.is_pawn(host) and PlayerLots.home_of(host) == Neighborhood.HOME

static func _host(sit: Dictionary):
	return SysUtil.folk(int((sit["host_ids"] as Array)[0]))

static func _guests(sit: Dictionary) -> Array:
	var out: Array = []
	for gid in sit["spawned"]:
		var g = SysUtil.folk(int(gid))
		if g != null:
			out.append(g)
	return out

static func _first_name(sit: Dictionary) -> String:
	var gs: Array = _guests(sit)
	return str(gs[0].name).get_slice(" ", 0) if not gs.is_empty() else "Someone"

## The guests have just appeared down the street: they walk up to the front door instead of in.
static func to_door(sit: Dictionary) -> void:
	sit["state"] = "door"
	sit["door"] = {"phase": "walking", "since": SysUtil.now()}
	var step: Vector2i = DoorActs.doorstep(Neighborhood.HOME)
	var k: int = 0
	for g in _guests(sit):
		g.clear_queue()
		var ir: Interaction = Interaction.create_goto(g, Crowd.free_near(step + Vector2i(k, 0)) if k > 0 else step, false)
		k += 1
		if ir != null:
			ir.def = ir.def.duplicate(true)
			ir.def["priority"] = "high"
			g.enqueue(ir)

# ------------------------------------------------------------------ the clock
static func on_minute() -> void:
	var now: int = SysUtil.now()
	for sit in Story.situations:
		match str(sit["state"]):
			"door":
				_door_tick(sit, now)
			"arrive", "mingle":
				if bool(sit.get("doorstep", false)):
					if now >= int(sit["end_min"]):
						_send_off(sit, "")
				elif sit.has("door"):
					_manners(sit, now)

static func _door_tick(sit: Dictionary, now: int) -> void:
	var d: Dictionary = sit["door"]
	var step: Vector2i = DoorActs.doorstep(Neighborhood.HOME)
	match str(d["phase"]):
		"walking":
			var there: bool = _guests(sit).any(func(g): return (g.tile - step).length() <= 1.5)
			if there or now >= int(d["since"]) + int(cfg().get("walk_min", 25)):
				_knock(sit, now)
		"knocked":
			if now >= int(d["since"]) + int(cfg().get("knock_again_min", 3)) and not bool(d.get("again", false)):
				d["again"] = true
				if _can_answer(sit):
					SysUtil.notify(_line("knock_again"), "story")
			if now >= int(d["since"]) + int(cfg().get("give_up_min", 6)):
				_give_up(sit)
		"asking":
			pass          # the player's answer moves it on

## The pawn hears the door: at home, here and awake.
static func _can_answer(sit: Dictionary) -> bool:
	var host = _host(sit)
	return host != null and not SysUtil.is_away(host) and Neighborhood.lot_of(host) == Neighborhood.HOME and not CrimePlace.is_asleep(host)

static func _knock(sit: Dictionary, now: int) -> void:
	var d: Dictionary = sit["door"]
	d["since"] = now
	d["phase"] = "knocked"
	if not _can_answer(sit):
		return          # nobody hears it: they knock, wait and go (_give_up)
	d["phase"] = "asking"
	var host = _host(sit)
	var opts: Array = [{"id": "answer", "label": "Answer the door"}]
	if WorldIface.world() != null and not WorldIface.world().objects_of_def("window").is_empty():
		opts.append({"id": "look", "label": "Look through the window"})
	opts.append({"id": "ignore", "label": "Ignore it"})
	JusticePlayer.ask(int(host.id), TITLE, _line("knock"), opts, func(ch): _answer(sit, str(ch)), "answer")

static func _answer(sit: Dictionary, ch: String) -> void:
	if str(sit["state"]) != "door":
		return
	var host = _host(sit)
	var n: String = _first_name(sit)
	match ch:
		"look":
			JusticePlayer.ask(int(host.id), TITLE, _line("look", ", ".join(StoryVisits._names(sit["spawned"]))),
				[{"id": "answer", "label": "Answer the door"}, {"id": "ignore", "label": "Ignore it"}], func(c2): _answer(sit, str(c2)), "answer")
		"ignore":
			var d: Dictionary = sit["door"]
			d["phase"] = "knocked"
			d["since"] = SysUtil.now()
			d["snubbed"] = true
		_:
			var why: String = str(sit["line"]) if sit.has("line") else _line("why_party" if str(sit["kind"]) == "party" else "why_visit")
			JusticePlayer.ask(int(host.id), TITLE, "%s opens the door. %s: %s" % [str(host.name).get_slice(" ", 0), n, why],
				[{"id": "in", "label": "Let them in"}, {"id": "step", "label": "Talk on the doorstep"}, {"id": "away", "label": "Send them away"}],
				func(c3): _opened(sit, str(c3)), "in")

static func _opened(sit: Dictionary, ch: String) -> void:
	var host = _host(sit)
	if host == null:
		sit["state"] = "done"
		return
	match ch:
		"away":
			_friend(sit, "sent_away")
			SysUtil.notify(_line("sent_away", _first_name(sit)), "story")
			_send_off(sit, "")
		"step":
			sit["doorstep"] = true
			sit["state"] = "arrive"
			sit["arrive_min"] = SysUtil.now()
			sit["end_min"] = SysUtil.now() + int(cfg().get("doorstep_min", 20))
			var g0 = _guests(sit)[0] if not _guests(sit).is_empty() else null
			if g0 != null:
				var talk := Interaction.create("chat", host, int(g0.id), true)
				if talk != null:
					host.enqueue(talk)
		_:
			var length: int = maxi(int(sit["end_min"]) - int(sit["arrive_min"]), 60)          # the visit as planned, from the moment they are let in
			sit["state"] = "arrive"
			sit["arrive_min"] = SysUtil.now()
			sit["end_min"] = SysUtil.now() + length
			for g in _guests(sit):
				g.set_meta("let_in", true)
				var greet := Interaction.create("chat", g, int(host.id), false)
				if greet != null:
					g.enqueue(greet)
			SysUtil.game_event("visit_started", {"folk_id": int(host.id), "situation": sit["id"], "guests": (sit["spawned"] as Array).duplicate()})

## Nobody let them in: they give up and walk off; a snub is felt, and a friend may text later.
static func _give_up(sit: Dictionary) -> void:
	var host = _host(sit)
	if bool((sit["door"] as Dictionary).get("snubbed", false)):
		_friend(sit, "snub")
	if _can_answer(sit):
		SysUtil.notify(_line("gave_up"), "story")
	elif host != null and PhoneOwn.block(int(host.id)) == "" and not _guests(sit).is_empty():
		SysUtil.notify(_line("came_by", _first_name(sit)), "info")
	_send_off(sit, "")

static func _send_off(sit: Dictionary, _why: String) -> void:
	sit["state"] = "leave"
	StoryVisits._begin_leave(sit)

static func _friend(sit: Dictionary, key: String) -> void:
	var host = _host(sit)
	var delta: float = float((cfg().get("friendship", {}) as Dictionary).get(key, 0.0))
	if host == null or delta == 0.0:
		return
	for gid in sit["spawned"]:
		RelationshipService.add_both(int(host.id), int(gid), "friendship", delta)

# ------------------------------------------------------------------ guests' manners
## A guest who heads for the bathroom asks first; one who heads for the fridge or a bed thinks better of it.
static func _manners(sit: Dictionary, now: int) -> void:
	var c: Dictionary = cfg()
	for g in _guests(sit):
		var cur: Interaction = g.current
		if cur == null or cur.obj == null or NeighborhoodLots.lot_at(cur.obj.tile) != Neighborhood.HOME:
			continue
		var def_id: String = str(cur.obj.def_id)
		if (c.get("private_defs", []) as Array).has(def_id):
			g.cooldowns[cur.def_id] = now + int(c.get("cooldown_min", 600))
			cur.cancel("a guest")
		elif (c.get("bath_defs", []) as Array).has(def_id) and not bool(g.get_meta("bath_ok", false)):
			g.cooldowns[cur.def_id] = now + 30
			cur.cancel("asks first")
			if not g.has_meta("bath_asked"):
				g.set_meta("bath_asked", true)
				var host = _host(sit)
				JusticePlayer.ask(int(host.id), "Your guest", _line("bath_ask", str(g.name).get_slice(" ", 0)),
					[{"id": "yes", "label": "Of course"}, {"id": "no", "label": "Rather not"}], func(ch): _bath(sit, g, str(ch)), "yes")

static func _bath(sit: Dictionary, g, ch: String) -> void:
	if ch == "yes":
		g.set_meta("bath_ok", true)
		g.cooldowns.erase("use_toilet")
	else:
		SysUtil.notify(_line("bath_no", str(g.name).get_slice(" ", 0)), "story")
		sit["end_min"] = mini(int(sit["end_min"]), SysUtil.now() + 30)          # they won't stay long now

# ------------------------------------------------------------------ asking them to leave
static func _sit_of_guest(gid: int) -> Dictionary:
	for sit in Story.situations:
		if str(sit["state"]) in ["arrive", "mingle"] and (sit["spawned"] as Array).has(gid) and sit.has("door"):
			return sit
	return {}

static func person_entries(f, target) -> Array:
	if f == null or target == null or not Pawn.is_pawn(f) or not (target is Folk) or not target.has_meta("visitor"):
		return []
	var sit: Dictionary = _sit_of_guest(int(target.id))
	if sit.is_empty():
		return []
	return [{"id": "ask_leave", "label": "It's getting late", "category": "Host", "enabled": true, "reason": "", "action": func(): ask_to_leave(sit, target)}]

static func ask_to_leave(sit: Dictionary, g) -> void:
	var host = _host(sit)
	var n: String = str(g.name).get_slice(" ", 0)
	var p: float = float(cfg().get("stay_refuse_hothead" if g.has_trait("hothead") else "stay_refuse", 0.12))
	if RelationshipService.value(int(g.id), int(host.id), "friendship") < 0.0:
		p += 0.15
	if SysUtil.rng.randf() >= p:
		SysUtil.notify(_line("leave_ok", n), "story")
		_send_off(sit, "")
		return
	JusticePlayer.ask(int(host.id), "Your guest", _line("leave_refuse", n),
		[{"id": "insist", "label": "Insist"}, {"id": "police", "label": "Call the police"}, {"id": "stay", "label": "Let them stay"}],
		func(ch): _refused(sit, g, str(ch)), "stay")

static func _refused(sit: Dictionary, g, ch: String) -> void:
	var n: String = str(g.name).get_slice(" ", 0)
	match ch:
		"insist":
			_friend(sit, "argued")
			RelationshipService.add_both(int(_host(sit).id), int(g.id), "tension", 30.0)
			SysUtil.notify(_line("insist", n), "bad")
			_send_off(sit, "")
		"police":
			_friend(sit, "police")
			SysUtil.notify(_line("police", n), "bad")
			_send_off(sit, "")
