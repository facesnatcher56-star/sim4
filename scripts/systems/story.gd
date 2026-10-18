class_name Story
extends RefCounted
## Story progression: a statistical simulation of ~12 off-lot townies (jobs, friendships, marriage, births, moves,
## old age) plus visitors who arrive as full Folk on the lot for a few hours (Situation-lite state machine:
## roles host/guest, states scheduled -> arrive -> mingle -> leave -> done, party score reward), party invites
## that take a resident off-lot, and a modest night-time burglar. Data: data/story.json.

static var townies: Dictionary = {}     # id -> townie dict
static var situations: Array = []       # visit/party situations
static var invites: Array = []          # {id, townie_id, folk_id, expires_min, state}
static var news: Array = []             # {day, text}
static var next_id: int = 0
static var _seq: int = 1
static var auto_accept_invites: bool = true
static var spawn_tile: Vector2i = Vector2i(-999, -999)   # lot entrance; (-999,-999) = use config default
static var burglaries: int = 0

static func reset() -> void:
	townies.clear()
	situations.clear()
	invites.clear()
	news.clear()
	next_id = 0
	_seq = 1
	auto_accept_invites = true
	spawn_tile = Vector2i(-999, -999)
	burglaries = 0

static func cfg() -> Dictionary:
	return SysUtil.table("story")

# ------------------------------------------------------------------ townie roster
static func is_townie(id: int) -> bool:
	return townies.has(id)

static func name_of(id: int) -> String:
	return str((townies.get(id, {}) as Dictionary).get("name", "Someone"))

static func traits_of(id: int) -> Array:
	return (townies.get(id, {}) as Dictionary).get("traits", [])

static func alive_townies() -> Array:
	var out: Array = []
	for id in townies:
		if bool(townies[id]["alive"]):
			out.append(townies[id])
	return out

static func _log(text: String) -> void:
	news.append({"day": SysUtil.day(), "text": text})
	while news.size() > 60:
		news.pop_front()

static func recent_news(n: int = 10) -> Array:
	return news.slice(maxi(news.size() - n, 0))

static func _new_name() -> String:
	var c: Dictionary = cfg()
	for _i in 40:
		var nm: String = "%s %s" % [str(SysUtil.pick(c.get("first_names", ["Sam"]))), str(SysUtil.pick(c.get("last_names", ["Doe"])))]
		var taken: bool = false
		for id in townies:
			if townies[id]["name"] == nm:
				taken = true
		if not taken:
			return nm
	return "Visitor %d" % next_id

static func add_townie(age_days: float = -1.0, nm: String = "", traits: Array = [], career: String = "", level: int = 1) -> Dictionary:
	var c: Dictionary = cfg()
	if next_id <= 0:
		next_id = int(c.get("first_id", 1000))
	var id: int = next_id
	next_id += 1
	if nm == "":
		nm = _new_name()
	if traits.is_empty():
		var pool: Array = (c.get("trait_pool", []) as Array).duplicate()
		for _i in 2:
			if pool.is_empty():
				break
			var t = SysUtil.pick(pool)
			pool.erase(t)
			traits.append(str(t))
	if age_days < 0.0:
		age_days = SysUtil.rng.randf_range(float(Aging.stage_def("adult").get("from_day", 44)) + 2.0, float(Aging.stage_def("elder").get("from_day", 140)) - 10.0)
	var t: Dictionary = {"id": id, "name": nm, "traits": traits.duplicate(), "age_days": age_days, "career": career, "level": level,
		"coins": SysUtil.rng.randi_range(100, 800), "alive": true, "lot": SysUtil.rng.randi_range(1, 6), "last_visit_day": -99}
	townies[id] = t
	return t

