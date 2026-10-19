class_name FireFolk
extends RefCounted
## What people do when a lot is on fire (called every game minute from Fire.on_minute): the smoke alarm wakes sleepers, folk notice (sooner
## in the same room), then each aware person in turn rescues a baby, calls the fire department, fights a small fire (extinguisher, bare hands)
## or runs out and waits in the street. Smoke hurts folk who stay inside; sleepers, babies and anyone trapped can die (cause: fire).
## Per-person state lives in the blaze record: blazes[lot]["folk"][folk_id] = {aware, t, expo, state, hurt, trap}.

const ADULT := ["teen", "adult", "elder"]

static var _health_checked: bool = false
static var _health_script = null

static func reset() -> void:
	pass

static func rec(b: Dictionary, f) -> Dictionary:
	var m: Dictionary = b["folk"]
	if not m.has(int(f.id)):
		m[int(f.id)] = {"aware": false, "t": 0, "expo": 0.0, "state": "none", "hurt": 0, "trap": 0, "aware_min": -1, "shouted": false}
	return m[int(f.id)]

## Health API of task 02 when it exists, else the hospital of task 01.
static func injure(f, severity: int, reason: String) -> void:
	if not _health_checked:
		_health_checked = true
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Health":
				_health_script = load(str(c["path"]))
	if _health_script != null and _health_script.has_method("injure"):
		_health_script.injure(f, severity, reason)
	else:
		Hospital.injure(f, severity, reason)

# ------------------------------------------------------------------ per minute
static func step(now: int) -> void:
	for lot in Fire.lots_burning():
		var b: Dictionary = Fire.blazes[lot]
		var fires: Array = Fire.fires_in(str(lot))
		if fires.is_empty():
			continue
		_alarm(b)
		for f in FireRules.folk_in_lot(str(lot)):
			_tick(b, f, fires, now)
		# folk who ran outside still wait for the all-clear
		for fid in (b["folk"] as Dictionary).keys():
			var o = SysUtil.folk(int(fid))
			if o != null and FireRules.lot_of(o.tile) != str(lot):
				_outside(b, o)

static func _alarm(b: Dictionary) -> void:
	if bool(b["alarm"]) or float(b["smoke"]) < FireRules.num("alarm_smoke", 0.12):
		return
	var heard: bool = false
	for o in FireRules.objects_in_lot(str(b["lot"]), ["smoke_alarm"]):
		if float(WorldIface.state_get(o, "battery", 0.0)) > 0.0 and not bool(WorldIface.state_get(o, "broken", false)) 				and FireSmoke.at(b, o.tile) >= FireRules.num("alarm_smoke", 0.12):
			heard = true
	if not heard:
		return
	b["alarm"] = true
	SysUtil.game_event("fire_alarm", {"lot": str(b["lot"]), "folk_id": -1})
	if FireRules.is_home(str(b["lot"])):
		SysUtil.notify("The smoke alarm is going off!", "warn")

static func _outside(b: Dictionary, f) -> void:
	var r: Dictionary = rec(b, f)
	if r["state"] != "safe":
		r["state"] = "safe"
	r["expo"] = maxf(float(r["expo"]) - 1.0, 0.0)
	_keep_waiting(f)

static func _keep_waiting(f) -> void:
	if f.current == null and f.queue.is_empty() and not SysUtil.is_away(f):
		var w := Interaction.create("watch_fire", f, -1, false)
		if w != null:
			f.enqueue(w)

static func _tick(b: Dictionary, f, fires: Array, now: int) -> void:
	var r: Dictionary = rec(b, f)
	var asleep: bool = FireRules.asleep(f)
	var helpless: bool = FireRules.helpless(f)
	var near: int = 1 << 20
	var room_stage: int = 0
	var lv: int = int(f.level)
	for fi in fires:
		near = mini(near, FireRules.dist(f.tile, fi["tile"]) + 4 * absi(lv - int(fi.get("level", 0))))      # another floor counts as far
		if int(fi.get("level", 0)) == lv and FireRules.same_room(f.tile, fi["tile"], lv):
			room_stage = maxi(room_stage, int(fi["stage"]))
	var here: float = FireSmoke.at(b, f.tile, lv)
	f.add_buff("fire_nearby")
	if here >= FireRules.num("smoky_at", 0.25):
		f.add_buff("fire_smoke")
	if r["state"] == "safe":
		if near >= 5 and room_stage == 0:
			r["expo"] = maxf(float(r["expo"]) - 1.0, 0.0)
			_keep_waiting(f)
			return
		r["state"] = "none"
	if asleep:
		if bool(b["alarm"]):
			_wake(f, r, now)
		elif Fire.rng.randf() < _wake_chance(f, here, room_stage, near):
			_wake(f, r, now)
		asleep = FireRules.asleep(f)
	if not bool(r["aware"]) and not asleep and not helpless:
		r["t"] = int(r["t"]) + 1
		var notice: bool = bool(b["alarm"]) or near <= 2 or (room_stage > 0 and int(r["t"]) >= int(FireRules.num("notice_room_min", 1.0))) \
			or (int(r["t"]) >= int(FireRules.num("notice_lot_min", 3.0)) and here >= 0.1)
		if notice:
			r["aware"] = true
			r["aware_min"] = now
			f.add_buff("fire_panic")
	if bool(r["aware"]) and not asleep and not helpless:
		_act(b, f, r, fires, now)
	_exposure(b, f, r, room_stage, asleep, helpless)

