class_name HealthInjury
extends RefCounted
## Injuries (falls, scuffles, workouts, fishing slips, accidents from other tasks): buff `injured` with a severity 1..3 in the record.
## While injured: walking is slower (speed_mult, applied in Interaction.start), exercise interactions are not offered (test patch, HealthContent),
## physical jobs are skipped (work_block). Rest (lying down) doubles recovery; first aid and a doctor shorten it; severity 2+ goes to hospital.
## (Sport, treadmill and fishing accidents are task 05's; they call Health.injure.)

static func injure(f, severity: int, cause: String = "") -> bool:
	if f == null:
		return false
	severity = clampi(severity, 1, 3)
	var r: Dictionary = Health.rec_of(int(f.id))
	var cur: int = int(r.get("inj", 0)) if f.has_buff("injured") else 0
	r["inj"] = maxi(cur, severity)
	r["inj_cause"] = cause
	var hours: float = float(IncidentDefs.cfg("hospital", {}).get("injured_hours", {}).get(str(r["inj"]), 24.0))
	HealthIllness.timed(f, "injured", hours * 60.0)
	Health.count("injured")
	SysUtil.game_event("injured", {"folk_id": int(f.id), "severity": severity, "reason": cause})
	if severity >= int(IncidentDefs.cfg("hospital", {}).get("min_admit_severity", 2)):
		Hospital.admit(int(f.id), severity, cause)
	return true

static func heal(f) -> void:
	if f == null:
		return
	f.remove_buff("injured")
	Health.rec_of(int(f.id)).erase("inj")

## Shorten the injury by `fraction` of what is left.
static func treat(f, fraction: float) -> void:
	for b in f.buffs:
		if str(b["id"]) == "injured" and float(b["remaining"]) > 0.0:
			b["remaining"] = float(b["remaining"]) * (1.0 - clampf(fraction, 0.0, 1.0))

static func tick_minute(f, r: Dictionary) -> void:
	if r.has("inj"):
		if not f.has_buff("injured"):
			r.erase("inj")
			r.erase("inj_cause")
			Health.tell(f, "healed", "good")
		elif str(f.posture) == "lie":
			treat_minutes(f, float(Health.cfg("injury").get("rest_bonus_per_min", 1.0)))

static func treat_minutes(f, minutes: float) -> void:
	for b in f.buffs:
		if str(b["id"]) == "injured" and float(b["remaining"]) > 0.0:
			b["remaining"] = float(b["remaining"]) - minutes

# ------------------------------------------------------------------ limits
static func speed_mult(f) -> float:
	if f == null:
		return 1.0
	var sc: Dictionary = Health.cfg("speed")
	var m: float = 1.0
	if f.has_buff("injured"):
		m *= float(sc.get("injured", {}).get(str(int(Health.rec_of(int(f.id)).get("inj", 1))), 0.8))
	for b in sc.get("buffs", {}):
		if f.has_buff(str(b)):
			m *= float(sc["buffs"][b])
	return maxf(m, float(sc.get("min", 0.3)))

## "" when fine, else a short reason (the thing the person cannot do because of how they feel).
static func blocks_activity(f, tags: Array) -> String:
	var ic: Dictionary = Health.cfg("injury")
	for t in tags:
		if (ic.get("blocked_tags", []) as Array).has(str(t)):
			if f.has_buff("injured"):
				return "too hurt to do that"
			if f.has_buff("flu") or f.has_buff("food_poisoning") or f.has_buff("hypothermia") or f.has_buff("heat_exhaustion"):
				return "too unwell to do that"
	return ""

static func work_block(f, career_id: String) -> String:
	if f.has_buff("flu") or f.has_buff("food_poisoning") or f.has_buff("hypothermia") or f.has_buff("heat_exhaustion"):
		return "was too unwell to go to work"
	if f.has_buff("injured"):
		var ic: Dictionary = Health.cfg("injury")
		if int(Health.rec_of(int(f.id)).get("inj", 1)) >= 2 or (ic.get("physical_careers", []) as Array).has(career_id):
			return "was too hurt to work"
	return ""

## A scuffle: picking a fight sometimes hurts the one on the receiving end.
static func on_social(payload: Dictionary) -> void:
	if str(payload.get("interaction", "")) != "insult":
		return
	var p: float = float(Health.cfg("injury").get("scuffle_chance", 0.08)) * Incidents.surprise_mult()
	var tid: int = int(payload.get("target_id", -1))
	if SysUtil.folk(tid) != null and Health.rng.randf() < p:
		Incidents.force("scuffle_injury", {"folk_id": tid})
