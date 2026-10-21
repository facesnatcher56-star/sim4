class_name SkillTeach
extends RefCounted
## Task 54 audit: tutoring teaches the subject the tutor actually knows (their strongest skill above the learner's), not charisma. How well it lands
## grows with the gap and the tutor's charisma. A tutor with nothing to teach the learner leaves them with little. (The tutor's own charisma xp is in the interaction.)
##   SkillTeach.on_game_event("tutored", {folk_id: tutor, target_id: learner})

const XP := 14.0

static func on_game_event(ev: String, p: Dictionary) -> void:
	if ev != "tutored":
		return
	var tutor = SysUtil.folk(int(p.get("folk_id", -1)))
	var learner = SysUtil.folk(int(p.get("target_id", -1)))
	if tutor == null or learner == null:
		return
	var best: String = ""
	var gap: int = 0
	for sk in tutor.skills:
		var g: int = tutor.skill_level(str(sk)) - learner.skill_level(str(sk))
		if g > gap:
			gap = g
			best = str(sk)
	if best == "":
		return
	var lands: float = 1.0 + SkillCheck.level(int(tutor.id), "charisma") * 0.08
	learner.add_skill_xp(best, XP * minf(float(gap), 4.0) * 0.5 * lands)
