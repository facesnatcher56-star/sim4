class_name EduServices
extends RefCounted
## The handlers (PlaceHandlers) of the education places: check() may refuse before anything is charged, finish() runs when the visit ends.
##   lecture (args.major)     EduCollege.lecture        course (args.course)   EduCourses.lesson
##   enrol_preschool          EduSchool.enrol_preschool tutor                  the Homework Club: extra grade and logic xp for a student

static func check(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> String:
	var a: Dictionary = svc.get("args", {})
	match handler:
		"lecture":
			return EduCollege.why_not(f, str(a.get("major", "")))
		"course":
			return EduCourses.why_not(f, str(a.get("course", "")))
		"enrol_preschool":
			return "%s is already enrolled." % f.name if bool(EduState.peek(int(f.id)).get("preschool", false)) else ""
		"tutor":
			return "" if Careers.school.has(int(f.id)) else "%s does not go to school." % f.name
	return ""

static func finish(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> Dictionary:
	var a: Dictionary = svc.get("args", {})
	match handler:
		"lecture":
			return EduCollege.lecture(f, str(a.get("major", "")))
		"course":
			return EduCourses.lesson(f, str(a.get("course", "")))
		"enrol_preschool":
			EduSchool.enrol_preschool(int(f.id), true)
			return {}
		"tutor":
			var tc: Dictionary = EduState.cfg().get("tutor", {})
			var fid: int = int(f.id)
			if Careers.school.has(fid):
				Careers.school[fid]["grade"] = clampf(float(Careers.school[fid]["grade"]) + float(tc.get("grade", 2.0)), 0.0, 100.0)
			f.add_skill_xp("logic", float(tc.get("xp", 8)))
			EduSchool.on_homework_done(fid)
			return {}
	return {}
