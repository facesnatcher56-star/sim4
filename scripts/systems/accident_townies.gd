class_name AccidentTownies
extends RefCounted
## The far-townie (STATISTICAL) side of the accident markers: once an hour every living townie who is not on the map gets the same
## `acc_*` marker names a Folk would get from what they do, rolled from config.accidents.townie (hourly chance per marker, hours of
## the day, extra chance for kids / people with a matching object, a physical career at work). The statistical incident outcomes
## then use the shared incident data. Deterministic (hash of day, hour, townie id): nothing extra to save.

static func _u(tid: int, hour: int, salt: int) -> float:
	return float(hash([SysUtil.day(), hour, tid, salt]) & 0xFFFFF) / 1048576.0

static func _in_hours(spec: Dictionary, hour: int) -> bool:
	var hs: Array = spec.get("hours", [])
	return hs.is_empty() or (hour >= int(hs[0]) and hour < int(hs[1]))

static func on_hour(hour: int) -> void:
	var c: Dictionary = (IncidentDefs.cfg("accidents", {}) as Dictionary)
	var spec: Dictionary = c.get("townie", {})
	if spec.is_empty():
		return
	var ids: Array = Story.townies.keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = Story.townies[tid]
		if not bool(t["alive"]) or IncidentSubject.on_map(int(tid)):
			continue
		var buffs: Array = []
		for b in (t.get("buffs", []) as Array):
			if not str(b).begins_with(AccidentMarks.PREFIX):
				buffs.append(b)
		if not bool(t.get("in_hospital", false)):
			_roll(int(tid), t, hour, c, spec, buffs)
		t["buffs"] = buffs

static func _roll(tid: int, t: Dictionary, hour: int, c: Dictionary, spec: Dictionary, buffs: Array) -> void:
	var stage: String = Story.stage_of(t)
	var kid: bool = stage == "child" or stage == "toddler"
	var salt: int = 0
	for m in spec.get("markers", {}):
		salt += 1
		var s: Dictionary = spec["markers"][m]
		if not _in_hours(s, hour):
			continue
		if s.has("stages") and not (s["stages"] as Array).has(stage):
			continue
		var p: float = float(s.get("p", 0.0))
		if kid:
			p *= float(s.get("kid_mult", 1.0))
		if _has_any_object(t, s.get("objects", [])):
			p *= float(s.get("object_mult", 1.0))
		if s.get("weather", "") == "slippery" and not _slippery():
			continue
		if s.get("weather", "") == "icy" and Weather.snow_cover() < float(c.get("icy_snow_cover", 0.25)):
			continue
		if bool(s.get("traffic", false)):
			p *= Traffic.risk_for_hour(float(hour))
		if _u(tid, hour, salt) < p:
			buffs.append(str(m))
	# a physical career at work
	var tier: int = Works.injury_tier(str(t.get("career", "")))
	var w: Array = spec.get("work_hours", [9, 17])
	if tier > 0 and hour >= int(w[0]) and hour < int(w[1]):
		buffs.append("acc_job_risky")
		if tier >= 2:
			buffs.append("acc_job_very_risky")
		if tier >= 3:
			buffs.append("acc_job_hazard")
	# company
	if _u(tid, hour, 99) < float(spec.get("alone_p", 0.25)):
		buffs.append("acc_alone")
	if kid and _u(tid, hour, 98) < float(spec.get("unsupervised_p", 0.3)):
		buffs.append("acc_unsupervised")

static func _slippery() -> bool:
	var c: Dictionary = (IncidentDefs.cfg("accidents", {}) as Dictionary)
	return Weather.snow_cover() >= float(c.get("icy_snow_cover", 0.25)) or Weather.wetness() >= float(c.get("slippery_wetness", 0.5))

static func _has_any_object(t: Dictionary, want: Array) -> bool:
	if want.is_empty():
		return false
	for o in (t.get("town_objects", []) as Array):
		if want.has(str(o)):
			return true
	return false
