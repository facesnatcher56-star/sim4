class_name SkillInterest
extends RefCounted
## Which skill a free-time activity grows is a matter of taste, not of who owns the nearest computer. Autonomy multiplies the score of an
## interaction that trains skills by this: FATIGUE (the higher the skill, the less they feel like doing more of it) and INTEREST (traits,
## aspiration and job point at certain skills: outdoorsy -> fitness / gardening / fishing, musical -> guitar / piano, a writer -> writing).
## Data: data/skill_interest.json. Needs, meals and work are exempt (same rule as AutonomyVariety).

static func cfg() -> Dictionary:
	return SysUtil.table("skill_interest")

## Skills this person cares about -> boost.
static func interests(folk) -> Dictionary:
	var c: Dictionary = cfg()
	var ic: Dictionary = c.get("interest", {})
	var out: Dictionary = {}
	var tmap: Dictionary = c.get("traits", {})
	for t in folk.traits:
		for s in tmap.get(str(t), []):
			out[str(s)] = maxf(float(out.get(str(s), 1.0)), float(ic.get("trait", 1.5)))
	var asp: String = str((Goals.profiles.get(int(folk.id), {}) as Dictionary).get("aspiration", ""))
	for s2 in (c.get("aspirations", {}) as Dictionary).get(asp, []):
		out[str(s2)] = maxf(float(out.get(str(s2), 1.0)), float(ic.get("aspiration", 1.8)))
	var career: String = Careers.career_of(int(folk.id))
	if career != "":
		var ps: String = str(Careers.cfg().get("careers", {}).get(career, {}).get("primary_skill", ""))
		if ps != "":
			out[ps] = maxf(float(out.get(ps, 1.0)), float(ic.get("career", 1.8)))
	return out

## Score multiplier for one skill.
static func skill_mult(folk, skill: String, interest: Dictionary) -> float:
	var c: Dictionary = cfg()
	var fc: Dictionary = c.get("fatigue", {})
	var ic: Dictionary = c.get("interest", {})
	var lvl: float = float(folk.skill_level(skill))
	var boost: float = float(interest.get(skill, 1.0))
	if boost > 1.0:
		lvl -= float(fc.get("interest_levels", 3))
	var m: float = clampf(1.0 - float(fc.get("per_level", 0.16)) * maxf(lvl - float(fc.get("from_level", 4)), 0.0), float(fc.get("min", 0.2)), 1.0)
	if boost > 1.0 and folk.skill_level(skill) < int(ic.get("boost_until_level", 8)):
		m *= minf(boost, float(ic.get("max_boost", 2.6)))
	return m

## Multiplier for an interaction def (1.0 when it trains nothing that is covered).
static func mult(folk, iid: String, d: Dictionary) -> float:
	var xp: Dictionary = d.get("skill_xp_per_min", {})
	if xp.is_empty() or AutonomyVariety.exempt(iid, d):
		return 1.0
	var ignore: Array = cfg().get("ignore_skills", [])
	var interest: Dictionary = {}
	var have: bool = false
	var total: float = 0.0
	var n: int = 0
	for s in xp:
		if ignore.has(str(s)):
			continue
		if not have:
			interest = interests(folk)
			have = true
		total += skill_mult(folk, str(s), interest)
		n += 1
	return total / float(n) if n > 0 else 1.0
