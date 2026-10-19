class_name ChaosClock
extends RefCounted
## Household chaos (task 07) over time: running water (damage per hour, mould, an overflow that stops by itself), roaches that grow while the
## house is messy, tradespeople who arrive some time after the call, and the player's repair interactions (their game events land here).
## Hooks (Incidents.on_minute / on_hour / on_day, SystemsManager game events) are no-ops while nothing is wrong.

# ------------------------------------------------------------------ markers
## Residents carry `plumbing_trouble` while water runs, `roaches_seen` once there are roaches, `pest_trouble` from the infestation level, `broken_things` while something is broken.
static func sync_markers(hid: int) -> void:
	var c: Dictionary = ChaosState.cfg("pests")
	var wet: bool = not ChaosState.leak_of(hid).is_empty()
	var bugs: bool = ChaosState.pest_level(hid) >= float(c.get("infested", 0.5))
	var broken: bool = not broken_objects(hid).is_empty()
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			_mark(f, "plumbing_trouble", wet)
			_mark(f, "roaches_seen", ChaosState.pest_level(hid) >= float(c.get("seen", 0.01)))
			_mark(f, "pest_trouble", bugs)
			_mark(f, "broken_things", broken)
	DisasterAftermath.sync_markers(hid)

static func _mark(f, buff: String, on: bool) -> void:
	if on and not f.has_buff(buff):
		f.add_buff(buff)
	elif not on and f.has_buff(buff):
		f.remove_buff(buff)

static func broken_objects(hid: int) -> Array:
	var out: Array = []
	for o in Economy.objects_of(hid):
		if bool(WorldIface.state_get(o, "broken", false)):
			out.append(o)
	return out

# ------------------------------------------------------------------ clock
static func on_minute() -> void:
	if ChaosState.jobs.is_empty():
		return
	var now: int = SysUtil.now()
	var keep: Array = []
	for j in ChaosState.jobs:
		if int(j["due"]) > now:
			keep.append(j)
			continue
		match str(j["kind"]):
			"plumber":
				stop_leak(int(j["hid"]), "the plumber")
			"exterminator":
				exterminate(int(j["hid"]))
			"handy":
				fix_all(int(j["hid"]))
	ChaosState.jobs = keep

static func on_hour() -> void:
	for key in ChaosState.leaks.keys():
		_leak_hour(int(key))

static func on_day() -> void:
	for key in ChaosState.pests.keys():
		_pest_day(int(key))

static func _leak_hour(hid: int) -> void:
	var lk: Dictionary = ChaosState.leak_of(hid)
	if lk.is_empty():
		return
	if not Economy.household_ids().has(hid):
		ChaosState.leaks.erase(str(hid))
		return
	var c: Dictionary = ChaosState.cfg(str(lk["kind"]))
	lk["hours"] = int(lk["hours"]) + 1
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	rec["cost"] = int(rec["cost"]) + int(c.get("flow_cost_per_hour", 10))
	rec["flood"] = minf(1.0, float(rec["flood"]) + float(c.get("flood_per_hour", 0.05)))
	var o = WorldIface.get_object(int(lk["obj"]))
	if o != null:
		ChaosEvents.spill(o.tile, c)
	if int(c.get("mould_after_hours", 0)) > 0 and int(lk["hours"]) == int(c["mould_after_hours"]):
		rec["mould"] = maxf(float(rec["mould"]), float(c.get("mould_start", 0.35)))
		ChaosState.count("mould")
		SysUtil.notify("The water has soaked in and damp is setting into the walls. Stop the leak and scrub the mould before it spreads.", "warn")
	if int(c.get("stops_after_hours", 0)) > 0 and int(lk["hours"]) >= int(c["stops_after_hours"]):
		ChaosState.leaks.erase(str(hid))
		SysUtil.notify("The water has stopped running. The toilet stays out of use until it is repaired.", "info")
	sync_markers(hid)

static func _pest_day(hid: int) -> void:
	var rec: Dictionary = ChaosState.pests[str(hid)]
	if not Economy.household_ids().has(hid):
		ChaosState.pests.erase(str(hid))
		return
	var c: Dictionary = ChaosState.cfg("pests")
	var before: float = float(rec["level"])
	var messy: bool = ChaosConds.mess_score(hid) >= int(c.get("messy_at", 2))
	var free: bool = int(rec.get("free_until", -1)) > SysUtil.day()
	var d: float = float(c.get("grow_per_day", 0.1)) if (messy and not free) else -float(c.get("decay_per_day", 0.06))
	rec["level"] = clampf(before + d, 0.0, 1.0)
	var lv: float = float(rec["level"])
	if lv <= 0.0:
		if before > 0.0:
			SysUtil.notify("The roaches are gone. Keep the kitchen clean and they stay away.", "good")
		if free:
			rec["level"] = 0.0                                   # keep the record: it holds the protection period
		else:
			ChaosState.pests.erase(str(hid))
		sync_markers(hid)
		return
	if lv >= float(c.get("infested", 0.5)):
		for o in Economy.objects_of(hid):
			if str(o.def_id) == "fridge" and WorldIface.state_get(o, "spoiled", null) != null:
				WorldIface.state_add(o, "spoiled", float(c.get("fridge_spoil", 1.0)))
		if before < float(c.get("infested", 0.5)):
			var msg := "The roaches have taken over the kitchen. The food is being spoiled and everyone feels grubby. Clean up, set traps or call an exterminator."
			SysUtil.notify(msg, "bad")
			ChronicleHook.note("pests", msg, [], "home:%d" % hid, 2, false)
	if lv >= float(c.get("swarm", 0.85)):
		var res: Array = SysUtil.residents().filter(func(f): return int(f.household_id) == hid and not f.has_buff("sick"))
		if not res.is_empty() and Incidents.rng.randf() < float(c.get("sick_chance", 0.15)):
			Hospital.fall_ill(res[Incidents.rng.randi_range(0, res.size() - 1)], 1, "something they ate from a roach-ridden kitchen")
	sync_markers(hid)

