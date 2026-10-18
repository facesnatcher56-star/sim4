class_name Incidents
extends RefCounted
## Rare events for the WHOLE town. Data: data/incidents.json + data/incidents/*.json (IncidentDefs). Every incident applies to every
## person and lot: the player's household and folk on the map run the FULL version (real handlers, toasts per notify_policy); far
## townies and lots run the STATISTICAL version (same rates / conditions / risk multipliers through IncidentSubject, a dice-rolled
## outcome and a one-line summary). Both record into history + counters and emit the chronicle hook (ChronicleHook.note).
##
## Public API (all static):
##   Incidents.surprise_mult() / level_id() / set_level("off"|"rare"|"normal"|"chaotic")      the Surprises setting (saved per game)
##   Incidents.list() / active() / history(n) / stat(id)                                      introspection (debug panel, tests)
##   Incidents.force(id, ctx) -> {ok, mode, text}     ctx: folk_id | townie_id | lot ("home:1" / "town:3" / household id) | outcome (index) | warn (bool)
##   Incidents.resolve_statistical(def_id, subject) -> {ok, summary, ...}                      subject: Folk, townie id or IncidentSubject
##   Incidents.register_handler(name, Callable) / handler(name)                                  complex behaviours (fire spread, crime ...)
##   Incidents.insurance_cover(amount, hid) -> coins an insurance pays (task 06 sets insurance_fn)
##   Incidents.call_doctor(folk_id) -> {ok, cost, defused}                                       counterplay hook (task 02 builds on it)
##   Incidents.effective_rate(id, subject) -> events per year right now (debug panel)
## Clock hooks (SystemsManager): on_minute (pending warnings), on_hour, on_day. Own rng (seeded, saved) so incident history is
## reproducible and independent of other systems' dice.

const DEFAULT_SEED := 90210

static var handlers: Dictionary = {}          # name -> Callable (code-registered; survives reset)
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var level: String = ""
static var counters: Dictionary = {}          # id -> {checks, exposure, triggered, averted, forced, warned, statistical, last_day, last_text}
static var pending: Array = []                # [{id, kind, sid, lot_key, due_min, defused}]
static var _history: Array = []
static var insurance_fn: Callable = Callable()

static func reset() -> void:
	IncidentDefs.reset()
	DeathCauses.reset()
	counters.clear()
	pending.clear()
	_history.clear()
	seed_rng(DEFAULT_SEED)
	level = _settings_level()
	Hospital.reset()
	Health.reset()
	Graves.reset()
	DisasterState.reset()
	ChronicleHook.reset()

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

# ------------------------------------------------------------------ Surprises setting
static func _settings_level() -> String:
	var lv: String = GameSettings.get_str("surprises")
	return lv if (IncidentDefs.cfg("levels", {}) as Dictionary).has(lv) else str(IncidentDefs.cfg("default_level", "rare"))

static func level_id() -> String:
	return level if level != "" else _settings_level()

static func set_level(id: String) -> void:
	if (IncidentDefs.cfg("levels", {}) as Dictionary).has(id):
		level = id

static func surprise_mult() -> float:
	return float((IncidentDefs.cfg("levels", {}) as Dictionary).get(level_id(), 1.0))

# ------------------------------------------------------------------ handlers
static func register_handler(hname: String, cb: Callable) -> void:
	handlers[hname] = cb

static func clear_handlers() -> void:
	handlers.clear()
	insurance_fn = Callable()

## A code-registered handler, else the {script, method} declared in a data file ("handlers" section).
static func handler(hname: String) -> Callable:
	if handlers.has(hname):
		return handlers[hname]
	var sp: Dictionary = IncidentDefs.handler_specs.get(hname, {})
	if sp.is_empty() or not ResourceLoader.exists(str(sp.get("script", ""))):
		return Callable()
	var scr: Script = load(str(sp["script"]))
	return Callable(scr, str(sp.get("method", "")))

# ------------------------------------------------------------------ introspection
static func list() -> Array:
	var out: Array = []
	for id in IncidentDefs.ids():
		var d: Dictionary = IncidentDefs.defs[id]
		out.append({"id": id, "label": str(d.get("label", id)), "scope": str(d.get("scope", "")), "check": str(d.get("check", "")),
			"base_rate": float(d.get("base_rate_per_year", 0.0)), "stat": stat(id)})
	return out

static func active() -> Array:
	return pending.duplicate(true)

static func history(n: int = 20) -> Array:
	return _history.slice(maxi(_history.size() - n, 0))

