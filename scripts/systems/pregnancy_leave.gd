class_name PregnancyLeave
extends RefCounted
## Maternity and paternity leave (task 18 part 3). A mother stops going to work in the last stretch of the pregnancy (`maternity_before_days`
## before the due day), while she is on bed rest, and for `maternity_after_days` after the birth; the other parent gets `paternity_after_days`.
## The job is KEPT (no skip penalty, no firing: CareerShifts asks on_leave before it records anything). Data: data/pregnancy.json "leave".
## Tier behaviour: a lookup when a shift starts (ACTIVE residents with a job); nothing runs on its own.

static func cfg() -> Dictionary:
	return Pregnancy.cfg("leave")

static func on_leave(folk_id: int) -> bool:
	var c: Dictionary = cfg()
	if Pregnancy.is_pregnant(folk_id):
		var r: Dictionary = Pregnancy.rec(folk_id)
		var f = SysUtil.folk(folk_id)
		if f != null and f.has_buff("bed_rest"):
			return true
		if bool(r.get("known", false)) and float(int(r["due_day"]) - SysUtil.day()) <= float(c.get("maternity_before_days", 0.34)) * 3.0:
			return true
	return Pregnancy.extra.has(folk_id) and SysUtil.day() < int((Pregnancy.extra[folk_id] as Dictionary).get("leave_until", 0))

static func on_birth(mother_id: int, father_id: int) -> void:
	var c: Dictionary = cfg()
	Fertility.state(mother_id)["leave_until"] = SysUtil.day() + int(c.get("maternity_after_days", 3))
	if father_id >= 0 and SysUtil.folk(father_id) != null:
		Fertility.state(father_id)["leave_until"] = SysUtil.day() + int(c.get("paternity_after_days", 1))
