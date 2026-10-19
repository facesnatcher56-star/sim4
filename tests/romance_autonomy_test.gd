extends RefCounted
## Autonomy never even considers a romantic interaction with a minor or a relative: the candidates are dropped while gathering
## (before any scoring), the scorer refuses them, and the pie menu reason says why.

const S = preload("res://tests/social_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := S.setup(9103)
	S.furnish_for_test(w)
	var cast: Dictionary = {}
	for nm in ["mum", "dad", "kid", "teen", "adult", "sib", "other"]:
		var stage: String = "teen" if nm == "teen" else ("child" if nm == "kid" else "adult")
		cast[nm] = S.K.make_folk(w, nm, ["romantic", "flirty"], 1, Vector2i(11 + cast.size(), 12), stage)
	Family.link_parent(cast["kid"].id, cast["mum"].id)
	Family.link_parent(cast["teen"].id, cast["mum"].id)
	Family.link_parent(cast["sib"].id, cast["mum"].id)
	var defs: Dictionary = SimEnv.data().interactions()
	var seen_ok: int = 0
	for nm in cast:
		var me: Folk = cast[nm]
		for row in Autonomy.gather(me):
			if str(row["kind"]) != "folk":
				continue
			var other: Folk = row["folk"]
			if not RomanceRules.is_romantic_def(defs[str(row["id"])]):
				continue
			S.expect(f, RomanceRules.allowed(me.id, other.id), "%s was offered %s towards %s" % [nm, row["id"], other.name])
			seen_ok += 1
	S.expect(f, seen_ok > 0, "adults do get romantic candidates (%d)" % seen_ok)
	# scoring and pie-menu reasons refuse too
	var flirt: Dictionary = defs["flirt"]
	var sd: Dictionary = flirt.get("social", {})
	var bad: Dictionary = SocialScoring.success_score(cast["mum"], cast["kid"], "flirt", flirt, sd, {}, false)
	var good: Dictionary = SocialScoring.success_score(cast["mum"], cast["other"], "flirt", flirt, sd, {}, false)
	S.expect(f, float(bad["score"]) < -5.0 and float(good["score"]) > -5.0, "scoring refuses a forbidden pair (%.1f vs %.1f)" % [bad["score"], good["score"]])
	S.expect(f, SocialScoring.reason_unavailable(cast["mum"], cast["sib"], "flirt", false) == "They are family.", "reason names family")
	S.expect(f, SocialScoring.reason_unavailable(cast["adult"], cast["teen"], "flirt", false) == "Too young for that.", "reason names age")
	# a whole day of autonomy: nobody ever starts a romantic interaction with a minor or a relative
	S.K.mgr.enabled = true
	var dir = S.director()
	S.set_time(1, 7)
	var started: int = 0
	for m in 720:
		SimEnv.clock().advance_minutes(1)
		dir.tick_minute(1)
		for nm in cast:
			var cur = cast[nm].current
			if cur != null and cur.target_kind == "folk" and RomanceRules.is_romantic_def(cur.def):
				started += 1
				S.expect(f, RomanceRules.allowed(int(cur.actor_id), int(cur.target_id)), "%s started %s with %d" % [nm, cur.def_id, cur.target_id])
	print("  romantic interaction minutes seen: %d" % started)
	S.teardown()
	return f
