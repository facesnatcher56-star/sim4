class_name CareerSpread
extends RefCounted
## Who is offered which career (task 19j). A first job and a new offer are a weighted pick over the careers the person can take, so the six children of a
## household do not all start at the café till, and a young adult who fits another line of work much better may change careers (with friction).
## Weights: base + skill x skill_w + trait bonus x trait_w + a bump when the career matches their aspiration + the job board (open / hot / closed),
## divided down for every housemate already in that career. All numbers: data/careers.json "first_job" and "switch". Randomness: the shared seeded stream.

static func cfg() -> Dictionary:
	return Careers.cfg().get("first_job", {})

static func teen_careers() -> Array:
	return cfg().get("teen_careers", ["barista", "gardener", "handyperson"])

## How much `f` fits the career `cid` right now (0 when they cannot take it at level 1).
static func weight(f, cid: String) -> float:
	var c: Dictionary = cfg()
	if Careers.why_not_work(f, cid, 1) != "":
		return 0.0
	if not bool(Careers.qualify(f, cid, 1)["ok"]):
		return 0.0
	var w: float = float(c.get("base", 1.0)) + float(Careers.skill_for(f, cid)) * float(c.get("skill_w", 1.5)) + Careers.trait_bonus(f, cid) * float(c.get("trait_w", 0.6))
	var asp: String = str((Goals.profiles.get(int(f.id), {}) as Dictionary).get("aspiration", ""))
	if ((c.get("aspiration_careers", {}) as Dictionary).get(asp, []) as Array).has(cid):
		w += float(c.get("aspiration_w", 2.0))
	var b: Dictionary = c.get("board", {})
	if EduJobs.openings(cid) > 0:
		w *= float(b.get("open_mult", 1.4)) * (float(b.get("hot_mult", 1.2)) if EduJobs.hot(cid) else 1.0)
	elif not (EduState.board as Dictionary).is_empty():
		w *= float(b.get("closed_mult", 0.7))
	w /= 1.0 + float(c.get("housemate_penalty", 0.7)) * float(housemates_in(f, cid))
	return maxf(w, float(c.get("floor", 0.2)))

static func housemates_in(f, cid: String) -> int:
	var n := 0
	for g in SysUtil.residents():
		if int(g.id) != int(f.id) and int(g.household_id) == int(f.household_id) and Careers.career_of(int(g.id)) == cid:
			n += 1
	return n

## The weighted pick among `ids` ("" when nothing fits). Teens only choose among the part-time careers.
static func pick(f, ids: Array) -> String:
	var pool: Array = []
	var ws: Array = []
	var teen: bool = str(f.age_stage) == "teen"
	for cid in ids:
		if teen and not teen_careers().has(cid):
			continue
		var w: float = weight(f, str(cid)) * clampf(1.0 + 0.5 * Creation.hiring_kind(int(f.id), Creation.job_kind(str(cid))), 0.2, 3.0)          # task 55: easier shop hiring
		if w > 0.0:
			pool.append(cid)
			ws.append(w)
	var p = SysUtil.pick_weighted(pool, ws)
	return str(p) if p != null else ""

# ------------------------------------------------------------------ changing careers
static func switch_cfg() -> Dictionary:
	return Careers.cfg().get("switch", {})

## Daily, from Careers.on_day: a young adult in an early level may leave for a career that fits clearly better. Returns the new career id or "".
static func maybe_switch(f) -> String:
	var fid: int = int(f.id)
	var c: Dictionary = switch_cfg()
	if c.is_empty() or not Careers.jobs.has(fid) or str(f.age_stage) != "adult":
		return ""
	var j: Dictionary = Careers.jobs[fid]
	var adult_from: float = float(Aging.stage_def("adult").get("from_day", 76))
	if Family.age_days_of(fid) > adult_from + float(c.get("young_days", 60)) or int(j["level"]) > int(c.get("max_level", 2)):
		return ""
	var today: int = SysUtil.day()
	if today - int(j.get("hired_day", today)) < int(c.get("min_days_in_job", 12)) or not JobSeeking.cooled_down(f):
		return ""
	var p: float = float(c.get("chance_per_day", 0.012))
	if float(j["performance"]) < float(c.get("unhappy_below", 40)):
		p *= float(c.get("unhappy_mult", 3.0))
	if not SysUtil.chance(p):
		return ""
	var cur: String = str(j["career"])
	var others: Array = Careers.career_ids().filter(func(x): return str(x) != cur)
	var target: String = pick(f, others)
	if target == "" or weight(f, target) < weight_current(f, cur) * float(c.get("better_by", 1.6)):
		return ""
	var old_label: String = str(Careers.career_def(cur).get("label", cur))
	Careers.quit_job(f, "changed career")
	if not Careers.hire(f, target, 1):
		return ""
	(Careers.jobs[fid] as Dictionary)["performance"] = maxf(float(Careers.settings().get("start_performance", 50)) - float(c.get("start_performance_penalty", 12)), 5.0)
	SysUtil.notify("%s left the %s job to try something new, starting again at the bottom." % [f.name, old_label], "career")
	return target

## Fit for the career they already have (their job is open to them, so only skill / trait / aspiration count, not openings or housemates).
static func weight_current(f, cid: String) -> float:
	var c: Dictionary = cfg()
	var w: float = float(c.get("base", 1.0)) + float(Careers.skill_for(f, cid)) * float(c.get("skill_w", 1.5)) + Careers.trait_bonus(f, cid) * float(c.get("trait_w", 0.6))
	var asp: String = str((Goals.profiles.get(int(f.id), {}) as Dictionary).get("aspiration", ""))
	if ((c.get("aspiration_careers", {}) as Dictionary).get(asp, []) as Array).has(cid):
		w += float(c.get("aspiration_w", 2.0))
	return maxf(w, float(c.get("floor", 0.2)))
