class_name Health
extends RefCounted
## Needs deaths, exposure, illness and injury for the people on the map (task 02). Data: `config.health` of data/incidents/02_needs_health.json
## (read through IncidentDefs.cfg("health")), buffs / interactions in the same file's `content`, illness dice are ordinary incidents there.
##
## Needs deaths (starvation, exhaustion, exposure) are NOT rare-event dice: they are deterministic consequences of long neglect, so the
## Surprises setting does not scale them. Illness and injury are dice (incidents), so Surprises does scale those.
##
## ---- Health API (other tasks call these) ----
##   Health.injure(folk_or_id, severity 1..3, cause) -> bool        marks them injured (slow, no exercise / physical work); 2+ goes to hospital
##   Health.is_injured(f) / Health.injury_severity(f) -> int         0 = not injured
##   Health.fall_ill(f, kind, severity, cause) -> bool               kind: cold | flu | food_poisoning | exposure | generic
##   Health.is_ill(f) / Health.illness_of(f) -> {kind, severity, since}
##   Health.speed_mult(f) -> float                                   walking speed factor (1.0 = healthy); Interaction.start divides travel time by it
##   Health.blocks_activity(f, tags) -> String                       "" or the reason (exercise / physical tags while injured or flu)
##   Health.work_block(f, career_id) -> String                       "" or the reason someone cannot work today (flu, injury in a physical job)
##   Health.is_collapsed(f) / Health.rescue(f, helper) / Health.collapse(f, kind)
##   Health.heal(f) / Health.on_doctor(f)                            cure (doctor call also revives the collapsed)
##   Health.register_neglect_hook(callable)                          task 07: callable(folk, {kind, minutes, needs}) when a dependent is neglected
##   Health.stage_of(f) -> {hunger, energy, cold, heat}              0 fine .. 3 collapsed (readable by tests / UI)
## Clock hooks (called from Incidents.on_minute / on_hour / on_day): tick state per person. Own seeded rng, saved with the game.

const DEFAULT_SEED := 20261018

static var records: Dictionary = {}          # folk_id -> record (minutes at the floor, collapse, illness ...)
static var counters: Dictionary = {}         # name -> count (tests / debug panel)
static var neglect_hooks: Array = []         # callables, survive reset (code registered)
static var contacts: Dictionary = {}         # "a_b" -> game minute of the last talk
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	records.clear()
	counters.clear()
	contacts.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = DEFAULT_SEED

static func cfg(section: String = "") -> Dictionary:
	var c: Dictionary = IncidentDefs.cfg("health", {})
	return c if section == "" else c.get(section, {})

