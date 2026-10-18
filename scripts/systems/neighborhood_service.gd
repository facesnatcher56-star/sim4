class_name NeighborhoodService
extends RefCounted
## Per-minute / per-hour glue for the neighbourhood layer (called from SystemsManager):
##   before_minute()  - off-lot folk whose shift/school starts are woken up so Careers can dispatch them; postpones
##                      home visits while the player is elsewhere
##   after_minute()   - reconciles where everybody is, simple "statistical" need satisfaction for off-lot folk,
##                      ambient NPC crowd + staff, venue buffs, chance meetings, hangout invitations, closing time
##   on_interaction_finished / on_game_event - venue skill bonuses, groceries, arrival toasts
## Invitations: NeighborhoodService.invite_to_venue(townie_id, folk_id, lot_id) (also Story.invite_to_venue).

static func install() -> void:
	NeighborhoodContent.install()

static func cfg() -> Dictionary:
	return Venues.cfg()

# ------------------------------------------------------------------ minute
static func before_minute() -> void:
	for f in SysUtil.residents():
		if not f.has_meta("offlot"):
			continue
		var fid: int = int(f.id)
		var reason: String = str(Away.info(fid).get("reason", ""))
		if reason == "" and Away.pending.has(fid):
			reason = str((Away.pending[fid] as Dictionary).get("reason", ""))
		if reason != Neighborhood.STAY:
			continue
		if _duty_due(f):
			Neighborhood._detach_away(f)        # Careers.on_minute (next) sends them to work / school; the metas keep them hidden
	_postpone_visits()

static func after_minute() -> void:
	_reconcile()
	_stay_needs()
	Crowd.update()
	_ambient()
	_meetings()
	_meetups()
	_closing()

## Is a shift or school day starting for this off-lot folk?
static func _duty_due(f) -> bool:
	var fid: int = int(f.id)
	var day: int = SysUtil.day()
	var h: float = SysUtil.hour_f()
	if Careers.jobs.has(fid):
		var j: Dictionary = Careers.jobs[fid]
		return int(j["attempt_day"]) != day and Careers.is_work_day(str(j["career"]), day, str(j.get("shift", "day"))) \
			and Careers.in_shift_window(h, f.work_start, f.work_end)
	if Careers.school.has(fid):
		var sc: Dictionary = Careers.cfg().get("school", {})
		var st: Dictionary = Careers.school[fid]
		return int(st["attempt_day"]) != day and Careers.is_school_day(day) and h >= float(sc.get("start", 9)) and h < float(sc.get("end", 15))
	return false

## Visits scheduled for the home lot cannot start while nobody is home to receive the guests.
static func _postpone_visits() -> void:
	var now: int = SimEnv.now_min()
	for sit in Story.situations:
		if str(sit["state"]) != "scheduled" or now < int(sit["arrive_min"]):
			continue
		var ready: bool = Neighborhood.current_lot == Neighborhood.HOME
		if ready:
			ready = false
			for hid in sit["host_ids"]:
				var hf = SysUtil.folk(int(hid))
				if hf != null and not hf.has_meta("offlot") and Neighborhood.where(int(hid)) == Neighborhood.HOME:
					ready = true
		if not ready:
			sit["arrive_min"] = int(sit["arrive_min"]) + 30
			sit["end_min"] = int(sit["end_min"]) + 30

static func _reconcile() -> void:
	for f in SysUtil.residents():
		var fid: int = int(f.id)
		if Away.active.has(fid) or Away.pending.has(fid):
			continue
		var at: String = Neighborhood.where(fid)
		if at != Neighborhood.current_lot:
			Neighborhood.make_stay(f)
		elif f.has_meta("offlot"):
			Neighborhood.appear(f)

## Cheap stand-in for autonomy: off-lot folk eat, wash, sleep and socialise on simple rules so nobody starves.
static func _stay_needs() -> void:
	var h: float = SysUtil.hour_f()
	var night: bool = h >= 23.0 or h < 6.5
	for f in SysUtil.residents():
		if not f.has_meta("offlot") or str(Away.info(int(f.id)).get("reason", "")) != Neighborhood.STAY:
			continue
		var at: String = Neighborhood.where(int(f.id))
		var is_home_like: bool = at == Neighborhood.HOME or Venues.type_of_lot(at) == "townie_home"
		var vtype: String = Venues.type_of_lot(at)
		if f.get_stat_value("hunger") < -2.0:
			var cost: int = 0 if is_home_like else 5
			if cost == 0 or Economy.spend(int(f.household_id), cost, "meal out"):
				f.add_to_stat("hunger", 48.0)
				f.add_to_stat("fun", 3.0)
		if f.get_stat_value("bladder") < -8.0:
			f.add_to_stat("bladder", 70.0)
		if f.get_stat_value("hygiene") < -8.0:
			f.add_to_stat("hygiene", 55.0 if is_home_like else 25.0)
		if night and f.get_stat_value("energy") < 92.0:
			f.add_to_stat("energy", 0.35)
		elif f.get_stat_value("energy") < -8.0:
			f.add_to_stat("energy", 35.0)
		if f.get_stat_value("social") < -8.0:
			f.add_to_stat("social", 35.0 if vtype in ["cafe", "park", "townie_home"] else 28.0)
		if f.get_stat_value("fun") < -8.0:
			f.add_to_stat("fun", 32.0)
		if f.get_stat_value("comfort") < -8.0:
			f.add_to_stat("comfort", 30.0)

