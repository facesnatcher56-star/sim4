class_name SocialScoring
extends RefCounted
## Social success scoring, outcome tiers and availability requirements/reasons.

# ------------------------------------------------------------------ success / tiers
static func mood_add(f, group: String, cat: String) -> float:
	var m: String = str(f.mood_name)
	if m == "neutral" or int(f.mood_intensity) <= 0:
		return 0.0
	var g: Dictionary = Emotions.def_of(m).get("social", {}).get(group, {})
	var v: float = float(g.get(cat, 0.0)) + float(g.get("all", 0.0))
	return v * Emotions.scale_for(int(f.mood_intensity))

## Breakdown of the success score of `a` doing `iid` to `t` (without noise). {score, parts}.
static func success_score(a, t, iid: String, d: Dictionary, sd: Dictionary, teff: Dictionary = {}, with_noise: bool = true) -> Dictionary:
	var oc: Dictionary = SocialDynamics.cfg().get("outcomes", {})
	var w: Dictionary = oc.get("weights", {})
	var cat: String = str(d.get("category", "friendly"))
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	var parts: Dictionary = {}
	parts["base"] = float(sd.get("base", 0.5))
	if RomanceRules.is_romantic_def(d) and not RomanceRules.allowed(aid, tid):
		return {"score": -9.0, "parts": {"not_allowed": -9.0}}
	var compat: float = RelationshipBits.compatibility(aid, tid)
	parts["compat"] = compat * float(w.get("compat", 0.25))
	parts["charisma"] = float(a.skill_level("charisma")) * float(w.get("charisma", 0.03))
	parts["history"] = RelationshipService.warmth(tid, aid) * float(w.get("warmth", 0.15)) - RelationshipService.grudge(tid, aid) * float(w.get("grudge", 0.25))
	parts["friendship"] = RelationshipService.value(tid, aid, "friendship") * float(w.get("friendship", 0.002))
	parts["trust"] = RelationshipService.value(tid, aid, "trust") * float(w.get("trust", 0.003))
	var ten: float = RelationshipService.value(tid, aid, "tension") * float(w.get("tension", 0.004))
	var tags: Array = d.get("tags", [])
	parts["tension"] = ten if cat == "mean" else (0.0 if tags.has("reconcile") else -ten)
	if cat == "romantic" or bool(sd.get("spark", false)):
		parts["spark"] = (RelationshipRomance.spark(aid, tid) - 0.5) * float(w.get("spark", 0.4))
	parts["reputation"] = RelationshipKnowledge.reputation(aid) * float(w.get("reputation", 0.0015))
	if not teff.is_empty():
		parts["topic"] = float(teff.get("bonus", 0.0))
	var cap: float = float(w.get("mood_cap", 0.25))
	parts["mood"] = clampf(mood_add(a, "give", cat) + mood_add(t, "receive", cat), -cap, cap)
	parts["traits"] = SocialDynamics.trait_add(aid, "give", cat) + SocialDynamics.trait_add(tid, "receive", cat)
	var total := 0.0
	for k in parts:
		total += float(parts[k])
	if with_noise:
		var n: float = float(oc.get("noise", 0.18))
		parts["noise"] = (SysUtil.rng.randf() * 2.0 - 1.0) * n
		total += float(parts["noise"])
	return {"score": total, "parts": parts}

static func tier_for(score: float, sd: Dictionary) -> String:
	var th: Dictionary = SocialDynamics.cfg().get("outcomes", {}).get("thresholds", {"great": 0.8, "good": 0.5, "meh": 0.28})
	if sd.has("thr"):
		var arr: Array = sd["thr"]
		th = {"great": float(arr[0]), "good": float(arr[1]), "meh": float(arr[2])}
	if score >= float(th["great"]):
		return "great"
	if score >= float(th["good"]):
		return "good"
	if score >= float(th["meh"]):
		return "meh"
	return "bad"

static func fx_for(sd: Dictionary, tier: String) -> Dictionary:
	var oc: Dictionary = sd.get("outcomes", {})
	var order: Array = {"great": ["great", "good", "meh"], "good": ["good", "meh"], "meh": ["meh"], "bad": ["bad", "meh"]}.get(tier, ["meh"])
	for k in order:
		if oc.has(k):
			return oc[k]
	return {}