static func stat(id: String) -> Dictionary:
	return counters.get(id, {"checks": 0, "exposure": 0.0, "triggered": 0, "averted": 0, "forced": 0, "warned": 0, "statistical": 0, "last_day": -1, "last_text": ""})

static func _counter(id: String) -> Dictionary:
	if not counters.has(id):
		counters[id] = stat(id).duplicate()
	return counters[id]

## Measured events per subject-year so far (statistical tests): triggered / exposure.
static func measured_rate(id: String) -> float:
	var s: Dictionary = stat(id)
	return float(s["triggered"]) / maxf(float(s["exposure"]), 0.0001)

static func effective_rate(id: String, subject) -> float:
	return IncidentRisk.effective_rate(IncidentDefs.get_def(id), IncidentSubject.make(subject))

static func insurance_cover(amount: int, hid: int = 0) -> int:
	if insurance_fn.is_valid():
		return clampi(int(insurance_fn.call(amount, hid)), 0, amount)
	return 0

# ------------------------------------------------------------------ clock hooks
static func on_minute() -> void:
	if not pending.is_empty():
		IncidentFlow.process_pending()
	Health.on_minute()

static func on_hour() -> void:
	Hospital.on_hour()
	Health.on_hour()
	IncidentChecks.run("hour")

static func on_day() -> void:
	Health.on_day()
	IncidentChecks.run("day")

# ------------------------------------------------------------------ force / statistical
static func force(id: String, ctx: Dictionary = {}) -> Dictionary:
	return IncidentFlow.force(id, ctx)

static func resolve_statistical(def_id: String, subject, outcome_index: int = -1) -> Dictionary:
	return IncidentFlow.resolve(def_id, IncidentSubject.make(subject), true, false, outcome_index)

## "Ask for a doctor": costs coins, gives a check-up and defuses warned incidents that allow it (doctor_can_defuse).
static func call_doctor(folk_id: int) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return {"ok": false, "cost": 0, "defused": 0}
	var cost: int = int(IncidentDefs.cfg("doctor_cost", 120))
	var net: int = maxi(cost - insurance_cover(cost, int(f.household_id)), 0)
	if net > 0 and not Economy.spend(int(f.household_id), net, "doctor"):
		SysUtil.notify("The household cannot afford a doctor right now.", "warn")
		return {"ok": false, "cost": net, "defused": 0}
	_timed_checkup(f)
	var treated: Array = Health.on_doctor(f)
	var n: int = 0
	for p in pending:
		if p["kind"] == "folk" and int(p["sid"]) == folk_id and bool(IncidentDefs.get_def(str(p["id"])).get("warning", {}).get("doctor_can_defuse", false)):
			p["defused"] = true
			n += 1
	SysUtil.notify("The doctor has examined %s." % f.name, "info")
	return {"ok": true, "cost": net, "defused": n, "treated": treated}

static func _timed_checkup(f) -> void:
	f.add_buff("checked_up")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"level": level_id(), "rng_seed": rng.seed, "rng_state": str(rng.state), "counters": counters.duplicate(true), "pending": pending.duplicate(true),
		"history": _history.duplicate(true), "hospital": Hospital.to_dict(), "health": Health.to_dict(), "graves": Graves.to_dict(), "disasters": DisasterState.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	level = str(d.get("level", level))
	rng.seed = int(d.get("rng_seed", DEFAULT_SEED))
	rng.state = int(str(d.get("rng_state", rng.state)))
	var src: Dictionary = d.get("counters", {})
	for id in src:
		var c: Dictionary = (src[id] as Dictionary).duplicate(true)
		SysUtil.ints_in(c, ["checks", "triggered", "averted", "forced", "warned", "statistical", "last_day"])
		c["exposure"] = float(c.get("exposure", 0.0))
		counters[id] = c
	for p in d.get("pending", []):
		var q: Dictionary = (p as Dictionary).duplicate(true)
		SysUtil.ints_in(q, ["sid", "due_min"])
		pending.append(q)
	_history = (d.get("history", []) as Array).duplicate(true)
	Hospital.from_dict(d.get("hospital", {}))
	Health.from_dict(d.get("health", {}))
	Graves.from_dict(d.get("graves", {}))
	DisasterState.from_dict(d.get("disasters", {}))

static func record_history(entry: Dictionary) -> void:
	_history.append(entry)
	var cap: int = int(IncidentDefs.cfg("history_cap", 200))
	while _history.size() > cap:
		_history.pop_front()
