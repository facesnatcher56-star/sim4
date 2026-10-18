class_name DisasterFar
extends RefCounted
## Statistical version of a disaster for a far lot (no real objects): dice for the cost and the people, a damage record in
## DisasterState.lots["town:<n>"] and one readable line (which the incident flow sends to the chronicle).

static func hit(ctx: Dictionary, kind: String, power: int) -> Dictionary:
	var subj = ctx["subject"]
	var d: Dictionary = DisasterDamage.cfg(kind)
	var house: String = subj.house_name()
	var key: String = str(subj.lot_key)
	var base: String = _text(kind, power).replace("{house}", house)
	if base == "":
		return {"text": "", "kind": "info"}
	var rng: RandomNumberGenerator = Incidents.rng
	var fc: Array = (d.get("far_cost", []) as Array)
	var cost: int = 0
	if not fc.is_empty():
		var band: Array = fc[clampi(power - 1, 0, fc.size() - 1)]
		cost = rng.randi_range(int(band[0]), int(band[1]))
	var rec: Dictionary = DisasterState.lot(key)
	rec["cost"] = int(rec["cost"]) + cost
	rec["repair_day"] = SysUtil.day() + rng.randi_range(3, 10)
	if kind == "flood":
		rec["mould"] = maxf(float(rec["mould"]), float(DisasterState.cfg("flood").get("mould_start", 0.5)) * 0.5)
	var tail: Array = []
	var worst: String = "warn" if power <= 1 else "bad"
	for m in subj.members():
		var out: bool = rng.randf() < 0.25
		var kill: float = DisasterDamage.at(d.get("out_kill" if out else "in_kill", []), power)
		var hurt: float = DisasterDamage.at(d.get("out_hurt" if out else "in_hurt", []), power)
		var nm: String = m.display_name()
		if kill > 0.0 and rng.randf() < kill:
			Aging.kill(m.id, str(d.get("cause", "tornado")))
			DisasterState.deaths.append({"id": int(m.id), "name": nm, "cause": str(d.get("cause", "")), "day": SysUtil.day()})
			tail.append("%s did not survive." % nm)
			worst = "bad"
		elif hurt > 0.0 and power >= 2 and rng.randf() < hurt:
			if Hospital.admit(m.id, 2, str(d.get("reason", "the storm"))):
				tail.append("%s was taken to hospital." % nm)
	var text: String = base if tail.is_empty() else "%s %s" % [base, " ".join(tail.slice(0, 2))]
	DisasterState.note_lot_event(key, kind, text)
	return {"text": text, "kind": worst}

static func _text(kind: String, power: int) -> String:
	var arr: Array = DisasterState.cfg("texts").get(kind, [])
	if arr.is_empty():
		return ""
	return str(arr[clampi(power - 1, 0, arr.size() - 1)])

## Far lots get repaired after a few days (daily tick).
static func on_day(day: int) -> void:
	for key in DisasterState.lots.keys():
		if not str(key).begins_with("town:"):
			continue
		var rec: Dictionary = DisasterState.lots[key]
		if int(rec["repair_day"]) >= 0 and day >= int(rec["repair_day"]):
			rec["cost"] = 0
			rec["mould"] = 0.0
			rec["repair_day"] = -1
