class_name LevelAccidents
extends RefCounted
## Accidents that only exist in a building with floors (task 10 part B; config.level_accidents in data/incidents/10_levels.json, defaults below).
##   Falls on the stairs: every game minute a folk stands on a flight of stairs / a ladder it may trip. Elders, toddlers, children, the injured,
##   the exhausted and the soaked fall far more often. A fall hurts through Health.injure (severity 2+ goes to hospital).
##   A lift that gets stuck (rare): the riders wait inside (`stuck_in_lift`), help comes after a while, then the lift stays out of service
##   until it is repaired. `World.set_object_state(lift, "out_of_order")` is what routing sees, so folk use the stairs meanwhile.
## Hooks: LevelSystems.on_minute -> on_minute(); Incidents.to_dict / from_dict / reset.

const DEFAULTS := {"fall_per_min": 0.0016, "elder_mult": 6.0, "toddler_mult": 6.0, "child_mult": 1.6, "injured_mult": 4.0, "tired_mult": 2.0,
	"soaked_mult": 3.0, "severity": [0.78, 0.2, 0.02], "fall_cooldown_min": 240,
	"stuck_per_rider_min": 0.0012, "rescue_min": [25, 60], "repair_min": [120, 300]}

static var stuck: Dictionary = {}          # lift object id -> {rescue_min, fixed_min, folk: [ids], rescued: bool}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func reset() -> void:
	stuck.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = 5150


static func cfg() -> Dictionary:
	var c: Dictionary = DEFAULTS.duplicate(true)
	c.merge(IncidentDefs.cfg("level_accidents", {}), true)
	return c


static func num(key: String) -> float:
	return float(cfg()[key])


static func on_minute() -> void:
	var w = WorldIface.world()
	if w == null or not ("portals" in w) or (w.portals.portals.is_empty() and stuck.is_empty()):
		return
	var now: int = SysUtil.now()
	for f in WorldIface.all_folk():
		if LevelInfo.on_stairs(f):
			_stairs(f, now)
	_lifts(w, now)


# ------------------------------------------------------------------ stairs
static func fall_chance(f) -> float:
	var c := cfg()
	var p: float = float(c["fall_per_min"])
	match str(f.age_stage):
		"elder":
			p *= float(c["elder_mult"])
		"toddler":
			p *= float(c["toddler_mult"])
		"child":
			p *= float(c["child_mult"])
	if f.has_buff("injured"):
		p *= float(c["injured_mult"])
	if f.has_buff("exhausted") or f.has_buff("tired"):
		p *= float(c["tired_mult"])
	if f.has_buff("soaked"):
		p *= float(c["soaked_mult"])
	return clampf(p, 0.0, 0.6)


static func _stairs(f, now: int) -> void:
	if SysUtil.is_away(f) or Hospital.is_in(f) or str(f.age_stage) == "baby":
		return
	if now - int(f.get_meta("lvl_fall_min", -99999)) < int(num("fall_cooldown_min")):
		return
	if rng.randf() >= fall_chance(f):
		return
	fall(f, now)


## The folk trips on the stairs: hurt by dice (severity list of the config), shaken, a toast for the household.
static func fall(f, now: int = -1, severity: int = 0) -> int:
	if now < 0:
		now = SysUtil.now()
	f.set_meta("lvl_fall_min", now)
	var sev: int = severity
	if sev <= 0:
		var roll: float = rng.randf()
		var tbl: Array = num_arr("severity")
		sev = 1
		var acc := 0.0
		for i in tbl.size():
			acc += float(tbl[i])
			if roll < acc:
				sev = i + 1
				break
	f.cancel_current("fell")
	f.clear_queue()
	Hospital.injure(f, sev, "a fall on the stairs")
	if not SimEnv.data().buff_def("shaken_up").is_empty():
		f.add_buff("shaken_up")
	SysUtil.game_event("fell_on_stairs", {"folk_id": int(f.id), "severity": sev, "level": int(f.level)})
	if SysUtil.is_resident(f):
		SysUtil.notify("%s lost their footing on the stairs%s." % [f.name, " and was badly hurt" if sev >= 2 else ""], "warn")
	return sev


static func num_arr(key: String) -> Array:
	return cfg()[key] as Array


