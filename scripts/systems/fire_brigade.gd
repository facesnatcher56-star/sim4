class_name FireBrigade
extends RefCounted
## The fire department. Somebody calls (a folk who noticed the fire, the player, or a neighbour after config.fire.neighbor_call_min), a crew of
## uniformed NPC firefighters (the same kind of visitor Folk the Crowd uses for staff) turns up at the lot gate after a delay (shorter with a
## smoke alarm), walks to the flames and puts them out one by one, carries out anyone who is stuck, tidies up and leaves.

const ID_BASE := 7000

static var _seq: int = 0

static func call_in(lot: String, caller_id: int = -1) -> void:
	var b: Dictionary = Fire.blazes.get(lot, {})
	if b.is_empty() or bool(b["called"]):
		return
	var d: Array = FireRules.cfg().get("brigade_delay", [9, 14])
	var delay: int = Fire.rng.randi_range(int(d[0]), int(d[1])) - (int(FireRules.num("brigade_alarm_saving", 2.0)) if bool(b["alarm"]) else 0)
	b["called"] = true
	b["call_min"] = SysUtil.now()
	b["due"] = SysUtil.now() + maxi(delay, 3)
	for f in FireRules.folk_in_lot(lot):
		f.add_buff("brigade_called")
	SysUtil.game_event("fire_brigade_called", {"lot": lot, "folk_id": caller_id})

static func step(now: int) -> void:
	for lot in Fire.lots_burning():
		var b: Dictionary = Fire.blazes[lot]
		if not bool(b["called"]) and now >= int(b["neighbor_min"]):
			call_in(str(lot), -1)
		if bool(b["called"]) and not bool(b["here"]) and now >= int(b["due"]):
			_arrive(b, now)
	for c in Fire.crew.duplicate():
		_drive(c, now)

# ------------------------------------------------------------------ arrival
static func _gate(lot: String) -> Vector2i:
	var g: Vector2i = NeighborhoodLots.gate_tile(lot)
	if g.x >= 0:
		return g
	var fires: Array = Fire.fires_in(lot)
	return FireRules.exit_tile(lot, fires[0]["tile"] if not fires.is_empty() else Vector2i(10, 10))

static func _uniform(ap: Dictionary) -> Dictionary:
	var out: Dictionary = ap.duplicate(true)
	out["shirt"] = "#c0392b"
	out["pants"] = "#2b2d33"
	out["accent"] = "#f1c40f"
	return out

static func _arrive(b: Dictionary, now: int) -> void:
	var lot: String = str(b["lot"])
	b["here"] = true
	b["here_min"] = now
	for i in int(FireRules.num("brigade_crew", 2.0)):
		_seq += 1
		var keep_next: int = Folk._next_id
		var f := Folk.create("Firefighter %s" % Names.pick_first([], _name_rng(_seq)), [], ID_BASE + _seq)
		Folk._next_id = keep_next
		f.household_id = -1
		f.age_stage = "adult"
		f.appearance = Genetics.normalize(_uniform(Genetics.random_appearance()))
		f.set_meta("visitor", true)
		f.set_meta("firefighter", lot)
		for n in f.needs:
			(f.needs[n] as Stat).set_value(60.0)
		SysUtil.world_add_folk(f, _gate(lot))
		f.idle_until_min = 1 << 30
		Fire.crew.append({"id": int(f.id), "lot": lot, "leave_min": -1, "leaving": -1})
	if FireRules.is_home(lot):
		SysUtil.notify("The fire department has arrived.", "info")
	SysUtil.game_event("fire_brigade_arrived", {"lot": lot, "folk_id": -1})

# ------------------------------------------------------------------ at work
static func _drive(c: Dictionary, now: int) -> void:
	var f = SysUtil.folk(int(c["id"]))
	if f == null:
		Fire.crew.erase(c)
		return
	var lot: String = str(c["lot"])
	if int(c["leaving"]) >= 0:
		if f.tile == _gate(lot) or now >= int(c["leaving"]):
			_remove(f, c)
		return
	if int(c["leave_min"]) >= 0:
		if now >= int(c["leave_min"]):
			c["leaving"] = now + 12
			f.clear_queue()
			var ir := Interaction.create_goto(f, _gate(lot), false)
			if ir != null:
				f.enqueue(ir)
		return
	var b: Dictionary = Fire.blazes.get(lot, {})
	if b.is_empty():
		return
	_rescue(b, f)
	var fires: Array = Fire.fires_in(lot)
	if fires.is_empty():
		return
	fires.sort_custom(func(a, d): return FireRules.dist(f.tile, a["tile"]) < FireRules.dist(f.tile, d["tile"]))
	var target: Dictionary = fires[0]
	if FireRules.dist(f.tile, target["tile"]) <= 2:
		Fire.extinguish(target, "brigade")
		return
	if f.current == null and f.queue.is_empty():
		var dest: Vector2i = target["tile"]
		var w = WorldIface.world()
		if w != null and w.has_method("nearest_reachable_neighbor"):
			var nb: Vector2i = w.nearest_reachable_neighbor(f.tile, dest)
			if nb.x >= 0:
				dest = nb
		var go := Interaction.create_goto(f, dest, false)
		if go != null:
			f.enqueue(go)

static func _rescue(b: Dictionary, ff) -> void:
	var r: float = FireRules.num("brigade_rescue_range", 6.0)
	for x in FireRules.folk_in_lot(str(b["lot"])):
		var xr: Dictionary = FireFolk.rec(b, x)
		if xr["state"] == "safe" or FireRules.dist(x.tile, ff.tile) > int(r):
			continue
		if FireRules.asleep(x) or FireRules.helpless(x) or xr["state"] == "trapped":
			FireFolk.carry_out(b, x, xr)

static func _remove(f, c: Dictionary) -> void:
	f.current = null
	f.queue.clear()
	SysUtil.world_remove_folk(int(f.id))
	Fire.crew.erase(c)

## The blaze is out: the crew tidies up for a few minutes, then leaves.
static func finish(b: Dictionary) -> void:
	var now: int = SysUtil.now()
	for c in Fire.crew:
		if str(c["lot"]) == str(b["lot"]) and int(c["leave_min"]) < 0:
			c["leave_min"] = now + int(FireRules.num("brigade_clean_min", 4.0))

static func _name_rng(seq: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seq * 104729 + 17
	return r