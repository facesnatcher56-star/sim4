class_name EduCourses
extends RefCounted
## Night classes and the library's courses (task 14): short courses of `sessions` lessons. Every lesson costs a few coins and teaches a skill;
## after the last lesson the person holds a CERTIFICATE (kept on their record: the job board counts it, and e.g. first aid helps in the clinic).
## Data: data/life/10_education.json "courses" + the lesson services of the places `night_school` and `library_courses`.

static func def(course: String) -> Dictionary:
	return LifeDefs.get_in("courses", course)

static func progress(fid: int, course: String) -> int:
	return int((EduState.peek(fid).get("courses", {}) as Dictionary).get(course, 0))

static func why_not(f, course: String) -> String:
	var d: Dictionary = def(course)
	if d.is_empty():
		return "No such course."
	if EduState.has_cert(int(f.id), course):
		return "%s already has the %s." % [f.name, str(d.get("cert", "certificate"))]
	return ""

static func lesson(f, course: String) -> Dictionary:
	var d: Dictionary = def(course)
	var fid: int = int(f.id)
	var r: Dictionary = EduState.rec(fid)
	var n: int = progress(fid, course) + 1
	r["courses"][course] = n
	if str(d.get("skill", "")) != "":
		f.add_skill_xp(str(d["skill"]), float(d.get("xp", 30)))
	f.add_to_stat("fun", 4.0)
	var need: int = int(d.get("sessions", 4))
	if n < need:
		return {"text": "%s finished lesson %d of %d in %s." % [f.name, n, need, str(d.get("label", course))], "lesson": n}
	(r["certs"] as Array).append(course)
	r["courses"].erase(course)
	var text := "%s finished the %s course and earned the %s." % [f.name, str(d.get("label", course)), str(d.get("cert", "certificate"))]
	LifeNote.say("certificate", text, [fid], 1, true, "good")
	SysUtil.game_event("course_done", {"folk_id": fid, "course": course})
	return {"text": text, "lesson": n, "certificate": course}
