class_name VacationLog
extends RefCounted
## The holiday / cruise story log. Every happening goes through the chronicle hook with `place` ("cruise" for anything aboard or ashore
## on a cruise, "vacation" for the other trips), so a reporter can tell the story afterwards (task 22b):
##   Events.game_event("chronicle", {kind, text, day, subjects, lot, severity, public, place, trip, tag})
## We also keep a capped list of our own (not the chronicle's 40-entry ring): VacationLog.entries(trip_id).
## State is saved with Vacation (cap config.log_cap, oldest dropped).

static var _log: Array = []       # {min, day, trip, place, tag, text, sev}

static func reset() -> void:
	_log.clear()

static func cap() -> int:
	return int(Vacation.cfg().get("log_cap", 300))

## tag: dinner | show | port | romance | incident | missed | crime | death | arrival | return | event ...
static func note(trip: Dictionary, tag: String, text: String, subjects: Array = [], severity: int = 1, is_public: bool = true) -> Dictionary:
	if text == "":
		return {}
	var place: String = "cruise" if str(trip.get("dest", "")) == "cruise" else "vacation"
	var ids: Array = []
	for s in subjects:
		ids.append(int(s))
	var p: Dictionary = {"kind": "cruise_" + tag if place == "cruise" else "vacation_" + tag, "text": text, "day": SysUtil.day(), "subjects": ids, "lot": "",
		"severity": severity, "public": is_public, "place": place, "trip": int(trip.get("id", -1)), "tag": tag}
	ChronicleHook.recent.append(p)
	while ChronicleHook.recent.size() > 40:
		ChronicleHook.recent.pop_front()
	SysUtil.game_event("chronicle", p)
	_log.append({"min": SysUtil.now(), "day": SysUtil.day(), "trip": int(trip.get("id", -1)), "place": place, "tag": tag, "text": text, "sev": severity})
	while _log.size() > cap():
		_log.pop_front()
	var tl: Array = trip.get("log", [])
	tl.append({"day": SysUtil.day(), "tag": tag, "text": text})
	while tl.size() > 80:
		tl.pop_front()
	trip["log"] = tl
	return p

static func entries(trip_id: int = -1) -> Array:
	if trip_id < 0:
		return _log.duplicate(true)
	return _log.filter(func(e): return int(e["trip"]) == trip_id)

static func count(tag: String, trip_id: int = -1) -> int:
	var n: int = 0
	for e in _log:
		if str(e["tag"]) == tag and (trip_id < 0 or int(e["trip"]) == trip_id):
			n += 1
	return n

static func to_dict() -> Dictionary:
	return {"log": _log.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	_log = (d.get("log", []) as Array).duplicate(true)
	for e in _log:
		SysUtil.ints_in(e, ["min", "day", "trip", "sev"])
