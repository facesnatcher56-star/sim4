class_name NeighborhoodService
extends RefCounted
## Per-minute / per-hour glue for the neighbourhood layer (called from SystemsManager). Every lot exists at once on the map, so
## all of this works PER LOT, using each folk's tile (Neighborhood.lot_of):
##   before_minute()  - postpones home visits while nobody is home
##   after_minute()   - region watcher (entry rules), ambient NPC crowd + staff per venue lot, venue buffs, chance meetings,
##                      hangout invitations, closing time
##   on_interaction_finished / on_game_event - venue skill bonuses, groceries
## Invitations: NeighborhoodService.invite_to_venue(townie_id, folk_id, lot_id) (also StoryVisits.invite_to_venue).

static func install() -> void:
	NeighborhoodContent.install()
	Workplace.install()

static func cfg() -> Dictionary:
	return Venues.cfg()

# ------------------------------------------------------------------ minute
static func before_minute() -> void:
	_postpone_visits()

static func after_minute() -> void:
	var t := PerfProf.start()
	NeighborhoodLots.on_minute()
	PerfProf.stop("after/NeighborhoodLots", t)
	t = PerfProf.start()
	Crowd.update()
	PerfProf.stop("after/Crowd.update", t)
	t = PerfProf.start()
	_ambient()
	_meetings()
	_meetups()
	PerfProf.stop("after/ambient+meetings+meetups", t)
	t = PerfProf.start()
	_closing()
	PerfProf.stop("after/closing", t)

## Visits scheduled for the home lot cannot start while nobody is home to receive the guests.
static func _postpone_visits() -> void:
	var now: int = SimEnv.now_min()
	for sit in Story.situations:
		if str(sit["state"]) != "scheduled" or now < int(sit["arrive_min"]):
			continue
		var ready: bool = false
		for hid in sit["host_ids"]:
			var hf = SysUtil.folk(int(hid))
			if hf != null and Neighborhood.where(int(hid)) == Neighborhood.HOME:
				ready = true
		if not ready:
			sit["arrive_min"] = int(sit["arrive_min"]) + 30
			sit["end_min"] = int(sit["end_min"]) + 30

## Venue ambience: a mood buff for every resident on a venue lot, refreshed on a timer.
static func _ambient() -> void:
	var now: int = SimEnv.now_min()
	for f in SysUtil.residents():
		if SysUtil.is_away(f):
			continue
		var lot_id: String = Neighborhood.lot_of(f)
		if lot_id == "" or lot_id == Neighborhood.HOME:
			continue
		var amb: Dictionary = Venues.ambient(Venues.type_of_lot(lot_id))
		if amb.is_empty():
			continue
		if now - int(f.get_meta("amb_last", -9999)) >= int(amb.get("every_min", 120)):
			f.set_meta("amb_last", now)
			f.add_buff(str(amb["buff"]))

static func _meetings() -> void:
	var now: int = SimEnv.now_min()
	if now % int(cfg().get("meet_check_min", 20)) != 0:
		return
	for r in SysUtil.residents():
		if SysUtil.is_away(r):
			continue
		var lot_id: String = Neighborhood.lot_of(r)
		if lot_id == "" or lot_id == Neighborhood.HOME:
			continue
		var lot_label: String = Neighborhood.label_of(lot_id)
		for n in Crowd.crowd_folk(lot_id):
			if n.has_meta("leaving"):
				continue
			var tid: int = int(n.get_meta("townie_id", -1))
			if tid < 0 or absi(r.tile.x - n.tile.x) + absi(r.tile.y - n.tile.y) > 7:
				continue
			var rid: int = int(r.id)
			if not RelationshipService.knows(rid, tid):
				if SysUtil.chance(0.55):
					RelationshipService.add_both(rid, tid, "friendship", float(Story.cfg().get("visits", {}).get("acquaintance_friendship", 6)))
					RelationshipService.add_history(rid, tid, "met", 0.3, tid)
					SysUtil.notify("%s met %s at %s." % [r.name, n.name, lot_label], "relationship")
					SysUtil.game_event("met_townie", {"folk_id": rid, "townie_id": tid, "lot_id": lot_id})
					break
			elif SysUtil.chance(0.3):
				RelationshipService.add_both(rid, tid, "friendship", 1.5)
				RelationshipService.touch(rid, tid)

# ------------------------------------------------------------------ closing time
static func _closing() -> void:
	var by_lot: Dictionary = {}           # lot id -> resident ids standing there (one pass over the residents, not one per lot)
	for r in SysUtil.residents():
		var rl: String = Neighborhood.lot_of_folk(r)
		if rl != "" and rl != Neighborhood.HOME:
			if not by_lot.has(rl):
				by_lot[rl] = []
			(by_lot[rl] as Array).append(int(r.id))
	if by_lot.is_empty():
		return
	for lot_id in Neighborhood.lot_ids():
		if lot_id == Neighborhood.HOME or not by_lot.has(lot_id):
			continue
		var here: Array = []
		for id in by_lot[lot_id]:
			if not Neighborhood.traveling(int(id)) and not SysUtil.is_away(SysUtil.folk(int(id))) and not Commute.exempt(SysUtil.folk(int(id)), lot_id):
				here.append(int(id))
		if here.is_empty():
			continue
		var left: int = Venues.minutes_to_close(lot_id)
		if left == int(cfg().get("closing_notice_min", 20)):
			SysUtil.notify("%s closes in %d minutes." % [Neighborhood.label_of(lot_id), left], "warn")
		if not Venues.is_open(lot_id):
			SysUtil.notify("%s is closed. Heading home." % Neighborhood.label_of(lot_id), "warn")
			Neighborhood.travel(here, Neighborhood.HOME, {"quiet": true})