## Chance per minute that a sleeper wakes by himself: thin haze almost never, thick smoke or flames in the room often; anywhere in the lot.
static func _wake_chance(f, smoke_here: float, room_stage: int, near: int) -> float:
	var wm: float = FireRules.wake_mult(f)
	if wm <= 0.0:
		return 0.0
	var p: float = FireRules.num("wake_base", 0.004) + FireRules.num("wake_smoke", 0.3) * pow(smoke_here, 1.5)
	var stage: int = room_stage if room_stage > 0 else (1 if near <= 3 else 0)
	if stage > 0:
		p += FireRules.at("wake_flames", stage - 1, 0.1) * (1.0 if room_stage > 0 else 0.5)
	return clampf(p * wm * FireRules.num("wake_scale", 1.0), 0.0, 0.9)

## "Fire!": every sleeper within earshot may wake (same room almost surely, a few rooms away through open or closed doors, walls muffle).
static func _shout(b: Dictionary, f, now: int) -> void:
	SimEnv.emit("thought", int(f.id), "Fire! Everybody out!")
	for s in FireRules.folk_in_lot(str(b["lot"])):
		if int(s.id) == int(f.id) or not FireRules.asleep(s):
			continue
		var wm: float = FireRules.wake_mult(s)
		if wm <= 0.0:
			continue
		var h: int = FireSmoke.hops(f.tile, s.tile)
		var p: float = 0.0
		var tab: Array = FireRules.cfg().get("shout_hops", [0.95, 0.8, 0.5, 0.15])
		if h < tab.size():
			p = float(tab[h])
		elif FireRules.dist(f.tile, s.tile) <= int(FireRules.num("shout_wall_range", 3.0)):
			p = FireRules.num("shout_wall", 0.3)
		if p > 0.0 and Fire.rng.randf() < minf(p * clampf(wm, 0.3, 1.3), 1.0):
			_wake(s, rec(b, s), now)

## Go and wake a family member sleeping in another room (before leaving). True while somebody is still being woken.
static func _wake_others(b: Dictionary, f, now: int) -> bool:
	for s in FireRules.folk_in_lot(str(b["lot"])):
		if int(s.id) == int(f.id) or not FireRules.asleep(s) or FireRules.wake_mult(s) <= 0.0:
			continue
		if Fire.rng.randf() < FireRules.num("wake_others_chance", 0.7):
			_wake(s, rec(b, s), now)
			SimEnv.emit("thought", int(f.id), "Wake up, wake up!")
		return true
	return false

static func _wake(f, r: Dictionary, now: int) -> void:
	f.cancel_current("alarm")
	f.clear_queue()
	r["aware"] = true
	r["aware_min"] = now
	f.add_buff("fire_panic")
	SimEnv.emit("thought", int(f.id), "Wake up! Something is on fire!")

