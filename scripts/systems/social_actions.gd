class_name SocialActions
extends RefCounted
## Special social actions plus gossip/rumors and group effects.

# ------------------------------------------------------------------ special actions
static func _act(act: String, arg: float, a, t, tier: String, iid: String) -> void:
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	if act in ["ask_out", "date", "make_official", "rekindle", "confess", "first_kiss"] and not RomanceRules.allowed(aid, tid):
		return
	match act:
		"argue":
			SocialConflict.escalate(aid, tid, arg)
		"maybe_argue":
			if SysUtil.rng.randf() < argue_probability(aid, tid, arg):
				SocialConflict.escalate(aid, tid, float(SocialDynamics.cfg().get("arguments", {}).get("maybe", {}).get("amount", 12)))
		"soothe":
			for x in [[aid, tid], [tid, aid]]:
				RelationshipRomance.add_tension(x[0], x[1], -arg)
			for bid in ["fuming", "offended", "annoyed", "furious"]:
				if t.has_buff(bid) and SysUtil.rng.randf() < 0.5:
					t.remove_buff(bid)
			SocialConflict._check_resolved(aid, tid, "soothe")
		"soothe_self":
			for bid2 in ["anxious_jitters", "embarrassed", "rejected", "guilty_pang", "heartbroken"]:
				if a.has_buff(bid2) and SysUtil.rng.randf() < 0.6:
					a.remove_buff(bid2)
			a.add_to_stat("social", 6.0)
		"forgive":
			SocialConflict._check_resolved(aid, tid, "forgive")
		"makeup":
			_clear_anger(a, t)
			SocialConflict._check_resolved(aid, tid, "makeup")
		"apology":
			_clear_anger(a, t)
			a.remove_buff("guilty_pang")
			RelationshipService.on_apologize(aid, tid)
			SocialConflict._check_resolved(aid, tid, "apology")
		"storm":
			Conversation.leave(aid)
			a.clear_queue()
			t.remember("folk:%d" % aid, -0.2)
			SysUtil.game_event("stormed_off", {"folk_id": aid, "target_id": tid})
		"ask_out":
			if tier == "great" or tier == "good":
				if not RelationshipRomance.exclusive_partners(aid).has(tid):
					RelationshipRomance.start_dating(aid, tid)
					SocialDynamics._count("dates", 0)
					SysUtil.game_event("date_accepted", {"folk_id": aid, "target_id": tid})
		"date":
			if arg >= 0.0:
				var p: Dictionary = RelationshipService._pair(aid, tid)
				p["dates"] = int(p.get("dates", 0)) + 1
				SocialDynamics._count("dates")
				SysUtil.game_event("date_completed", {"folk_id": aid, "target_id": tid, "quality": tier, "dates": int(p["dates"])})
				Emotions.imprint_pair(a, t, 0.35 if tier in ["good", "great"] else 0.1, "date", "a date")
		"make_official":
			if tier == "great" or tier == "good":
				var pp: Dictionary = RelationshipService._pair(aid, tid)
				var fl: Dictionary = pp["flags"]
				if fl.get("dating", false):
					RelationshipBits.set_flag(aid, tid, "sweetheart")
				elif fl.get("sweetheart", false):
					var ro: float = minf(RelationshipService.value(aid, tid, "romance"), RelationshipService.value(tid, aid, "romance"))
					var fr: float = minf(RelationshipService.value(aid, tid, "friendship"), RelationshipService.value(tid, aid, "friendship"))
					if ro >= 60.0 and fr >= 40.0:
						RelationshipBits.set_flag(aid, tid, "partner")
					else:
						SysUtil.notify("%s and %s are not quite ready for that yet." % [a.name, t.name], "info")
		"breakup":
			if RelationshipRomance.breakup(aid, tid, "breakup", arg):
				SocialDynamics._count("breakups")
		"rekindle":
			if tier == "great" or tier == "good":
				RelationshipBits.set_flag(aid, tid, "ex", false)
				RelationshipRomance.start_dating(aid, tid)
		"confess":
			var cp: Dictionary = RelationshipService._pair(aid, tid)
			cp["confessed"] = aid
			if arg > 0.0:
				SysUtil.game_event("feelings_shared", {"folk_id": aid, "target_id": tid})
		"first_kiss":
			var kp: Dictionary = RelationshipService._pair(aid, tid)
			if not bool(kp.get("first_kiss", false)):
				kp["first_kiss"] = true
				var rc: Dictionary = SocialDynamics.cfg().get("romance", {})
				Emotions.imprint_pair(a, t, float(rc.get("first_kiss_memory", 0.5)), "first_kiss", "your first kiss")
				SysUtil.game_event("first_kiss", {"folk_id": aid, "target_id": tid})
		"confront":
			SocialConflict._confront(a, t, tier)
		"share_secret":
			var sec: Dictionary = RelationshipKnowledge.secret_for_sharing(aid, tid)
			if not sec.is_empty() and arg > 0.0:
				RelationshipKnowledge.learn_secret(tid, aid, int(sec["id"]))
				SysUtil.game_event("secret_shared", {"folk_id": aid, "target_id": tid, "secret": int(sec["id"])})
		"gossip":
			if arg > 0.0:
				_gossip(aid, tid, tier, false, 1.0)
		"spread_rumor":
			_rumor(aid, tid, tier, arg)
		"group_boost":
			_group_boost(aid, arg)
		"toast":
			_toast(aid, arg)

