class_name ChaosGas
extends RefCounted
## Gas leak (task 07b). A gas line at the stove starts to leak: a smell of rotten eggs (a working smoke alarm beeps too and wakes sleepers).
## The player can shut the gas off at the stove (`shut_off_gas`), call the gas company at the mailbox, and get everybody outside; folk who smell it
## and do nothing walk out on their own after a quarter of an hour (the `flee_fire` / `watch_fire` interactions of the fire task), carrying
## babies and toddlers. If the leak runs on and somebody is still inside, it may go off (a blast: injuries and a real fire through Fire.ignite).
## With everybody outside it only costs the gas company's fee. Numbers: config.chaos.gas. State: ChaosState.gas. Far lots: statistical lines only.

static func cfg() -> Dictionary:
	return ChaosState.cfg("gas")

static func active(hid: int) -> bool:
	return ChaosState.gas.has(hid)

static func start(hid: int) -> Dictionary:
	if active(hid):
		return {"text": ""}
	var stove = null
	for o in Economy.objects_of(hid):
		if str(o.def_id) == "stove" and (stove == null or int(o.id) < int(stove.id)):
			stove = o
	if stove == null:
		return {"text": ""}
	var alarm := false
	for o2 in Economy.objects_of(hid):
		if str(o2.def_id) == "smoke_alarm" and not bool(WorldIface.state_get(o2, "broken", false)) and float(WorldIface.state_get(o2, "battery", 1.0)) > 0.0:
			alarm = true
	ChaosState.gas[hid] = {"obj": int(stove.id), "since": SysUtil.now(), "alarm": alarm, "out": {}, "called": false}
	ChaosState.count("gas")
	var text := "A smell of rotten eggs is drifting from the kitchen: a gas leak. Shut the gas off at the stove, call the gas company at the mailbox, and get everybody outside. Do not light anything."
	if alarm:
		text += " The alarm is beeping."
	return {"text": text, "kind": "bad"}

# ------------------------------------------------------------------ every minute
static func on_minute() -> void:
	for hid in ChaosState.gas.keys():
		_tick(int(hid))

static func _folk_of(hid: int) -> Array:
	return SysUtil.residents().filter(func(f): return int(f.household_id) == hid and not SysUtil.is_away(f))

static func _tick(hid: int) -> void:
	var rec: Dictionary = ChaosState.gas[hid]
	if not Economy.household_ids().has(hid):
		ChaosState.gas.erase(hid)
		return
	var c: Dictionary = cfg()
	var age: int = SysUtil.now() - int(rec["since"])
	var smell_at: int = int(c.get("alarm_notice_min", 1)) if bool(rec["alarm"]) else int(c.get("notice_min", 4))
	var folk: Array = _folk_of(hid)
	if age >= smell_at:
		for f in folk:
			if bool(rec["alarm"]) and FireRules.asleep(f) and not f.has_buff("gas_smell"):
				f.cancel_current("woken by the alarm")
			if not FireRules.asleep(f) and not f.has_buff("gas_smell"):
				f.add_buff("gas_smell")
	if age >= int(c.get("flee_after_min", 14)):
		_evacuate(hid, rec, folk)
	if age >= int(c.get("blast_after_min", 90)):
		_resolve_ignored(hid, rec, folk)

## Everybody who is awake and has smelled it for long enough walks out; helpless folk are carried out by the first one to leave.
static func _evacuate(hid: int, rec: Dictionary, folk: Array) -> void:
	var out: Dictionary = rec["out"]
	var runner = null
	for f in folk:
		if out.has(int(f.id)) or FireRules.asleep(f) or FireRules.helpless(f) or not f.has_buff("gas_smell"):
			continue
		if f.current != null and str(f.current.def_id) == "shut_off_gas":
			continue
		_run(f, hid)
		out[int(f.id)] = true
		runner = f
	if runner != null:
		for h in folk:
			if not out.has(int(h.id)) and FireRules.helpless(h):
				h.cancel_current("carried out")
				h.clear_queue()
				h.tile = FireRules.exit_tile(Neighborhood.HOME, h.tile)
				out[int(h.id)] = true
		if not bool(rec["called"]):
			rec["called"] = true
			SimEnv.emit("thought", int(runner.id), "Everybody out! I'll call the gas company.")
			ChaosClock.hire_gas(hid, true)