static func generate_townies(count: int = -1) -> void:
	var c: Dictionary = cfg()
	if count < 0:
		count = int(c.get("townie_count", 12))
	var careers: Array = c.get("careers", [])
	for i in count:
		var tn: Dictionary = add_townie()
		if i % 3 != 2 and not careers.is_empty():
			tn["career"] = str(SysUtil.pick(careers))
			tn["level"] = SysUtil.rng.randi_range(1, 3)
	# a teen and an elder for variety
	if count >= 4:
		var ids: Array = townies.keys()
		(townies[ids[0]] as Dictionary)["age_days"] = SysUtil.rng.randf_range(float(Aging.stage_def("teen").get("from_day", 28)) + 1.0, 42.0)
		(townies[ids[0]] as Dictionary)["career"] = ""
		(townies[ids[1]] as Dictionary)["age_days"] = float(Aging.stage_def("elder").get("from_day", 140)) + 6.0
		(townies[ids[1]] as Dictionary)["career"] = ""
	# starting social web: friendships, one couple, one family
	var adults: Array = []
	for t2 in alive_townies():
		if stage_of(t2) in ["adult", "elder"]:
			adults.append(int(t2["id"]))
	for _k in count:
		var a = SysUtil.pick(adults)
		var b = SysUtil.pick(adults)
		if a != null and b != null and a != b:
			RelationshipService.add_both(int(a), int(b), "friendship", SysUtil.rng.randf_range(8.0, 45.0))
	if adults.size() >= 4:
		RelationshipService.add_both(adults[2], adults[3], "friendship", 60.0)
		RelationshipService.add_both(adults[2], adults[3], "romance", 70.0)
		RelationshipService.set_flag(adults[2], adults[3], "partner", true, false)
		if adults.size() >= 6:
			RelationshipService.add_both(adults[4], adults[5], "friendship", 50.0)
			RelationshipService.set_flag(adults[4], adults[5], "family", true, false)

static func stage_of(t: Dictionary) -> String:
	return Aging.stage_for_days(float(t["age_days"]))

# ------------------------------------------------------------------ daily advance
static func on_day(day: int) -> void:
	if townies.is_empty():
		generate_townies()
	var c: Dictionary = cfg()
	var dc: Dictionary = c.get("daily", {})
	var rate: float = Aging.age_rate()
	var dcfg: Dictionary = Aging.cfg().get("death", {})
	for t in alive_townies():
		t["age_days"] = float(t["age_days"]) + rate
		var st: String = stage_of(t)
		if st == "elder" and str(t["career"]) != "":
			t["career"] = ""
			_log("%s retired." % t["name"])
		elif st == "adult":
			if str(t["career"]) == "":
				if SysUtil.chance(float(dc.get("job_chance", 0.12))):
					t["career"] = str(SysUtil.pick(c.get("careers", [])))
					t["level"] = 1
					_log("%s started a new job." % t["name"])
			else:
				var lmax: int = Careers.max_level(str(t["career"]))
				if SysUtil.chance(float(dc.get("promote_chance", 0.04))) and int(t["level"]) < lmax:
					t["level"] = int(t["level"]) + 1
					_log("%s got promoted to level %d." % [t["name"], t["level"]])
				elif SysUtil.chance(float(dc.get("demote_chance", 0.015))):
					t["level"] = int(t["level"]) - 1
					if int(t["level"]) < 1:
						t["career"] = ""
						t["level"] = 1
						_log("%s lost their job." % t["name"])
				if str(t["career"]) != "":
					t["coins"] = int(t["coins"]) + int(dc.get("coins_per_level", 40)) * int(t["level"])
		var dstart: float = float(dcfg.get("start_day", 170))
		if float(t["age_days"]) >= dstart and SysUtil.chance(float(dcfg.get("chance_per_day", 0.03)) + float(dcfg.get("ramp_per_day", 0.004)) * (float(t["age_days"]) - dstart)):
			_townie_dies(t)
	_pair_events(dc)
	_life_events(dc)
	_visits_and_invites(day)

static func _townie_dies(t: Dictionary) -> void:
	t["alive"] = false
	t["died_day"] = SysUtil.day()
	_log("%s passed away." % t["name"])
	for rid in SysUtil.residents():
		if RelationshipService.knows(int(rid.id), int(t["id"])) and RelationshipService.value(int(rid.id), int(t["id"]), "friendship") >= 20.0:
			SysUtil.notify("%s, a friend of %s, has passed away." % [t["name"], rid.name], "death")
			rid.add_buff("grieving")