static func argue_probability(a: int, t: int, base: float) -> float:
	var am: Dictionary = SocialDynamics.cfg().get("arguments", {}).get("maybe", {})
	var compat: float = RelationshipBits.compatibility(a, t)
	var mod: float = 0.6 + maxf(-compat, 0.0) * 1.0 + (0.35 if (SocialDynamics.has_t(a, "hot_headed") or SocialDynamics.has_t(t, "hot_headed")) else 0.0)
	mod += (RelationshipService.value(t, a, "tension") + RelationshipService.value(a, t, "tension")) * 0.005
	mod *= sqrt(SocialDynamics.trait_mult(a, "arg_mult", 1.0) * SocialDynamics.trait_mult(t, "arg_mult", 1.0))
	return clampf(base * mod, 0.0, 0.95) if base > 0.0 else float(am.get("base", 0.12)) * mod

static func _clear_anger(a, t) -> void:
	for f in [a, t]:
		for bid in ["fuming", "furious", "offended", "annoyed"]:
			if f.has_buff(bid):
				f.remove_buff(bid)

# ------------------------------------------------------------------ gossip / rumors
static func _gossip(a: int, t: int, tier: String, rumor: bool, strength: float) -> void:
	if DeadPools.any_dead([a, t]):
		return
	var gc: Dictionary = SocialDynamics.cfg().get("gossip", {})
	var pick: Dictionary = {}
	var items: Array = RelationshipKnowledge.gossip_for(a)
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if int(it["about"]) != t and int(it.get("other", -1)) != t and not (it["told"] as Array).has(t):
			pick = it
			break
	if pick.is_empty():
		return
	(pick["told"] as Array).append(t)
	var about: int = int(pick["about"])
	var sev: float = 0.3
	if int(pick.get("sid", -1)) >= 0:
		for s in RelationshipKnowledge.ensure_secrets(about):
			if int(s["id"]) == int(pick["sid"]):
				sev = float(s["severity"])
	var honest := SocialDynamics.has_t(t, "honest")
	var gossipy := SocialDynamics.has_t(t, "gossip")
	SocialDynamics._count("gossip")
	if tier == "bad":
		RelationshipService.add_value(t, a, "trust", -3.0)      # they disapprove of gossip
		return
	var closeness: float = clampf(RelationshipService.value(t, about, "friendship") / 100.0, 0.0, 1.0)
	RelationshipKnowledge.add_gossip(t, about, str(pick["text"]), str(pick["kind"]), int(pick.get("sid", -1)), a)
	if int(pick.get("sid", -1)) >= 0:
		RelationshipKnowledge.learn_secret(t, about, int(pick["sid"]))
	RelationshipService.add_value(t, about, "friendship", -float(gc.get("subject_friendship_loss", 4)) * sev * (1.0 - closeness * 0.5))
	RelationshipKnowledge.add_reputation(about, -float(gc.get("subject_reputation_loss", 3)) * sev * strength)
	if honest:
		RelationshipService.add_value(t, a, "trust", -4.0)
	else:
		RelationshipService.add_value(t, a, "trust", float(gc.get("trust_gain_if_likes", 1.0)))
	var p: float = float(gc.get("backfire_base", 0.15)) + float(gc.get("backfire_closeness", 0.25)) * closeness
	if honest:
		p += float(gc.get("honest_bonus", 0.2))
	if gossipy:
		p += float(gc.get("gossip_trait_bonus", -0.1))
	if rumor:
		p = maxf(p, float(gc.get("rumor_backfire", 0.35)))
	p = clampf(p, 0.02, 0.9)
	SysUtil.game_event("gossip_spread", {"folk_id": a, "target_id": t, "about": about})
	if SysUtil.rng.randf() < p:
		gossip_backfire(a, t, about, rumor)

