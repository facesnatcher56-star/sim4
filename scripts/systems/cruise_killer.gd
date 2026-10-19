class_name CruiseKiller
extends RefCounted
## A killer aboard (task 22b: Incidents.force("serial_killer_aboard", {ship})). The normal serial-killer track (CrimeSerial state, CrimeMurder.kill,
## CaseDiscovery, CaseEvidence, JusticeProcess ...) on a ship, with the ship's own rules:
##   * the killer is a passenger (a real townie) who picks ISOLATED people at night: a night deck, a cabin corridor, someone alone at the rail;
##     the victim simply is not there any more (hidden death), so nobody knows at first,
##   * the disappearance is noticed at the next DINNER or morning HEADCOUNT (CaseDiscovery "missing"), the crew searches, the body is found,
##   * the passengers are frightened (buff), the captain RESTRICTS movement (no shore leave, the programme is cancelled, a curfew),
##   * ship security investigates by itself (CruiseCrime.security_hour: fewer places to hide, but no police at sea; the town police are held off
##     by the cases' `ship_hold`), may detain the suspect in the brig,
##   * at the next port (or the home quay) the POLICE take over: the cases are reported, an arrest is processed (charges, trial, sentence) like in town.
## Non-graphic: notifications and the chronicle only (place "cruise"). State in trip["cruise"]["killer"]:
##   {pid, name, victims [ids], cases [case ids], next_kill, detained, phase: hunting | detained | police | caught, restricted_at, started}
## Status for reports: CruiseKiller.status(trip_id).

static func cfg() -> Dictionary:
	return (CruiseRoute.cfg().get("killer", {}) as Dictionary)

static func of(t: Dictionary) -> Dictionary:
	return (t.get("cruise", {}) as Dictionary).get("killer", {})

static func status(trip_id: int) -> Dictionary:
	var k: Dictionary = of(Vacation.trip(trip_id))
	return k.duplicate(true)

