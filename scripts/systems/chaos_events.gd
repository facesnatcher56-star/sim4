class_name ChaosEvents
extends RefCounted
## Household chaos (task 07), the FULL versions of the incidents in data/incidents/07_chaos.json. One handler `chaos_trouble` (args.kind):
## pipe (a pipe bursts: water, damage, mould if left), overflow (a toilet floods a little), appliance (something stops working),
## pests (roaches turn up). Far lots (statistical) only use the data summaries, so every handler returns at once for them.
## The player's counterplay lives in ChaosClock (check the pipes, fix it yourself, call a plumber / handyperson / exterminator, traps, cleaning).

static func on_incident(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var kind: String = str(args.get("kind", ""))
	if kind == "layoff":                                      # far townies lose their job too
		return ChaosJob.layoff(ctx, args)
	if bool(ctx.get("statistical", false)):
		return {}
	var hid: int = int(ctx.get("household_id", 0))
	if hid <= 0:
		return {"text": ""}
	match kind:
		"gas":
			return ChaosGas.start(hid)
		"mould":
			return mould(hid)
		"midlife":
			return ChaosJob.midlife(ctx, args)
		"theft":
			return ChaosMoney.theft(ctx.get("folk", null))
		"eviction":
			return ChaosMoney.eviction(hid)
		"runaway":
			return ChaosTeen.run_away(ctx.get("folk", null))
		"inheritance":
			return ChaosKin.inheritance(hid)
		"kin":
			return ChaosKin.long_lost(hid)
		"pipe":
			return pipe(hid, "pipe")
		"overflow":
			return pipe(hid, "overflow")
		"appliance":
			return appliance(hid)
		"pests":
			return pests(hid)
	return {}

static func label_of(o) -> String:
	return str(DisasterDamage.def_of(o).get("label", o.def_id)).to_lower()

static func _pick(list: Array):
	return list[Incidents.rng.randi_range(0, list.size() - 1)] if not list.is_empty() else null

# ------------------------------------------------------------------ water
static func pipe(hid: int, kind: String) -> Dictionary:
	if not ChaosState.leak_of(hid).is_empty():
		return {"text": ""}                                                 # already flooding: no second leak
	var c: Dictionary = ChaosState.cfg(kind)
	var fx: Array = ChaosConds.fixtures(hid)
	if kind == "overflow":
		var toilets: Array = fx.filter(func(o): return str(o.def_id) == "toilet")
		fx = toilets if not toilets.is_empty() else fx
	var o = _pick(fx)
	if o == null:
		return {"text": ""}
	WorldIface.state_set(o, "broken", true)
	ChaosState.leaks[str(hid)] = {"obj": int(o.id), "kind": kind, "since": SysUtil.now(), "hours": 0}
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	rec["cost"] = int(rec["cost"]) + int(c.get("burst_cost", 30))
	rec["flood"] = minf(1.0, float(rec["flood"]) + float(c.get("flood_start", 0.1)))
	spill(o.tile, c)
	ChaosState.count(kind)
	ChaosClock.sync_markers(hid)
	var name: String = label_of(o)
	if kind == "overflow":
		return {"text": "The %s is overflowing and water is creeping across the floor. Fix it yourself (the handiness skill helps) or call a plumber from it for about %d coins." % [name, int(c.get("plumber_fee", 55))], "kind": "warn"}
	return {"text": "A pipe burst under the %s and water is pouring out. The damage grows by the hour and damp turns to mould. Fix it yourself (the handiness skill helps) or call a plumber from it for about %d coins." % [name, int(c.get("plumber_fee", 90))], "kind": "bad"}

## Puddles on the floor around the fixture (the same mess the slip checks and the floor tint read).
static func spill(tile: Vector2i, c: Dictionary) -> void:
	var w = WorldIface.world()
	if w == null or not w.has_method("add_mess"):
		return
	var r: int = int(c.get("mess_radius", 2))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if absi(dx) + absi(dy) <= r:
				w.add_mess(tile + Vector2i(dx, dy), float(c.get("mess", 2.0)))

# ------------------------------------------------------------------ appliances
static func appliance(hid: int) -> Dictionary:
	var o = _pick(ChaosConds.appliances(hid))
	if o == null:
		return {"text": ""}
	WorldIface.state_set(o, "broken", true)
	var extra := ""
	if WorldIface.state_get(o, "spoiled", null) != null:
		WorldIface.state_add(o, "spoiled", float(ChaosState.cfg("appliance").get("fridge_spoil", 3.0)))
		extra = " The food inside is starting to turn."
	ChaosState.count("appliance")
	ChaosClock.sync_markers(hid)
	return {"text": "The %s has stopped working.%s Repair it yourself (the handiness skill helps) or call a handyperson at the mailbox for about %d coins." % [label_of(o), extra, ChaosClock.handy_quote(hid)], "kind": "warn"}

# ------------------------------------------------------------------ mould
## Slow damp: a first patch of mould on the home's damage record. DisasterAftermath grows it day by day until it is scrubbed (scrub_mould) or repaired.
static func mould(hid: int) -> Dictionary:
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	rec["mould"] = maxf(float(rec["mould"]), float(ChaosState.cfg("mould").get("start", 0.3)))
	ChaosState.count("mould_slow")
	ChaosClock.sync_markers(hid)
	return {"text": "Dark patches of mould are creeping across the bathroom wall. Scrub it off at the sink or bath before it spreads and makes people ill; a clean, dry bathroom keeps it away.", "kind": "warn"}

# ------------------------------------------------------------------ pests
static func pests(hid: int) -> Dictionary:
	var rec: Dictionary = ChaosState.pest_rec(hid)
	rec["level"] = maxf(float(rec["level"]), float(ChaosState.cfg("pests").get("start", 0.25)))
	ChaosState.count("pests")
	ChaosClock.sync_markers(hid)
	return {"text": "A roach ran across the kitchen floor, and there will be more. Clear away dirty dishes and spoiled food, set traps at the bin, or call an exterminator at the mailbox.", "kind": "warn"}
