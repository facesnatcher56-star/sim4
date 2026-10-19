class_name VacationWork
extends RefCounted
## Work and school while on holiday (task 22). Paid leave per game year = base + per_level x career level (config.leave). A work day lost
## on a trip uses a paid day (pays the day's wage) while the allowance lasts, otherwise it is a missed day (performance penalty, like
## skipping). School days lost cost grade points unless the day is a holiday. CareerShifts does not send a traveller to work
## (hook: `Vacation.on_trip`). Everything is settled when the trip ends (`settle`), the same maths gives the booking preview (`plan`).

static func cfg() -> Dictionary:
	return (Vacation.cfg().get("leave", {}) as Dictionary)

static func year_of(day: int) -> int:
	return (day - 1) / maxi(int(IncidentDefs.cfg("year_days", 28)), 1)

## Paid days still available to this person in the year of `day`.
static func allowance(fid: int, day: int) -> int:
	var k: Dictionary = cfg()
	var total: int = int(k.get("base_paid_days", 2)) + int(k.get("paid_days_per_level", 1)) * Careers.level_of(fid)
	var used: Dictionary = Vacation.leave_used.get(fid, {})
	var spent: int = int(used.get("used", 0)) if int(used.get("year", -1)) == year_of(day) else 0
	return maxi(total - spent, 0)

## Work days (a shift that lies inside [from_min, to_min]) the folk would miss.
static func work_days_lost(fid: int, from_min: int, to_min: int) -> int:
	var j: Dictionary = Careers.jobs.get(fid, {})
	var f = SysUtil.folk(fid)
	if j.is_empty() or f == null or f.work_start < 0.0:
		return 0
	var n: int = 0
	var d0: int = from_min / 1440 + 1
	var d1: int = to_min / 1440 + 1
	for d in range(d0, d1 + 1):
		if not CareerShifts.is_work_day(str(j["career"]), d, str(j.get("shift", "day"))):
			continue
		var s0: int = (d - 1) * 1440 + int(f.work_start * 60.0)
		var s1: int = (d - 1) * 1440 + int((f.work_end if f.work_end > f.work_start else f.work_end + 24.0) * 60.0)
		if s0 < to_min and s1 > from_min:
			n += 1
	return n

static func school_days_lost(fid: int, from_min: int, to_min: int) -> int:
	if not Careers.school.has(fid):
		return 0
	var n: int = 0
	for d in range(from_min / 1440 + 1, to_min / 1440 + 2):
		if not CareerShifts.is_school_day(d):
			continue
		if bool(cfg().get("school_holiday_free", true)) and not Holidays.today(d).is_empty():
			continue
		var sc: Dictionary = Careers.cfg().get("school", {})
		var s0: int = (d - 1) * 1440 + int(float(sc.get("start", 9)) * 60.0)
		var s1: int = (d - 1) * 1440 + int(float(sc.get("end", 15)) * 60.0)
		if s0 < to_min and s1 > from_min:
			n += 1
	return n

## Preview for the booking dialog: [{folk_id, name, work_days, paid, unpaid, school_days}] for the people who work or study.
static func plan(fids: Array, from_min: int, to_min: int) -> Array:
	var out: Array = []
	for fid in fids:
		var wd: int = work_days_lost(int(fid), from_min, to_min)
		var sd: int = school_days_lost(int(fid), from_min, to_min)
		if wd == 0 and sd == 0:
			continue
		var paid: int = mini(wd, allowance(int(fid), from_min / 1440 + 1))
		out.append({"folk_id": int(fid), "name": SysUtil.folk_name(int(fid)), "work_days": wd, "paid": paid, "unpaid": wd - paid, "school_days": sd})
	return out

## The trip is over: pay the paid days, penalise the missed ones. Stores the result in trip["leave"].
static func settle(trip: Dictionary, from_min: int, to_min: int) -> void:
	var k: Dictionary = cfg()
	var res: Array = []
	for fid in trip["folk"]:
		var f = SysUtil.folk(int(fid))
		if f == null:
			continue
		var wd: int = work_days_lost(int(fid), from_min, to_min)
		var sd: int = school_days_lost(int(fid), from_min, to_min)
		if wd == 0 and sd == 0:
			continue
		var day: int = from_min / 1440 + 1
		var paid: int = mini(wd, allowance(int(fid), day))
		var unpaid: int = wd - paid
		var rec: Dictionary = {"folk_id": int(fid), "work_days": wd, "paid": paid, "unpaid": unpaid, "school_days": sd, "pay": 0}
		if wd > 0 and Careers.jobs.has(int(fid)):
			var j: Dictionary = Careers.jobs[int(fid)]
			var ld: Dictionary = Careers.level_def(str(j["career"]), int(j["level"]), str(j.get("branch", "")))
			rec["pay"] = int(round(float(paid) * float(k.get("paid_day_hours", 8)) * float(ld.get("pay", 0))))
			if int(rec["pay"]) > 0:
				Economy.deposit(int(f.household_id), int(rec["pay"]), "paid leave")
			var used: Dictionary = Vacation.leave_used.get(int(fid), {})
			var yr: int = year_of(day)
			Vacation.leave_used[int(fid)] = {"year": yr, "used": (int(used.get("used", 0)) if int(used.get("year", -1)) == yr else 0) + paid}
			if unpaid > 0:
				j["days_skipped"] = int(j.get("days_skipped", 0)) + unpaid
				CareerProgress.add_performance(int(fid), -float(k.get("unpaid_penalty", 6.0)) * float(unpaid), true)
		if sd > 0 and Careers.school.has(int(fid)):
			var st: Dictionary = Careers.school[int(fid)]
			st["skipped"] = int(st.get("skipped", 0)) + sd
			st["grade"] = clampf(float(st["grade"]) - float(k.get("school_grade_penalty", 4.0)) * float(sd), 0.0, 100.0)
		res.append(rec)
	trip["leave"] = res
