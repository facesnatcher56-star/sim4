class_name CrimeLifePath
extends RefCounted
## Task 21, part 1: the criminal path. A HIDDEN career with five ranks (petty thief, burglar, fence, crew boss, mastermind), an underworld
## reputation ("cred") that moves the opposite way to the town record, skills (the new `stealth` skill plus handiness, logic, charisma, fitness)
## and contacts. Players and townies are the same record (CrimeLifeState.members). Rank is recomputed from cred, skills and what has been done.
##   join / leave / drift_check   how a person ends up on the path (the player chooses, or drifts in under desperation, 09c)
##   add_cred                     street reputation up or down; ranks follow
##   skill                        a person's level in a skill (Folk, or the townie's own record)

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("path")

static func ranks() -> Array:
	return CrimeLifeState.cfg().get("ranks", [])

static func is_member(pid: int) -> bool:
	return CrimeLifeState.members.has(pid)

static func member(pid: int) -> Dictionary:
	return CrimeLifeState.members.get(pid, {})

static func rank_id(pid: int) -> String:
	return str(member(pid).get("rank", ""))

static func rank_index(pid: int) -> int:
	var rid: String = rank_id(pid)
	var list: Array = ranks()
	for i in list.size():
		if str(list[i]["id"]) == rid:
			return i
	return -1

static func rank_label(pid: int) -> String:
	var i: int = rank_index(pid)
	return str(ranks()[i]["label"]) if i >= 0 else ""

static func rank_index_of_id(rid: String) -> int:
	var list: Array = ranks()
	for i in list.size():
		if str(list[i]["id"]) == rid:
			return i
	return 0

static func cred(pid: int) -> float:
	return float(member(pid).get("cred", 0.0))

static func in_custody(pid: int) -> bool:
	return CrimePerson.in_custody(pid)

# ------------------------------------------------------------------ skills
static func skill(pid: int, sk: String) -> int:
	var m: Dictionary = member(pid)
	if CrimePerson.folk(pid) == null and bool(m.get("townie", false)):
		var own: Dictionary = m.get("skills", {})
		if own.has(sk):
			return int(own[sk])
	return CrimePerson.skill(pid, sk)

## Practice: a Folk gains real skill xp, a townie member now and then a whole level.
static func train(pid: int, sk: String, xp: float) -> void:
	var f = CrimePerson.folk(pid)
	if f != null:
		f.add_skill_xp(sk, xp)
		return
	var m: Dictionary = member(pid)
	if m.is_empty():
		return
	var own: Dictionary = m.get("skills", {})
	if CrimeLifeState.chance(xp / 40.0) and int(own.get(sk, 0)) < 8:
		own[sk] = int(own.get(sk, 0)) + 1
	m["skills"] = own

## Mean of weighted skills, 0..1 (level 10 = 1.0), plus a little from traits.
static func skill_score(pid: int, weights: Dictionary) -> float:
	var total: float = 0.0
	var sum_w: float = 0.0
	for sk in weights:
		total += float(weights[sk]) * minf(float(skill(pid, str(sk))), 10.0) / 10.0
		sum_w += float(weights[sk])
	var s: float = total / maxf(sum_w, 0.001)
	var r: Dictionary = CrimeLifeState.sect("roll")
	if CrimePerson.has_trait(pid, "dishonest"):
		s += float(r.get("dishonest", 0.04))
	if CrimePerson.has_trait(pid, "clumsy"):
		s -= 0.06
	if CrimePerson.has_trait(pid, "active"):
		s += 0.03
	return clampf(s, 0.0, 1.0)

# ------------------------------------------------------------------ joining
static func join(pid: int, why: String = "chose") -> bool:
	if is_member(pid) or not CrimePerson.alive(pid) or not CrimePerson.is_adult(pid):
		return false
	var townie: bool = CrimePerson.folk(pid) == null
	var m: Dictionary = {"cred": float(cfg().get("start_cred", 2)), "rank": "petty_thief", "jobs": 0, "heists": 0, "fenced": 0, "since": SysUtil.day(), "snitch": false,
		"heat": 0.0, "caught": 0, "straight_until": -1, "notoriety": 0.0, "hist": {}, "townie": townie, "why": why}
	if townie:
		var sr: Array = CrimeLifeState.sect("townie").get("skill_start", [0, 3])
		m["skills"] = {"stealth": CrimeLifeState.range_i(sr), "handiness": CrimeLifeState.range_i(sr), "charisma": CrimeLifeState.range_i(sr)}
	CrimeLifeState.members[pid] = m
	CrimeLifeState.count("joined")
	if CrimePerson.is_player(pid):
		var text: String = "%s has taken to the criminal life%s." % [CrimePerson.name_of(pid), " (it was that or go hungry)" if why == "drift" else ""]
		SysUtil.notify(text, "story")
	SysUtil.game_event("crime_life_joined", {"folk_id": pid, "why": why})
	return true

