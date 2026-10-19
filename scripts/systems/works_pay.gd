class_name WorksPay
extends RefCounted
## What the industrial careers change about a working day (task 31), called from small hooks:
##   off_day(f, j)                  CareerShifts._start_shift: a strike or a rained-off site means no work today, with no penalty
##   adjust_pay(f, j, pay, ...)     CareerShifts.on_returned: wage rises won by strikes, overtime (opt-in per job, `j.overtime`), union dues
##   townie_shift(t)                CommuteTownies.window: some townies work the career's night shift
## Numbers: data/careers_works.json works.overtime / works.union.

## True when today is not a working day for this job. Strikes: no pay (strike pay for union members); weather: construction only.
static func off_day(f, j: Dictionary) -> bool:
	var cid: String = str(j["career"])
	if not Works.is_works(cid):
		return false
	var fid: int = int(f.id)
	if WorksEvents.on_strike(cid):
		var pay: int = 0
		if WorksUnion.is_member(fid):
			var lv: Dictionary = Careers.level_def(cid, int(j["level"]), str(j.get("branch", "")))
			pay = WorksUnion.strike_pay(int(lv.get("pay", 0)))
			Economy.deposit(int(f.household_id), pay, "strike pay")
		SysUtil.notify(Works.fill("strike_picket" if pay > 0 else "strike_picket_nopay", {"name": f.name, "pay": pay}), "warn")
		SysUtil.game_event("works_off_day", {"folk_id": fid, "why": "strike"})
		return true
	var off: Array = Careers.career_def(cid).get("weather_off", [])
	if not off.is_empty() and off.has(Weather.current()):
		SysUtil.notify(Works.fill("rained_off", {"name": f.name}), "info")
		SysUtil.game_event("works_off_day", {"folk_id": fid, "why": "weather"})
		return true
	return false

## Pay of a finished shift after the industrial rules. `hours` = hours worked.
static func adjust_pay(f, j: Dictionary, pay: int, hours: float, completed: bool) -> int:
	var cid: String = str(j["career"])
	if not Works.is_works(cid):
		return pay
	var fid: int = int(f.id)
	pay = int(round(float(pay) * WorksEvents.wage_mult(cid)))
	var ot: Dictionary = Works.cfg().get("overtime", {})
	if completed and bool(j.get("overtime", false)) and int(j["level"]) >= int(ot.get("min_level", 1)) and f.get_stat_value("energy") > -40.0 \
			and hours > 0.0 and WorksEvents.rng.randf() < float(ot.get("busy_chance", 0.25)):
		var extra: int = int(round(float(pay) / hours * float(ot.get("hours", 2)) * float(ot.get("pay_mult", 1.5))))
		pay += extra
		f.add_to_stat("energy", float(ot.get("energy", -22)))
		f.add_buff(str(ot.get("buff", "overtime_worn")))
		CareerProgress.add_performance(fid, float(ot.get("perf", 3)))
		SysUtil.notify(Works.fill("overtime_done", {"name": f.name, "pay": extra}), "career")
		SysUtil.game_event("works_overtime", {"folk_id": fid, "extra": extra})
	if WorksUnion.is_member(fid):
		pay -= WorksUnion.dues(pay)
	return pay

## {start, end} of the night shift a townie works, or {} for the ordinary day hours (a fixed share of the townies of each career).
static func townie_shift(t: Dictionary) -> Dictionary:
	var cid: String = str(t.get("career", ""))
	if not Works.is_works(cid) or (int(t.get("id", 0)) * 13) % 100 >= int(float(Works.cfg().get("townie_night_share", 0.25)) * 100.0):
		return {}
	var shifts: Dictionary = Careers.career_def(cid).get("shifts", {})
	for sid in shifts:
		var sv: Dictionary = shifts[sid]
		if float(sv["end"]) <= float(sv["start"]) and int(t.get("level", 1)) >= int(sv.get("min_level", 1)):
			return {"start": float(sv["start"]), "end": float(sv["end"])}
	return {}
