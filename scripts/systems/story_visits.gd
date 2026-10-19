class_name StoryVisits
extends RefCounted
## Townie visits, party invites and situations.

static func _visits_and_invites(day: int) -> void:
	var v: Dictionary = Story.cfg().get("visits", {})
	var residents: Array = SysUtil.residents()
	if residents.is_empty():
		return
	# schedule a visit
	if SysUtil.chance(float(v.get("daily_chance", 0.55)) * StoryPacing.mult("visit", int(residents[0].household_id))):
		var cands: Array = []
		var weights: Array = []
		for t in Story.free_townies():
			if Story.stage_of(t) in ["baby", "toddler"] or day - int(t["last_visit_day"]) < 2:
				continue
			var w: float = 1.0
			for r in residents:
				if RelationshipService.knows(int(r.id), int(t["id"])):
					w += 2.0
			cands.append(t)
			weights.append(w)
		var pick = SysUtil.pick_weighted(cands, weights)
		var host = SysUtil.pick(residents)
		if pick != null and host != null and not JusticeOrders.bars(int(pick["id"]), int(host.id)):          # a protective order keeps them away
			var hour: float = SysUtil.rng.randf_range(float(v.get("hour_min", 10)), float(v.get("hour_max", 19)))
			var dur: Array = v.get("duration_min", [120, 240])
			var arrive: int = (day - 1) * 1440 + int(hour * 60.0)
			schedule_visit([int(pick["id"])], int(host.id), arrive, SysUtil.rng.randi_range(int(dur[0]), int(dur[1])), "visit")
	# party invites
	var ic: Dictionary = Story.cfg().get("invites", {})
	if SysUtil.chance(float(ic.get("daily_chance", 0.25))):
		for r2 in residents:
			if SysUtil.is_away(r2):
				continue
			var inviters: Array = []
			for t2 in Story.free_townies():
				if Story.stage_of(t2) in ["adult", "elder", "teen"] and RelationshipService.value(int(t2["id"]), int(r2.id), "friendship") >= float(ic.get("min_friendship", 15)):
					inviters.append(t2)
			var who = SysUtil.pick(inviters)
			if who != null and not _has_open_invite(int(r2.id)):
				send_invite(int(who["id"]), int(r2.id))
				break

static func _has_open_invite(folk_id: int) -> bool:
	for inv in Story.invites:
		if int(inv["folk_id"]) == folk_id and str(inv["state"]) == "open":
			return true
	return false

## Where visitors come to: the door of the host's home lot (`host_id` = the host folk; a co-op guest hosts at their OWN lot, -1 = the home lot), a fixed tile in tests / a single lot.
static func entrance(host_id: int = -1) -> Vector2i:
	if Story.spawn_tile != Vector2i(-999, -999):
		return Story.spawn_tile
	var door: Vector2i = Neighborhood.entry_tile(PlayerLots.home_of(SysUtil.folk(host_id)) if host_id >= 0 else Neighborhood.HOME)
	if door.x >= 0:
		return door
	var w = WorldIface.world()
	if w != null and "starter_spawn_tiles" in w and (w.starter_spawn_tiles as Array).size() > 0:
		return (w.starter_spawn_tiles as Array)[0]
	var e: Array = Story.cfg().get("visits", {}).get("entrance", [1, 1])
	return Vector2i(int(e[0]), int(e[1]))

const MAX_GUEST_WALK := 30      # tiles a guest walks to the door at most: farther away it is placed this far out on its route

## Where a guest appears: at its own home's entry, but at most MAX_GUEST_WALK tiles of road from the host door.
static func arrival_tile(townie_id: int, door: Vector2i) -> Vector2i:
	var home_lot: String = Neighborhood.home_of_townie(townie_id)
	if home_lot == "":
		return door
	var start: Vector2i = Neighborhood.entry_tile(home_lot)
	if start.x < 0:
		return door
	var path: Array = WorldIface.find_path(start, door)
	if path.size() > MAX_GUEST_WALK:
		return path[path.size() - MAX_GUEST_WALK]
	return start

## Schedule guests (townie ids) to visit `host_id` at absolute game minute `arrive_min`.
static func schedule_visit(guest_ids: Array, host_id: int, arrive_min: int, duration: int, kind: String = "visit") -> Dictionary:
	var v: Dictionary = Story.cfg().get("visits", {})
	var sit: Dictionary = {"id": Story._seq, "kind": kind, "state": "scheduled", "host_ids": [host_id], "guest_ids": guest_ids.duplicate(),
		"arrive_min": arrive_min, "end_min": arrive_min + duration, "score": 0.0, "target_score": float(v.get("party_target_score", 12)),
		"roles": {}, "spawned": []}
	Story._seq += 1
	Story.situations.append(sit)
	return sit