# ------------------------------------------------------------------ fixes
static func stop_leak(hid: int, by: String) -> void:
	var lk: Dictionary = ChaosState.leak_of(hid)
	if lk.is_empty():
		return
	ChaosState.leaks.erase(str(hid))
	var o = WorldIface.get_object(int(lk["obj"]))
	if o != null:
		unbreak(hid, o)
	ChaosState.count("leaks_fixed")
	SysUtil.notify("The leak is fixed by %s. Mop up the puddles and scrub away any mould; call the repairers for the water damage." % by, "good")
	sync_markers(hid)

static func unbreak(hid: int, o) -> void:
	WorldIface.state_set(o, "broken", false)
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	(rec["broken"] as Array).erase(int(o.id))

static func fix_all(hid: int) -> void:
	var n := 0
	for o in broken_objects(hid):
		if int(ChaosState.leak_of(hid).get("obj", -1)) == int(o.id):
			continue                                   # a running leak needs the plumber
		unbreak(hid, o)
		n += 1
	if n > 0:
		SysUtil.notify("The handyperson fixed %d broken thing%s." % [n, "" if n == 1 else "s"], "good")
	sync_markers(hid)

static func exterminate(hid: int) -> void:
	ChaosState.pests[str(hid)] = {"level": 0.0, "day": SysUtil.day(), "free_until": SysUtil.day() + int(ChaosState.cfg("pests").get("free_days", 14))}
	ChaosState.count("exterminated")
	SysUtil.notify("The exterminator cleared out the roaches. Keep the house clean and they should stay away for weeks.", "good")
	sync_markers(hid)

## What a handyperson charges: a visit plus a share of the price of everything broken.
static func handy_quote(hid: int) -> int:
	var c: Dictionary = ChaosState.cfg("appliance")
	var q: int = int(c.get("visit_fee", 15))
	for o in broken_objects(hid):
		q += maxi(int(Economy.object_price(o) * float(c.get("fee_share", 0.2))), int(c.get("min_fee", 12)))
	return q

# ------------------------------------------------------------------ interactions (game events)
const EVENTS := ["fix_leak", "check_pipes", "call_plumber", "call_exterminator", "call_handyperson", "set_roach_traps"]

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if not EVENTS.has(ev):
		return
	var f = SysUtil.folk(int(payload.get("folk_id", -1)))
	if f == null or int(f.household_id) <= 0:
		return
	var hid: int = int(f.household_id)
	match ev:
		"check_pipes":
			SysUtil.notify("%s checked the pipes and tightened what was loose." % f.name, "info")
		"fix_leak":
			_diy(f, hid)
		"call_plumber":
			_hire(hid, "plumber", int(ChaosState.cfg(str(ChaosState.leak_of(hid).get("kind", "pipe"))).get("plumber_fee", 90)), "the plumber", "plumber")
		"call_exterminator":
			_hire(hid, "exterminator", int(ChaosState.cfg("pests").get("exterminator_fee", 80)), "the exterminator", "exterminator")
		"call_handyperson":
			_hire(hid, "handy", handy_quote(hid), "the handyperson", "handyperson")
		"set_roach_traps":
			var rec: Dictionary = ChaosState.pest_rec(hid)
			rec["level"] = maxf(0.0, float(rec["level"]) - float(ChaosState.cfg("pests").get("trap_effect", 0.3)))
			SysUtil.notify("%s set traps along the kitchen floor." % f.name, "info")
			if float(rec["level"]) <= 0.0 and int(rec.get("free_until", -1)) <= SysUtil.day():
				ChaosState.pests.erase(str(hid))
				SysUtil.notify("The roaches are gone.", "good")
			sync_markers(hid)

static func _diy(f, hid: int) -> void:
	var lk: Dictionary = ChaosState.leak_of(hid)
	if lk.is_empty():
		return
	var c: Dictionary = ChaosState.cfg(str(lk["kind"]))
	var p: float = minf(float(c.get("diy_base", 0.3)) + float(c.get("diy_per_level", 0.1)) * f.skill_level("handiness"), float(c.get("diy_max", 0.95)))
	if Incidents.rng.randf() < p:
		stop_leak(hid, str(f.name))
		f.add_buff("tidy_pride")
	else:
		Economy.spend(hid, int(c.get("diy_fail_cost", 12)), "spare parts")
		ChaosState.count("diy_failed")
		SysUtil.notify("%s's patch did not hold and the water is still running. More practice would help, or call a plumber." % f.name, "warn")

static func _hire(hid: int, kind: String, fee: int, who: String, what: String) -> void:
	if ChaosState.job_pending(hid, kind):
		SysUtil.notify("%s is already on the way." % who.capitalize(), "info")
		return
	if not Economy.spend(hid, fee, what):
		SysUtil.notify("%s wants %d coins and the household cannot afford it yet." % [who.capitalize(), fee], "warn")
		return
	var span: Array = ChaosState.cfg("jobs").get(kind, [40, 90])
	ChaosState.jobs.append({"hid": hid, "kind": kind, "due": SysUtil.now() + Incidents.rng.randi_range(int(span[0]), int(span[1]))})
	SysUtil.notify("You paid %s %d coins. They will be there within the hour or two." % [who, fee], "info")
