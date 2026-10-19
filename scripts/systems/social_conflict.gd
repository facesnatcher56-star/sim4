class_name SocialConflict
extends RefCounted
## Arguments, reconciliation and cheating.

# ------------------------------------------------------------------ arguments
static func arg_level(a: int, b: int) -> int:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return 0
	var ar: Dictionary = p.get("arg", {})
	if SysUtil.now() - int(ar.get("t", -99999)) > int(SocialDynamics.cfg().get("arguments", {}).get("window_min", 90)):
		return 0
	return int(ar.get("level", 0))

## An argument flares up (or escalates when it follows another within the window).
static func escalate(a: int, b: int, amount: float) -> int:
	var ac: Dictionary = SocialDynamics.cfg().get("arguments", {})
	var p: Dictionary = RelationshipService._pair(a, b)
	var ar: Dictionary = RelationshipRomance._sub(p, "arg", {"level": 0, "t": -99999, "count": 0})
	var now := SysUtil.now()
	var level: int = int(ar.get("level", 0))
	if now - int(ar.get("t", -99999)) <= int(ac.get("window_min", 90)):
		level = mini(level + 1, int(ac.get("max_level", 4)))
	else:
		level = 1
	ar["level"] = level
	ar["t"] = now
	ar["count"] = int(ar.get("count", 0)) + 1
	var mult: float = 1.0 + float(ac.get("level_mult", 0.25)) * (level - 1)
	if SocialDynamics.has_t(a, "hot_headed") or SocialDynamics.has_t(b, "hot_headed"):
		mult *= float(ac.get("hot_headed_mult", 1.3))
	var amt: float = amount * mult
	RelationshipRomance.add_tension(a, b, amt)
	RelationshipRomance.add_tension(b, a, amt)
	SocialDynamics._count("arguments")
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	var tc: Dictionary = SocialDynamics.cfg().get("tension", {})
	if level >= int(ac.get("screaming_level", 3)):
		RelationshipService.add_value(a, b, "friendship", -float(ac.get("friendship_loss", 6)))
		RelationshipService.add_value(b, a, "friendship", -float(ac.get("friendship_loss", 6)))
		RelationshipService.add_value(a, b, "trust", -float(ac.get("trust_loss", 2)))
		RelationshipService.add_value(b, a, "trust", -float(ac.get("trust_loss", 2)))
		for f in [fa, fb]:
			if f != null:
				f.add_buff(str(ac.get("furious_buff", "furious")) if f.has_trait("hot_headed") else str(ac.get("fuming_buff", "fuming")))
		SysUtil.notify("%s and %s are screaming at each other!" % [SysUtil.folk_name(a), SysUtil.folk_name(b)], "warn")
	for pair in [[fa, b], [fb, a]]:
		var f2 = pair[0]
		if f2 != null and RelationshipRomance.tension(int(f2.id), int(pair[1])) >= float(tc.get("avoid_threshold", 25)):
			f2.remember("folk:%d" % int(pair[1]), float(tc.get("avoid_memory", -0.25)))
	SysUtil.game_event("argument", {"folk_id": a, "target_id": b, "level": level, "amount": amt})
	_witness_argument(a, b)
	return level

static func _witness_argument(a: int, b: int) -> void:
	var fa = SysUtil.folk(a)
	if fa == null:
		return
	for f in WorldIface.all_folk():
		if int(f.id) == a or int(f.id) == b or SysUtil.is_away(f):
			continue
		if Vector2(f.tile - fa.tile).length() <= 6.0:
			Emotions.add_hidden(f, "caught_tense")

static func _check_resolved(a: int, b: int, how: String) -> bool:
	var ac: Dictionary = SocialDynamics.cfg().get("arguments", {})
	var worst: float = maxf(RelationshipRomance.tension(a, b), RelationshipRomance.tension(b, a))
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return false
	if worst > float(ac.get("resolve_below", 10)) or not bool(p.get("heated", false)):
		return false
	p.erase("heated")
	var ar: Dictionary = RelationshipRomance._sub(p, "arg", {"level": 0, "t": -99999, "count": 0})
	ar["level"] = 0
	RelationshipService.add_both(a, b, "friendship", float(ac.get("resolved_bonus_friendship", 3)))
	RelationshipService.add_both(a, b, "trust", float(ac.get("resolved_bonus_trust", 3)))
	for f in [SysUtil.folk(a), SysUtil.folk(b)]:
		if f != null:
			f.add_buff(str(ac.get("resolved_buff", "makeup_glow")))
	RelNotify.say([a, b], "%s and %s made up." % [SysUtil.folk_name(a), SysUtil.folk_name(b)], "relationship")
	SysUtil.game_event("argument_resolved", {"folk_id": a, "target_id": b, "how": how})
	return true