## The subject of the gossip finds out who spread it.
static func gossip_backfire(a: int, listener: int, subject: int, rumor: bool = false) -> void:
	if DeadPools.any_dead([a, listener, subject]):
		return
	var gc: Dictionary = SocialDynamics.cfg().get("gossip", {})
	var mult: float = 1.5 if rumor else 1.0
	RelationshipService.add_value(subject, a, "trust", -float(gc.get("trust_loss", 30)) * mult)
	RelationshipService.add_value(subject, a, "friendship", -float(gc.get("friendship_loss", 12)) * mult)
	RelationshipRomance.add_tension(subject, a, float(gc.get("tension", 25)) * mult)
	RelationshipKnowledge.add_reputation(a, -float(gc.get("reputation_loss", 8)) * mult)
	SocialDynamics._count("backfires")
	var fa = SysUtil.folk(a)
	var fs = SysUtil.folk(subject)
	if fa != null:
		fa.add_buff("guilty_pang")
		fa.add_buff("reputation_smear")
	if fs != null:
		fs.add_buff("offended")
	RelNotify.say([subject, a], "%s found out that %s was gossiping about them!" % [SysUtil.folk_name(subject), SysUtil.folk_name(a)], "warn")
	SysUtil.game_event("gossip_backfired", {"folk_id": a, "target_id": listener, "about": subject})

static func _rumor(a: int, t: int, tier: String, strength: float) -> void:
	var gc: Dictionary = SocialDynamics.cfg().get("gossip", {})
	var best := -1
	var best_v := -9999.0
	for o in RelationshipBits.all_known(a):
		if int(o) == t:
			continue
		var v: float = RelationshipRomance.tension(a, int(o)) - RelationshipService.value(a, int(o), "friendship") * 0.3
		if v > best_v:
			best_v = v
			best = int(o)
	if best < 0:
		return
	RelationshipKnowledge.add_gossip(t, best, "%s can't be trusted" % SysUtil.folk_name(best), "rumor", -1, a)
	RelationshipService.add_value(t, best, "friendship", -2.0 * strength)
	RelationshipKnowledge.add_reputation(best, -float(gc.get("rumor_reputation_loss", 7)) * strength)
	SocialDynamics._count("gossip")
	SysUtil.game_event("rumor_spread", {"folk_id": a, "target_id": t, "about": best})
	var p: float = float(gc.get("rumor_backfire", 0.35)) + (float(gc.get("honest_bonus", 0.2)) if SocialDynamics.has_t(t, "honest") else 0.0)
	if tier == "bad":
		p = 1.0
	if SysUtil.rng.randf() < p:
		gossip_backfire(a, t, best, true)

# ------------------------------------------------------------------ group effects
static func _group_boost(actor: int, strength: float) -> void:
	var mem: Array = Conversation.members_of(actor)
	for m in mem:
		if int(m) == actor:
			continue
		RelationshipService.add_both(actor, int(m), "friendship", 1.0 * strength)
		var f = SysUtil.folk(int(m))
		if f != null:
			f.add_to_stat("social", 4.0 * strength)
			f.add_to_stat("fun", 2.0 * strength)
	var c: Dictionary = Conversation.circle_of(actor)
	if not c.is_empty():
		c["score"] = float(c["score"]) + 1.5 * strength * mem.size()
	SysUtil.game_event("group_boost", {"folk_id": actor, "size": mem.size()})

static func _toast(actor: int, strength: float) -> void:
	var mem: Array = Conversation.members_of(actor)
	for i in mem.size():
		var f = SysUtil.folk(int(mem[i]))
		if f != null:
			f.add_to_stat("fun", 8.0 * strength)
			if SysUtil.rng.randf() < 0.6 * strength:
				f.add_buff("cheered_up")
		for j in range(i + 1, mem.size()):
			RelationshipService.add_both(int(mem[i]), int(mem[j]), "friendship", 0.4 * strength)
	var c: Dictionary = Conversation.circle_of(actor)
	if not c.is_empty():
		c["score"] = float(c["score"]) + 3.0 * strength
	SysUtil.game_event("toast", {"folk_id": actor, "size": mem.size()})
