class_name JusticeRecords
extends RefCounted
## Criminal records (task 20): every conviction is kept with its date, charge, verdict, sentence, victim and time served
## (JusticeState.records[person] = [{day, charge, case, result, victim, sentence, served, expunged}]). Minor offences are EXPUNGED after a clean
## period (the charge's record.expunge_days; 0 = never); an expunged entry no longer counts as a record or closes jobs, but stays in the file
## history for the case board. The job bans of each charge are data (record.job_bans).

static func entries(pid: int) -> Array:
	return JusticeState.records.get(pid, [])

## Entries that still count (not expunged).
static func visible(pid: int) -> Array:
	return entries(pid).filter(func(r): return not bool(r.get("expunged", false)))

## Convictions (guilty, plea, petty) that still count.
static func convictions(pid: int) -> Array:
	return visible(pid).filter(func(r): return str(r.get("result", "")) in ["guilty", "plea", "petty"])

static func add(pid: int, charge: String, case_id: int, result: String, victim: int = -1, sentence: String = "") -> Dictionary:
	var e: Dictionary = {"day": SysUtil.day(), "charge": charge, "case": case_id, "result": result, "victim": victim, "sentence": sentence}
	var list: Array = entries(pid)
	list.append(e)
	JusticeState.records[pid] = list
	return e

## The last open entry of a case gets the time served when the person is released.
static func note_served(pid: int, days: int) -> void:
	var list: Array = entries(pid)
	for i in range(list.size() - 1, -1, -1):
		if not list[i].has("served"):
			list[i]["served"] = days
			return

static func label(r: Dictionary) -> String:
	var cd: Dictionary = JusticeProcess.charge_def(str(r.get("charge", "")))
	return str(cd.get("label", str(r.get("charge", "")))).to_lower()

## True when a conviction on file closes the career.
static func bans(pid: int, career: String) -> bool:
	for r in convictions(pid):
		if (JusticeProcess.charge_def(str(r.get("charge", ""))).get("record", {}) as Dictionary).get("job_bans", []).has(career):
			return true
	return false

## Daily: expunge entries after their clean period (no newer conviction since, not locked away).
static func on_day() -> void:
	var today: int = SysUtil.day()
	for pid in JusticeState.records.keys():
		if JusticeState.inmates.has(pid):
			continue
		var list: Array = JusticeState.records[pid]
		for e in list:
			if bool(e.get("expunged", false)):
				continue
			var span: int = int((JusticeProcess.charge_def(str(e.get("charge", ""))).get("record", {}) as Dictionary).get("expunge_days", 0))
			if span <= 0 or today - int(e.get("day", today)) < span:
				continue
			var clean: bool = true
			for o in list:
				if int(o.get("day", 0)) > int(e.get("day", 0)) and today - int(o.get("day", 0)) < span:
					clean = false
			if clean:
				e["expunged"] = true
				JusticeState.count("expunged")
