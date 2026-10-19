class_name LifeHubJobs
extends RefCounted
## The "Jobs" tab of LifeHub: this week's openings for the selected person, best fit first, with what is still missing and an Apply button.

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var why: String = Careers.why_not_work(f)
	if why != "":
		dlg.line("%s is %s." % [f.name, why], 14, UITheme.MUTED)
		return
	if Careers.has_job(dlg.folk_id):
		dlg.line("Now: %s. Applying to another job means leaving this one." % Careers.title_of(dlg.folk_id), 13, UITheme.MUTED)
	var rows: Array = EduJobs.board_for(f)
	if rows.is_empty():
		dlg.line("No openings this week. Check again next week.", 14, UITheme.MUTED)
		return
	dlg.heading("This week's openings")
	for r in rows:
		var txt: String = "%s, %s: %d coins an hour%s. %d opening%s, fit %d%%." % [r["label"], str(r["title"]), r["pay"], " (in demand)" if r["hot"] else "", r["openings"], "" if int(r["openings"]) == 1 else "s", int(float(r["match"]) * 100.0)]
		if not bool(r["qualified"]):
			txt += " Needs " + ", ".join(r["missing"]) + "."
		dlg.row_with(txt, [dlg.button("Apply", "Take the job" if bool(r["qualified"]) else "Not qualified yet", func(): dlg.act("job_apply", {"career": r["career"]}), bool(r["qualified"]))], not bool(r["qualified"]))
