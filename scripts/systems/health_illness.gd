class_name HealthIllness
extends RefCounted
## Colds, flu and food poisoning. The CATCHING is ordinary incident dice (data/incidents/02_needs_health.json: catch_cold, catch_flu, so the
## Surprises setting, force hooks and the far-townie statistical version all work). This class keeps the state:
##  * fall_ill(): the illness buff (common_cold / flu / food_poisoning) + the generic `sick` marker, a record, admit when serious
##  * contagion: every hour a contagious person marks the people they live with (and anyone they talked to lately) with a hidden
##    `exposed_cold` / `exposed_flu` buff; the incident's risk multiplier does the rest. Recovery gives a few days of immunity.
##  * eating from a fridge with spoiled food rolls food poisoning (a warned, defusable incident); rest (lying down) and medicine speed recovery.

static func kinds() -> Dictionary:
	return Health.cfg("illness").get("kinds", {})

static func kind_def(kind: String) -> Dictionary:
	return kinds().get(kind, kinds().get("generic", {}))

static func timed(f, buff: String, minutes: float) -> void:
	if buff == "" or SimEnv.data().buff_def(buff).is_empty():
		return
	var old_left: float = 0.0
	for b in f.buffs:
		if str(b["id"]) == buff:
			old_left = float(b["remaining"])
	f.add_buff(buff)                       # (re-adding would stretch it to the definition's length, so set it ourselves)
	for b2 in f.buffs:
		if str(b2["id"]) == buff:
			b2["remaining"] = maxf(old_left, minutes)

static func mark_sick(f, hours: float) -> void:
	timed(f, "sick", hours * 60.0)

static func fall_ill(f, kind: String, severity: int = 1, cause: String = "") -> bool:
	if f == null:
		return false
	severity = clampi(severity, 1, 3)
	if kind == "food_poisoning" and SysUtil.rng.randf() > Creation.mult(int(f.id), "food_sickness_mult"):
		return false          # task 55: an iron stomach shrugs it off
	var kd: Dictionary = kind_def(kind)
	var r: Dictionary = Health.rec_of(int(f.id))
	var mins: float = float(kd.get("hours", 24.0)) * 60.0 * (1.0 + 0.5 * float(severity - 1))
	if kind == "generic":          # framework `sick` effect / Hospital.fall_ill: durations by severity from config.hospital.sick_hours
		mins = float(IncidentDefs.cfg("hospital", {}).get("sick_hours", {}).get(str(severity), 24.0)) * 60.0
	timed(f, str(kd.get("buff", "")), mins)
	timed(f, "sick", mins)
	if not Health.is_ill(f):
		r["ill_since"] = SysUtil.now()
	r["ill"] = kind if kind in kinds() else "generic"
	r["ill_sev"] = maxi(int(r.get("ill_sev", 0)), severity)
	Health.count("ill_" + kind)
	SysUtil.game_event("fell_ill", {"folk_id": int(f.id), "severity": severity, "reason": cause, "kind": kind})
	if severity >= int(IncidentDefs.cfg("hospital", {}).get("min_admit_severity", 2)):
		Hospital.emergency(int(f.id), severity, cause)
	return true

## Treat: shorten the illness by `fraction` (1.0 = cured now). Returns true when the illness is over.
static func cure(f, fraction: float) -> bool:
	if f == null or not Health.is_ill(f):
		return false
	var r: Dictionary = Health.rec_of(int(f.id))
	var kd: Dictionary = kind_def(str(r["ill"]))
	for buff in [str(kd.get("buff", "")), "sick"]:
		if buff == "" or not f.has_buff(buff):
			continue
		if fraction >= 0.999:
			f.remove_buff(buff)
		else:
			for b in f.buffs:
				if str(b["id"]) == buff and float(b["remaining"]) > 0.0:
					b["remaining"] = float(b["remaining"]) * (1.0 - fraction)
	if fraction >= 0.999:
		_recovered(f, r, kd)
		return true
	return false

static func _recovered(f, r: Dictionary, kd: Dictionary) -> void:
	r.erase("ill")
	r.erase("ill_sev")
	r.erase("ill_since")
	if str(kd.get("immune_buff", "")) != "":
		timed(f, str(kd["immune_buff"]), float(kd.get("immune_hours", 48)) * 60.0)
	if str(kd.get("exposed_buff", "")) != "":
		f.remove_buff(str(kd["exposed_buff"]))
	Health.count("recovered")
	Health.tell(f, "recovered", "good")
	SysUtil.game_event("recovered", {"folk_id": int(f.id)})

