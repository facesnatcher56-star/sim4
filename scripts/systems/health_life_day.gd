class_name HealthLifeDay
extends RefCounted
## The daily pass of the health meters (task 14): fitness and diet drift, teeth wear (and hurt below a limit), work strain eases or burns out,
## long-term conditions roll (HealthCond). Residents are ACTIVE people, townies are STATISTICAL (the same numbers, no body, no toasts).
## Order is stable: residents in world order, then alive townies in id order. One pass costs O(people), a few arithmetic lines each.

static func on_day(day: int) -> void:
	for f in SysUtil.residents():
		_person(int(f.id), str(f.age_stage), f)
	for t in Story.alive_townies():
		var tid: int = int(t["id"])
		var f2 = SysUtil.folk(tid)
		if f2 != null and SysUtil.is_resident(f2):
			continue
		_person(tid, Story.stage_of(t), null)

static func _person(id: int, stage: String, f) -> void:
	var c: Dictionary = HealthLife.cfg()
	var r: Dictionary = HealthLife.rec(id)
	var fit: Dictionary = c.get("fitness", {})
	r["fitness"] = maxf(float(r["fitness"]) - float(fit.get("decay", 0.5)), float(fit.get("floor", 5)))
	var dt: Dictionary = c.get("diet", {})
	var drift: float = float(dt.get("drift", 1.2))
	r["diet"] = move_toward(float(r["diet"]), float(dt.get("target", 50)), drift)
	var dn: Dictionary = c.get("dental", {})
	var clean: bool = f != null and f.get_stat_value("hygiene") > float(dn.get("clean_hygiene", 20))
	r["dental"] = maxf(float(r["dental"]) - float(dn.get("decay_clean", 0.7) if clean else dn.get("decay", 1.1)), 0.0)
	if f != null:
		_resident(id, f, r, c, dn)
	HealthCond.day(id, stage, f != null)

static func _resident(id: int, f, r: Dictionary, c: Dictionary, dn: Dictionary) -> void:
	var tb: String = str(dn.get("toothache_buff", "toothache"))
	if float(r["dental"]) < float(dn.get("toothache_below", 35)):
		if not f.has_buff(tb):
			f.add_buff(tb)
			SysUtil.notify("%s has a toothache. The dentist can fix it." % f.name, "warn")
	elif f.has_buff(tb):
		f.remove_buff(tb)
	var st: Dictionary = c.get("strain", {})
	var worked_yesterday: bool = int(r["last_work_day"]) >= SysUtil.day() - 1
	if not worked_yesterday:
		r["strain"] = maxf(float(r["strain"]) - float(st.get("rest_day", 5.0) if Careers.has_job(id) else st.get("idle_day", 3.0)), 0.0)
	if f.has_buff("vacation_glow"):
		r["strain"] = maxf(float(r["strain"]) - float(st.get("holiday_glow", 10.0)), 0.0)
	if float(r["strain"]) >= float(st.get("burnout_at", 85)) and not f.has_buff("burnt_out"):
		f.add_buff("burnt_out")
		r["strain"] = float(st.get("after_burnout", 60))
		HealthLife.count("burnout")
		LifeNote.say("burnout", "%s is burnt out from too much work. Rest, a holiday or a counsellor will help." % f.name, [id], 2, true, "warn")

## A work shift ended (event `returned_from_work`): strain grows, more when the person is worn out.
static func on_work(id: int, skipped: bool) -> void:
	var f = SysUtil.folk(id)
	if f == null or skipped:
		return
	var st: Dictionary = HealthLife.cfg().get("strain", {})
	var r: Dictionary = HealthLife.rec(id)
	r["last_work_day"] = SysUtil.day()
	var add: float = float(st.get("work", 3.0))
	if f.get_stat_value("energy") < float(st.get("tired_below", -20)):
		add += float(st.get("tired_extra", 3.0))
	r["strain"] = minf(float(r["strain"]) + add, 100.0)
