class_name PlaceAutoTrip
extends RefCounted
## Walking out, using the service and coming home (task 14b), one trip per person. Every step is a call the Town window makes (LifeCommand):
##   go {place}  ->  use {place, service, target}  (or phone_invite {other, outing} to take company, phone_respond {id, yes} for an invitation)  ->  home
## A due plan starts when the person is free (not at work, asleep, hurt, steered by the player ...); if they are not free within `wait_min` it is dropped.
## states: go (walking there) -> use (arrived, pick the service now) -> visit (the visit runs) -> done (walk home, the trip is erased).
## Runs once a game minute only while a plan is waiting or a trip is on (SimRegistry gate PlaceAuto.busy).

const PLAYER := 1          # the command layer wants a player id; autonomy acts for nobody in particular (LifeCommand ignores it)

static func can_go(f) -> bool:
	return block_reason(f) == ""

## Why this person cannot set off right now ("" = free): a word for the drop statistics.
static func block_reason(f) -> String:
	if f == null or not SysUtil.is_resident(f):
		return "gone"
	var fid: int = int(f.id)
	if SysUtil.is_away(f) or Away.pending.has(fid) or Vacation.on_trip(fid) or Commute.active(fid):
		return "away"
	if Hospital.is_in(fid) or JusticeState.inmates.has(fid) or Health.is_collapsed(f):
		return "hospital"
	if CareerShifts.player_busy(f) or PlaceUse.pending.has(fid):
		return "ordered"
	if CareerShifts.is_critical(f):
		return "critical"
	var c: Dictionary = PlaceAuto.cfg()
	if f.get_stat_value("energy") < float(c.get("min_energy", -45)) or f.get_stat_value("bladder") < float(c.get("min_bladder", -50)):
		return "tired"
	if f.current != null and (f.current.def.get("tags", []) as Array).has("sleep") and not PlaceAutoTime.awake(f, SysUtil.hour_f()):
		return "asleep"             # a nap in the day is cut short for an appointment, the night's sleep is not
	if NeighborhoodLots.walking_to(f) != "":
		return "walking"
	return ""

static func on_minute() -> void:
	var now: int = SysUtil.now()
	if not PlaceAuto.plans.is_empty():
		var keep: Array = []
		for p in PlaceAuto.plans:
			if int(p["expires"]) <= now:
				PlaceAuto.count("dropped")
				PlaceAuto.tick("drops", "expired:%s:%s" % [str(p["kind"]), str(p.get("why", "busy"))])
				continue
			if int(p["at"]) > now or not _start(p, now):
				keep.append(p)
		PlaceAuto.plans = keep
	if not PlaceAuto.trips.is_empty():
		var ids: Array = PlaceAuto.trips.keys()
		ids.sort()
		for fid in ids:
			_step(int(fid), now)

# ------------------------------------------------------------------ starting
## A service of the plan the person may use right now ("" = none yet).
static func choose(f, services: Array, kind_pick: String, target: int) -> String:
	var ok: Array = []
	var now: int = SysUtil.now()
	for s in services:
		var pid: String = PlaceAutoPlan.place_of(str(s))
		if pid == "" or not Places.is_open(pid, now) or not PlaceAutoPlan.viable_at(f, str(s), now, target):
			continue
		var svc: Dictionary = Places.services(pid)[str(s)]
		if bool(svc.get("once_per_day", false)) and int(PlaceUse.last_used.get("%d|%s" % [int(f.id), str(s)], -1)) == SysUtil.day():
			continue
		if not Economy.can_afford(int(f.household_id), PlaceUse.price(pid, str(s), int(f.id))):
			continue
		ok.append(str(s))
	if ok.is_empty():
		return ""
	return str(ok[PlaceAuto.rng.randi_range(0, ok.size() - 1)]) if kind_pick == "random" else str(ok[0])

## Try to start a due plan. Returns true when it is finished with (started or dropped), false to keep waiting.
static func _start(p: Dictionary, now: int) -> bool:
	var fid: int = int(p["fid"])
	var f = SysUtil.folk(fid)
	if f == null or PlaceAuto.trips.has(fid):
		return f == null
	var why: String = block_reason(f)
	if why != "":
		p["why"] = why
		return false
	var d: Dictionary = PlaceAutoPlan.kind_def(str(p["kind"]))
	var ctx: Dictionary = p.get("ctx", {})
	var sid: String = choose(f, p["services"], str(d.get("pick", "first")), int(ctx.get("target", -1)))
	if sid == "":
		p["why"] = "closed"
		return false
	var pid: String = PlaceAutoPlan.place_of(sid)
	var trip := {"kind": str(p["kind"]), "place": pid, "service": sid, "state": "go", "t0": now, "ctx": ctx.duplicate(), "services": (p["services"] as Array).duplicate(), "until": 0}
	if Places.is_there(f, pid):
		trip["state"] = "use"
	else:
		var go: Dictionary = LifeCommand.run(PLAYER, fid, "go", {"place": pid, "opts": {"quiet": true, "silent": PlaceAuto.quiet_for(f)}})
		if not bool(go.get("ok", false)):
			PlaceAuto.count("dropped")
			PlaceAuto.tick("drops", "go:" + str(p["kind"]))
			return true
	PlaceAuto.trips[fid] = trip
	PlaceAuto.count("started")
	PlaceAuto.tick("kinds", str(p["kind"]))
	return true