# ------------------------------------------------------------------ requirements / reasons
static func check_requires(actor: int, target: int, req: Array) -> String:
	for r in req:
		match str(r):
			"bonded":
				if not RelationshipRomance.exclusive_partners(actor).has(target):
					return "You need to be together first."
			"not_bonded":
				if RelationshipRomance.exclusive_partners(actor).has(target):
					return "You are already together."
			"not_married":
				if RelationshipBits.has_flag(actor, target, "spouse"):
					return "Spouses have to divorce instead."
			"knows_career":
				if not RelationshipKnowledge.knows_career(actor, target):
					return "You don't know their job yet."
			"knows_aspiration":
				if not RelationshipKnowledge.knows_aspiration(actor, target):
					return "You don't know their dreams yet."
			"knows_trait":
				if RelationshipKnowledge.known_traits(actor, target).is_empty():
					return "You don't know them well enough yet."
	return ""

static func describe_cond(c: Dictionary, who: String = "you") -> String:
	for key in c:
		var v: Variant = c[key]
		match str(key):
			"relationship_above":
				var trk: String = str(v[0])
				var val: float = float(v[1])
				match trk:
					"bond":
						return "%s must be dating or together" % who.capitalize() if val < 1.0 else "needs a serious relationship"
					"ex":
						return "only for exes"
					"tension":
						return "needs unresolved tension (%d+)" % int(val)
					_:
						return "needs %s above %d" % [trk, int(val)]
			"mood_is":
				return "only while %s" % str(v)
			"has_trait":
				return "needs trait %s" % str(v)
			"lacks_trait":
				return "not for %s folk" % str(v)
			"has_buff":
				return {"in_group": "needs a group chat of 3+", "in_conversation": "they are not in a conversation", "has_gossip": "no gossip to share",
					"cheated_on": "only after being cheated on"}.get(str(v), "needs %s" % str(v))
			"lacks_buff":
				return {"has_partner": "already attached", "away": "is away", "in_conversation": "already talking"}.get(str(v), "not while %s" % str(v))
			"stat_below":
				return "not in the mood (%s too high)" % str(v[0])
			"stat_above":
				return "%s too low" % str(v[0])
			"skill_at_least":
				return "needs %s skill %d" % [str(v[0]), int(v[1])]
			"posture_not":
				return "they are lying down"
			"not":
				if v is Dictionary:
					if (v as Dictionary).has("mood_is"):
						return "too %s right now" % str((v as Dictionary)["mood_is"])
					return "blocked: " + describe_cond(v, who)
			"any":
				var parts: Array = []
				for sub in v:
					if sub is Dictionary:
						parts.append(describe_cond(sub, who))
				return "needs one of: " + " / ".join(parts)
	return "unavailable"

## Human-readable reason why `actor` cannot do `iid` to `target` right now ("" = available).
static func reason_unavailable(actor, target, iid: String, include_cooldown: bool = true) -> String:
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if d.is_empty():
		return "Unknown action"
	if include_cooldown and actor.on_cooldown(iid):
		return "Too soon to do that again"
	if target != null and str(d.get("target", "")) == "folk" and RomanceRules.is_romantic_def(d) and not RomanceRules.allowed(int(actor.id), int(target.id)):
		return RomanceRules.why_not(int(actor.id), int(target.id))
	var ctx := {"folk": actor, "object": null, "target": target}
	for c in d.get("tests", []):
		if not Cond.check([c], ctx):
			return "You: " + describe_cond(c, "you")
	if target != null and str(d.get("target", "")) == "folk":
		var tctx := {"folk": target, "object": null, "target": actor}
		for c2 in d.get("target_tests", []):
			if not Cond.check([c2], tctx):
				return "%s: %s" % [target.name, describe_cond(c2, "they")]
		var req: Array = (d.get("social", {}) as Dictionary).get("requires", [])
		var rf := check_requires(int(actor.id), int(target.id), req)
		if rf != "":
			return rf
	return ""