static func _pair_events(dc: Dictionary) -> void:
	var adults: Array = []
	for t in alive_townies():
		if stage_of(t) in ["teen", "adult", "elder"]:
			adults.append(int(t["id"]))
	if adults.size() < 2:
		return
	for _i in int(dc.get("pair_events", 6)):
		var a: int = int(SysUtil.pick(adults))
		var b: int = int(SysUtil.pick(adults))
		if a == b:
			continue
		var compat: float = RelationshipService.compatibility(a, b)
		var hot: bool = traits_of(a).has("hot_headed")
		if SysUtil.chance(0.12 + (0.18 if hot else 0.0) - compat * 0.1):
			RelationshipService.add_both(a, b, "friendship", -SysUtil.rng.randf_range(3.0, 8.0))
			RelationshipService.add_history(a, b, "insult", -0.8, a)
		else:
			RelationshipService.add_both(a, b, "friendship", SysUtil.rng.randf_range(1.0, 4.0) * (1.0 + compat * 0.5))
			RelationshipService.add_history(a, b, "chat", 0.3, a)
			if stage_of(townies[a]) != "teen" and stage_of(townies[b]) != "teen" and compat > 0.1 and RelationshipService.value(a, b, "friendship") > 25.0:
				RelationshipService.add_both(a, b, "romance", SysUtil.rng.randf_range(1.0, 4.0))
		RelationshipService.touch(a, b)
		RelationshipService.auto_status(a, b)

static func _life_events(dc: Dictionary) -> void:
	var c: Dictionary = cfg()
	# marriage
	for key in RelationshipService.pairs.keys():
		var p: Dictionary = RelationshipService.pairs[key]
		var a: int = int(p["lo"])
		var b: int = int(p["hi"])
		if not (townies.has(a) and townies.has(b)) or not (bool(townies[a]["alive"]) and bool(townies[b]["alive"])):
			continue
		var fl: Dictionary = p["flags"]
		if fl.get("partner", false) and not fl.get("spouse", false):
			if RelationshipService.value(a, b, "romance") >= 80.0 and SysUtil.chance(float(dc.get("marry_chance", 0.12))):
				RelationshipService.set_flag(a, b, "spouse", true, false)
				_log("%s and %s got married!" % [name_of(a), name_of(b)])
				_tell_residents_about(a, b, "%s and %s got married!" % [name_of(a), name_of(b)])
		elif fl.get("spouse", false) or fl.get("partner", false):
			if alive_townies().size() < int(c.get("max_population", 20)) and SysUtil.chance(float(dc.get("baby_chance", 0.05))):
				var baby: Dictionary = add_townie(0.0, "", [])
				baby["name"] = "%s %s" % [str(SysUtil.pick(Aging.cfg().get("name_pool", ["Pip"]))), name_of(a).split(" ")[-1]]
				RelationshipService.set_flag(int(baby["id"]), a, "family", true, false)
				RelationshipService.set_flag(int(baby["id"]), b, "family", true, false)
				_log("%s and %s had a baby, %s." % [name_of(a), name_of(b), baby["name"]])
	# moving away / arriving
	for t in alive_townies():
		if SysUtil.chance(float(dc.get("move_away_chance", 0.01))) and stage_of(t) == "adult":
			t["alive"] = false
			t["moved"] = true
			_log("%s moved out of town." % t["name"])
	if alive_townies().size() < int(c.get("townie_count", 12)) and SysUtil.chance(float(dc.get("arrive_chance", 0.12))):
		var n: Dictionary = add_townie()
		n["career"] = str(SysUtil.pick(c.get("careers", [])))
		_log("%s moved to town." % n["name"])

static func _tell_residents_about(a: int, b: int, text: String) -> void:
	for r in SysUtil.residents():
		var rid: int = int(r.id)
		if RelationshipService.knows(rid, a) or RelationshipService.knows(rid, b):
			SysUtil.notify(text, "story")
			return