# ------------------------------------------------------------------ following
static func _step(fid: int, now: int) -> void:
	var t: Dictionary = PlaceAuto.trips[fid]
	var f = SysUtil.folk(fid)
	if f == null:
		PlaceAuto.trips.erase(fid)
		return
	match str(t["state"]):
		"go":
			if Places.is_there(f, str(t["place"])) and NeighborhoodLots.walking_to(f) == "":
				t["state"] = "use"
			elif now - int(t["t0"]) > int(PlaceAuto.cfg().get("walk_limit_min", 120)):
				_finish(f, t, false, "late")
				return
			else:
				return
			_use(f, t, now)
		"use":
			_use(f, t, now)
		"visit":
			if not PlaceUse.pending.has(fid) or now > int(t["until"]):
				_finish(f, t, true, "")

static func _use(f, t: Dictionary, now: int) -> void:
	var fid: int = int(f.id)
	var ctx: Dictionary = t["ctx"]
	var d: Dictionary = PlaceAutoPlan.kind_def(str(t["kind"]))
	if not can_go(f) and not PlaceUse.pending.has(fid):
		if now - int(t["t0"]) > int(PlaceAuto.cfg().get("walk_limit_min", 120)):
			_finish(f, t, false, "busy")
		return
	var sid: String = choose(f, t["services"], str(d.get("pick", "first")), int(ctx.get("target", -1)))
	if sid == "":
		_finish(f, t, false, "closed")
		return
	var pid: String = PlaceAutoPlan.place_of(sid)
	var res: Dictionary = {}
	if ctx.has("invite"):
		res = LifeCommand.run(PLAYER, fid, "phone_respond", {"id": int(ctx["invite"]), "yes": true})
	else:
		var buddy: Dictionary = _company(f, d, pid)
		if not buddy.is_empty():
			res = LifeCommand.run(PLAYER, fid, "phone_invite", {"other": int(buddy["id"]), "outing": str(buddy["outing"]), "pay_both": true})
			if not bool(res.get("ok", false)) or not bool(res.get("accepted", false)):
				res = {}
		if res.is_empty():
			res = LifeCommand.run(PLAYER, fid, "use", {"place": pid, "service": sid, "target": int(ctx.get("target", -1)), "quiet": PlaceAuto.quiet_for(f)})
	if not bool(res.get("ok", false)):
		_finish(f, t, false, "refused")
		PlaceAuto.tick("drops", "use:%s:%s" % [str(t["kind"]), str(res.get("reason", ""))])
		return
	PlaceAuto.mark(fid, str(t["kind"]))
	t["service"] = sid
	t["state"] = "visit"
	var svc: Dictionary = Places.services(pid).get(sid, {})
	t["until"] = now + int(svc.get("minutes", 0)) + 60

## A partner or friend to take along ({id, outing} or {}).
static func _company(f, d: Dictionary, pid: String) -> Dictionary:
	var oid: String = str(d.get("company", ""))
	if oid == "":
		return {}
	var o: Dictionary = PhoneCmd.outing_by_id(oid)
	if o.is_empty() or str(o.get("place", "")) != pid:
		return {}
	var c: Dictionary = PlaceAuto.cfg()
	var fid: int = int(f.id)
	var best: Array = []
	var ws: Array = []
	for row in PhoneCmd.contacts(fid, 14):
		if str(row["reason"]) != "" or not (c.get("company_bits", []) as Array).has(str(row["bit"])):
			continue
		if float(row["friendship"]) < float(c.get("company_min_friendship", 30)) or not LifeOuting.could(fid, int(row["id"]), o):
			continue
		if LifeOuting.why_not(fid, int(row["id"]), o) != "":
			continue
		best.append(row)
		ws.append(float(row["friendship"]) * (2.0 if str(row["bit"]) in ["partner", "spouse", "sweetheart", "dating"] else 1.0))
	if best.is_empty() or PlaceAuto.rng.randf() >= float(c.get("company_chance", 0.45)):
		return {}
	var pick: Variant = PlaceAutoGate._weighted(best, ws)
	return {} if pick == null else {"id": int(pick["id"]), "outing": oid}

static func _finish(f, t: Dictionary, ok: bool, why: String) -> void:
	var fid: int = int(f.id)
	PlaceAuto.trips.erase(fid)
	if ok:
		PlaceAuto.count("done")
	else:
		PlaceAuto.count("dropped")
		PlaceAuto.tick("drops", why + ":" + str(t["kind"]))
	if str(t["place"]) != "" and Places.lot_of(str(t["place"])) != Places.HOME and not SysUtil.is_away(f):
		LifeCommand.run(PLAYER, fid, "home", {"opts": {"quiet": true, "silent": PlaceAuto.quiet_for(f)}})
