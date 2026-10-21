class_name LifeHubJobs
extends RefCounted
## The "Jobs" tab of LifeHub in the card style of docs/UI_STYLE.md: this week's openings, best pay first among the jobs you can take, one card each with
## the pay, the hours, the days, the openings and the fit as chips, what is still missing as cross chips and one Apply button.

const DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

static func _days_text(days: Array) -> String:
	var d: Array = days.map(func(x): return int(x))
	d.sort()
	if d.size() >= 3 and int(d[d.size() - 1]) - int(d[0]) == d.size() - 1:
		return "%s-%s" % [DAYS[int(d[0])], DAYS[int(d[d.size() - 1])]]
	return ", ".join(d.map(func(x): return DAYS[int(x)]))

## `only` = just these lines of work (the paper's ads); [] = the whole board.
static func build(dlg: LifeHub, only: Array = []) -> void:
	var f = dlg.folk_obj()
	var why: String = Careers.why_not_work(f)
	if why != "":
		dlg.line("%s is %s." % [f.name, why], 14, UITheme.MUTED)
		return
	var w: float = dlg.dialog_width - 50.0
	if Careers.has_job(dlg.folk_id):
		dlg.line("Now: %s. Applying to another job means leaving this one." % Careers.title_of(dlg.folk_id), 13, UITheme.MUTED)
	CareerDialog.offer_card(dlg, dlg.folk_id)          # a pending offer (the toast) is answered right here: Accept / Decline
	var rows: Array = EduJobs.board_for(f)
	if not only.is_empty():
		rows = rows.filter(func(r): return only.has(str(r["career"])))
	if rows.is_empty():
		dlg.line("No openings this week. Check again on day %d." % (((SysUtil.day() - 1) / 7 + 1) * 7 + 1), 14, UITheme.MUTED)
		return
	rows.sort_custom(func(a, b):
		if bool(a["qualified"]) != bool(b["qualified"]):
			return bool(a["qualified"])
		return int(a["pay"]) > int(b["pay"]))
	dlg.heading("This week's openings (best pay first)")
	for r in rows:
		var cdef: Dictionary = Careers.career_def(str(r["career"]))
		var ld: Dictionary = Careers.level_def(str(r["career"]), int(r["level"]))
		var hours: int = int(ld.get("end", 0)) - int(ld.get("start", 0))
		var days: Array = cdef.get("days", [])
		var week: int = int(r["pay"]) * hours * days.size()
		var inner: VBoxContainer = UICard.card(dlg.body, w, "%s  (%s)" % [str(r["title"]), str(r["label"])], "IN DEMAND" if bool(r["hot"]) else "", str(cdef.get("description", "")))
		UICard.chips(inner, [["Pay", "%d/h" % int(r["pay"])], ["Hours", "%02d-%02d" % [int(ld.get("start", 0)), int(ld.get("end", 0))]], ["Days", _days_text(days)], ["Week", "%d" % week],
			["Openings", "%d" % int(r["openings"])], ["Fit", "%d%%" % int(float(r["match"]) * 100.0)]])
		var missing: Array = r["missing"]
		if not missing.is_empty():
			UICard.reqs(inner, missing.map(func(m): return [str(m), false]))
		var rr: Dictionary = r
		UICard.action(inner, "Apply", func(): dlg.act("job_apply", {"career": rr["career"]}), bool(r["qualified"]), "Needs " + ", ".join(missing) if not bool(r["qualified"]) else "")