## Player-driven: invite a townie over right now (arrives in ~15 minutes).
static func invite_over(townie_id: int, host_id: int, duration: int = 180) -> Dictionary:
	if not Story.townies.has(townie_id) or not bool(Story.townies[townie_id]["alive"]):
		return {}
	return schedule_visit([townie_id], host_id, SysUtil.now() + 15, duration, "visit")

## Player-driven: ask a townie to meet a folk at a neighbourhood venue (see NeighborhoodService.invite_to_venue).
static func invite_to_venue(townie_id: int, host_id: int, lot_id: String, delay: int = 40, duration: int = 120) -> Dictionary:
	if lot_id == Neighborhood.HOME:
		return invite_over(townie_id, host_id, duration)
	return NeighborhoodService.invite_to_venue(townie_id, host_id, lot_id, delay, duration)

## A party: several townies at once.
static func start_party(host_id: int, townie_ids: Array, duration: int = 240) -> Dictionary:
	return schedule_visit(townie_ids, host_id, SysUtil.now() + 20, duration, "party")

static func on_minute() -> void:
	var now: int = SysUtil.now()
	for sit in Story.situations:
		match str(sit["state"]):
			"scheduled":
				if now >= int(sit["arrive_min"]):
					_arrive(sit)
			"arrive":
				if now >= int(sit["arrive_min"]) + 10:
					sit["state"] = "mingle"
			"mingle":
				if now >= int(sit["end_min"]) or Circadian.guests_curfew():
					sit["state"] = "leave"
					_begin_leave(sit)
			"leave":
				if now >= int(sit["leave_done_min"]):
					_finish_situation(sit)
	for sit2 in Story.situations:      # guests are looked after while inside a lot (food, a bathroom, a seat): they do not go home in a bad way
		if str(sit2["state"]) in ["arrive", "mingle", "leave"]:
			for gid in sit2["spawned"]:
				var g = SysUtil.folk(int(gid))
				if g != null and g.has_meta("visitor") and NeighborhoodLots.lot_at(g.tile) != "":
					Crowd.recover(g, float(now - int(sit2["arrive_min"])) / 60.0)
	# open invites that nobody answered
	for inv in Story.invites:
		if str(inv["state"]) == "open":
			if Story.auto_accept_invites and now >= int(inv["created_min"]) + 30:
				respond_invite(int(inv["id"]), true)
			elif now >= int(inv["expires_min"]):
				inv["state"] = "expired"
	while Story.situations.size() > 0 and str(Story.situations[0]["state"]) == "done":
		Story.situations.pop_front()
	if Story.invites.size() > 30:
		Story.invites = Story.invites.slice(Story.invites.size() - 30)

static func _arrive(sit: Dictionary) -> void:
	var hosts_alive: Array = []
	for hid in sit["host_ids"]:
		if SysUtil.folk(int(hid)) != null:
			hosts_alive.append(int(hid))
	if hosts_alive.is_empty():
		sit["state"] = "done"
		return
	sit["host_ids"] = hosts_alive
	var tile: Vector2i = entrance(int(hosts_alive[0]))
	var count: int = 0
	for gid in sit["guest_ids"]:
		var t: Dictionary = Story.townies.get(int(gid), {})
		if t.is_empty() or not bool(t["alive"]) or JusticeState.inmates.has(int(gid)):
			continue                          # dead, or held in custody: a charged suspect does not come to dinner
		var there = SysUtil.folk(int(gid))
		if there != null:
			if not there.has_meta("crowd"):
				continue
			Crowd.dismiss(there)          # the townie was hanging out at a venue: they leave it to come over
		var keep_next: int = Folk._next_id      # townie ids (1000+) must not push regular folk ids up
		var f := Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), int(gid))
		Folk._next_id = keep_next
		f.household_id = -1
		f.age_stage = Story.stage_of(t)
		f.appearance = Genetics.normalize(Genetics.ensure(t))
		f.set_meta("visitor", true)
		f.set_meta("townie_id", int(gid))
		# visitors arrive in decent shape
		for n in f.needs:
			(f.needs[n] as Stat).set_value(SysUtil.rng.randf_range(20.0, 70.0))
		RelationshipService.restore_folk(f)
		SysUtil.world_add_folk(f, arrival_tile(int(gid), tile))
		Aging.apply_stage_buff(f)
		(sit["roles"] as Dictionary)[str(gid)] = "guest"
		(sit["spawned"] as Array).append(int(gid))
		t["last_visit_day"] = SysUtil.day()
		for hid2 in hosts_alive:
			if not RelationshipService.knows(int(hid2), int(gid)):
				RelationshipService.add_both(int(hid2), int(gid), "friendship", float(Story.cfg().get("visits", {}).get("acquaintance_friendship", 6)))
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
			var out := Interaction.create_goto(f, _host_door(sit), false)       # guests walk to the door before they are gone
			if out != null:
				f.enqueue(out)
	sit["leave_done_min"] = SysUtil.now() + 8

