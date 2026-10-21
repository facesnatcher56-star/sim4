class_name AttemptGates
extends RefCounted
## Task 53 sweep: the player's person may try object and self interactions their skill or purse would once have hidden (data/attempts.json).
## A skill gate becomes an attempt that can go poorly (a lesser result, a cooking fire); a coin gate becomes a refusal at the moment of paying.
## NPC autonomy keeps the old gates. Social interactions already work this way (SocialFit / SocialReaction, task 52).
##   AttemptGates.hard_tests(def_id, tests)   tests that still decide availability for the pawn
##   AttemptGates.resolve(ir) -> "ok" | "poor" | "refused"   (Interaction.finish, before the effects)

static func cfg() -> Dictionary:
	return SysUtil.table("attempts")

## keep_coins: the defs that need the coin itself (by their label, since a def does not carry its id).
static func _keeps_coins(d: Dictionary) -> bool:
	for id in cfg().get("keep_coins", []):
		if str(SimEnv.data().interaction_def(str(id)).get("label", "?")) == str(d.get("label", "")):
			return true
	return false

static func _soft(d: Dictionary, t) -> bool:
	if not (t is Dictionary) or (t as Dictionary).size() != 1:
		return false
	if (t as Dictionary).has("skill_at_least") or (t as Dictionary).has("stat_below") or (t as Dictionary).has("stat_above"):
		return true          # a need level never hides an act (you can cook when full, work out when tired); the effects are what they are
	if (t as Dictionary).has("coins_at_least"):
		return not _keeps_coins(d)
	return false

static func hard_tests(d: Dictionary, tests: Array) -> Array:
	return tests.filter(func(t): return not _soft(d, t))

static func _line(k: String, tags: Array) -> String:
	var pool: Dictionary = cfg().get("lines", {}).get(k, {}) if k == "poor" else {}
	var lines: Array = []
	if k == "poor":
		for tg in ["cook", "creative", "music", "fish", "garden", "repair"]:
			if tags.has(tg) or (tg == "cook" and tags.has("food")) or (tg == "creative" and (tags.has("art") or tags.has("write"))):
				lines = pool.get(tg, [])
				break
		if lines.is_empty():
			lines = pool.get("default", [""])
	else:
		lines = cfg().get("lines", {}).get(k, [""])
	return str(lines[PlayerPrompt._pick("attempt|" + k, lines.size())])

static func resolve(ir) -> String:
	var f = ir.actor
	if not SocialFit.player_controlled(f) or str(ir.target_kind) == "folk":
		return "ok"
	var tags: Array = ir.def.get("tags", [])
	for t in ir.def.get("tests", []):
		if not _soft(ir.def, t):
			continue
		if (t as Dictionary).has("stat_below") or (t as Dictionary).has("stat_above"):
			continue
		if (t as Dictionary).has("coins_at_least"):
			if Economy.balance(int(f.household_id)) < int(t["coins_at_least"]):
				SysUtil.notify(_line("refused", tags), "story")
				return "refused"
		else:
			var sk: Array = t["skill_at_least"]
			var need: float = float(sk[1])
			var have: float = SkillCheck.level(int(f.id), str(sk[0]))
			if have >= need:
				continue
			var c: Dictionary = cfg().get("skill", {})
			var ratio: float = clampf(have / maxf(need, 1.0), 0.0, 1.0)
			var near: float = float(c.get("base", 0.15)) + float(c.get("share", 0.6)) * ratio          # the curve close to the level
			var p: float = lerpf(float(c.get("floor", 0.03)), near, pow(ratio, float(c.get("gap_curve", 1.5)))) + SkillCondition.modifier(int(f.id))
			if SysUtil.rng.randf() < clampf(p, 0.01, 0.95):
				continue          # a lucky go: it works this time
			f.add_skill_xp(str(sk[0]), float(cfg().get("fail_xp", 4)))
			SysUtil.notify(_line("poor", tags), "story")
			if tags.has("cook"):
				SkillCheck.attempt(int(f.id), "cook", {"object": ir.obj})          # a deep miss in the kitchen is a fire (SkillCatastrophe)
			return "poor"
	return "ok"

## The effects of a poor go: the fallback interaction's (a plain meal instead of a gourmet one), or nothing.
static func poor_effects(def_id: String) -> Array:
	var fb: String = str(cfg().get("fallback", {}).get(def_id, ""))
	if fb == "":
		return []
	return SimEnv.data().interaction_def(fb).get("on_finish", [])
