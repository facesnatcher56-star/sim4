class_name CrimeLifeTownie
extends RefCounted
## Task 21: townies run the same path STATISTICALLY (daily dice, no walking): a few drift in under pressure, work their rank's jobs with the same odds
## as the player, are caught (or quit after a spell inside), fence goods and now and then crew up for a heist. Rare overall: a small share of
## adults, about one job a month each. Called once a day per townie from CrimeFlow.person_day (bucketed) or CrimeFlow.on_day (tests).

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("townie")

static func member_share() -> float:
	var adults: int = 0
	for tid in CrimePerson.townies_only():
		if CrimePerson.is_adult(tid):
			adults += 1
	var n: int = 0
	for pid in CrimeLifeState.members:
		if not CrimePerson.is_player(int(pid)):
			n += 1
	return float(n) / float(maxi(adults, 1))

static func join_chance(pid: int) -> float:
	var k: Dictionary = cfg()
	var p: float = float(k.get("join_base", 0.0004))
	if not CrimePerson.has_job(pid):
		p *= float(k.get("jobless", 1.8))
	if CrimePerson.has_record(pid):
		p *= float(k.get("record", 2.0))
	if CrimePerson.has_trait(pid, "dishonest"):
		p *= float(k.get("dishonest", 2.5))
	if CrimePerson.has_trait(pid, "kleptomaniac"):
		p *= float(k.get("kleptomaniac", 1.4))
	if CrimePerson.has_trait(pid, "honest"):
		p *= float(k.get("honest", 0.08))
	if CrimePerson.has_trait(pid, "generous"):
		p *= float(k.get("generous", 0.4))
	p *= 1.0 + float(k.get("pressure_mult", 3.0)) * CrimePressure.risk(pid)
	return p * CrimeRate.crime_mult()

static func person_day(pid: int) -> void:
	if CrimePerson.is_player(pid) or not CrimePerson.alive(pid):
		return
	var k: Dictionary = cfg()
	if CrimePerson.in_custody(pid) or Hospital.is_in(pid) or not CrimePerson.is_adult(pid) or CrimePerson.stage(pid) == "elder":
		return
	if not CrimeLifePath.is_member(pid):
		if CrimeLifePath.going_straight(pid) or member_share() >= float(k.get("max_share", 0.12)):
			return
		if CrimeLifeState.chance(join_chance(pid)):
			CrimeLifePath.join(pid, "drift" if CrimePressure.risk(pid) >= float(CrimeLifeState.sect("path").get("drift_pressure", 0.55)) else "chose")
		return
	CrimeLifePath.on_day_member(pid)
	var m: Dictionary = CrimeLifePath.member(pid)
	if m.is_empty():
		return
	if CrimeLifeState.chance(float(k.get("quit_daily", 0.002))) or (int(m.get("caught", 0)) > 0 and SysUtil.day() - int(m.get("last_job_day", 0)) > 20 and CrimeLifeState.chance(float(k.get("quit_after_arrest", 0.5)) * 0.1)):
		CrimeLifePath.leave(pid, "quit")
		return
	var ri: int = maxi(CrimeLifePath.rank_index(pid), 0)
	var rates: Array = k.get("rank_daily", [0.02])
	var daily: float = float(rates[mini(ri, rates.size() - 1)]) * Incidents.surprise_mult() * CrimeRate.crime_mult()
	if CrimeLifeState.chance(float(k.get("heist_daily", 0.004))):
		heist(pid)
		return
	if CrimeLifeState.chance(daily):
		work(pid)

## One ordinary job for a townie.
static func work(pid: int) -> Dictionary:
	var weights: Dictionary = cfg().get("job_weights", {})
	var ids: Array = []
	var w: Array = []
	for jid in CrimeLifeJobs.ids():
		if not weights.has(jid) or not CrimeLifeJobs.unlocked(pid, str(jid)):
			continue
		ids.append(jid)
		w.append(float(weights[jid]) * (float(cfg().get("burglar_weight", 3.0)) / 3.0 if jid == "burglary" else 1.0))
	var i: int = CrimeLifeState.pick_index(w)
	if i < 0:
		return {}
	var jid2: String = str(ids[i])
	var target: Dictionary = CrimeLifeJobs.pick_target(pid, jid2)
	if target.is_empty():
		return {}
	return CrimeLifeJobs.run(pid, jid2, target, {"night": bool(CrimeLifeRoll.job(jid2).get("night", false)), "statistical": true})

## A statistical heist: any member may be talked into one big job now and then (a jeweller or a bank, ~one per 3 to 6 town-years); the boss pulls in up to two other members, the target is already well known.
static func heist(pid: int) -> Dictionary:
	var ids: Array = CrimeLifeHeist.target_ids()
	if ids.is_empty() or not CrimeLifeHeist.plan_of(pid).is_empty():
		return {}
	var t: String = str(ids[CrimeLifeState.rng.randi_range(0, ids.size() - 1)])
	var res: Dictionary = CrimeLifeHeist.plan(pid, t, true)
	if not bool(res["ok"]):
		return {}
	var h: Dictionary = CrimeLifeHeist.get_heist(int(res["heist"]))
	var pool: Array = []
	for q in CrimeLifeState.members.keys():
		if int(q) != pid and CrimePerson.alive(int(q)) and not CrimePerson.in_custody(int(q)) and not CrimePerson.is_player(int(q)) and not bool(CrimeLifeState.members[q].get("snitch", false)):
			pool.append(int(q))
	pool.sort()
	var roles: Array = (CrimeLifeHeist.cfg().get("roles", {}) as Dictionary).keys()
	roles.sort()
	for q2 in pool.slice(0, 2):
		(h["crew"] as Array).append({"pid": int(q2), "role": str(roles[CrimeLifeState.rng.randi_range(0, roles.size() - 1)]), "cut": float(CrimeLifeHeist.cfg().get("cut_default", 0.15)),
			"loyal": clampf(0.3 + CrimeLifeState.rng.randf() * 0.5, 0.05, 0.98)})
	CrimeLifeState.cased[CrimeLifeRoll.cased_key(pid, str(h["scene"]))] = {"amount": CrimeLifeState.rng.randf_range(0.4, 0.9), "day": SysUtil.day()}
	h["stage"] = "ready"
	return CrimeLifeHeistRun.run(h)

## Non-sliced fallback (tests call on_day directly): every townie once.
static func on_day_all() -> void:
	for tid in CrimePerson.townies_only():
		person_day(int(tid))
