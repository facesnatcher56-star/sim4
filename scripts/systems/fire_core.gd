class_name Fire
extends RefCounted
## Fire in the house. State + public API; the parts live in FireRules (data, lookups), FireSpread (growth, burning, spread), FireFolk (panic,
## smoke, harm), FireBrigade (the fire department), FireEvents (the sources, armed by the incidents in data/incidents/03_fire.json) and
## FireTown (far lots). Docs: docs/INCIDENTS.md, "Fire API".
##
##   Fire.ignite(target, source = "unknown", opts = {}) -> bool    target: an object, an object id or a Vector2i tile
##        opts: culprit (folk id), force (burn even if nothing there is flammable), stage (1..3), quiet (no "Fire!" toast)
##        sources used for the summary text: cooking fireplace electrical repair candle lightning arson wildfire
##   Fire.extinguish(target, by = "") -> bool     a fire tile / object / id;  Fire.extinguish_lot(lot, by) -> int
##   Fire.is_burning(target) -> bool      Fire.active() -> Array of fire records      Fire.fires_in(lot) -> Array      Fire.lots_burning() -> Array
##   Fire.smoke_of(lot) -> 0..1     Fire.call_brigade(lot, caller_id = -1)     Fire.stats (counters)     Fire.hover_text(object)
## Clock hooks (SystemsManager): on_minute, on_day, reset, to_dict / from_dict (saved under systems.fire).

const DEFAULT_SEED := 31337

static var fires: Dictionary = {}       # id -> {id, tile, tiles, obj, def, lot, born, age, stage, burn, next_spread, source, culprit}
static var blazes: Dictionary = {}      # lot -> blaze record (see _new_blaze)
static var scorch: Dictionary = {}      # "x,y" -> {lv 1..3, day}
static var crew: Array = []             # firefighters on the map [{id, lot, leave_min}]
static var stats: Dictionary = {}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _seq: int = 1

static func reset() -> void:
	fires.clear()
	blazes.clear()
	scorch.clear()
	crew.clear()
	stats = {"ignited": 0, "blazes": 0, "spread_blazes": 0, "spread_events": 0, "destroyed": 0, "loss": 0, "deaths": 0, "hurt": 0, "by_folk": 0,
		"by_sprinkler": 0, "by_brigade": 0, "burned_out": 0, "rescued": 0, "armed": 0, "averted": 0}
	_seq = 1
	rng = RandomNumberGenerator.new()
	rng.seed = DEFAULT_SEED
	FireEvents.reset()
	FireRules.reset()
	FireFolk.reset()
	FireTown.reset()

static func key(t: Vector2i) -> String:
	return "%d,%d" % [t.x, t.y]

static func _stat(k: String, n: int = 1) -> void:
	stats[k] = int(stats.get(k, 0)) + n

# ------------------------------------------------------------------ queries
static func active() -> Array:
	var out: Array = fires.values()
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out

static func fires_in(lot: String) -> Array:
	var out: Array = []
	for f in active():
		if str(f["lot"]) == lot:
			out.append(f)
	return out

static func lots_burning() -> Array:
	var out: Array = blazes.keys()
	out.sort()
	return out

static func smoke_of(lot: String) -> float:
	return float((blazes.get(lot, {}) as Dictionary).get("smoke", 0.0))

static func fire_at(t: Vector2i) -> Dictionary:
	for f in fires.values():
		if (f["tiles"] as Array).has(t):
			return f
	return {}

static func is_burning(target) -> bool:
	var r: Dictionary = _resolve(target)
	return not r.is_empty() and not fire_at(r["tile"]).is_empty()

static func hover_text(o) -> String:
	return FireRules.hover_text(o)

static func _resolve(target) -> Dictionary:
	var o = null
	var tile := Vector2i(-1, -1)
	if target is Vector2i:
		tile = target
		o = FireRules.object_at(tile)
	elif target is int:
		o = WorldIface.get_object(int(target))
	elif target is Dictionary:
		return {"tile": target["tile"], "obj": WorldIface.get_object(int(target.get("obj", -1)))}
	else:
		o = target
	if o != null:
		tile = o.tile
	return {"tile": tile, "obj": o} if tile.x >= 0 else {}

