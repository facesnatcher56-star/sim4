class_name CruiseIncidents
extends RefCounted
## The rare happenings of a cruise (task 22, data/incidents/22_cruise.json, all very rare, all with the Incidents force hook): storm at sea,
## stomach-bug outbreak (Health illness "norovirus", spreads aboard), a fire on board (Fire.ignite; ship rules: the crew put it out), someone
## overboard (search and rescue; death very rare), a theft from a cabin, a crime among passengers (both handled by ship security, then the
## police at the next port: CruiseCrime) and the forced killer (CruiseKiller). One handler `cruise_incident` serves them all (args.kind).
## Everything is announced as short notifications and logged with place "cruise"; nothing is shown graphically.

static func cfg() -> Dictionary:
	return (CruiseRoute.cfg().get("incident", {}) as Dictionary)

## The cruise trip an incident is about: the household's own cruise, else the one named by a forced `ship` (trip id or ship id), else any.
static func trip_for(ctx: Dictionary) -> Dictionary:
	var hid: int = int(ctx.get("household_id", 0))
	var t: Dictionary = Vacation.trip_of_household(hid)
	var forced: Variant = IncidentFlow.last_force.get("ship", null)
	if forced != null:
		for id in Cruise.ship_ids():
			var tt: Dictionary = Vacation.trip(int(id))
			if str(forced) == str(id) or str(forced) == str((tt.get("cruise", {}) as Dictionary).get("ship", "")):
				return tt
	if not t.is_empty() and str(t["dest"]) == "cruise" and str(t["state"]) == "there":
		return t
	for id2 in Cruise.ship_ids():
		var t2: Dictionary = Vacation.trip(int(id2))
		if str(t2["state"]) == "there":
			return t2
	return {}

static func on_incident(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ctx.get("statistical", false)):
		return {"text": ""}
	var t: Dictionary = trip_for(ctx)
	if t.is_empty() or str(t["state"]) != "there" or Cruise.of(t).is_empty():
		return {"text": ""}
	match str(args.get("kind", "")):
		"storm": storm(t)
		"norovirus": norovirus(t)
		"fire": fire(t)
		"overboard": overboard(t)
		"cabin_theft": cabin_theft(t)
		"onboard_crime": onboard_crime(t)
		"serial_killer": CruiseKiller.begin(t, ctx)
	return {"text": ""}

static func people_aboard(t: Dictionary) -> Array:
	var out: Array = Cruise.members_aboard(t).duplicate()
	out.append_array(CruiseCrew.passengers(t))
	return out

