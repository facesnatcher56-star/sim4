class_name WorkNudge
extends RefCounted
## Task 61B: no autopilot surprise. About an hour before the pawn's shift, if they are not on their way yet, one quiet line says where and when
## and roughly when they will set off (the commute still starts on its own at that time). Once per shift, and only while the job is new
## (its first shifts) or when the pawn is out or busy with something the player asked for: a routine morning at home stays quiet.

static var said_day: int = -1

static func on_minute() -> void:
	var fid: int = Pawn.of()
	if not Careers.jobs.has(fid) or said_day == SysUtil.day():
		return
	var f = SysUtil.folk(fid)
	if f == null or SysUtil.is_away(f) or Commute.active(fid):
		return
	var routine: bool = int(Careers.jobs[fid].get("days_worked", 0)) >= 2 and not CareerShifts.player_busy(f) 		and NeighborhoodLots.lot_at(f.tile) == Neighborhood.HOME
	if routine:
		return
	var ns: Dictionary = CalendarBook.next_shift(fid)
	if ns.is_empty() or int(ns["day"]) != SysUtil.day():
		return
	var lead: float = Commute.lead_hours(f)
	var left: float = float(ns["hour"]) - SysUtil.hour_f()
	if left > maxf(1.0, lead + 0.25) or left < lead:
		return                          # about an hour before the shift, and always before they set off
	said_day = SysUtil.day()
	var go: float = float(ns["hour"]) - lead
	var where: String = (", " + str(ns["place"])) if str(ns["place"]) != "" else ""
	SysUtil.notify("Work at %s%s. You set off around %s." % [_hm(float(ns["hour"])), where, _hm(go)], "career")

static func _hm(h: float) -> String:
	var m: int = int(round(h * 60.0))
	return "%d:%02d" % [posmod(m / 60, 24), posmod(m, 60)]
