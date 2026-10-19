class_name CrimeLifeRoll
extends RefCounted
## Task 21: the one place where a criminal act is rolled. `odds()` turns skill, gear, how well the place is KNOWN (casing), the place's security,
## the hour, police patrols and the person's heat into three chances; `roll()` draws the outcome. The same numbers serve a player folk, a far
## townie and the heist phases, so a test can compare any two situations by comparing odds.
##   pull_off  the act itself works (a lock gives, a pocket is light)
##   detect    somebody or something notices (witness, guard, alarm, camera)
##   catch     given that it was noticed, the person is caught on the spot
##   trace     physical evidence left behind (0..1), later revealed by the investigation

static func jobs() -> Dictionary:
	return CrimeLifeState.sect("jobs")

static func job(jid: String) -> Dictionary:
	return jobs().get(jid, {})

static func gear_cfg() -> Dictionary:
	return CrimeLifeState.sect("roll").get("gear", {})

static func has_gear(pid: int, gid: String) -> bool:
	return bool((CrimeLifeState.gear.get(pid, {}) as Dictionary).get(gid, false))

static func gear_effect(pid: int, key: String) -> float:
	var out: float = 0.0
	for gid in (CrimeLifeState.gear.get(pid, {}) as Dictionary):
		if bool(CrimeLifeState.gear[pid][gid]):
			out += float((gear_cfg().get(gid, {}) as Dictionary).get(key, 0.0))
	return out

# ------------------------------------------------------------------ casing
static func cased_key(pid: int, target: String) -> String:
	return "%d|%s" % [pid, target]

## How well `pid` knows `target` (0..1), fading if the knowledge is old.
static func cased(pid: int, target: String) -> float:
	var rec: Dictionary = CrimeLifeState.cased.get(cased_key(pid, target), {})
	if rec.is_empty():
		return 0.0
	var k: Dictionary = CrimeLifeState.sect("casing")
	var age: int = SysUtil.day() - int(rec.get("day", 0))
	var stale: int = int(k.get("stale_days", 14))
	var amt: float = float(rec.get("amount", 0.0))
	if age > stale:
		amt -= float(age - stale) * float(k.get("decay_day", 0.02))
	return clampf(amt, 0.0, 1.0)

# ------------------------------------------------------------------ odds
## opts: night (bool, default by clock), cased (override 0..1), crowd (0..1 extra eyes), hour_f.
static func odds(pid: int, jid: String, scene: String, opts: Dictionary = {}) -> Dictionary:
	var j: Dictionary = job(jid)
	var r: Dictionary = CrimeLifeState.sect("roll")
	var skill: float = CrimeLifePath.skill_score(pid, j.get("skills", {"stealth": 1.0}))
	var stealth: float = clampf(float(CrimeLifePath.skill(pid, "stealth")) / 10.0, 0.0, 1.0)
	var h: float = float(opts.get("hour_f", SysUtil.hour_f()))
	var night: bool = bool(opts.get("night", h >= 21.0 or h < 5.5))
	var prof: Dictionary = CrimeSecurity.profile_for(scene) if scene.begins_with("home:") or scene.begins_with("town:") or scene.begins_with("biz:") else CrimeSecurity.empty()
	var fx: Dictionary = CrimeSecurity.effects(prof, night, gear_effect(pid, "alarm"))
	var known: float = float(opts["cased"]) if opts.has("cased") else cased(pid, scene)
	var fail: float = (float(j.get("difficulty", 0.4)) + float(fx["difficulty"]) + float(opts.get("diff_add", 0.0))) * (1.0 - float(r.get("skill_cut", 0.7)) * skill) * (1.0 - float(r.get("cased_fail", 0.4)) * known) \
		* (1.0 - gear_effect(pid, "fail"))
	var pull: float = clampf(1.0 - fail, float(r.get("min_pull", 0.08)), float(r.get("max_pull", 0.97)))
	var guards: int = int(prof.get("guards", 0))
	var alert: float = CrimeSecurityGuards.alert_for(scene) if guards > 0 else 1.0
	if guards > 0:
		alert *= 1.0 - float(CrimeLifeState.sect("heists").get("guard_gap_bonus", 0.5)) * known       # a cased guard's round has gaps
	var watch: float = float(fx["detect"]) - float(fx["guard_inc"]) * (1.0 - alert)          # a sleepy guard adds less
	var inv_patrol: float = clampf(1.0 / maxf(Police.patrol_factor(), 0.01), 1.0, 1.6) if scene == "street" or scene.begins_with("venue") else 1.0
	var detect: float = float(j.get("detect", 0.3)) * (1.0 - float(r.get("detect_cut", 0.55)) * stealth) * watch * (1.0 - float(r.get("cased_detect", 0.5)) * known) \
		* (float(r.get("night_detect", 0.8)) if night and not scene.begins_with("biz:") else 1.0) * inv_patrol * (1.0 - gear_effect(pid, "detect")) \
		* (1.0 + float(CrimeLifePath.member(pid).get("heat", 0.0)) * 0.02) * crowd_mult(j, opts, h) 		* (1.0 + (1.0 - CrimeRate.crime_mult()) * 0.3)           # a safe, watchful town notices more; a lawless one less
	detect = clampf(1.0 - exp(-detect), 0.01, 0.97)               # soft saturation keeps every extra piece of cover visible in the number
	var fit: float = clampf(float(CrimeLifePath.skill(pid, "fitness")) / 10.0, 0.0, 1.0)
	var catch_p: float = clampf(float(j.get("catch", 0.3)) * Police.strength() * (1.0 - float(r.get("catch_fit", 0.5)) * fit) * (1.0 + 0.5 * float(guards) * alert), 0.02, 0.95)
	var trace: float = clampf(float(j.get("trace", 0.15)) * (1.0 - float(r.get("trace_skill", 0.07)) * float(CrimeLifePath.skill(pid, "stealth"))) * (1.0 - gear_effect(pid, "trace")), 0.01, 0.9)
	return {"pull_off": pull, "detect": detect, "catch": catch_p, "trace": trace, "cased": known, "skill": skill, "profile": prof, "fx": fx, "night": night}

## Eyes on the act: a crowd HIDES a pickpocket (busy hours of the day by default), but more people see a burglar or a robber.
static func crowd_mult(j: Dictionary, opts: Dictionary, hour_f: float) -> float:
	if bool(j.get("crowd_cover", false)):
		var busy: float = float(opts["crowd"]) if opts.has("crowd") else (1.0 if (hour_f >= 11.0 and hour_f < 14.0) or (hour_f >= 17.0 and hour_f < 19.0) else (0.5 if hour_f >= 8.0 and hour_f < 21.0 else 0.1))
		return 1.0 - 0.4 * busy
	return 1.0 + float(opts.get("crowd", 0.0)) * 0.5

# ------------------------------------------------------------------ the draw
## Outcome: "fail" (nothing taken, unseen), "fail_seen" (nothing taken, somebody saw), "clean" (taken, unseen), "seen" (taken, noticed), "caught" (noticed and held).
static func roll(o: Dictionary) -> String:
	if not CrimeLifeState.chance(float(o["pull_off"])):
		return "fail_seen" if CrimeLifeState.chance(float(o["detect"]) * 0.5) else "fail"
	if CrimeLifeState.chance(float(o["detect"])):
		return "caught" if CrimeLifeState.chance(float(o["catch"])) else "seen"
	return "clean"