# ------------------------------------------------------------------ visits & invites
static func _visits_and_invites(day: int) -> void:
	var v: Dictionary = cfg().get("visits", {})
	var residents: Array = SysUtil.residents()
	if residents.is_empty():
		return
	# schedule a visit
	if SysUtil.chance(float(v.get("daily_chance", 0.55))):
		var cands: Array = []
		var weights: Array = []
		for t in alive_townies():
			if stage_of(t) in ["baby", "toddler"] or day - int(t["last_visit_day"]) < 2:
				continue
			var w: float = 1.0
			for r in residents:
				if RelationshipService.knows(int(r.id), int(t["id"])):
					w += 2.0
			cands.append(t)
			weights.append(w)
		var pick = SysUtil.pick_weighted(cands, weights)
		var host = SysUtil.pick(residents)
		if pick != null and host != null:
			var hour: float = SysUtil.rng.randf_range(float(v.get("hour_min", 10)), float(v.get("hour_max", 19)))
			var dur: Array = v.get("duration_min", [120, 240])
			var arrive: int = (day - 1) * 1440 + int(hour * 60.0)
			schedule_visit([int(pick["id"])], int(host.id), arrive, SysUtil.rng.randi_range(int(dur[0]), int(dur[1])), "visit")
	# party invites
	var ic: Dictionary = cfg().get("invites", {})
	if SysUtil.chance(float(ic.get("daily_chance", 0.25))):
		for r2 in residents:
			if SysUtil.is_away(r2):
				continue
			var inviters: Array = []
			for t2 in alive_townies():
				if stage_of(t2) in ["adult", "elder", "teen"] and RelationshipService.value(int(t2["id"]), int(r2.id), "friendship") >= float(ic.get("min_friendship", 15)):
					inviters.append(t2)
			var who = SysUtil.pick(inviters)
			if who != null and not _has_open_invite(int(r2.id)):
				send_invite(int(who["id"]), int(r2.id))
				break

static func _has_open_invite(folk_id: int) -> bool:
	for inv in invites:
		if int(inv["folk_id"]) == folk_id and str(inv["state"]) == "open":
			return true
	return false

static func entrance() -> Vector2i:
	if spawn_tile != Vector2i(-999, -999):
		return spawn_tile
	var w = WorldIface.world()
	if w != null and "starter_spawn_tiles" in w and (w.starter_spawn_tiles as Array).size() > 0:
		return (w.starter_spawn_tiles as Array)[0]
	var e: Array = cfg().get("visits", {}).get("entrance", [1, 1])
	return Vector2i(int(e[0]), int(e[1]))

## Schedule guests (townie ids) to visit `host_id` at absolute game minute `arrive_min`.
static func schedule_visit(guest_ids: Array, host_id: int, arrive_min: int, duration: int, kind: String = "visit") -> Dictionary:
	var v: Dictionary = cfg().get("visits", {})
	var sit: Dictionary = {"id": _seq, "kind": kind, "state": "scheduled", "host_ids": [host_id], "guest_ids": guest_ids.duplicate(),
		"arrive_min": arrive_min, "end_min": arrive_min + duration, "score": 0.0, "target_score": float(v.get("party_target_score", 12)),
		"roles": {}, "spawned": []}
	_seq += 1
	situations.append(sit)
	return sit

## Player-driven: invite a townie over right now (arrives in ~15 minutes).
static func invite_over(townie_id: int, host_id: int, duration: int = 180) -> Dictionary:
	if not townies.has(townie_id) or not bool(townies[townie_id]["alive"]):
		return {}
	return schedule_visit([townie_id], host_id, SysUtil.now() + 15, duration, "visit")

## A party: several townies at once.
static func start_party(host_id: int, townie_ids: Array, duration: int = 240) -> Dictionary:
	return schedule_visit(townie_ids, host_id, SysUtil.now() + 20, duration, "party")

static func on_minute() -> void:
	var now: int = SysUtil.now()
	for sit in situations:
		match str(sit["state"]):
			"scheduled":
				if now >= int(sit["arrive_min"]):
					_arrive(sit)
			"arrive":
				if now >= int(sit["arrive_min"]) + 10:
					sit["state"] = "mingle"
			"mingle":
				if now >= int(sit["end_min"]):
					sit["state"] = "leave"
					_begin_leave(sit)
			"leave":
				if now >= int(sit["leave_done_min"]):
					_finish_situation(sit)
	# open invites that nobody answered
	for inv in invites:
		if str(inv["state"]) == "open":
			if auto_accept_invites and now >= int(inv["created_min"]) + 30:
				respond_invite(int(inv["id"]), true)
			elif now >= int(inv["expires_min"]):
				inv["state"] = "expired"
	while situations.size() > 0 and str(situations[0]["state"]) == "done":
		situations.pop_front()
	if invites.size() > 30:
		invites = invites.slice(invites.size() - 30)

