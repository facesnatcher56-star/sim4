class_name SkillSeed
extends RefCounted
## Task 54: townies carry the same skills as the player, seeded from what they do and who they are (data/skills.json "seed"): their job (a detective
## reads people, a mechanic hotwires, a bouncer fights), its level, their traits and life stage, plus a stable personal spread from their id.
## Computed on read (a new job shifts it). Trained skills a townie holds in its record (crew life) win when they are higher.
##   SkillSeed.level(tid, skill) -> int

static func cfg() -> Dictionary:
	return SysUtil.table("skills").get("seed", {})

static func level(tid: int, skill: String) -> int:
	var t: Dictionary = Story.townies.get(tid, {})
	if t.is_empty():
		return 0
	var c: Dictionary = cfg()
	var v: float = 0.0
	var career: String = str(t.get("career", ""))
	var job: Dictionary = (c.get("by_career", {}) as Dictionary).get(career, {})
	if job.has(skill):
		v += float(job[skill]) + float(c.get("per_career_level", 0.6)) * maxf(float(t.get("level", 1)) - 1.0, 0.0)
	for tr in t.get("traits", []):
		v += float((c.get("by_trait", {}) as Dictionary).get(str(tr), {}).get(skill, 0.0))
	v += float((c.get("by_stage", {}) as Dictionary).get(Story.stage_of(t), {}).get(skill, 0.0))
	if v > 0.0:
		v += float(absi(hash("%d|%s" % [tid, skill])) % 100) / 100.0 * float(c.get("spread", 1.5))
	var own: int = int((t.get("skills", {}) as Dictionary).get(skill, 0))
	return maxi(own, clampi(int(v), 0, 10))