# ------------------------------------------------------------------ lifts
static func _lifts(w, now: int) -> void:
	for oid in w.portals.elevators._book.keys():
		if stuck.has(int(oid)):
			continue
		var n: int = w.portals.elevators.riders(int(oid))
		if n > 0 and rng.randf() < num("stuck_per_rider_min") * float(n):
			get_stuck(int(oid), now)
	for lid in stuck.keys():
		var rec: Dictionary = stuck[lid]
		if not bool(rec["rescued"]) and now >= int(rec["rescue_min"]):
			rescue(int(lid))
		if now >= int(rec["fixed_min"]):
			_repair(int(lid))


## A lift stops between floors with its riders inside.
static func get_stuck(oid: int, now: int = -1) -> bool:
	var w = WorldIface.world()
	var lift = WorldIface.get_object(oid)
	if w == null or lift == null or stuck.has(oid):
		return false
	if now < 0:
		now = SysUtil.now()
	var riders: Array = []
	for b in w.portals.elevators._book.get(oid, []):
		var f = SysUtil.folk(int(b[0]))
		if f != null and float(b[1]) > float(now):
			riders.append(int(f.id))
	var rr: Array = num_arr("rescue_min")
	var fx: Array = num_arr("repair_min")
	var rescue_at: int = now + rng.randi_range(int(rr[0]), int(rr[1]))
	var rec := {"rescue_min": rescue_at, "fixed_min": rescue_at + rng.randi_range(int(fx[0]), int(fx[1])), "folk": riders, "rescued": false}
	stuck[oid] = rec
	WorldIface.state_set(lift, "out_of_order", true)
	w.portals.elevators.forget(oid)
	var stop: Vector2i = lift.tile + WorldObject.rotate_offset(Vector2i(0, 1), int(lift.rot))
	for id in riders:
		var f2 = SysUtil.folk(int(id))
		f2.cancel_current("stuck")
		f2.clear_queue()
		f2.tile = stop
		f2.level = clampi(int(f2.level), int(lift.level), int(lift.level) + int(lift.span))
		var ir := Interaction.create("stuck_in_lift", f2, -1, false)
		if ir != null:
			ir.def = ir.def.duplicate(true)
			ir.def["duration_min"] = float(rescue_at - now) + 5.0
			f2.enqueue(ir)
		SimEnv.emit("thought", int(id), "The lift has stopped!")
	SysUtil.game_event("lift_stuck", {"object": oid, "folk_ids": riders})
	if not riders.is_empty() and SysUtil.is_resident(SysUtil.folk(int(riders[0]))):
		SysUtil.notify("The lift has stuck between floors with %s inside. Help is on the way." % SysUtil.folk_name(int(riders[0])), "warn")
	return true


## The riders are let out (the lift stays out of order until repaired).
static func rescue(oid: int) -> void:
	var rec: Dictionary = stuck.get(oid, {})
	if rec.is_empty() or bool(rec["rescued"]):
		return
	rec["rescued"] = true
	for id in rec["folk"]:
		var f = SysUtil.folk(int(id))
		if f == null:
			continue
		if f.current != null and f.current.def_id == "stuck_in_lift":
			f.current.cancel("rescued")
		for q in f.queue.duplicate():
			if (q as Interaction).def_id == "stuck_in_lift":
				f.queue.erase(q)
		if not SimEnv.data().buff_def("shaken_up").is_empty():
			f.add_buff("shaken_up")
	SysUtil.game_event("lift_rescued", {"object": oid, "folk_ids": rec["folk"]})


static func _repair(oid: int) -> void:
	var lift = WorldIface.get_object(oid)
	if lift != null:
		WorldIface.state_set(lift, "out_of_order", false)
	stuck.erase(oid)


static func is_stuck(oid: int) -> bool:
	return stuck.has(oid)


# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for k in stuck:
		out[str(k)] = (stuck[k] as Dictionary).duplicate(true)
	return {"stuck": out, "rng": str(rng.state)}


static func from_dict(d: Dictionary) -> void:
	reset()
	var s: Dictionary = d.get("stuck", {})
	for k in s:
		var r: Dictionary = (s[k] as Dictionary).duplicate(true)
		SysUtil.ints_in(r, ["rescue_min", "fixed_min"])
		r["folk"] = SysUtil.to_ints(r.get("folk", []))
		stuck[int(str(k))] = r
	if d.has("rng"):
		rng.state = int(str(d["rng"]))