static func count(key: String, n: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n

static func rec_of(fid: int) -> Dictionary:
	if not records.has(fid):
		records[fid] = {}
	return records[fid]

## Player text from config.health.text with {name} filled in.
static func text(key: String, f) -> String:
	var t: String = str(cfg("text").get(key, ""))
	if f != null:
		t = Sexes.fill(t, int(f.id))          # {they} {them} for a known sex
	return t.replace("{name}", str(f.name) if f != null else "Someone")

static func tell(f, key: String, kind: String = "warn") -> void:
	var t: String = text(key, f)
	if t != "" and f != null and SysUtil.is_resident(f):
		SysUtil.notify(t, kind)

static func think(f, key: String) -> void:
	var t: String = str(cfg("thought").get(key, ""))
	if t != "" and f != null:
		SimEnv.emit("thought", int(f.id), t)

static func stage_mult(f) -> float:
	return float(cfg("stage_mult").get(str(f.age_stage), 1.0))

static func register_neglect_hook(cb: Callable) -> void:
	if cb.is_valid() and not neglect_hooks.has(cb):
		neglect_hooks.append(cb)

static func _folk(x):
	return x if x is Folk else SysUtil.folk(int(x))

# ------------------------------------------------------------------ public API (delegates)
static func injure(x, severity: int, cause: String = "") -> bool:
	return HealthInjury.injure(_folk(x), severity, cause)

static func is_injured(f) -> bool:
	return f != null and f.has_buff("injured")

static func injury_severity(f) -> int:
	return int(rec_of(int(f.id)).get("inj", 1)) if is_injured(f) else 0

static func fall_ill(x, kind: String, severity: int = 1, cause: String = "") -> bool:
	return HealthIllness.fall_ill(_folk(x), kind, severity, cause)

static func is_ill(f) -> bool:
	return f != null and str(rec_of(int(f.id)).get("ill", "")) != ""

static func illness_of(f) -> Dictionary:
	var r: Dictionary = rec_of(int(f.id))
	return {"kind": str(r.get("ill", "")), "severity": int(r.get("ill_sev", 0)), "since": int(r.get("ill_since", 0))} if is_ill(f) else {}

static func is_collapsed(f) -> bool:
	return f != null and f.has_buff("collapsed")

static func collapse(f, kind: String) -> bool:
	return HealthCollapse.collapse(f, kind)

static func rescue(f, helper = null) -> bool:
	return HealthCollapse.rescue(f, helper)

static func speed_mult(f) -> float:
	return HealthInjury.speed_mult(f)

static func blocks_activity(f, tags: Array) -> String:
	return HealthInjury.blocks_activity(f, tags)

static func work_block(f, career_id: String) -> String:
	return HealthInjury.work_block(f, career_id)

static func heal(f) -> void:
	HealthInjury.heal(f)
	HealthIllness.cure(f, 1.0)

## Doctor visit (Incidents.call_doctor): revive the collapsed, treat illness and injury. Returns what was treated.
static func on_doctor(f) -> Array:
	var treated: Array = []
	if is_collapsed(f) and HealthCollapse.rescue(f, null):
		treated.append("collapse")
	if is_ill(f):
		HealthIllness.cure(f, float(cfg("doctor").get("illness_cure", 0.75)))
		treated.append("illness")
	if is_injured(f):
		HealthInjury.treat(f, float(cfg("doctor").get("injury_cure", 0.5)))
		treated.append("injury")
	f.add_buff("medicated")
	return treated

static func stage_of(f) -> Dictionary:
	return HealthNeeds.stages(f, rec_of(int(f.id)))

## "Flu", "Cold", "Food poisoning" or the generic "Unwell" for the sick chip.
static func sick_label(f) -> String:
	return {"cold": "Cold", "flu": "Flu", "food_poisoning": "Food poisoning"}.get(str(rec_of(int(f.id)).get("ill", "")), "Unwell")

## Folk panel chips for the states Hospital does not cover (Hospital.status_chips appends these).
static func status_chips(f) -> Array:
	var out: Array = []
	var tips: Dictionary = cfg("chips")
	for b in ["collapsed", "hypothermia", "heat_exhaustion", "shivering", "overheating", "weak_hunger", "neglected"]:
		if f.has_buff(b) and tips.has(b):
			var t: Dictionary = tips[b]
			out.append({"text": str(t.get("text", b)), "color": Color(str(t.get("color", "#e5534b"))), "tip": str(t.get("tip", ""))})
	return out

# ------------------------------------------------------------------ clock
static func on_minute() -> void:
	var now: int = SysUtil.now()
	for f in WorldIface.all_folk():
		var resident: bool = SysUtil.is_resident(f) and not SysUtil.is_away(f)
		var r: Variant = records.get(int(f.id), null)
		if r == null:
			if not resident:
				continue                       # no health record and nothing to track: strangers cost nothing per minute
			r = rec_of(int(f.id))
		if Hospital.is_in(f):
			continue
		if not (r as Dictionary).is_empty():
			HealthInjury.tick_minute(f, r)         # (both only act on a person who has an injury / illness record)
			HealthIllness.tick_minute(f, r)
		if resident:
			HealthNeeds.tick(f, r, now)
			HealthExposure.tick(f, r, now)
			HealthCollapse.tick(f, r, now)

static func on_hour() -> void:
	for f in WorldIface.all_folk():
		if Hospital.is_in(f):
			continue
		var r: Dictionary = rec_of(int(f.id))
		HealthIllness.hourly(f, r)
		if SysUtil.is_resident(f) and not SysUtil.is_away(f):
			HealthNeeds.hourly(f, r)
			HealthExposure.hourly(f, r)
	_prune()

static func on_day() -> void:
	var now: int = SysUtil.now()
	for k in contacts.keys():
		if now - int(contacts[k]) > 1440:
			contacts.erase(k)

static func _prune() -> void:
	for fid in records.keys():
		if SysUtil.folk(int(fid)) == null:
			records.erase(fid)

# ------------------------------------------------------------------ hooks from SystemsManager / Hospital
static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	match ev_name:
		"social_done":
			HealthIllness.note_contact(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
			HealthInjury.on_social(payload)
		"health_rescue":
			HealthCollapse.rescue(SysUtil.folk(int(payload.get("target_id", -1))), SysUtil.folk(int(payload.get("folk_id", -1))))
		"health_medicine":
			var f = SysUtil.folk(int(payload.get("folk_id", -1)))
			if f != null:
				HealthIllness.cure(f, float(cfg("medicine").get("illness_cure", 0.4)))
		"health_first_aid":
			var f2 = SysUtil.folk(int(payload.get("folk_id", -1)))
			if f2 != null:
				HealthInjury.treat(f2, float(cfg("medicine").get("injury_cure", 0.3)))
		"health_cooled":
			var f3 = SysUtil.folk(int(payload.get("folk_id", -1)))
			if f3 != null:
				HealthExposure.cool_down(f3)

static func on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	HealthIllness.on_started(f, iid, target_id)

## Admitted to hospital: a collapsed person is brought round (their rescue is the hospital's job now).
static func on_admitted(f) -> void:
	if is_collapsed(f):
		HealthCollapse.rescue(f, null)

## Hospital stay is over: the illness / injury is treated.
static func on_discharged(f) -> void:
	HealthInjury.heal(f)
	HealthIllness.cure(f, 1.0)

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"records": SysUtil.str_keys(records).duplicate(true), "counters": counters.duplicate(), "contacts": contacts.duplicate(),
		"rng_seed": rng.seed, "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for k in (d.get("records", {}) as Dictionary):
		records[int(str(k))] = (d["records"][k] as Dictionary).duplicate(true)
	for k2 in (d.get("counters", {}) as Dictionary):
		counters[str(k2)] = int(d["counters"][k2])
	for k3 in (d.get("contacts", {}) as Dictionary):
		contacts[str(k3)] = int(d["contacts"][k3])
	rng.seed = int(d.get("rng_seed", DEFAULT_SEED))
	rng.state = int(str(d.get("rng_state", rng.state)))
