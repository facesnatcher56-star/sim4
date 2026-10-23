class_name SkillCheck
extends RefCounted
## Task 54: one check behind every attempt. SkillCheck.attempt(actor_id, act, ctx) resolves an act from data/skills.json "acts" by the actor's primary skill plus helper
## shares, the tools carried, the conditions (dark, crowded, tired, drunk, injured ...) and traits, against the act's difficulty or, when somebody resists or watches,
## against THEIR skill (ctx.opponent: a person id). The result is graded, not pass or fail:
##   {grade: clean | slow | partial | quiet_fail | loud_fail | catastrophic, ok, p, minutes, noise, trace, alarm}
## catastrophic: the act's own deep miss from data (SkillCatastrophe: injury, evidence, alarm, fire); ctx.scene / ctx.object say where.
## The player never sees p or the grade as a number. Failures still teach (a share of the XP). Townies use the same skills (CrimeLifePath.skill).
##   SkillCheck.level(pid, skill)   effective level 0..10 with helpers      SkillCheck.attempt(pid, act, ctx)      SkillCheck.train(pid, skill, xp, ok)

static func cfg() -> Dictionary:
	return SysUtil.table("skills")

static func own(pid: int, skill: String) -> float:
	var f = SysUtil.folk(pid)
	if f != null:
		if Story.townies.has(pid):          # a townie walking about as Folk keeps the skills of their life (SkillSeed)
			return float(maxi(f.skill_level(skill), SkillSeed.level(pid, skill)))
		return float(f.skill_level(skill))
	return float(CrimeLifePath.skill(pid, skill))

## Own level plus the helpers' shares, 0..10.
static func level(pid: int, skill: String) -> float:
	var def: Dictionary = (cfg().get("skills", {}) as Dictionary).get(skill, {})
	var v: float = own(pid, skill)
	for h in (def.get("helpers", {}) as Dictionary):
		v += own(pid, str(h)) * float(def["helpers"][h])
	v += Creation.check(pid, skill)          # task 55: perks and flaws (strong, keen eye, bad back, poor eyesight ...)
	return clampf(v, 0.0, 10.0)

## The place and moment (dark, noisy, crowded, raining) plus the shared body condition (SkillCondition: age, injury, drunk or high, tired, hungry, sick).
static func _conditions(pid: int, ctx: Dictionary) -> float:
	var c: Dictionary = cfg().get("conditions", {})
	var s: float = SkillCondition.modifier(pid)
	var h: float = SysUtil.hour_f()
	if (h >= 21.0 or h < 5.0) and str(ctx.get("wants", "")) == "unseen":
		s += float(c.get("dark", 0.06))
	for k in ["noisy", "crowded", "raining"]:
		if bool(ctx.get(k, false)):
			s += float(c.get(k, 0.0))
	return s

## Tools that help THIS act (acts.<act>.tools): the ones passed in ctx.tools plus crime gear the person owns (tools_from_gear).
static func _tools(pid: int, d: Dictionary, ctx: Dictionary) -> float:
	var have: Array = (ctx.get("tools", []) as Array).duplicate()
	var from_gear: Dictionary = cfg().get("tools_from_gear", {})
	for gid in from_gear:
		if gid != "_doc" and CrimeLifeRoll.has_gear(pid, str(gid)):
			have.append(str(from_gear[gid]))
	var t: float = 0.0
	var from_items: Dictionary = cfg().get("tools_from_items", {})          # task 62: a toolbox (and the weapons with a "tool") carried
	for e in Inventory.items(pid):
		for tl in (from_items.get(str(e["id"]), []) as Array):
			have.append(str(tl))
		var wt: String = str(WeaponPermits.def_weapon(str(e["id"])).get("tool", ""))
		if wt != "":
			have.append(wt)
	var tools: Dictionary = cfg().get("tools", {})
	for k in (d.get("tools", []) as Array):
		if have.has(k):
			t += float(tools.get(str(k), 0.0))
	return t

static func chance(pid: int, act: String, ctx: Dictionary = {}) -> float:
	var d: Dictionary = (cfg().get("acts", {}) as Dictionary).get(act, {})
	if d.is_empty():
		return 0.5
	var mine: float = level(pid, str(d["skill"])) / 10.0
	if act == "outrun":
		mine *= Creation.mult(pid, "chase_mult")          # asthma, a smoker's lungs
	var theirs: float = float(d.get("difficulty", 0.5))
	if ctx.has("opponent") and d.has("opposed"):
		theirs = clampf(0.25 + level(int(ctx["opponent"]), str(d["opposed"])) / 10.0 * 0.6 + (0.1 if bool(ctx.get("watching", true)) else -0.1), 0.05, 0.95)
		if act in ["threaten", "lie"]:
			theirs = clampf(theirs + 0.05 * Creation.add(int(ctx["opponent"]), "willpower"), 0.05, 0.95)          # task 55: hard to push around
	var p: float = 0.5 + (mine - theirs) * 0.9 + _tools(pid, d, ctx) + _conditions(pid, ctx) + float(ctx.get("bonus", 0.0))
	for tr in (ctx.get("traits", {}) as Dictionary):
		if SocialDynamics.has_t(pid, str(tr)):
			p += float(ctx["traits"][tr])
	if SocialDynamics.has_t(pid, "clumsy"):
		p -= 0.06
	return clampf(p, 0.03, 0.97)

static func attempt(pid: int, act: String, ctx: Dictionary = {}) -> Dictionary:
	var d: Dictionary = (cfg().get("acts", {}) as Dictionary).get(act, {})
	var p: float = chance(pid, act, ctx)
	var r: float = SysUtil.rng.randf()
	var grade: String
	if r >= 1.0 - SkillCatastrophe.chance(pid, act, p):
		grade = "catastrophic"          # the deepest misses (the top of the roll) are the catastrophes
	elif r < p * 0.55:
		grade = "clean"
	elif r < p:
		grade = "slow" if r < p * 0.8 else "partial"
	else:
		grade = "quiet_fail" if SysUtil.rng.randf() < 0.55 else "loud_fail"
	var minutes: float = float(d.get("minutes", 5))
	var noise: float = float(d.get("noise", 0.0))
	match grade:
		"slow":
			minutes *= 2.0
		"loud_fail":
			noise = clampf(noise + 0.5, 0.0, 1.0)
		"catastrophic":
			noise = clampf(noise + 0.5, 0.0, 1.0)
		"clean":
			minutes *= 0.7
	var ok: bool = grade in ["clean", "slow", "partial"]
	train(pid, str(d.get("skill", "")), float(ctx.get("xp", 6.0)), ok)
	var out: Dictionary = {"grade": grade, "ok": ok, "p": p, "minutes": minutes, "noise": noise, "act": act, "trace": 0.0, "alarm": false}
	if grade == "catastrophic":
		var e: Dictionary = SkillCatastrophe.apply(pid, act, ctx)
		out["trace"] = e["trace"]
		out["alarm"] = e["alarm"]
		out["noise"] = maxf(noise, float(e["noise"]))
	return out

static func train(pid: int, skill: String, xp: float, ok: bool) -> void:
	if skill == "":
		return
	CrimeLifePath.train(pid, skill, xp * (1.0 if ok else float(cfg().get("xp_fail", 0.35))))