static func _finish_situation(sit: Dictionary) -> void:
	var v: Dictionary = Story.cfg().get("visits", {})
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
	Story._log(msg)
	SysUtil.game_event("visit_finished", {"situation": sit["id"], "score": score, "success": success, "reward": reward,
		"folk_id": int(sit["host_ids"][0]) if not (sit["host_ids"] as Array).is_empty() else -1})

## Social interactions between participants raise (or lower) the score.
static func on_social_done(actor: int, target: int, iid: String) -> void:
	var weights: Dictionary = Story.cfg().get("visits", {}).get("score", {})
	if not weights.has(iid):
		return
	for sit in Story.situations:
		if str(sit["state"]) != "mingle" and str(sit["state"]) != "arrive":
			continue
		var roles: Dictionary = sit["roles"]
		if roles.has(str(actor)) and roles.has(str(target)):
			sit["score"] = float(sit["score"]) + float(weights[iid])

static func on_interaction(folk_id: int, iid: String, success: bool) -> void:
	if not success:
		return
	var weights: Dictionary = Story.cfg().get("visits", {}).get("score", {})
	if not weights.has(iid):
		return
	# object interactions (eating, TV) done by participants also count a little
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if str(d.get("target", "object")) == "folk":
		return
	for sit in Story.situations:
		if str(sit["state"]) == "mingle" and (sit["roles"] as Dictionary).has(str(folk_id)):
			sit["score"] = float(sit["score"]) + float(weights[iid]) * 0.5

static func active_situations() -> Array:
	var out: Array = []
	for s in Story.situations:
		if str(s["state"]) != "done":
			out.append(s)
	return out

static func is_visitor(folk_id: int) -> bool:
	var f = SysUtil.folk(folk_id)
	return f != null and f.has_meta("visitor")

# ------------------------------------------------------------------ party invites
static func send_invite(townie_id: int, folk_id: int) -> Dictionary:
	var ic: Dictionary = Story.cfg().get("invites", {})
	var inv: Dictionary = {"id": Story._seq, "townie_id": townie_id, "folk_id": folk_id, "state": "open", "created_min": SysUtil.now(),
		"expires_min": SysUtil.now() + int(float(ic.get("expire_hours", 24)) * 60.0)}
	Story._seq += 1
	Story.invites.append(inv)
	SysUtil.notify("%s invites %s to a party!" % [Story.name_of(townie_id), SysUtil.folk_name(folk_id)], "invite")
	SysUtil.game_event("party_invite", {"folk_id": folk_id, "townie_id": townie_id, "invite_id": inv["id"]})
	return inv

static func open_invites(folk_id: int = -1) -> Array:
	var out: Array = []
	for inv in Story.invites:
		if str(inv["state"]) == "open" and (folk_id < 0 or int(inv["folk_id"]) == folk_id):
			out.append(inv)
	return out

static func respond_invite(invite_id: int, accept: bool) -> bool:
	for inv in Story.invites:
		if int(inv["id"]) != invite_id or str(inv["state"]) != "open":
			continue
		if not accept:
			inv["state"] = "declined"
			return true
		var f = SysUtil.folk(int(inv["folk_id"]))
		if f == null:
			inv["state"] = "expired"
			return false
		var ic: Dictionary = Story.cfg().get("invites", {})
		if Away.send(f, float(ic.get("away_minutes", 180)), "party", {"label": "At a party", "invite_id": invite_id, "townie_id": inv["townie_id"]}):
			inv["state"] = "accepted"
			return true
		return false
	return false

static func on_party_return(f, rec: Dictionary) -> void:
	var ic: Dictionary = Story.cfg().get("invites", {})
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
		for t in Story.alive_townies():
			if int(t["id"]) != tid:
				others.append(int(t["id"]))
		for _i in 2:
			var o = SysUtil.pick(others)
			if o != null:
				others.erase(o)
				RelationshipService.add_both(int(f.id), int(o), "friendship", 6.0 if RelationshipService.knows(int(f.id), int(o)) else 5.0)
		SysUtil.notify("%s had a great time at the party." % f.name, "visit")
		SysUtil.game_event("party_attended", {"folk_id": f.id, "townie_id": tid})

## Door of the lot where this situation's (first) host lives.
static func _host_door(sit: Dictionary) -> Vector2i:
	var hosts: Array = sit.get("host_ids", [])
	return entrance(int(hosts[0]) if not hosts.is_empty() else -1)
