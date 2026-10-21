class_name SocialFit
extends RefCounted
## Task 52 (owner: "freedom to try, the world reacts"): what the PLAYER may do to another person is never limited by how well they know them. A kiss, a hug, a prank, an
## insult, a deep talk or a secret are always on the menu for the player's person; only what is truly impossible hides (the person is lying down or away, it needs a thing
## you do not have, a stage that does not allow it, knowledge you have not learned). The old social gates (relationship_above, "not in the mood" social need, a skill level,
## "only when angry" for the mean actions, "no partner") become the INPUT of how the other person reacts (SocialReaction) instead of availability rules.
## NPCs keep the gates (their own behaviour is unchanged). Without a Players table (classic tests) nothing here applies.
##   SocialFit.player_controlled(f)      is this the player's person?
##   SocialFit.hard_tests(tests)         the tests that stay (physical / practical / stage / knowledge) once the social-fit ones are dropped
##   SocialFit.gap(actor_id, target_id, d)   0 = a natural fit ... 1+ = far out of place (how much the actor's tests and the target's tests fall short)

const SOFT_ANY_KEYS := ["has_trait", "mood_is", "relationship_above", "has_buff"]

static func player_controlled(f) -> bool:
	return f != null and not Players.table.is_empty() and Pawn.is_pawn(f)

## One test: does it only measure social fit (true) or is it a real limit (false)?
static func is_soft(t: Dictionary) -> bool:
	for k in t:
		var v = t[k]
		match str(k):
			"relationship_above":
				if str((v as Array)[0]) in ["bond", "ex", "tension"]:
					return false          # a real state, not social fit: no break-up without being together, no rekindling without an ex, nothing to forgive without a fight
				continue
			"stat_below":
				if str((v as Array)[0]) != "social":
					return false
			"skill_at_least":
				continue
			"lacks_buff":
				if str(v) != "has_partner":
					return false
			"not":
				if not (v is Dictionary) or not is_soft(v):
					return false
			"any":
				# "any of these moods / traits" = a fit rule (the mean actions); "any stage" is a real limit
				for sub in (v as Array):
					for sk in (sub as Dictionary):
						if not SOFT_ANY_KEYS.has(str(sk)):
							return false
						if str(sk) == "has_buff" and str((sub as Dictionary)[sk]).begins_with("stage_"):
							return false
			"mood_is":
				continue
			_:
				return false
	return true

static func hard_tests(tests: Array) -> Array:
	var out: Array = []
	for t in tests:
		if t is Dictionary and is_soft(t):
			continue
		out.append(t)
	return out

## How far from natural is it? The shortfall of every relationship test of the actor and of the target (normalised by what the test asks), a partner conflict, and a
## trait or mood mismatch of the mean actions. 0 = fits.
static func gap(actor_id: int, target_id: int, d: Dictionary) -> float:
	var parts: Array = []
	for t in d.get("tests", []):
		parts.append(_shortfall(t, actor_id, target_id, true))
	for t2 in d.get("target_tests", []):
		parts.append(_shortfall(t2, target_id, actor_id, false))
	var worst: float = 0.0
	var rest: float = 0.0
	for p in parts:
		if float(p) > worst:
			rest += worst
			worst = float(p)
		else:
			rest += float(p)
	return clampf(worst + 0.25 * rest, 0.0, 1.0)

static func _shortfall(t: Dictionary, who: int, other: int, actor_side: bool) -> float:
	if not (t is Dictionary) or not is_soft(t):
		return 0.0
	var s: float = 0.0
	for k in t:
		var v = t[k]
		match str(k):
			"relationship_above":
				var track: String = str((v as Array)[0])
				var need: float = float((v as Array)[1])
				var have: float = RelationshipService.value(who, other, track) if track in ["friendship", "romance", "trust", "tension"] else (1.0 if RelationshipBits.has_flag(who, other, "partner") or RelationshipBits.has_flag(who, other, "spouse") else 0.0)
				if have < need:
					s += (need - have) / maxf(need, 1.0)
			"lacks_buff":
				var f = SysUtil.folk(who)
				if f != null and f.has_buff(str(v)):
					s += 0.5          # someone who has a partner is being asked / flirted with
			"any":
				var okay: bool = Cond.check_one(t, {"folk": SysUtil.folk(who), "object": null, "target": SysUtil.folk(other)}) if SysUtil.folk(who) != null else true
				if not okay:
					s += 0.3
	return s
