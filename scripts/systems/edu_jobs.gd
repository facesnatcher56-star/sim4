class_name EduJobs
extends RefCounted
## The skills-based job market (task 14). Every week the town has a few OPENINGS in each career (more in a boom: MarketEconomy.hiring_mult) and a demand
## level. The board shows a person the openings with the best level they qualify for (skills, degree gates, a clean record), what is still missing
## for the rest, and a match score where certificates and degrees count. Applying takes an opening and hires them (Careers.hire), leaving a current job.
## Tier: TOWN, weekly refresh (one dice per career), board built on demand for the person looking. Saved in EduState.board.

static func jc() -> Dictionary:
	return EduState.cfg().get("jobs", {})

static func refresh(day: int) -> void:
	var week: int = day / maxi(int(jc().get("week_days", 7)), 1)
	if int(EduState.board.get("week", -1)) == week:
		return
	var open: Dictionary = {}
	var demand: Dictionary = {}
	var hm: float = MarketEconomy.hiring_mult() if MarketEconomy.enabled else 1.0
	for cid in Careers.career_ids():
		var n: int = int(floor(EduState.rng.randf() * (float(jc().get("openings_max", 3)) + 1.0) * clampf(hm, 0.3, 1.6)))
		open[str(cid)] = clampi(n, 0, int(jc().get("openings_max", 3)))
		demand[str(cid)] = lerpf(float(jc().get("demand_min", 0.9)), float(jc().get("demand_max", 1.15)), EduState.rng.randf())
	EduState.board = {"week": week, "openings": open, "demand": demand}

static func openings(cid: String) -> int:
	return int((EduState.board.get("openings", {}) as Dictionary).get(cid, 0))

static func hot(cid: String) -> bool:
	return float((EduState.board.get("demand", {}) as Dictionary).get(cid, 1.0)) >= 1.1

## How well the person fits a career level: the share of the requirements met, plus certificates and degrees that point at the career.
static func match_score(f, cid: String, level: int) -> float:
	var req: Dictionary = (Careers.level_def(cid, level).get("requires", {}) as Dictionary).get("skills", {})
	var met := 0.0
	for s in req:
		met += minf(float(f.skill_level(str(s))) / maxf(float(req[s]), 1.0), 1.0)
	var base: float = 1.0 if req.is_empty() else met / float(req.size())
	var cs: float = 0.0
	for course in EduState.peek(int(f.id)).get("certs", []):
		if str(EduCourses.def(str(course)).get("skill", "")) == str(Careers.career_def(cid).get("primary_skill", "-")):
			cs = float(jc().get("cert_match", 0.08))
	var deg: float = float(jc().get("degree_match", 0.12)) if EduGate.pay_mult(int(f.id), cid) > 1.0 else 0.0
	return clampf(base * 0.8 + cs + deg, 0.0, 1.0)

## Rows for the UI: [{career, label, level, title, pay, openings, hot, qualified, missing, match}] best match first.
static func board_for(f) -> Array:
	refresh(SysUtil.day())
	var out: Array = []
	for cid in Careers.career_ids():
		var n: int = openings(str(cid))
		if n <= 0:
			continue
		var level := 1
		var q: Dictionary = Careers.qualify(f, str(cid), 1)
		# a degree in the career's own field lets a new hire start one rung higher
		var cap: int = int(jc().get("max_start_level", 3)) - (0 if EduGate.pay_mult(int(f.id), str(cid)) > 1.0 else 1)
		for lv in range(mini(cap, Careers.max_level(str(cid))), 0, -1):
			var ql: Dictionary = Careers.qualify(f, str(cid), lv)
			if bool(ql["ok"]):
				level = lv
				q = ql
				break
		var ld: Dictionary = Careers.level_def(str(cid), level)
		out.append({"career": str(cid), "label": str(Careers.career_def(str(cid)).get("label", cid)), "level": level, "title": str(ld.get("title", "")),
			"pay": int(ld.get("pay", 0)), "openings": n, "hot": hot(str(cid)), "qualified": bool(q["ok"]), "missing": q["missing"], "match": match_score(f, str(cid), level)})
	out.sort_custom(func(a, b): return (bool(a["qualified"]) and not bool(b["qualified"])) or (a["qualified"] == b["qualified"] and float(a["match"]) > float(b["match"])))
	return out

## Can this person apply for that line of work now? {ok, reason, level} (the gates of apply, without hiring: JobApps sends the application).
static func check(fid: int, cid: String) -> Dictionary:
	var f = SysUtil.folk(fid)
	if f == null:
		return {"ok": false, "reason": "Nobody is looking for work."}
	refresh(SysUtil.day())
	var why: String = Careers.why_not_work(f, cid, 1)
	if why != "":
		return {"ok": false, "reason": "%s is %s." % [f.name, why]}
	if openings(cid) <= 0:
		return {"ok": false, "reason": "No openings in that line of work this week."}
	for r in board_for(f):
		if str(r["career"]) == cid:
			if bool(r["qualified"]):
				return {"ok": true, "reason": "", "level": int(r["level"])}
			return {"ok": false, "reason": "Not yet: needs %s." % ", ".join(r.get("missing", ["more experience"]))}
	return {"ok": false, "reason": "No openings in that line of work this week."}

## Instant hire (townie and test paths; the player's Apply goes through JobApps.send).
static func apply(fid: int, cid: String) -> Dictionary:
	var f = SysUtil.folk(fid)
	if f == null:
		return {"ok": false, "reason": "Nobody is looking for work."}
	refresh(SysUtil.day())
	var why: String = Careers.why_not_work(f, cid, 1)
	if why != "":
		return {"ok": false, "reason": "%s is %s." % [f.name, why]}
	if openings(cid) <= 0:
		return {"ok": false, "reason": "No openings in that line of work this week."}
	var row: Dictionary = {}
	for r in board_for(f):
		if str(r["career"]) == cid:
			row = r
	if row.is_empty() or not bool(row["qualified"]):
		return {"ok": false, "reason": "Not yet: needs %s." % ", ".join(row.get("missing", ["more experience"]))}
	if Careers.has_job(fid):
		Careers.quit_job(f, "took another job")
	if not Careers.hire(f, cid, int(row["level"])):
		return {"ok": false, "reason": "They could not take the job."}
	EduState.board["openings"][cid] = openings(cid) - 1
	return {"ok": true, "reason": "", "career": cid, "level": int(row["level"])}