# ------------------------------------------------------------------ ticks
static func tick_minute(f, r: Dictionary) -> void:
	if str(r.get("ill", "")) == "" or str(f.posture) != "lie":
		return
	var bonus: float = float(Health.cfg("illness").get("rest_bonus_per_min", 1.0))
	var kd: Dictionary = kind_def(str(r["ill"]))
	for buff in [str(kd.get("buff", "")), "sick"]:
		for b in f.buffs:
			if str(b["id"]) == buff and float(b["remaining"]) > 0.0:
				b["remaining"] = maxf(float(b["remaining"]) - bonus, 0.0)      # never below zero: a negative timer means "no timer" and the buff would stay for ever

static func hourly(f, r: Dictionary) -> void:
	var kind: String = str(r.get("ill", ""))
	if kind == "":
		return
	var kd: Dictionary = kind_def(kind)
	var buff: String = str(kd.get("buff", ""))
	if buff == "":
		buff = "sick"
	if not f.has_buff(buff) or _timer_lost(f, buff):      # the buff ran out (or the hospital took it): over
		f.remove_buff(buff)
		f.remove_buff("sick")
		_recovered(f, r, kd)
		return
	if bool(kd.get("contagious", false)) and not SysUtil.is_away(f):
		_spread(f, kd)

## An illness buff whose timer went negative (older saves: the rest bonus could push a fractional timer below zero, which Folk.tick_buffs reads
## as "no timer") is over: the person would otherwise be ill, contagious and uncomfortable for the rest of their life.
static func _timer_lost(f, buff: String) -> bool:
	for b in f.buffs:
		if str(b["id"]) == buff:
			return float(b["remaining"]) < 0.0
	return false

static func _spread(f, kd: Dictionary) -> void:
	var ic: Dictionary = Health.cfg("illness")
	var window: int = int(ic.get("talk_window_min", 90))
	var near: int = int(ic.get("home_tiles", 30))
	var now: int = SysUtil.now()
	for o in WorldIface.all_folk():
		if int(o.id) == int(f.id) or SysUtil.is_away(o) or Hospital.is_in(o):
			continue
		if o.has_buff(str(kd.get("immune_buff", "-"))) or o.has_buff(str(kd.get("buff", "-"))):
			continue
		var lives_with: bool = int(o.household_id) > 0 and int(o.household_id) == int(f.household_id) and absi(o.tile.x - f.tile.x) + absi(o.tile.y - f.tile.y) <= near
		var talked: bool = now - int(Health.contacts.get(SysUtil.pair_key(int(o.id), int(f.id)), -100000)) <= window
		if lives_with or talked:
			timed(o, str(kd.get("exposed_buff", "")), float(ic.get("exposed_hours", 8)) * 60.0)
			Health.count("exposed")

static func note_contact(a: int, b: int) -> void:
	if a >= 0 and b >= 0:
		Health.contacts[SysUtil.pair_key(a, b)] = SysUtil.now()

# ------------------------------------------------------------------ food poisoning
## Eating from a fridge that holds spoiled food (or a meal made from it) may make you ill: warned, defusable by medicine / a doctor.
static func on_started(f, iid: String, target_id: int) -> void:
	var fc: Dictionary = Health.cfg("food_poisoning")
	if fc.is_empty() or not SysUtil.is_resident(f) or f.has_buff("food_poisoning"):
		return
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var tags: Array = d.get("tags", [])
	var per: float = 0.0
	if tags.has("meal"):
		per = float(fc.get("meal_per_item", 0.05)) * _household_spoiled(int(f.household_id), true)
	elif tags.has("food") and str(d.get("target", "object")) == "object":
		var o = WorldIface.get_object(target_id)
		if o != null and str(o.def_id) == "fridge":
			per = float(fc.get("snack_per_item", 0.12)) * float(WorldIface.state_get(o, "spoiled", 0.0))
	if per <= 0.0:
		return
	per = minf(per, float(fc.get("max", 0.5)))
	if f.skill_level("cooking") >= int(fc.get("cook_skill_notices", 5)):
		per *= float(fc.get("skilled_mult", 0.5))
	per *= maxf(Creation.mult(int(f.id), "food_sickness_mult"), 1.0)          # task 55: a weak stomach falls ill more often (an iron stomach is the fall_ill roll)
	per = minf(per * Incidents.surprise_mult(), 0.95)
	Health.count("spoiled_meals")
	if Health.rng.randf() < per and not _pending_poison(int(f.id)):
		Health.count("spoiled_hits")
		Incidents.force("food_poisoning", {"folk_id": int(f.id), "warn": true})

static func _pending_poison(fid: int) -> bool:
	for p in Incidents.pending:
		if str(p["id"]) == "food_poisoning" and int(p["sid"]) == fid:
			return true
	return false

## Spoiled items in the household's fridges (the worst one, or the sum).
static func _household_spoiled(hid: int, worst: bool) -> float:
	var total: float = 0.0
	for o in Economy.objects_of(hid):
		if str(o.def_id) == "fridge":
			var s: float = float(WorldIface.state_get(o, "spoiled", 0.0))
			total = maxf(total, s) if worst else total + s
	return total