## Venue ambience: a mood buff for every resident on the lot, refreshed on a timer.
static func _ambient() -> void:
	if Neighborhood.current_lot == Neighborhood.HOME:
		return
	var amb: Dictionary = Venues.ambient(Venues.type_of_lot(Neighborhood.current_lot))
	if amb.is_empty():
		return
	var now: int = SimEnv.now_min()
	for f in SysUtil.residents():
		if f.has_meta("offlot") or SysUtil.is_away(f) or Neighborhood.where(int(f.id)) != Neighborhood.current_lot:
			continue
		if now - int(f.get_meta("amb_last", -9999)) >= int(amb.get("every_min", 120)):
			f.set_meta("amb_last", now)
			f.add_buff(str(amb["buff"]))

static func _meetings() -> void:
	if Neighborhood.current_lot == Neighborhood.HOME:
		return
	var now: int = SimEnv.now_min()
	if now % int(cfg().get("meet_check_min", 20)) != 0:
		return
	var lot_label: String = Neighborhood.label_of(Neighborhood.current_lot)
	for r in SysUtil.residents():
		if r.has_meta("offlot") or SysUtil.is_away(r):
			continue
		for n in Crowd.crowd_folk():
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
					SysUtil.game_event("met_townie", {"folk_id": rid, "townie_id": tid, "lot_id": Neighborhood.current_lot})
					break
			elif SysUtil.chance(0.3):
				RelationshipService.add_both(rid, tid, "friendship", 1.5)
				RelationshipService.touch(rid, tid)

# ------------------------------------------------------------------ closing time
static func _closing() -> void:
	var lot_id: String = Neighborhood.current_lot
	if lot_id == Neighborhood.HOME:
		return
	var left: int = Venues.minutes_to_close(lot_id)
	var here: Array = Neighborhood.folk_at(lot_id)
	if here.is_empty():
		return
	if left == int(cfg().get("closing_notice_min", 20)):
		SysUtil.notify("%s closes in %d minutes." % [Neighborhood.label_of(lot_id), left], "warn")
	if not Venues.is_open(lot_id):
		var ids: Array = []
		for id in here:
			if not Neighborhood.traveling(int(id)):
				ids.append(int(id))
		if not ids.is_empty():
			SysUtil.notify("%s is closed. Heading home." % Neighborhood.label_of(lot_id), "warn")
			Neighborhood.travel(ids, Neighborhood.HOME, {"quiet": true})

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
				var folk_here: bool = Neighborhood.current_lot == str(m["lot_id"]) and Neighborhood.where(int(m["folk_id"])) == Neighborhood.current_lot
				if folk_here and Crowd.count() < Venues.crowd_cap() + 1:
					var t: Dictionary = Story.townies.get(int(m["townie_id"]), {})
					var existing = SysUtil.folk(int(m["townie_id"]))
					if t.is_empty() or (existing != null and not existing.has_meta("crowd")):
						m["state"] = "done"
						continue
					var npc = existing
					if npc == null:
						npc = Crowd.spawn_npc(t, str(m["lot_id"]), Venues.type_of_lot(str(m["lot_id"])), int(m["end_min"]) - now)
					else:
						npc.set_meta("leave_min", int(m["end_min"]))      # already in the crowd: they simply stay for the hangout
						if npc.has_meta("leaving"):
							npc.remove_meta("leaving")
					npc.set_meta("meetup", true)
					m["state"] = "here"
					var greet := Interaction.create("chat", npc, int(m["folk_id"]), false)
					if greet != null:
						npc.enqueue(greet)
					SysUtil.notify("%s arrived at %s to hang out with %s." % [npc.name, Neighborhood.label_of(str(m["lot_id"])), SysUtil.folk_name(int(m["folk_id"]))], "visit")
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
	if not success or Neighborhood.current_lot == Neighborhood.HOME:
		return
	var f = SysUtil.folk(folk_id)
	if f == null or not SysUtil.is_resident(f):
		return
	var xp: Array = Venues.interaction_xp(Venues.type_of_lot(Neighborhood.current_lot)).get(iid, [])
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
					if Neighborhood.where(int(f.id)) == Neighborhood.current_lot:
						SysUtil.notify("%s arrived at %s." % [f.name, Neighborhood.label_of(Neighborhood.current_lot)], "travel")