# ------------------------------------------------------------------ start
## Put a killer among the passengers. ctx may carry `delay_hours`, `killer` (a townie id) or the forced `ship` (see IncidentFlow.last_force).
static func begin(t: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var c: Dictionary = t["cruise"]
	if not (c.get("killer", {}) as Dictionary).is_empty():
		return c["killer"]
	var forced: Dictionary = IncidentFlow.last_force
	var r := Vacation.rng_for(t)
	var pid: int = int(forced.get("killer", ctx.get("killer", -1)))
	if pid < 0:
		var cands: Array = []
		var weights: Array = []
		for npc in CruiseCrew.passengers(t):
			var tid: int = int(npc.get_meta("townie_id", -1))
			if tid < 0 or Story.townies.get(tid, {}).is_empty():
				continue
			cands.append(tid)
			weights.append(1.0 + (1.0 if CrimePerson.has_trait(tid, "loner") else 0.0) + (0.5 if not CrimePerson.has_job(tid) else 0.0))
		var pick = SysUtil.pick_weighted(cands, weights)
		pid = int(pick) if pick != null else -1
	if pid < 0:
		return {}
	var delay_h: float = float(forced.get("delay_hours", ctx.get("delay_hours", cfg().get("start_delay_hours", 18))))
	c["killer"] = {"pid": pid, "name": CrimePerson.name_of(pid), "victims": [], "cases": [], "next_kill": SysUtil.now() + int(delay_h * 60.0), "detained": -1,
		"phase": "hunting", "restricted_at": -1, "started": SysUtil.now(), "reported": []}
	if not CrimeSerial.active():
		CrimeSerial.start(pid)
	elif int(JusticeState.serial.get("pid", -1)) != pid:
		c["killer"]["note"] = "another run was already active"
	if JusticeState.serial.has("next_kill"):
		JusticeState.serial["next_kill"] = SysUtil.day() + 400          # the town waits: this killer works on the ship for now
	if Story.townies.has(pid):
		Story.townies[pid]["archetype"] = "serial"
	JusticeState.count("serial_aboard")
	return c["killer"]

# ------------------------------------------------------------------ hourly
static func on_hour(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var k: Dictionary = c.get("killer", {})
	if k.is_empty() or str(k["phase"]) == "caught":
		return
	var now: int = SysUtil.now()
	var h: int = int(SysUtil.hour_f())
	if int(k["detained"]) < 0 and (k["victims"] as Array).size() < int(cfg().get("victim_cap", 3)) and now >= int(k["next_kill"]):
		var iso: Array = cfg().get("isolation_hours", [23, 5])
		if h >= int(iso[0]) or h < int(iso[1]):
			_kill_one(t, k)
	if h == 19 or h == 8:
		_headcount(t, k, "dinner" if h == 19 else "the morning headcount")
	_search(t, k)
	if bool(c.get("restricted", false)) and h == 22:
		for f in Cruise.members_aboard(t):
			f.add_buff("confined")

static func _kill_one(t: Dictionary, k: Dictionary) -> void:
	var killer: int = int(k["pid"])
	var r := Vacation.rng_for(t)
	var ids: Array = []
	var w: Array = []
	for npc in CruiseCrew.passengers(t):
		var tid: int = int(npc.get_meta("townie_id", -1))
		if tid < 0 or tid == killer or (k["victims"] as Array).has(tid) or not CrimePerson.alive(tid):
			continue
		ids.append(tid)
		w.append(pow(CrimeSerial.isolation(tid), 2.0))
	for f in Cruise.members_aboard(t):
		ids.append(int(f.id))
		w.append(pow(CrimeSerial.isolation(int(f.id)), 2.0) * float(JusticeState.sect("serial").get("player_mult", 0.3)))
	var victim = SysUtil.pick_weighted(ids, w)
	if victim == null:
		return
	var v: int = int(victim)
	var places: Array = ["a quiet corner of the night deck", "an empty cabin corridor", "the rail at the stern", "a closed lounge"]
	var place: String = str(places[r.randi_range(0, places.size() - 1)])
	var resident: bool = CrimePerson.is_player(v)
	if not resident:
		remove_person(t, v, true)                                   # gone from the deck: a quiet, hidden disappearance
	var cs: Dictionary = CrimeMurder.kill(killer, v, "ship:%d" % int(t["id"]), "serial", {})
	cs["serial"] = 1
	cs["ship_hold"] = true
	cs["ship_trip"] = int(t["id"])
	cs["ship_place"] = place
	if not (t["cruise"].get("cases", null) is Array):
		t["cruise"]["cases"] = []
	(t["cruise"]["cases"] as Array).append(int(cs["id"]))
	(k["victims"] as Array).append(v)
	(k["cases"] as Array).append(int(cs["id"]))
	var s: Dictionary = JusticeState.serial
	if int(s.get("pid", -1)) == killer:
		(s["victims"] as Array).append(v)
		(s["cases"] as Array).append(int(cs["id"]))
		s["mistakes"] = float(s.get("mistakes", 0.0)) + float(cfg().get("mistake_per_victim", 0.28))
	k["next_kill"] = SysUtil.now() + int(r.randf_range(float((cfg().get("gap_hours", [14, 26]) as Array)[0]), float((cfg().get("gap_hours", [14, 26]) as Array)[1])) * 60.0)
	VacationLog.note(t, "crime", "Somebody was last seen alone at %s. (Only the ship's log knows; nobody has noticed yet.)" % place, [], 2, false)
	if resident:
		_alarm(t, k, "A member of the party was found dead on the ship.")

## The disappearance comes out at dinner or at the morning headcount.
static func _headcount(t: Dictionary, k: Dictionary, occasion: String) -> void:
	var now: int = SysUtil.now()
	for cid in k["cases"]:
		var cs: Dictionary = CaseStore.get_case(int(cid))
		if cs.is_empty() or str(cs["state"]) != "hidden" or now - int(cs["minute"]) < 6 * 60:
			continue
		var v: int = int(cs["victim"])
		CaseDiscovery.report(cs, CaseDiscovery._reporter_for(v), "missing")
		cs["ship_hold"] = true
		(k["reported"] as Array).append(v)
		VacationLog.note(t, "crime", "%s did not turn up at %s. The crew searched the decks and could not find them." % [CrimePerson.name_of(v), occasion], [v], 4, true)
		_alarm(t, k, "%s is missing from the ship." % CrimePerson.name_of(v))

static func _search(t: Dictionary, k: Dictionary) -> void:
	var r := Vacation.rng_for(t)
	for cid in k["cases"]:
		var cs: Dictionary = CaseStore.get_case(int(cid))
		if cs.is_empty() or str(cs["state"]) != "open" or bool(cs.get("found", true)):
			continue
		if r.randf() < 0.14:
			CaseDiscovery._found(cs, "search")
			cs["ship_hold"] = true
			VacationLog.note(t, "death", "The search found %s. The captain informed the police by radio." % CrimePerson.name_of(int(cs["victim"])), [int(cs["victim"])], 5, true)

## The ship takes fright: buffs, the captain's order, a notification.
static func _alarm(t: Dictionary, k: Dictionary, text: String) -> void:
	var c: Dictionary = t["cruise"]
	var scared: String = str(cfg().get("scared_buff", "ship_scare"))
	for f in Cruise.members_aboard(t):
		f.add_buff(scared)
	if not bool(c.get("restricted", false)):
		c["restricted"] = true
		k["restricted_at"] = SysUtil.now()
		VacationLog.note(t, "crime", "The captain ordered everyone to stay in public areas, cabins locked at night, no shore leave. Ship security is patrolling.", t["folk"], 4, true)
		SysUtil.notify("%s The captain has restricted movement on the ship." % text, "bad")
	else:
		SysUtil.notify(text, "bad")

static func on_detained(t: Dictionary, pid: int) -> void:
	var k: Dictionary = of(t)
	if k.is_empty():
		return
	k["detained"] = pid
	k["phase"] = "detained"
	var c: Dictionary = t["cruise"]
	if pid == int(k["pid"]):
		c["restricted"] = false
		for f in Cruise.members_aboard(t):
			f.remove_buff("confined")
		SysUtil.notify("The captain lifted the restrictions: the suspect is in the brig.", "good")

## The police boarded at a port: whatever the security knew is now theirs.
static func on_handover(t: Dictionary) -> void:
	var k: Dictionary = of(t)
	if k.is_empty():
		return
	var c: Dictionary = t["cruise"]
	c["restricted"] = false
	for f in Cruise.members_aboard(t):
		f.remove_buff("confined")
	if CrimePerson.in_custody(int(k["pid"])):
		k["phase"] = "caught"
	else:
		k["phase"] = "police"
		k["next_kill"] = maxi(int(k["next_kill"]), SysUtil.now() + 24 * 60)

## Remove a passenger from the ship (arrested, victim, overboard).
static func remove_person(t: Dictionary, pid: int, gone: bool = true) -> void:
	var f = SysUtil.folk(pid)
	if f != null and f.has_meta("trip_npc"):
		Crowd.dismiss(f)
	if gone:
		for e in t.get("roster", []):
			if int(e["id"]) == pid:
				e["gone"] = true

## The trip ends: a killer still free goes back to the town's normal serial track.
static func on_leave(t: Dictionary) -> void:
	var k: Dictionary = of(t)
	if k.is_empty() or str(k["phase"]) == "caught":
		return
	if int(JusticeState.serial.get("pid", -1)) == int(k["pid"]) and bool(JusticeState.serial.get("active", false)):
		JusticeState.serial["next_kill"] = SysUtil.day() + JusticeState.rng.randi_range(3, 8)