static func leave(pid: int, reason: String = "left") -> void:
	if not is_member(pid):
		return
	CrimeLifeState.notoriety_kept[pid] = float(member(pid).get("notoriety", 0.0))
	CrimeLifeState.straight[pid] = SysUtil.day() + int(cfg().get("going_straight_days", 28))
	CrimeLifeState.members.erase(pid)
	CrimeLifeState.count("left_" + reason)
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s is going straight." % CrimePerson.name_of(pid), "good")

static func going_straight(pid: int) -> bool:
	return int(CrimeLifeState.straight.get(pid, -1)) >= SysUtil.day()

# ------------------------------------------------------------------ cred and rank
static func add_cred(pid: int, amount: float, _why: String = "") -> void:
	var m: Dictionary = member(pid)
	if m.is_empty():
		return
	m["cred"] = clampf(float(m["cred"]) + amount, 0.0, 100.0)
	m["notoriety"] = float(m.get("notoriety", 0.0)) + maxf(amount, 0.0) * float(CrimeLifeState.sect("moral").get("notoriety_per_cred", 0.6))
	update_rank(pid)

static func update_rank(pid: int) -> void:
	var m: Dictionary = member(pid)
	if m.is_empty():
		return
	var best: int = 0
	var list: Array = ranks()
	for i in list.size():
		if _meets(pid, m, list[i]):
			best = i
	var old: String = str(m.get("rank", ""))
	var nw: String = str(list[best]["id"])
	m["rank"] = nw
	if nw != old and old != "":
		var up: bool = rank_index_of_id(nw) > rank_index_of_id(old)
		var text: String = "%s is now known as a %s in the underworld." % [CrimePerson.name_of(pid), str(list[best]["label"]).to_lower()] if up else \
			"%s has slipped back to %s." % [CrimePerson.name_of(pid), str(list[best]["label"]).to_lower()]
		if CrimePerson.is_player(pid):
			SysUtil.notify(text, "story" if up else "warn")
		SysUtil.game_event("crime_rank_changed", {"folk_id": pid, "rank": nw, "up": up})

static func _meets(pid: int, m: Dictionary, r: Dictionary) -> bool:
	if float(m.get("cred", 0.0)) < float(r.get("cred", 0.0)):
		return false
	for sk in (r.get("skills", {}) as Dictionary):
		if skill(pid, str(sk)) < int(r["skills"][sk]):
			return false
	if int(m.get("jobs", 0)) < int(r.get("jobs", 0)) or int(m.get("heists", 0)) < int(r.get("heists", 0)) or int(m.get("fenced", 0)) < int(r.get("fenced", 0)):
		return false
	return true

## Slow loss of street name when nothing is done (called daily for members).
static func on_day_member(pid: int) -> void:
	var m: Dictionary = member(pid)
	if m.is_empty():
		return
	m["heat"] = maxf(float(m.get("heat", 0.0)) - 0.35, 0.0)
	if float(m["cred"]) > 0.0 and SysUtil.day() - int(m.get("last_job_day", m.get("since", 0))) > 14:
		m["cred"] = maxf(float(m["cred"]) - float(cfg().get("cred_decay_day", 0.04)), 0.0)
		update_rank(pid)

## What the town can read from a record vs. what the underworld thinks: the two reputations as one line for the dialog.
static func summary(pid: int) -> Dictionary:
	var m: Dictionary = member(pid)
	return {"member": not m.is_empty(), "rank": rank_label(pid), "cred": int(cred(pid)), "town_rep": int(CrimePerson.reputation(pid)), "record": CrimePerson.record_count(pid),
		"heat": int(float(m.get("heat", 0.0))), "jobs": int(m.get("jobs", 0)), "snitch": bool(m.get("snitch", false))}

# ------------------------------------------------------------------ drifting in (task 09c desperation)
## Called by CrimePressure when a desperate person does something illegal: a PLAYER folk is asked, a townie may drift in.
static func drift_check(pid: int, risk: float) -> void:
	if is_member(pid) or going_straight(pid) or risk < float(cfg().get("drift_pressure", 0.55)):
		return
	if CrimePerson.has_trait(pid, "honest") and not CrimeLifeState.chance(0.1):
		return
	if CrimeLifeState.chance(float(cfg().get("drift_daily", 0.04)) * (1.0 + risk)):
		join(pid, "drift")
