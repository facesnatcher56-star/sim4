class_name SkillCatastrophe
extends RefCounted
## Task 54 review: the deep miss. Each act names its own catastrophe in data/skills.json acts.<act>.catastrophe, and it goes through the real systems:
##   injure [severity, cause]  -> Health.injure (a shoulder from a forced door, a cut hand from glass, a shock from wiring)
##   trace  0..1               -> returned to the caller, who adds it to the crime it commits (a snapped pick with prints, blood on the glass)
##   alarm  true               -> the place's real alarm (CrimeSecurity profile) rings if it has one: everybody hears it and it raises the trace
##   fire   true               -> Fire.ignite on ctx.object (or ctx.tile)
##   line   [..]               -> what physically happens, said once (never a hint beforehand)
##   SkillCatastrophe.chance(pid, act, p) -> share of rolls that go catastrophic      SkillCatastrophe.apply(pid, act, ctx) -> {trace, alarm, noise, line}

static func cfg() -> Dictionary:
	return SysUtil.table("skills").get("catastrophe", {})

## How likely a roll is a deep miss: high at low skill, rare at high skill, worse drunk/high/injured/tired. Never more than the failure share (1 - p).
static func chance(pid: int, act: String, p: float) -> float:
	var d: Dictionary = (SysUtil.table("skills").get("acts", {}) as Dictionary).get(act, {})
	if not d.has("catastrophe"):
		return 0.0
	var lv: float = SkillCheck.level(pid, str(d["skill"])) / 10.0
	var c: Dictionary = cfg()
	var base: float = lerpf(float(c.get("at_skill_0", 0.16)), float(c.get("at_skill_10", 0.005)), sqrt(lv))
	return clampf(base * SkillCondition.catastrophe_mult(pid) * float(d["catastrophe"].get("weight", 1.0)), 0.0, (1.0 - p) * float(c.get("max_fail_share", 0.6)))

static func apply(pid: int, act: String, ctx: Dictionary) -> Dictionary:
	var e: Dictionary = (SysUtil.table("skills").get("acts", {}) as Dictionary).get(act, {}).get("catastrophe", {})
	var out: Dictionary = {"trace": float(e.get("trace", 0.0)), "alarm": false, "noise": float(e.get("noise", 0.0)), "line": ""}
	var f = SysUtil.folk(pid)
	var lines: Array = e.get("line", [])
	if not lines.is_empty() and f != null and CrimePerson.is_player(pid):
		out["line"] = str(lines[PlayerPrompt._pick("catastrophe|" + act, lines.size())])
		SysUtil.notify(out["line"], "bad")
	if e.has("injure") and f != null:
		var inj: Array = e["injure"]
		Health.injure(f, int(inj[0]), str(inj[1]))
	if bool(e.get("alarm", false)) and str(ctx.get("scene", "")) != "":
		if bool(CrimeSecurity.profile_for(str(ctx["scene"])).get("alarm", false)):
			out["alarm"] = true
			out["noise"] = 1.0
			out["trace"] = float(out["trace"]) + float(cfg().get("alarm_trace", 0.3))
			if CrimePerson.is_player(pid):
				SysUtil.notify("An alarm starts wailing.", "bad")
	if bool(e.get("fire", false)):
		var target = ctx.get("object", ctx.get("tile", null))
		if target != null:
			Fire.ignite(target, str(e.get("fire_source", act)), {"culprit": pid})
	return out