# ------------------------------------------------------------------ ignite
static func ignite(target, source: String = "unknown", opts: Dictionary = {}) -> bool:
	var r: Dictionary = _resolve(target)
	if r.is_empty():
		return false
	var o = r["obj"]
	var tile: Vector2i = r["tile"]
	var tiles: Array = FireRules.footprint(o) if o != null else [tile]
	for t in tiles:
		if not fire_at(t).is_empty():
			return false
	var flam: float = FireRules.flammability(o, tile)
	if flam <= 0.0 and not bool(opts.get("force", ["arson", "wildfire", "lightning"].has(source))):
		return false
	var lot: String = FireRules.lot_of(tile)
	var burn: float = (FireRules.num("burn_base", 9.0) + FireRules.num("burn_flam", 14.0) * flam) * rng.randf_range(0.8, 1.2)
	if o == null:
		burn = FireRules.num("burn_min_floor", 5.0) * rng.randf_range(0.8, 1.2)
	var stage: int = clampi(int(opts.get("stage", 1)), 1, 3)
	var age: float = 0.0 if stage == 1 else FireRules.at("stage_age", stage - 2, 4.0)
	var f := {"id": _seq, "tile": tile, "tiles": tiles, "obj": int(o.id) if o != null else -1, "def": str(o.def_id) if o != null else "", "lot": lot,
		"born": SysUtil.now(), "age": age, "stage": stage, "burn": burn, "next_spread": SysUtil.now() + int(FireRules.num("spread_min", 4.0) + FireRules.num("first_spread_delay", 1.0)),
		"source": source, "culprit": int(opts.get("culprit", -1))}
	_seq += 1
	fires[int(f["id"])] = f
	_stat("ignited")
	var b: Dictionary = blazes.get(lot, {})
	if b.is_empty():
		b = _new_blaze(lot, source, int(opts.get("culprit", -1)))
		blazes[lot] = b
		_stat("blazes")
		_announce(b, f, bool(opts.get("quiet", false)))
	b["peak"] = maxi(int(b["peak"]), fires_in(lot).size())
	SysUtil.game_event("fire_started", {"lot": lot, "tile": [tile.x, tile.y], "source": source, "object": str(f["def"]), "folk_id": -1})
	return true

static func _new_blaze(lot: String, source: String, culprit: int) -> Dictionary:
	return {"lot": lot, "source": source, "culprit": culprit, "start": SysUtil.now(), "called": false, "call_min": -1, "due": -1, "alarm": false, "here": false,
		"here_min": -1, "spread": false, "peak": 1, "lost": [], "loss": 0, "smoke": 0.0, "hid": FireRules.hid_of_lot(lot), "folk": {}, "hurt": [], "dead": [],
		"rescued": [], "neighbor_min": SysUtil.now() + int(FireRules.num("neighbor_call_min", 18.0)), "out_min": -1}

static func _announce(b: Dictionary, f: Dictionary, quiet: bool) -> void:
	if quiet or not FireRules.is_home(str(b["lot"])):
		return
	var label: String = "Something"
	if int(f["obj"]) >= 0:
		var o = WorldIface.get_object(int(f["obj"]))
		if o != null:
			label = str(FireRules.obj_def(o).get("label", o.def_id))
	SysUtil.notify("Fire! The %s is burning." % label.to_lower() if label != "Something" else "Fire! Something is burning.", "bad")

# ------------------------------------------------------------------ extinguish / end
## Put a fire out (it stays where it is as a scorched, partly burnt object). `by`: folk | sprinkler | brigade | self.
static func extinguish(target, by: String = "") -> bool:
	var r: Dictionary = _resolve(target)
	if r.is_empty():
		return false
	var f: Dictionary = fire_at(r["tile"])
	if f.is_empty():
		return false
	end_fire(int(f["id"]), "out", by)
	return true

static func extinguish_lot(lot: String, by: String = "") -> int:
	var n: int = 0
	for f in fires_in(lot):
		end_fire(int(f["id"]), "out", by)
		n += 1
	return n

## how: out (put out) | burnt (burnt down: the object is gone).
static func end_fire(id: int, how: String, by: String = "") -> void:
	var f: Dictionary = fires.get(id, {})
	if f.is_empty():
		return
	fires.erase(id)
	var lv: int = clampi(int(f["stage"]), 1, 3)
	if how == "burnt":
		lv = maxi(lv, 2)
	for t in f["tiles"]:
		mark_scorch(t, lv)
	if how == "burnt":
		_stat("burned_out")
	else:
		match by:
			"folk", "smothered":
				_stat("by_folk")
			"sprinkler":
				_stat("by_sprinkler")
			"brigade":
				_stat("by_brigade")
		FireSpread.damage_survivor(f)
	SysUtil.game_event("fire_ended", {"lot": str(f["lot"]), "how": how, "by": by, "folk_id": -1})

