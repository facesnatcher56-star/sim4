class_name EarlyLuck
extends RefCounted
## Task 63: a broke solo start gets at most ONE real problem in its first week (data/solo.json "early_luck": {days, min_severity}). Once a problem
## (an incident with a bad outcome, severity >= min_severity) has hit the player's household or home in that time, the odds of every other
## bad incident on them are 0 until the week is over. Read from the incident history, so it needs no save of its own.
##   EarlyLuck.rate_mult(def, subj) -> 0.0 or 1.0 (IncidentRisk.effective_rate)

static var _stamp: int = -1
static var _hit: bool = false

static func cfg() -> Dictionary:
	return SoloCfg.cfg().get("early_luck", {})

static func rate_mult(def: Dictionary, subj) -> float:
	if not SoloHome.active or SysUtil.day() > int(cfg().get("days", 7)) or not _is_problem(def) or not _mine(subj):
		return 1.0
	return 0.0 if _had_one() else 1.0

static func _is_problem(def: Dictionary) -> bool:
	return (def.get("outcomes", []) as Array).any(func(o): return o is Dictionary and str(o.get("kind", "")) == "bad")

static func _hid() -> int:
	return Economy.primary_household()

static func _mine(subj) -> bool:
	if subj == null:
		return false
	if str(subj.lot_key) == "home:%d" % _hid():
		return true
	return subj.folk != null and int(subj.folk.household_id) == _hid()

## Once an hour: has a problem already landed on the player this week?
static func _had_one() -> bool:
	var stamp: int = floori(SysUtil.now() / 60.0) * 1000 + Incidents._history.size()          # a new problem or a new game refreshes it
	if stamp == _stamp:
		return _hit
	_stamp = stamp
	_hit = false
	var days: int = int(cfg().get("days", 7))
	var sev: int = int(cfg().get("min_severity", 2))
	for e in Incidents.history(200):
		if str(e.get("kind", "")) != "incident" or int(e.get("day", 99)) > days or int(e.get("severity", 0)) < sev or str(e.get("mode", "")) != "full":
			continue
		if str(e.get("lot", "")) == "home:%d" % _hid():
			_hit = true
			break
		var f = SysUtil.folk(int(e.get("folk_id", -1)))
		if f != null and int(f.household_id) == _hid():
			_hit = true
			break
	return _hit
