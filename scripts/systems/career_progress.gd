class_name CareerProgress
extends RefCounted
## Performance, promotion/demotion, branches and daily tasks.

# ------------------------------------------------------------------ performance
static func performance_of(folk_id: int) -> float:
	return float((Careers.jobs.get(folk_id, {}) as Dictionary).get("performance", 0.0))

static func pay_multiplier(perf: float) -> float:
	var s: Dictionary = Careers.settings()
	return float(s.get("pay_perf_floor", 0.8)) + float(s.get("pay_perf_span", 0.4)) * clampf(perf / 100.0, 0.0, 1.0)

## Performance change for one finished shift, from mood, buffs, skill and traits.
static func shift_gain(f, cid: String, level: int) -> float:
	var s: Dictionary = Careers.settings()
	var gain: float = float(s.get("base_gain", 3))
	var mg: Dictionary = s.get("mood_gain", {})
	gain += float(mg.get(str(f.mood_name), 0.0)) * float(maxi(int(f.mood_intensity), 1)) / 2.0
	var bg: Dictionary = s.get("buff_gain", {})
	for b in f.buffs:
		gain += float(bg.get(str(b["id"]), 0.0))
	var skill: int = Careers.skill_for(f, cid)
	var cap: float = float(s.get("skill_gain_cap", 3))
	gain += clampf(float(skill - (level * 2 - 2)), -cap, cap)
	gain += Careers.trait_bonus(f, cid)
	return gain

static func add_performance(folk_id: int, delta: float, allow_demote: bool = false) -> void:
	if not Careers.jobs.has(folk_id):
		return
	var j: Dictionary = Careers.jobs[folk_id]
	var s: Dictionary = Careers.settings()
	j["performance"] = clampf(float(j["performance"]) + delta, 0.0, 100.0)
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	if float(j["performance"]) >= float(s.get("promote_at", 100)):
		_try_promote(f)
	elif allow_demote and float(j["performance"]) <= float(s.get("demote_at", 0)):
		_demote(f)

## Branch to enter when reaching the fork level: the player's preference if it is set, else the best-fitting
## qualifying track (trunk "" included). Returns {"branch": String, "q": qualify result}.
static func _pick_branch(f, cid: String, nxt: int, pref: String) -> Dictionary:
	var brs: Dictionary = Careers.career_def(cid).get("branches", {})
	var options: Array = [""] + brs.keys()
	if pref != "" and brs.has(pref):
		options = [pref]
	var best: Dictionary = {}
	var best_score: float = -1.0e9
	for b in options:
		if b == "" and nxt > Careers.max_level(cid):
			continue
		var q2: Dictionary = Careers.qualify(f, cid, nxt, str(b))
		var sc: float = branch_affinity(f, cid, str(b)) + (100.0 if bool(q2["ok"]) else 0.0)
		if sc > best_score:
			best_score = sc
			best = {"branch": str(b), "q": q2}
	return best

static func branch_affinity(f, cid: String, branch: String) -> float:
	var br: Dictionary = Careers.branch_def(cid, branch)
	if br.is_empty():
		return 0.0
	var aff: Dictionary = br.get("affinity", {})
	var s: float = 0.0
	for t in f.traits:
		s += float((aff.get("traits", {}) as Dictionary).get(t, 0.0))
	for sk in aff.get("skills", {}):
		s += float(f.skill_level(str(sk))) * float(aff["skills"][sk]) * 0.25
	return s

static func _fork_level(cid: String) -> int:
	var lvl: int = 0
	for b in Careers.branch_ids(cid):
		lvl = int(Careers.branch_def(cid, str(b)).get("from_level", 4))
	return lvl

## Player choice: which branch to take at the fork ("" = generalist trunk). Allowed until the fork is reached.
static func set_branch_preference(f, branch: String) -> bool:
	var j: Dictionary = Careers.jobs.get(int(f.id), {})
	if j.is_empty():
		return false
	var cid: String = str(j["career"])
	if branch != "" and Careers.branch_def(cid, branch).is_empty():
		return false
	if _fork_level(cid) == 0 or int(j["level"]) >= _fork_level(cid):
		return false
	j["branch_pref"] = branch
	return true

## Switch between "day" and a career shift variant (night shifts etc.).
static func set_shift(f, shift: String) -> bool:
	var j: Dictionary = Careers.jobs.get(int(f.id), {})
	if j.is_empty():
		return false
	var cid: String = str(j["career"])
	if shift != "day":
		var sv: Dictionary = Careers.shift_def(cid, shift)
		if sv.is_empty() or int(j["level"]) < int(sv.get("min_level", 1)):
			return false
	j["shift"] = shift
	Careers.apply_schedule(f)
	return true

