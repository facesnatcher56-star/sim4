class_name DisasterConds
extends RefCounted
## The `disaster` condition key of incidents (IncidentCond hands it over): a dictionary of checks, all must hold.
##   rain_days_at_least N   dry_days_at_least N   overdue_bills true   insured true|false   damaged true|false   outage true|false
## `subj` is the IncidentSubject the incident is being rolled for (a town roll uses a dummy lot, so only town-wide keys make sense there).

static func check(v: Variant, subj) -> bool:
	if not (v is Dictionary):
		return false
	for key in v:
		var want: Variant = v[key]
		var ok: bool = false
		match str(key):
			"rain_days_at_least":
				ok = DisasterState.rain_days >= int(want)
			"dry_days_at_least":
				ok = DisasterState.dry_days >= int(want)
			"overdue_bills":
				ok = _overdue(subj) == bool(want)
			"insured":
				ok = (DisasterInsurance.level(_hid(subj)) != "") == bool(want)
			"damaged":
				ok = DisasterState.lot_damaged(str(subj.lot_key)) == bool(want)
			"outage":
				ok = DisasterState.affects("outage", _hid(subj)) == bool(want)
		if not ok:
			return false
	return true

static func _hid(subj) -> int:
	if subj.household_id > 0:
		return int(subj.household_id)
	return int(subj.folk.household_id) if subj.folk != null else 0

static func _overdue(subj) -> bool:
	var hid: int = _hid(subj)
	if hid <= 0:
		return false
	var day: int = SysUtil.day()
	for bl in Economy.outstanding(hid):
		if bool(bl.get("late", false)) or day >= int(bl.get("due", 99999)):
			return true
	return false