static func _run(f, hid: int) -> void:
	var ir := Interaction.create("flee_fire", f, -1, false)
	if ir == null:
		return
	ir.goto_tile = FireRules.exit_tile(Neighborhood.HOME, f.tile)
	ir.goto_level = 0
	f.enqueue(ir)
	var w := Interaction.create("watch_fire", f, -1, false)
	if w != null:
		f.enqueue(w)
	SimEnv.emit("thought", int(f.id), "Get out, it's gas!")

static func inside(hid: int, rec: Dictionary) -> Array:
	return _folk_of(hid).filter(func(f): return not (rec["out"] as Dictionary).has(int(f.id)))

## The leak ran for far too long. With nobody inside it thins out harmlessly; somebody still inside risks a blast.
static func _resolve_ignored(hid: int, rec: Dictionary, folk: Array) -> void:
	var c: Dictionary = cfg()
	var left: Array = inside(hid, rec)
	var stove = WorldIface.get_object(int(rec["obj"]))
	ChaosState.gas.erase(hid)
	release(hid, folk)
	if left.is_empty() or Incidents.rng.randf() >= float(c.get("blast_chance", 0.7)):
		for f in left:
			Hospital.fall_ill(f, 1, "breathing in gas")
		ChaosState.count("gas_thinned")
		SysUtil.notify("The gas has thinned out by itself. Open the windows and have the stove looked at before cooking again.", "warn")
		return
	ChaosState.count("gas_blast")
	for f2 in left:
		Health.injure(f2, int(c.get("blast_injury", 2)), "a gas blast")
	var r: Dictionary = DisasterState.lot("home:%d" % hid)
	r["cost"] = int(r["cost"]) + int(c.get("blast_cost", 220))
	if stove != null:
		WorldIface.state_set(stove, "broken", true)
		if Incidents.rng.randf() < float(c.get("fire_chance", 0.8)):
			Fire.ignite(stove, "gas", {"force": true})
	var msg := "The gas went off in the kitchen with a bang. %s hurt and the stove is on fire." % ("Someone was" if left.size() == 1 else "People were")
	SysUtil.notify(msg, "bad")
	ChronicleHook.note("gas_leak", "A gas leak went off in the kitchen.", [], "home:%d" % hid, 4, false)
	ChaosClock.sync_markers(hid)

# ------------------------------------------------------------------ ending it
static func release(hid: int, folk: Array = []) -> void:
	if folk.is_empty():
		folk = _folk_of(hid)
	for f in folk:
		f.remove_buff("gas_smell")
		if f.current != null and (str(f.current.def_id) == "watch_fire" or str(f.current.def_id) == "flee_fire"):
			f.current.cancel("gas_over")
		for q in f.queue.duplicate():
			if str((q as Interaction).def_id) in ["watch_fire", "flee_fire"]:
				f.queue.erase(q)

## The gas is shut off (by a housemate or the gas company): the danger is over.
static func stop(hid: int, by: String) -> void:
	if not active(hid):
		return
	var rec: Dictionary = ChaosState.gas[hid]
	ChaosState.gas.erase(hid)
	release(hid)
	ChaosState.count("gas_stopped")
	SysUtil.notify("The gas is off (%s) and the air is clearing. %s" % [by, "Everybody can go back in." if not (rec["out"] as Dictionary).is_empty() else "Open a window to be safe."], "good")
	ChronicleHook.note("gas_leak", "A gas leak was dealt with in time.", [], "home:%d" % hid, 2, false)
	ChaosClock.sync_markers(hid)