static func _arrive(sit: Dictionary) -> void:
	var hosts_alive: Array = []
	for hid in sit["host_ids"]:
		if SysUtil.folk(int(hid)) != null:
			hosts_alive.append(int(hid))
	if hosts_alive.is_empty():
		sit["state"] = "done"
		return
	sit["host_ids"] = hosts_alive
	var tile: Vector2i = entrance()
	var count: int = 0
	for gid in sit["guest_ids"]:
		var t: Dictionary = townies.get(int(gid), {})
		if t.is_empty() or not bool(t["alive"]) or SysUtil.folk(int(gid)) != null:
			continue
		var keep_next: int = Folk._next_id      # townie ids (1000+) must not push regular folk ids up
		var f := Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), int(gid))
		Folk._next_id = keep_next
		f.household_id = -1
		f.age_stage = stage_of(t)
		f.set_meta("visitor", true)
		f.set_meta("townie_id", int(gid))
		# visitors arrive in decent shape
		for n in f.needs:
			(f.needs[n] as Stat).set_value(SysUtil.rng.randf_range(20.0, 70.0))
		RelationshipService.restore_folk(f)
		SysUtil.world_add_folk(f, tile)
		Aging.apply_stage_buff(f)
		(sit["roles"] as Dictionary)[str(gid)] = "guest"
		(sit["spawned"] as Array).append(int(gid))
		t["last_visit_day"] = SysUtil.day()
		for hid2 in hosts_alive:
			if not RelationshipService.knows(int(hid2), int(gid)):
				RelationshipService.add_both(int(hid2), int(gid), "friendship", float(cfg().get("visits", {}).get("acquaintance_friendship", 6)))
				RelationshipService.add_history(int(hid2), int(gid), "visit", 0.3, int(gid))
				SysUtil.notify("%s met %s." % [SysUtil.folk_name(int(hid2)), t["name"]], "relationship")
		count += 1
		# greet the host
		var greet := Interaction.create("chat", f, int(hosts_alive[0]), false)
		if greet != null:
			f.enqueue(greet)
	for hid3 in hosts_alive:
		(sit["roles"] as Dictionary)[str(hid3)] = "host"
	if count == 0:
		sit["state"] = "done"
		return
	sit["state"] = "arrive"
	SysUtil.notify("%s arrived for a %s." % [", ".join(_names(sit["spawned"])), str(sit["kind"])], "visit")
	SysUtil.game_event("visit_started", {"folk_id": int(hosts_alive[0]), "situation": sit["id"], "guests": sit["spawned"].duplicate()})