# ------------------------------------------------------------------ acting
static func _act(b: Dictionary, f, r: Dictionary, fires: Array, now: int) -> void:
	var st: String = str(r["state"])
	if st == "trapped":
		_trapped(b, f, r)
		return
	if st == "fighting":
		if f.current != null and str(f.current.def_id) == "use_extinguisher" or not f.queue.is_empty():
			return
		r["state"] = "none"
	elif st == "fleeing":
		if f.current != null or not f.queue.is_empty():
			return
		r["state"] = "none"
	var lot: String = str(b["lot"])
	var adult: bool = ADULT.has(str(f.age_stage))
	if adult and _rescue_dependants(b, f, now):
		return
	var tiny: bool = fires.size() == 1 and int(fires[0]["stage"]) <= 1
	if not bool(r["shouted"]) and (adult or Fire.rng.randf() < FireRules.num("shout_child", 0.6)):
		r["shouted"] = true
		_shout(b, f, now)
	if adult and not tiny and _wake_others(b, f, now):
		return
	if not bool(b["called"]) and now - int(r["aware_min"]) >= int(FireRules.num("call_after_aware_min", 1.0)) and Fire.rng.randf() < FireRules.num("call_chance", 0.6):
		Fire.call_brigade(lot, int(f.id))
		SimEnv.emit("thought", int(f.id), "Calling the fire department!")
	var top: int = 0
	for fi in fires:
		top = maxi(top, int(fi["stage"]))
	var score: float = FireRules.trait_score(f)
	var ext = FireRules.best_extinguisher(lot, f.tile) if adult else null
	var close_ext: bool = ext != null and FireRules.dist(ext.tile, f.tile) <= 3
	var small: bool = fires.size() == 1 and top <= 1 and FireRules.dist(f.tile, fires[0]["tile"]) <= int(FireRules.num("smother_range", 3.0))
	if adult and small and not close_ext:
		# a young fire right beside you: try to smother it first (lid, wet towel); the extinguisher is too far to be quicker
		var skill: int = maxi(f.skill_level("cooking"), f.skill_level("handiness"))
		var p: float = FireRules.num("smother_chance", 0.1) + FireRules.num("smother_per_skill", 0.04) * skill + 0.03 * score
		if Fire.rng.randf() < p:
			Fire.extinguish(fires[0], "folk")
			SimEnv.emit("thought", int(f.id), "Phew! I put it out.")
		elif ext == null:
			pass
		else:
			_use(f, r, ext)
		return
	if adult and top <= 2 and fires.size() <= 4 and ext != null and Fire.rng.randf() < clampf(0.95 + 0.05 * score, 0.2, 1.0):
		_use(f, r, ext)
		return
	_flee(b, f, r)

static func _use(f, r: Dictionary, ext) -> void:
	var ir := Interaction.create("use_extinguisher", f, int(ext.id), false)
	if ir != null and ir.can_run(f, null, false):
		f.enqueue(ir)
		r["state"] = "fighting"

static func _flee(b: Dictionary, f, r: Dictionary) -> void:
	var lot: String = str(b["lot"])
	var exit: Vector2i = FireRules.blaze_exit(b, f.tile)
	if f.tile == exit:
		r["state"] = "safe"
		_keep_waiting(f)
		return
	var path: Array = FireLevels.escape_route(f, exit)          # stairs / fire escape, never the lift (switched off while it burns)
	var blocked: bool = path.is_empty()
	for p in path:
		var fi: Dictionary = Fire.fire_at(Vector2i(p.x, p.y), p.z)
		if not fi.is_empty() and int(fi["stage"]) >= 3:
			blocked = true
	if blocked:
		r["state"] = "trapped"
		SimEnv.emit("thought", int(f.id), "I'm trapped!")
		return
	if not bool(b["called"]) and Fire.rng.randf() < 0.85:           # on the way out: phone from the street
		Fire.call_brigade(lot, int(f.id))
		SimEnv.emit("thought", int(f.id), "Calling the fire department!")
	var ir := Interaction.create("flee_fire", f, -1, false)
	if ir == null:
		return
	ir.goto_tile = exit
	ir.goto_level = 0
	f.enqueue(ir)
	var w := Interaction.create("watch_fire", f, -1, false)
	if w != null:
		f.enqueue(w)
	r["state"] = "fleeing"
	SimEnv.emit("thought", int(f.id), "Get out!")

static func _trapped(b: Dictionary, f, r: Dictionary) -> void:
	r["trap"] = int(r["trap"]) + 1
	if int(r["trap"]) >= int(FireRules.num("trapped_escape_after", 8.0)) and Fire.rng.randf() < FireRules.num("trapped_escape_chance", 0.06):
		f.tile = FireRules.blaze_exit(b, f.tile)
		FireLevels.land(f, true)
		r["state"] = "safe"
		r["expo"] = maxf(float(r["expo"]), FireRules.num("hurt_min", 9.0))
		SimEnv.emit("thought", int(f.id), "I got out through a window!")
		_keep_waiting(f)

## Awake grown-ups carry out babies, toddlers and anyone collapsed first.
static func _rescue_dependants(b: Dictionary, f, now: int) -> bool:
	var lot: String = str(b["lot"])
	var any: bool = false
	for d in FireRules.folk_in_lot(lot):
		if int(d.id) == int(f.id) or not FireRules.helpless(d):
			continue
		var dr: Dictionary = rec(b, d)
		if dr["state"] == "safe":
			continue
		any = true
		var heavy: bool = false
		for fi in Fire.fires_in(lot):
			if int(fi["stage"]) >= 3 and int(fi.get("level", 0)) == int(d.level) and FireRules.same_room(d.tile, fi["tile"], int(d.level)):
				heavy = true
		if Fire.rng.randf() < (0.4 if heavy else 0.85):
			carry_out(b, d, dr)
			SimEnv.emit("thought", int(f.id), "I've got you!")
	return any

