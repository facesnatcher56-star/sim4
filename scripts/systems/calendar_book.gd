class_name CalendarBook
extends RefCounted
## Task 61B: what a person has on, the way they would know it: work shifts, bills and rent coming due, and appointments (job interviews, a
## probation check-in, a court date). Appointments are kept here (JobApps and SoloOpening add them); the rest is read from the real systems
## each time. The phone's Calendar app, the "Work 9:00" note by the clock and the nudge before a shift read it.
##   CalendarBook.add(fid, day, hour, lot, label, kind, ref)   CalendarBook.entries(fid, days) -> [{day, hour, label, kind, lot}]   next_shift(fid)

static var appts: Array = []          # [{fid, day, hour, lot, label, kind, ref}]

static func reset() -> void:
	appts = []

static func add(fid: int, day: int, hour: float, lot: String, label: String, kind: String, ref: int = -1) -> void:
	appts.append({"fid": fid, "day": day, "hour": hour, "lot": lot, "label": label, "kind": kind, "ref": ref})

static func remove_ref(kind: String, ref: int) -> void:
	appts = appts.filter(func(a): return not (str(a["kind"]) == kind and int(a["ref"]) == ref))

## The next work shift from now: {day, hour, end, lot, place} or {} (no job, or nothing in the next week).
static func next_shift(fid: int) -> Dictionary:
	var j: Dictionary = Careers.jobs.get(fid, {})
	var f = SysUtil.folk(fid)
	if j.is_empty() or f == null or f.work_start < 0.0:
		return {}
	var cid: String = str(j["career"])
	for i in 8:
		var d: int = SysUtil.day() + i
		if d < int(j.get("start_day", 0)) or not CareerShifts.is_work_day(cid, d, str(j.get("shift", "day"))):
			continue
		if i == 0 and (int(j.get("attempt_day", -1)) == d or SysUtil.hour_f() >= f.work_end):
			continue
		var lot: String = Workplace.lot_of_folk(f)
		return {"day": d, "hour": f.work_start, "end": f.work_end, "lot": lot, "place": Neighborhood.label_of(lot) if lot != "" else ""}
	return {}

## Everything from today for `days` days, soonest first.
static func entries(fid: int, days: int = 7) -> Array:
	var out: Array = []
	var today: int = SysUtil.day()
	var last: int = today + days - 1
	var f = SysUtil.folk(fid)
	var j: Dictionary = Careers.jobs.get(fid, {})
	if not j.is_empty() and f != null and f.work_start >= 0.0:
		var lot: String = Workplace.lot_of_folk(f)
		for d in range(today, last + 1):
			if d >= int(j.get("start_day", 0)) and CareerShifts.is_work_day(str(j["career"]), d, str(j.get("shift", "day"))):
				out.append({"day": d, "hour": f.work_start, "label": "Work, %d:00-%d:00%s" % [int(f.work_start), int(f.work_end) % 24,
					(" at " + Neighborhood.label_of(lot)) if lot != "" else ""], "kind": "work", "lot": lot})
	var hid: int = int(f.household_id) if f != null else -1
	var rent_billed: bool = false
	for b in Economy.bills:
		if int(b["hid"]) == hid and not bool(b["paid"]) and int(b["due"]) <= last:
			var rent: bool = str(b.get("reason", "")) == "rent"
			rent_billed = rent_billed or rent
			out.append({"day": maxi(int(b["due"]), today), "hour": 0.0, "label": "%s due: %d coins%s" % ["Rent" if rent else "Bills", int(b["amount"]),
				" (late)" if bool(b["late"]) else ""], "kind": "bill", "lot": ""})
	if not rent_billed and SoloHome.active and not SoloHome.homeless:
		var p: Dictionary = SoloHome.prop()
		var due: int = HousingRent.next_cycle + 3
		if not p.is_empty() and str(p.get("tenant_kind", "")) == "player" and due >= today and due <= last:
			out.append({"day": due, "hour": 0.0, "label": "Rent due: %d coins" % SoloRent.next_rent(p), "kind": "bill", "lot": ""})
	for a in appts:
		if int(a["fid"]) == fid and int(a["day"]) >= today and int(a["day"]) <= last:
			out.append({"day": int(a["day"]), "hour": float(a["hour"]), "label": str(a["label"]), "kind": str(a["kind"]), "lot": str(a["lot"])})
	for c in JusticeState.cases.values():
		if int(c.get("accused", -1)) == fid and int(c.get("closed_day", -1)) < 0 and int(c.get("trial_day", -1)) >= today and int(c.get("trial_day", -1)) <= last:
			out.append({"day": int(c["trial_day"]), "hour": 10.0, "label": "Court: the trial", "kind": "court", "lot": ""})
	out.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]) or (int(a["day"]) == int(b["day"]) and float(a["hour"]) < float(b["hour"])))
	return out

static func to_dict() -> Dictionary:
	return {"appts": appts.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	appts = (d.get("appts", []) as Array).duplicate(true)