# ------------------------------------------------------------------ storm
static func storm(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	c["storm_until"] = SysUtil.now() + int(cfg().get("storm_hours", 9)) * 60
	c["sea"] = "rough"
	VacationLog.note(t, "incident", "A storm hit %s: the decks were cleared and the sea was rough." % str(c["name"]), t["folk"], 2, true)
	SysUtil.notify("A storm at sea! Hold on to something.", "warn")
	CruiseLife._seasick(t)
	for f in Cruise.members_aboard(t):
		f.add_to_stat("comfort", -12.0)

# ------------------------------------------------------------------ stomach bug
static func norovirus(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	c["noro_until"] = SysUtil.now() + int(cfg().get("noro_days", 3)) * 1440
	var aboard: Array = Cruise.members_aboard(t)
	var zero: String = "a passenger"
	if not aboard.is_empty() and r.randf() < 0.5:
		var f = aboard[r.randi_range(0, aboard.size() - 1)]
		Health.fall_ill(f, "norovirus", 1, "a stomach bug")
		zero = str(f.name)
	else:
		var ps: Array = CruiseCrew.passengers(t)
		if not ps.is_empty():
			var p = ps[r.randi_range(0, ps.size() - 1)]
			zero = str(p.name)
			(c["ill"] as Array).append(int(p.id))
	VacationLog.note(t, "incident", "A stomach bug broke out aboard, starting with %s. The crew began disinfecting and asked everyone to wash their hands." % zero, t["folk"], 3, true)
	SysUtil.notify("A stomach bug is spreading on %s. Wash your hands and rest if you feel ill." % str(c["name"]), "warn")

## Hourly while the outbreak lasts: the bug spreads among the party and the passengers.
static func noro_hour(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	if SysUtil.now() >= int(c.get("noro_until", 0)):
		return
	var r := Vacation.rng_for(t)
	var p: float = float(cfg().get("noro_spread", 0.45)) / 24.0
	for f in Cruise.members_aboard(t):
		if f.has_buff("norovirus") or f.has_buff("immune_noro"):
			continue
		var pm: float = p * (2.0 if f.has_buff("exposed_noro") else 1.0)
		if r.randf() < pm * float(maxi(ill_count(t), 1)):
			Health.fall_ill(f, "norovirus", 1, "the stomach bug")
			VacationLog.note(t, "incident", "%s came down with the stomach bug." % f.name, [int(f.id)], 2, true)
	for npc in CruiseCrew.passengers(t):
		if not (c["ill"] as Array).has(int(npc.id)) and r.randf() < p * 2.0:
			(c["ill"] as Array).append(int(npc.id))

static func ill_count(t: Dictionary) -> int:
	var n: int = (t["cruise"]["ill"] as Array).size()
	for f in Cruise.members_aboard(t):
		if f.has_buff("norovirus"):
			n += 1
	return n

# ------------------------------------------------------------------ fire
static func fire(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	var rc := DestLoader.zone_rect(int(t["zone"]))
	var cand: Array = []
	for o in WorldIface.world().objects.values():
		if rc.has_point(o.tile) and not o.is_wall_mounted() and not o.is_floor_layer() and not bool(o.def.has("portal")):
			cand.append(o)
	cand.sort_custom(func(a, b): return int(a.id) < int(b.id))
	if cand.is_empty():
		return
	var o2 = cand[r.randi_range(0, cand.size() - 1)]
	var ok: bool = Fire.ignite(o2, "electrical", {"force": true})
	if not ok:
		return
	var deck: String = "deck %d" % (int(o2.level) + 2)
	c["fire_lot"] = str(t["lot"])
	Cruise.schedule(t, SysUtil.now() + int(cfg().get("fire_alarm_minutes", 25)), "fire_out")
	VacationLog.note(t, "incident", "Fire on %s! The alarm sounded and the crew rushed to the %s." % [deck, str(o2.def.get("label", o2.def_id)).to_lower()], t["folk"], 4, true)
	SysUtil.notify("FIRE on board! Follow the crew's instructions.", "bad")

# ------------------------------------------------------------------ overboard
static func overboard(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	var pool: Array = []
	var weights: Array = []
	for npc in CruiseCrew.passengers(t):
		pool.append(npc)
		weights.append(1.0)
	for f in Cruise.members_aboard(t):
		pool.append(f)
		weights.append(0.5)
	if pool.is_empty():
		return
	var forced: Dictionary = IncidentFlow.last_force               # tests / reports: {victim: folk id, rescued: bool}
	var victim = SysUtil.folk(int(forced["victim"])) if forced.has("victim") else SysUtil.pick_weighted(pool, weights)
	if victim == null:
		return
	var hours: int = int(cfg().get("overboard_search_hours", 3))
	var rescued: bool = bool(forced["rescued"]) if forced.has("rescued") else r.randf() < float(cfg().get("overboard_rescue_chance", 0.92))
	c["search"] = {"pid": int(victim.id), "name": str(victim.name), "rescued": rescued, "party": victim.household_id > 0}
	Cruise.schedule(t, SysUtil.now() + hours * 60, "overboard_end")
	if victim.household_id > 0:
		victim.add_buff("shaken")
	CruiseKiller.remove_person(t, int(victim.id), true)
	VacationLog.note(t, "incident", "Man overboard! %s went over the rail. The ship turned back and a search and rescue began." % victim.name, [int(victim.id)], 4, true)
	SysUtil.notify("Overboard! The ship has stopped for a search and rescue.", "bad")

static func overboard_end(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var s: Dictionary = c.get("search", {})
	if s.is_empty():
		return
	c.erase("search")
	var pid: int = int(s["pid"])
	if bool(s["rescued"]):
		VacationLog.note(t, "incident", "%s was pulled from the water, cold and shaken but alive." % str(s["name"]), [pid], 3, true)
		SysUtil.notify("%s was rescued!" % str(s["name"]), "good")
		if bool(s.get("party", false)):
			var f = SysUtil.folk(pid)
			if f != null:
				f.add_buff("shaken")
			return
		_respawn(t, pid)
	else:
		VacationLog.note(t, "death", "The search for %s was called off. They did not survive the night in the sea." % str(s["name"]), [pid], 5, true)
		SysUtil.notify("The search for %s was called off." % str(s["name"]), "death")
		if Story.townies.has(pid) or SysUtil.folk(pid) != null:
			Aging.kill(pid, "overboard")

static func _respawn(t: Dictionary, pid: int) -> void:
	for e in t.get("roster", []):
		if int(e["id"]) == pid:
			e.erase("gone")
	VacationLife.ensure_npcs(t, 6)

# ------------------------------------------------------------------ thefts and brawls
static func cabin_theft(t: Dictionary) -> void:
	var r := Vacation.rng_for(t)
	var cands: Array = CruiseCrew.passengers(t).filter(func(x): return str(x.age_stage) in ["adult", "elder"])
	var aboard: Array = Cruise.members_aboard(t)
	if cands.is_empty() or aboard.is_empty():
		return
	var thief = cands[r.randi_range(0, cands.size() - 1)]
	var victim = aboard[r.randi_range(0, aboard.size() - 1)]
	var loss: Array = CruiseCrime.cfg().get("cabin_theft_loss", [40, 220])
	var amt: int = r.randi_range(int(loss[0]), int(loss[1]))
	amt = mini(amt, maxi(Economy.balance(int(t["hid"])), 0))
	var cs: Dictionary = CruiseCrime.open(t, "theft", int(thief.id), int(victim.id), {"coins": amt})
	Economy.deposit(int(t["hid"]), -amt, "stolen from the cabin")
	CrimePerson.add_coins(int(thief.id), amt)
	CruiseCrime.report_aboard(t, cs, int(victim.id), "noticed")
	VacationLog.note(t, "crime", "%s found %d coins missing from the cabin safe. Ship security was told." % [victim.name, amt], [int(victim.id)], 3, true)
	SysUtil.notify("Theft in a cabin: %d coins gone. Ship security is investigating." % amt, "bad")
	Cruise.schedule(t, SysUtil.now() + int(cfg().get("security_arrest_delay_min", 90)), "security_check", {"case": int(cs["id"])})

static func onboard_crime(t: Dictionary) -> void:
	var r := Vacation.rng_for(t)
	var ps: Array = CruiseCrew.passengers(t)
	if ps.size() < 2:
		return
	var a = ps[r.randi_range(0, ps.size() - 1)]
	var b = ps[r.randi_range(0, ps.size() - 1)]
	if a == b:
		return
	var cs: Dictionary = CruiseCrime.open(t, "assault", int(a.id), int(b.id), {})
	CruiseCrime.report_aboard(t, cs, int(b.id), "seen")
	VacationLog.note(t, "crime", "%s hit %s in an argument at the bar. Ship security separated them and wrote up the incident." % [a.name, b.name], [int(a.id), int(b.id)], 3, true)

# ------------------------------------------------------------------ timeline entries of the incidents
static func on_timeline(t: Dictionary, e: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	match str(e["kind"]):
		"fire_out":
			var n: int = Fire.extinguish_lot(str(c.get("fire_lot", t["lot"])), "crew")
			c.erase("fire_lot")
			VacationLog.note(t, "incident", "The crew put the fire out%s." % (" after %d burning spots" % n if n > 1 else ""), t["folk"], 3, true)
		"overboard_end":
			overboard_end(t)
		"security_check":
			CruiseCrime.security_hour(t)
		"killer_hour":
			CruiseKiller.on_hour(t)
