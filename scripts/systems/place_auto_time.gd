class_name PlaceAutoTime
extends RefCounted
## When can this person go out today (task 14b)? Awake hours (Circadian), minus the shift or school hours and the walk to them, minus the evening after the
## time the person likes to be back (Circadian.party_end_hour). Answers are per whole hour of the day: free[h] = the hour starting at h is usable.

static func _in(h: float, lo: float, hi: float) -> bool:
	lo = fposmod(lo, 24.0)
	hi = fposmod(hi, 24.0)
	if is_equal_approx(lo, hi):
		return false
	if lo < hi:
		return h >= lo and h < hi
	return h >= lo or h < hi

static func awake(f, h: float) -> bool:
	var s: Array = Circadian.schedule(f)          # [bed, wake]
	return _in(h, float(s[1]) + 0.5, float(s[0]) - 1.0)

## Hour ranges [from, to) of this day that work or school takes (with the walk there and back).
static func blocked(f, day: int) -> Array:
	var out: Array = []
	var fid: int = int(f.id)
	if Careers.jobs.has(fid):
		var j: Dictionary = Careers.jobs[fid]
		if CareerShifts.is_work_day(str(j.get("career", "")), day, str(j.get("shift", "day"))):
			var ws: float = float(f.work_start)
			var we: float = float(f.work_end)
			if ws >= 0.0:
				if we > ws:
					out.append([ws - 1.75, we + 0.5])
				else:
					out.append([ws - 1.75, 24.0])
					out.append([0.0, we + 0.75])
	elif Careers.school.has(fid) and CareerShifts.is_school_day(day):
		var sc: Dictionary = Careers.cfg().get("school", {})
		out.append([float(sc.get("start", 9.0)) - 1.5, float(sc.get("end", 15.0)) + 0.25])
	return out

## Is this hour (now) inside the time work or school takes today, with the walk there? Nothing is started then.
static func in_block(f, hour: float) -> bool:
	for b in blocked(f, SysUtil.day()):
		if hour >= float(b[0]) and hour < float(b[1]):
			return true
	return false

## True when work or school takes part of this day.
static func works_today(f, day: int) -> bool:
	return not blocked(f, day).is_empty()

## free[h] for h in 0..23.
static func free_hours(f, day: int) -> Array:
	var bl: Array = blocked(f, day)
	var free: Array = []
	for h in 24:
		var ok: bool = awake(f, float(h) + 0.5)
		if ok:
			for b in bl:
				if float(h) + 1.0 > float(b[0]) and float(h) < float(b[1]):
					ok = false
		free.append(ok)
	return free

## The latest hour (of the day, may pass 24) this person likes to be out until.
static func home_by(f) -> float:
	return Circadian.party_end_hour(f)