## Public: lower tension between a pair (used by apologize events, tests).
static func reconcile(a: int, b: int, amount: float, how: String = "apology") -> bool:
	RelationshipRomance.add_tension(a, b, -amount)
	RelationshipRomance.add_tension(b, a, -amount)
	return _check_resolved(a, b, how)

static func _confront(a, t, tier: String) -> void:
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	if tier == "great" or tier == "good":
		RelationshipRomance.add_tension(aid, tid, -20.0)
		RelationshipRomance.add_tension(tid, aid, -10.0)
		RelationshipService.add_value(aid, tid, "trust", 6.0)
		a.remove_buff("cheated_on")
		t.add_buff("guilty_pang")
	elif tier == "bad":
		if RelationshipRomance.breakup(aid, tid, "cheating", 1.2):
			SocialDynamics._count("breakups")
		a.remove_buff("cheated_on")

# ------------------------------------------------------------------ cheating
static func cheat_check(a: int, b: int) -> void:
	for pr in [[a, b], [b, a]]:
		var x: int = pr[0]
		var o: int = pr[1]
		for victim in RelationshipRomance.exclusive_partners(x):
			if int(victim) == o:
				continue
			var fv = SysUtil.folk(int(victim))
			var fx = SysUtil.folk(x)
			var rc: Dictionary = SocialDynamics.cfg().get("romance", {}).get("cheat", {})
			SocialDynamics._count("cheats")
			if fv != null and not SysUtil.is_away(fv) and fx != null and Vector2(fv.tile - fx.tile).length() <= float(rc.get("range", 14)):
				discover_cheating(int(victim), x, o)
			else:
				var known := false
				for af in RelationshipService.affairs:
					if int(af["cheater"]) == x and int(af["other"]) == o and int(af["victim"]) == int(victim):
						known = true
				if not known:
					RelationshipService.affairs.append({"cheater": x, "other": o, "victim": int(victim), "day": SysUtil.day()})

static func discover_cheating(victim: int, cheater: int, other: int) -> void:
	var rc: Dictionary = SocialDynamics.cfg().get("romance", {}).get("cheat", {})
	RelationshipService.add_value(victim, cheater, "trust", -float(rc.get("trust_loss", 45)))
	RelationshipService.add_value(victim, cheater, "romance", -float(rc.get("romance_loss", 35)))
	RelationshipService.add_value(victim, cheater, "friendship", -float(rc.get("friendship_loss", 10)))
	RelationshipRomance.add_tension(victim, cheater, float(rc.get("tension", 35)))
	RelationshipRomance.add_tension(cheater, victim, 15.0)
	RelationshipService.add_history(cheater, victim, "cheated", -1.0, cheater)
	RelationshipKnowledge.add_reputation(cheater, float(rc.get("reputation", -6)))
	var fv = SysUtil.folk(victim)
	var fc = SysUtil.folk(cheater)
	if fv != null:
		fv.add_buff(str(rc.get("buff", "cheated_on")))
		if fv.has_trait("jealous"):
			fv.add_buff("jealous_pang")
	if fc != null:
		fc.add_buff(str(rc.get("guilty", "guilty_pang")))
	var keep: Array = []
	for af in RelationshipService.affairs:
		if not (int(af["cheater"]) == cheater and int(af["victim"]) == victim):
			keep.append(af)
	RelationshipService.affairs = keep
	RelNotify.say([victim, cheater, other], "%s found out that %s was cheating with %s!" % [SysUtil.folk_name(victim), SysUtil.folk_name(cheater), SysUtil.folk_name(other)], "bad")
	SysUtil.game_event("cheating_discovered", {"folk_id": victim, "target_id": cheater, "other_id": other})
	var p: float = float(rc.get("auto_breakup", 0.6))
	if SocialDynamics.has_t(victim, "jealous"):
		p *= 1.3
	if SocialDynamics.has_t(victim, "forgiving"):
		p *= 0.5
	if SocialDynamics.has_t(victim, "easygoing"):
		p *= 0.7
	if SysUtil.rng.randf() < p:
		if RelationshipRomance.breakup(victim, cheater, "cheating", 1.2):
			SocialDynamics._count("breakups")