static func mark_scorch(t: Vector2i, lv: int) -> void:
	var k: String = key(t)
	var old: int = int((scorch.get(k, {}) as Dictionary).get("lv", 0))
	scorch[k] = {"lv": maxi(old, lv), "day": SysUtil.day()}

static func call_brigade(lot: String, caller_id: int = -1) -> void:
	FireBrigade.call_in(lot, caller_id)

# ------------------------------------------------------------------ clock
static func on_minute() -> void:
	FireTown.ensure()
	if fires.is_empty() and blazes.is_empty() and crew.is_empty() and FireEvents.armed.is_empty():
		return
	var now: int = SysUtil.now()
	FireSpread.step_all(now)
	FireEvents.step(now)
	FireFolk.step(now)
	FireBrigade.step(now)
	_close_finished(now)

static func on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	FireEvents.on_interaction_started(folk_id, iid, target_id)

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev.begins_with("fire_"):
		FireEvents.on_game_event(ev, payload)

static func on_day(day: int) -> void:
	FireTown.on_day(day)
	var gone: Array = []
	for k in scorch:
		if day - int(scorch[k]["day"]) > int(FireRules.num("scorch_days", 6.0)):
			gone.append(k)
	for k2 in gone:
		scorch.erase(k2)

static func _close_finished(now: int) -> void:
	for lot in blazes.keys():
		var b: Dictionary = blazes[lot]
		if not fires_in(str(lot)).is_empty():
			continue
		b["out_min"] = now
		FireFolk.release(b)
		FireBrigade.finish(b)
		FireEvents.summarize(b)
		blazes.erase(lot)

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	var fl: Array = []
	for f in active():
		var c: Dictionary = (f as Dictionary).duplicate(true)
		c["tile"] = [f["tile"].x, f["tile"].y]
		var ts: Array = []
		for t in f["tiles"]:
			ts.append([t.x, t.y])
		c["tiles"] = ts
		fl.append(c)
	return {"fires": fl, "blazes": blazes.duplicate(true), "scorch": scorch.duplicate(true), "crew": crew.duplicate(true), "stats": stats.duplicate(),
		"seq": _seq, "rng_seed": rng.seed, "rng_state": str(rng.state), "events": FireEvents.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for c in d.get("fires", []):
		var f: Dictionary = (c as Dictionary).duplicate(true)
		f["tile"] = Vector2i(int(c["tile"][0]), int(c["tile"][1]))
		var ts: Array = []
		for t in c["tiles"]:
			ts.append(Vector2i(int(t[0]), int(t[1])))
		f["tiles"] = ts
		SysUtil.ints_in(f, ["id", "obj", "born", "stage", "next_spread", "culprit"])
		f["age"] = float(f.get("age", 0.0))
		f["burn"] = float(f.get("burn", 10.0))
		fires[int(f["id"])] = f
	var bs: Dictionary = d.get("blazes", {})
	for lot in bs:
		var b: Dictionary = (bs[lot] as Dictionary).duplicate(true)
		SysUtil.ints_in(b, ["culprit", "start", "call_min", "due", "here_min", "peak", "loss", "hid", "neighbor_min", "out_min"])
		b["smoke"] = float(b.get("smoke", 0.0))
		b["folk"] = SysUtil.int_keys(b.get("folk", {}))
		b["hurt"] = SysUtil.to_ints(b.get("hurt", []))
		b["dead"] = SysUtil.to_ints(b.get("dead", []))
		b["rescued"] = SysUtil.to_ints(b.get("rescued", []))
		blazes[str(lot)] = b
	scorch = (d.get("scorch", {}) as Dictionary).duplicate(true)
	for k in scorch:
		SysUtil.ints_in(scorch[k], ["lv", "day"])
	crew = (d.get("crew", []) as Array).duplicate(true)
	for c2 in crew:
		SysUtil.ints_in(c2, ["id", "leave_min"])
	var st: Dictionary = d.get("stats", {})
	for k2 in st:
		stats[k2] = int(st[k2])
	_seq = int(d.get("seq", 1))
	rng.seed = int(d.get("rng_seed", DEFAULT_SEED))
	rng.state = int(str(d.get("rng_state", rng.state)))
	FireEvents.from_dict(d.get("events", {}))