static func _names(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		out.append(SysUtil.folk_name(int(i)))
	return out

static func _begin_leave(sit: Dictionary) -> void:
	for gid in sit["spawned"]:
		var f = SysUtil.folk(int(gid))
		if f != null:
			f.cancel_current("leaving")
			f.clear_queue()
			f.add_buff("cheered_up")
	sit["leave_done_min"] = SysUtil.now() + 8

static func _finish_situation(sit: Dictionary) -> void:
	var v: Dictionary = cfg().get("visits", {})
	var score: float = float(sit["score"])
	var success: bool = score >= float(sit["target_score"]) * (1.0 if str(sit["kind"]) == "party" else 0.5)
	for gid in sit["spawned"]:
		var f = SysUtil.folk(int(gid))
		if f != null:
			RelationshipService.sync_folk(f)
			f.cancel_current("left")
			f.clear_queue()
			SysUtil.world_remove_folk(int(gid))
		for hid in sit["host_ids"]:
			if success:
				RelationshipService.add_both(int(hid), int(gid), "friendship", float(v.get("success_friendship", 6)))
			RelationshipService.touch(int(hid), int(gid))
	var reward: int = int(round(maxf(score, 0.0) * 5.0)) if success else 0
	for hid2 in sit["host_ids"]:
		var h = SysUtil.folk(int(hid2))
		if h == null:
			continue
		if success:
			h.add_buff("social_glow")
			h.add_to_stat("social", 25.0)
			Economy.deposit(int(h.household_id), reward, "visitor gifts")
	sit["state"] = "done"
	var msg: String = "The %s is over. Score: %d%s" % [str(sit["kind"]), int(round(score)), (" - a hit! (+%d coins in gifts)" % reward) if success else "."]
	SysUtil.notify(msg, "visit")
	_log(msg)
	SysUtil.game_event("visit_finished", {"situation": sit["id"], "score": score, "success": success, "reward": reward,
		"folk_id": int(sit["host_ids"][0]) if not (sit["host_ids"] as Array).is_empty() else -1})

## Social interactions between participants raise (or lower) the score.
static func on_social_done(actor: int, target: int, iid: String) -> void:
	var weights: Dictionary = cfg().get("visits", {}).get("score", {})
	if not weights.has(iid):
		return
	for sit in situations:
		if str(sit["state"]) != "mingle" and str(sit["state"]) != "arrive":
			continue
		var roles: Dictionary = sit["roles"]
		if roles.has(str(actor)) and roles.has(str(target)):
			sit["score"] = float(sit["score"]) + float(weights[iid])

static func on_interaction(folk_id: int, iid: String, success: bool) -> void:
	if not success:
		return
	var weights: Dictionary = cfg().get("visits", {}).get("score", {})
	if not weights.has(iid):
		return
	# object interactions (eating, TV) done by participants also count a little
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if str(d.get("target", "object")) == "folk":
		return
	for sit in situations:
		if str(sit["state"]) == "mingle" and (sit["roles"] as Dictionary).has(str(folk_id)):
			sit["score"] = float(sit["score"]) + float(weights[iid]) * 0.5

static func active_situations() -> Array:
	var out: Array = []
	for s in situations:
		if str(s["state"]) != "done":
			out.append(s)
	return out

static func is_visitor(folk_id: int) -> bool:
	var f = SysUtil.folk(folk_id)
	return f != null and f.has_meta("visitor")

# ------------------------------------------------------------------ party invites
static func send_invite(townie_id: int, folk_id: int) -> Dictionary:
	var ic: Dictionary = cfg().get("invites", {})
	var inv: Dictionary = {"id": _seq, "townie_id": townie_id, "folk_id": folk_id, "state": "open", "created_min": SysUtil.now(),
		"expires_min": SysUtil.now() + int(float(ic.get("expire_hours", 24)) * 60.0)}
	_seq += 1
	invites.append(inv)
	SysUtil.notify("%s invites %s to a party!" % [name_of(townie_id), SysUtil.folk_name(folk_id)], "invite")
	SysUtil.game_event("party_invite", {"folk_id": folk_id, "townie_id": townie_id, "invite_id": inv["id"]})
	return inv

static func open_invites(folk_id: int = -1) -> Array:
	var out: Array = []
	for inv in invites:
		if str(inv["state"]) == "open" and (folk_id < 0 or int(inv["folk_id"]) == folk_id):
			out.append(inv)
	return out

static func respond_invite(invite_id: int, accept: bool) -> bool:
	for inv in invites:
		if int(inv["id"]) != invite_id or str(inv["state"]) != "open":
			continue
		if not accept:
			inv["state"] = "declined"
			return true
		var f = SysUtil.folk(int(inv["folk_id"]))
		if f == null:
			inv["state"] = "expired"
			return false
		var ic: Dictionary = cfg().get("invites", {})
		if Away.send(f, float(ic.get("away_minutes", 180)), "party", {"label": "At a party", "invite_id": invite_id, "townie_id": inv["townie_id"]}):
			inv["state"] = "accepted"
			return true
		return false
	return false

static func on_party_return(f, rec: Dictionary) -> void:
	var ic: Dictionary = cfg().get("invites", {})
	var tid: int = int(rec["data"].get("townie_id", -1))
	if bool(rec.get("completed", false)):
		f.add_to_stat("social", float(ic.get("reward_social", 50)))
		f.add_to_stat("fun", float(ic.get("reward_fun", 30)))
		f.add_buff("social_glow")
		if tid >= 0:
			RelationshipService.add_both(int(f.id), tid, "friendship", float(ic.get("friendship_gain", 8)))
			RelationshipService.add_history(int(f.id), tid, "party", 0.6, tid)
		# meet two other guests
		var others: Array = []
		for t in alive_townies():
			if int(t["id"]) != tid:
				others.append(int(t["id"]))
		for _i in 2:
			var o = SysUtil.pick(others)
			if o != null:
				others.erase(o)
				RelationshipService.add_both(int(f.id), int(o), "friendship", 6.0 if RelationshipService.knows(int(f.id), int(o)) else 5.0)
		SysUtil.notify("%s had a great time at the party." % f.name, "visit")
		SysUtil.game_event("party_attended", {"folk_id": f.id, "townie_id": tid})

# ------------------------------------------------------------------ burglar
static func on_hour(hour: int) -> void:
	var b: Dictionary = cfg().get("burglar", {})
	if hour < int(b.get("hour_min", 1)) or hour > int(b.get("hour_max", 5)):
		return
	if not SysUtil.chance(float(b.get("chance", 0.06))):
		return
	try_burglary(true)

## Everyone asleep + no lamp on -> a burglar steals coins. `force` skips the dice (tests).
static func try_burglary(force: bool = false) -> int:
	var res: Array = SysUtil.residents()
	if res.is_empty():
		return 0
	for f in res:
		if SysUtil.is_away(f):
			continue
		var asleep: bool = f.current != null and (str(f.current.def_id).begins_with("sleep") or str(f.current.def_id) == "pass_out" or f.posture == "lie")
		if not asleep:
			return 0
	for o in SysUtil.all_world_objects():
		if str(o.def_id) == "lamp" and bool(WorldIface.state_get(o, "on", false)):
			return 0
	if not force:
		pass
	var b: Dictionary = cfg().get("burglar", {})
	var hid: int = int((res[0] as Folk).household_id)
	var bal: int = WorldIface.get_coins(hid)
	var amount: int = clampi(int(float(bal) * float(b.get("steal_rate", 0.1))), int(b.get("steal_min", 20)), int(b.get("steal_max", 300)))
	amount = mini(amount, bal)
	if amount <= 0:
		return 0
	Economy.deposit(hid, -amount, "burglary")
	burglaries += 1
	SysUtil.notify("A burglar broke in during the night and stole %d coins! Leave a lamp on or stay up late." % amount, "bad")
	SysUtil.game_event("burglary", {"household_id": hid, "stolen": amount})
	_log("Burglary: %d coins stolen." % amount)
	return amount

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"townies": SysUtil.str_keys(townies).duplicate(true), "situations": situations.duplicate(true), "invites": invites.duplicate(true),
		"news": news.duplicate(true), "next_id": next_id, "seq": _seq, "auto_accept": auto_accept_invites, "burglaries": burglaries}

