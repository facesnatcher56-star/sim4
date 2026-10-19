class_name LifeHubStudy
extends RefCounted
## The "Study" tab of LifeHub: how the selected person is doing at school, college and in courses, with their degrees and certificates.

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var fid: int = dlg.folk_id
	var rec: Dictionary = EduState.peek(fid)
	dlg.heading("%s" % f.name)
	if Careers.school.has(fid):
		var g: float = CareerShifts.grade_of(fid)
		dlg.line("School: grade %s (%d%%)%s." % [CareerShifts.grade_letter(g), int(g), ". Homework is due" if EduSchool.homework_due(fid) else ""], 14)
		var reps: Array = rec.get("reports", [])
		if not reps.is_empty():
			var last: Dictionary = reps[reps.size() - 1]
			dlg.line("Last report card (day %d): %s. %s" % [int(last["day"]), str(last["letter"]), str(last["comment"])], 13, UITheme.MUTED)
			var parts: Array = []
			for s in (last.get("grades", {}) as Dictionary):
				parts.append("%s %s" % [s, CareerShifts.grade_letter(float(last["grades"][s]))])
			dlg.line(", ".join(parts), 13, UITheme.MUTED)
	if str(f.age_stage) == "toddler":
		var on: bool = bool(rec.get("preschool", false))
		dlg.row_with("Preschool: %s." % ("enrolled" if on else "not enrolled"), [dlg.button("Leave", "Stop the daily fee", func(): dlg.act("preschool_leave"), on)])
	var sm: Dictionary = EduCollege.summary(fid)
	if not sm.is_empty():
		dlg.row_with("College: %s, %d of %d credits, exams %s." % [sm["label"], sm["credits"], sm["needed"], sm["letter"]],
			[dlg.button("Drop out", "Give up the course. Credits are lost.", func(): dlg.act("college_drop"))])
	if str(rec.get("diploma", "")) != "":
		dlg.line("School diploma: %s." % rec["diploma"], 14)
	var degs: Array = EduState.degrees(fid)
	if not degs.is_empty():
		dlg.line("Degrees: " + ", ".join(degs.map(func(d): return EduCollege.major_label(str(d)))), 14)
	var certs: Array = rec.get("certs", [])
	if not certs.is_empty():
		dlg.line("Certificates: " + ", ".join(certs.map(func(c): return str(EduCourses.def(str(c)).get("cert", c)))), 14)
	var cp: Dictionary = rec.get("courses", {})
	for c in cp:
		dlg.line("%s: lesson %d of %d" % [str(EduCourses.def(str(c)).get("label", c)), int(cp[c]), int(EduCourses.def(str(c)).get("sessions", 4))], 13, UITheme.MUTED)
	if not Careers.school.has(fid) and sm.is_empty() and degs.is_empty() and certs.is_empty() and cp.is_empty():
		dlg.line("Nothing studied yet. The college and the night classes are under Places.", 13, UITheme.MUTED)