## Put someone safely in the street (rescue by a parent or by the fire department); smoke may have hurt them on the way.
static func carry_out(b: Dictionary, d, dr: Dictionary) -> void:
	d.cancel_current("rescued")
	d.clear_queue()
	d.tile = FireRules.blaze_exit(b, d.tile)
	FireLevels.land(d)
	dr["state"] = "safe"
	dr["aware"] = true
	if not (b["rescued"] as Array).has(int(d.id)):
		(b["rescued"] as Array).append(int(d.id))
		Fire._stat("rescued")
	var ex: float = float(dr["expo"]) / FireRules.dose_mult(d)
	if ex >= FireRules.num("severe_min", 17.0):
		injure(d, 2, "smoke")
		_hurt(b, d, dr, 2)
	elif ex >= FireRules.num("hurt_min", 9.0):
		_hurt(b, d, dr, 1)
	_keep_waiting(d)

# ------------------------------------------------------------------ smoke harm
static func _hurt(b: Dictionary, f, r: Dictionary, sev: int) -> void:
	if int(r["hurt"]) >= sev:
		return
	if int(r["hurt"]) == 0:
		(b["hurt"] as Array).append(int(f.id))
		Fire._stat("hurt")
	r["hurt"] = sev

static func _exposure(b: Dictionary, f, r: Dictionary, room_stage: int, asleep: bool, helpless: bool) -> void:
	var d: float = 0.0
	if room_stage >= 3:
		d = 1.5
	elif room_stage == 2:
		d = 1.0
	else:
		var lvl: float = FireSmoke.at(b, f.tile, int(f.level))
		d = 0.8 if lvl >= 0.6 else (0.4 if lvl >= 0.35 else (0.15 if lvl >= 0.2 else 0.0))
	if d > 0.0 and FireSmoke.near_vent(f):
		d *= FireRules.num("near_vent_dose", 0.6)
	if str(r["state"]) == "fleeing":
		d *= 0.5
	if d <= 0.0:
		r["expo"] = maxf(float(r["expo"]) - 0.5, 0.0)
		return
	r["expo"] = float(r["expo"]) + d
	var ex: float = float(r["expo"]) / FireRules.dose_mult(f)          # frail folk reach every threshold sooner
	if ex >= FireRules.num("hurt_min", 9.0) and int(r["hurt"]) < 1:
		injure(f, 1, "smoke")
		_hurt(b, f, r, 1)
		SimEnv.emit("thought", int(f.id), "I can't breathe!")
	if ex >= FireRules.num("lethal_min", 28.0):
		(b["dead"] as Array).append(int(f.id))
		Fire._stat("deaths")
		Aging.kill(int(f.id), "fire")

# ------------------------------------------------------------------ events / end
## fire_extinguish_try (a folk finished the extinguisher interaction): up to two nearby fires get a chance of going out.
static func on_extinguisher_used(folk_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	var lot: String = FireRules.lot_of(f.tile)
	var fires: Array = Fire.fires_in(lot)
	fires.sort_custom(func(a, b): return FireRules.dist(f.tile, a["tile"]) < FireRules.dist(f.tile, b["tile"]))
	var out: int = 0
	var tried: int = 0
	for fi in fires:
		if tried >= 2 or FireRules.dist(f.tile, fi["tile"]) > 5:
			break
		tried += 1
		var p: float = FireRules.at("extinguish_chance", int(fi["stage"]) - 1, 0.5) + FireRules.num("extinguish_handy_bonus", 0.02) * f.skill_level("handiness")
		if Fire.rng.randf() < p:
			Fire.extinguish(fi, "folk")
			out += 1
	var b: Dictionary = Fire.blazes.get(lot, {})
	if not b.is_empty():
		rec(b, f)["state"] = "none"
	if out == 0 and tried > 0:
		SimEnv.emit("thought", int(f.id), "It is too big!")

## The blaze is over: everybody may go about their day again.
static func release(b: Dictionary) -> void:
	for fid in (b["folk"] as Dictionary).keys():
		var f = SysUtil.folk(int(fid))
		if f == null:
			continue
		var r: Dictionary = b["folk"][fid]
		if f.current != null and (str(f.current.def_id) == "watch_fire" or str(f.current.def_id) == "flee_fire"):
			f.current.cancel("fire_over")
		for q in f.queue.duplicate():
			if str((q as Interaction).def_id) in ["watch_fire", "flee_fire"]:
				f.queue.erase(q)
		for bf in ["fire_panic", "fire_nearby", "fire_smoke", "brigade_called"]:
			f.remove_buff(bf)
		if bool(r["aware"]):
			f.add_buff("shaken" if int(r["hurt"]) > 0 or not (b["dead"] as Array).is_empty() else "relieved")