static func _try_promote(f) -> void:
	var j: Dictionary = Careers.jobs[int(f.id)]
	var cid: String = str(j["career"])
	var nxt: int = int(j["level"]) + 1
	var cur_branch: String = str(j.get("branch", ""))
	var new_branch: String = cur_branch
	var q: Dictionary
	if cur_branch == "" and nxt == _fork_level(cid):
		var pick: Dictionary = _pick_branch(f, cid, nxt, str(j.get("branch_pref", "")))
		if pick.is_empty():
			return
		new_branch = str(pick["branch"])
		q = pick["q"]
	else:
		if nxt > Careers.max_level(cid, cur_branch):
			return
		q = Careers.qualify(f, cid, nxt, cur_branch)
	if not bool(q["ok"]):
		if int(j.get("cap_note_day", -1)) != SysUtil.day():
			j["cap_note_day"] = SysUtil.day()
			SysUtil.notify("%s is ready for a promotion but needs: %s" % [f.name, ", ".join(q["missing"])], "career")
		return
	var old_pay: int = int(Careers.level_def(cid, int(j["level"]), cur_branch).get("pay", 0))
	j["level"] = nxt
	j["branch"] = new_branch
	j["level_since"] = SysUtil.day()
	j["performance"] = float(Careers.settings().get("after_promotion_performance", 40))
	Careers.apply_schedule(f)
	var ld: Dictionary = Careers.level_def(cid, nxt, new_branch)
	var bonus: int = int(ld.get("pay", old_pay)) * 8
	Economy.deposit(int(f.household_id), bonus, "promotion bonus")
	SysUtil.notify("Promotion! %s is now a %s (%d coins/hour). Bonus: %d coins." % [f.name, str(ld.get("title", "")), int(ld.get("pay", 0)), bonus], "career")
	if str(ld.get("flavor", "")) != "":
		SysUtil.notify("\"%s\"" % str(ld["flavor"]), "career")
	if new_branch != cur_branch:
		SysUtil.notify("%s chose the %s track." % [f.name, str(Careers.branch_def(cid, new_branch).get("label", new_branch))], "career")
		SysUtil.game_event("branch_chosen", {"folk_id": f.id, "career": cid, "branch": new_branch})
	SysUtil.game_event("promoted", {"folk_id": f.id, "career": cid, "level": nxt, "title": ld.get("title", ""), "branch": new_branch})

static func _demote(f) -> void:
	var j: Dictionary = Careers.jobs[int(f.id)]
	var cid: String = str(j["career"])
	if int(j["level"]) <= 1:
		Careers.fire(f)
		return
	j["level"] = int(j["level"]) - 1
	if int(j["level"]) < _fork_level(cid):
		j["branch"] = ""
	j["level_since"] = SysUtil.day()
	j["performance"] = float(Careers.settings().get("after_demotion_performance", 35))
	Careers.apply_schedule(f)
	SysUtil.notify("Demoted! %s is now a %s." % [f.name, Careers.title_of(int(f.id))], "bad")
	SysUtil.game_event("demoted", {"folk_id": f.id, "career": cid, "level": j["level"]})

## Called after a folk finishes any interaction: work-ish interactions at home move the meter.
static func on_interaction(folk_id: int, iid: String, success: bool) -> void:
	if not success:
		return
	if Careers.jobs.has(folk_id):
		var hooks: Dictionary = Careers.career_def(str(Careers.jobs[folk_id]["career"])).get("hooks", {})
		if hooks.has(iid):
			add_performance(folk_id, float(hooks[iid]))
		if Careers.jobs.has(folk_id):
			_task_progress(folk_id, iid)
	if Careers.school.has(folk_id):
		var sh: Dictionary = Careers.cfg().get("school", {}).get("hooks", {})
		if sh.has(iid):
			Careers.school[folk_id]["grade"] = clampf(float(Careers.school[folk_id]["grade"]) + float(sh[iid]), 0.0, 100.0)

# ------------------------------------------------------------------ daily tasks
## Per-career daily tasks: finishing a matching interaction (at home) `count` times earns a one-off performance bonus.
static func _tasks_state(j: Dictionary) -> Dictionary:
	var ts: Dictionary = j.get("tasks", {})
	if ts.is_empty() or int(ts.get("day", -1)) != SysUtil.day():
		ts = {"day": SysUtil.day(), "progress": {}, "done": []}
		j["tasks"] = ts
	return ts

static func tasks_for(folk_id: int) -> Array:
	if not Careers.jobs.has(folk_id):
		return []
	var j: Dictionary = Careers.jobs[folk_id]
	var ts: Dictionary = _tasks_state(j)
	var out: Array = []
	for t in Careers.career_def(str(j["career"])).get("tasks", []):
		if int(j["level"]) < int(t.get("min_level", 1)):
			continue
		out.append({"id": t["id"], "label": t["label"], "count": int(t.get("count", 1)), "bonus": float(t.get("bonus", 5)),
			"progress": int((ts["progress"] as Dictionary).get(str(t["id"]), 0)), "done": (ts["done"] as Array).has(str(t["id"]))})
	return out

static func _task_progress(folk_id: int, iid: String) -> void:
	var j: Dictionary = Careers.jobs[folk_id]
	var ts: Dictionary = _tasks_state(j)
	for t in Careers.career_def(str(j["career"])).get("tasks", []):
		var tid: String = str(t["id"])
		if int(j["level"]) < int(t.get("min_level", 1)) or (ts["done"] as Array).has(tid):
			continue
		if not (t.get("interactions", []) as Array).has(iid):
			continue
		var n: int = int((ts["progress"] as Dictionary).get(tid, 0)) + 1
		ts["progress"][tid] = n
		if n >= int(t.get("count", 1)):
			(ts["done"] as Array).append(tid)
			var f = SysUtil.folk(folk_id)
			if f != null:
				SysUtil.notify("%s finished a work task: %s (+%d performance)" % [f.name, str(t["label"]), int(t.get("bonus", 5))], "career")
				SysUtil.game_event("daily_task_done", {"folk_id": folk_id, "career": str(j["career"]), "task": tid})
				f.add_buff("on_a_roll")
			add_performance(folk_id, float(t.get("bonus", 5)))
			return