static func from_dict(d: Dictionary) -> void:
	reset()
	townies = SysUtil.int_keys((d.get("townies", {}) as Dictionary).duplicate(true))
	for k in townies:
		var t: Dictionary = townies[k]
		t["id"] = int(t["id"])
		t["level"] = int(t["level"])
		t["coins"] = int(t["coins"])
		t["lot"] = int(t.get("lot", 1))
		t["last_visit_day"] = int(t.get("last_visit_day", -99))
	situations = (d.get("situations", []) as Array).duplicate(true)
	for s in situations:
		for key in ["id", "arrive_min", "end_min"]:
			s[key] = int(s[key])
		if s.has("leave_done_min"):
			s["leave_done_min"] = int(s["leave_done_min"])
		for lk in ["host_ids", "guest_ids", "spawned"]:
			var arr: Array = []
			for x in s[lk]:
				arr.append(int(x))
			s[lk] = arr
	invites = (d.get("invites", []) as Array).duplicate(true)
	for inv in invites:
		for key2 in ["id", "townie_id", "folk_id", "created_min", "expires_min"]:
			inv[key2] = int(inv[key2])
	news = (d.get("news", []) as Array).duplicate(true)
	next_id = int(d.get("next_id", 0))
	_seq = int(d.get("seq", 1))
	auto_accept_invites = bool(d.get("auto_accept", true))
	burglaries = int(d.get("burglaries", 0))