# ------------------------------------------------------------------ hangouts
## Ask a townie to meet a folk at a venue (arrives `delay` minutes from now for `duration` minutes). Returns the record or {}.
static func invite_to_venue(townie_id: int, folk_id: int, lot_id: String, delay: int = 40, duration: int = 120) -> Dictionary:
	if not Story.townies.has(townie_id) or not bool(Story.townies[townie_id]["alive"]):
		return {}
	if Neighborhood.lot(lot_id).is_empty() or lot_id == Neighborhood.HOME:
		return {}
	var now: int = SimEnv.now_min()
	var arrive: int = now + delay
	if not Venues.is_open(lot_id, arrive) or not Venues.is_open(lot_id, arrive + 30):
		SysUtil.notify("%s will not be open then." % Neighborhood.label_of(lot_id), "warn")
		return {}
	var rec: Dictionary = {"townie_id": townie_id, "folk_id": folk_id, "lot_id": lot_id, "arrive_min": arrive, "end_min": arrive + duration,
		"state": "pending"}
	Neighborhood.meetups.append(rec)
	var hh: int = (arrive % 1440) / 60
	var mm: int = arrive % 60
	SysUtil.notify("%s will meet %s at %s around %02d:%02d." % [Story.name_of(townie_id), SysUtil.folk_name(folk_id), Neighborhood.label_of(lot_id), hh, mm], "invite")
	SysUtil.game_event("venue_invite", {"folk_id": folk_id, "townie_id": townie_id, "lot_id": lot_id})
	return rec

static func _meetups() -> void:
	if Neighborhood.meetups.is_empty():
		return
	var now: int = SimEnv.now_min()
	for m in Neighborhood.meetups:
		match str(m["state"]):
			"pending":
				if now < int(m["arrive_min"]):
					continue
				var lot_id: String = str(m["lot_id"])
				var folk_here: bool = Neighborhood.where(int(m["folk_id"])) == lot_id
				if folk_here and Crowd.count(lot_id) < Venues.crowd_cap() + 1:
					var t: Dictionary = Story.townies.get(int(m["townie_id"]), {})
					var existing = SysUtil.folk(int(m["townie_id"]))
					if t.is_empty() or (existing != null and not existing.has_meta("crowd")):
						m["state"] = "done"
						continue
					var npc = existing
					if npc == null:
						npc = Crowd.spawn_npc(t, lot_id, Venues.type_of_lot(lot_id), int(m["end_min"]) - now)
					else:
						npc.set_meta("leave_min", int(m["end_min"]))      # already in the crowd: they simply stay for the hangout
						if npc.has_meta("leaving"):
							npc.remove_meta("leaving")
					npc.set_meta("meetup", true)
					m["state"] = "here"
					var greet := Interaction.create("chat", npc, int(m["folk_id"]), false)
					if greet != null:
						npc.enqueue(greet)
					SysUtil.notify("%s arrived at %s to hang out with %s." % [npc.name, Neighborhood.label_of(lot_id), SysUtil.folk_name(int(m["folk_id"]))], "visit")
				elif now > int(m["arrive_min"]) + 60:
					m["state"] = "done"
					RelationshipService.add_both(int(m["folk_id"]), int(m["townie_id"]), "friendship", -3.0)
					SysUtil.notify("%s waited and gave up - nobody came." % Story.name_of(int(m["townie_id"])), "warn")
			"here":
				if now >= int(m["end_min"]):
					m["state"] = "done"
					var fid: int = int(m["folk_id"])
					var tid: int = int(m["townie_id"])
					RelationshipService.add_both(fid, tid, "friendship", 7.0)
					RelationshipService.add_history(fid, tid, "hangout", 0.6, tid)
					var f = SysUtil.folk(fid)
					if f != null:
						f.add_buff("social_glow")
						f.add_to_stat("social", 20.0)
					SysUtil.game_event("hangout_done", {"folk_id": fid, "townie_id": tid, "lot_id": m["lot_id"]})
	while Neighborhood.meetups.size() > 0 and str(Neighborhood.meetups[0]["state"]) == "done":
		Neighborhood.meetups.pop_front()

# ------------------------------------------------------------------ events
static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if not success:
		return
	var f = SysUtil.folk(folk_id)
	if f == null or not SysUtil.is_resident(f):
		return
	var lot_id: String = Neighborhood.lot_of(f)
	if lot_id == "" or lot_id == Neighborhood.HOME:
		return
	var xp: Array = Venues.interaction_xp(Venues.type_of_lot(lot_id)).get(iid, [])
	if xp.size() >= 2:
		f.add_skill_xp(str(xp[0]), float(xp[1]))

static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	match ev_name:
		"buy_groceries":
			var units: int = int(Neighborhood.cfg().get("pantry", {}).get("units_per_trip", 6))
			Neighborhood.add_pantry(units)
		"returned_to_lot":
			if str(payload.get("reason", "")) == Neighborhood.TRAVEL and bool(payload.get("completed", false)):
				var f = SysUtil.folk(int(payload.get("folk_id", -1)))
				if f != null:
					f.set_meta("amb_last", -9999)
					var at: String = Neighborhood.lot_of(f)
					if at != "":
						SysUtil.notify("%s arrived at %s." % [f.name, Neighborhood.label_of(at)], "travel")