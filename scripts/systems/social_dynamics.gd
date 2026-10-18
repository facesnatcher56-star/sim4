class_name SocialDynamics
extends RefCounted
## The social engine behind data-driven interactions that carry a `"social"` block (see data/interactions.json).
##
## social block:  {base, mode: "full"|"extra", topical, requires:[...], conv, intimate, spark, thr:[...], outcomes:{great,good,meh,bad}}
## An outcome (fx) is a small dictionary:
##   fr / ro / tr / te   relationship deltas (friendship, romance, trust, tension) as felt by the TARGET; the actor feels a share
##   buff / tbuff (+ p)  buff ids for actor / target, applied with probability p (default 1)
##   say / tsay          thought balloons          reveal / reveal_self   [trait|career|aspiration|interest]  (getting to know)
##   act (+ arg)         special action: argue, maybe_argue, soothe, makeup, forgive, apology, ask_out, date, make_official, breakup,
##                       rekindle, confess, first_kiss, share_secret, gossip, spread_rumor, group_boost, toast, storm, confront...
## `full` interactions rely entirely on these outcomes; `extra` ones (chat, tell_joke, flirt, ...) keep their classic Loot and
## only add the nuance (topics, knowledge, trust, arguments, ...).
## Success = base + compatibility + charisma + warmth/grudge + friendship/trust/tension + spark + reputation + topic + mood + traits + noise.
## Everything here is static state so UI/tests can call it directly; hooks come from RelationshipService and SocialContent.

const TIER_ORDER := ["great", "good", "meh", "bad"]

static var goals: Dictionary = {}          # folk_id -> {kind, target, text}
static var gatherings: Array = []          # active gatherings
static var recent_gatherings: Array = []   # finished ones (last 8), for group_score() / UI
static var outcome_log: Array = []         # recent resolved interactions (debug / tests)
static var stats: Dictionary = {}          # counters
static var last_social: Dictionary = {}    # folk_id -> game minute of their last social (for the "needs contact" nudge)
static var _next_gathering: int = 1

static func reset() -> void:
	goals.clear()
	gatherings.clear()
	recent_gatherings.clear()
	last_social.clear()
	outcome_log.clear()
	stats = {"arguments": 0, "tiers": {}, "gossip": 0, "backfires": 0, "dates": 0, "breakups": 0, "cheats": 0, "gatherings": 0}
	_next_gathering = 1

static func cfg() -> Dictionary:
	return SysUtil.table("social")

static func _count(key: String, by: int = 1) -> void:
	if stats.is_empty():
		reset()
	stats[key] = int(stats.get(key, 0)) + by

# ------------------------------------------------------------------ trait helpers
## Product of traits' social[key] values (e.g. jealousy_mult, arg_mult, neg_mult, pos_mult).
static func trait_mult(fid: int, key: String, default_v: float = 1.0) -> float:
	var m := default_v
	for t in RelationshipService.traits_of(fid):
		var sd: Dictionary = SimEnv.data().trait_def(str(t)).get("social", {})
		if sd.has(key):
			m *= float(sd[key])
	return m

## Sum of traits' social[group][cat] + social[group]["all"] (e.g. give / receive modifiers).
static func trait_add(fid: int, group: String, cat: String) -> float:
	var s := 0.0
	for t in RelationshipService.traits_of(fid):
		var g: Dictionary = SimEnv.data().trait_def(str(t)).get("social", {}).get(group, {})
		s += float(g.get(cat, 0.0)) + float(g.get("all", 0.0))
	return s

static func has_t(fid: int, tr: String) -> bool:
	return RelationshipService.traits_of(fid).has(tr)

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
	var oc: Dictionary = cfg().get("outcomes", {})
	var w: Dictionary = oc.get("weights", {})
	var cat: String = str(d.get("category", "friendly"))
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	var parts: Dictionary = {}
	parts["base"] = float(sd.get("base", 0.5))
	var compat: float = RelationshipService.compatibility(aid, tid)
	parts["compat"] = compat * float(w.get("compat", 0.25))
	parts["charisma"] = float(a.skill_level("charisma")) * float(w.get("charisma", 0.03))
	parts["history"] = RelationshipService.warmth(tid, aid) * float(w.get("warmth", 0.15)) - RelationshipService.grudge(tid, aid) * float(w.get("grudge", 0.25))
	parts["friendship"] = RelationshipService.value(tid, aid, "friendship") * float(w.get("friendship", 0.002))
	parts["trust"] = RelationshipService.value(tid, aid, "trust") * float(w.get("trust", 0.003))
	var ten: float = RelationshipService.value(tid, aid, "tension") * float(w.get("tension", 0.004))
	var tags: Array = d.get("tags", [])
	parts["tension"] = ten if cat == "mean" else (0.0 if tags.has("reconcile") else -ten)
	if cat == "romantic" or bool(sd.get("spark", false)):
		parts["spark"] = (RelationshipService.spark(aid, tid) - 0.5) * float(w.get("spark", 0.4))
	parts["reputation"] = RelationshipService.reputation(aid) * float(w.get("reputation", 0.0015))
	if not teff.is_empty():
		parts["topic"] = float(teff.get("bonus", 0.0))
	var cap: float = float(w.get("mood_cap", 0.25))
	parts["mood"] = clampf(mood_add(a, "give", cat) + mood_add(t, "receive", cat), -cap, cap)
	parts["traits"] = trait_add(aid, "give", cat) + trait_add(tid, "receive", cat)
	var total := 0.0
	for k in parts:
		total += float(parts[k])
	if with_noise:
		var n: float = float(oc.get("noise", 0.18))
		parts["noise"] = (SysUtil.rng.randf() * 2.0 - 1.0) * n
		total += float(parts["noise"])
	return {"score": total, "parts": parts}

static func tier_for(score: float, sd: Dictionary) -> String:
	var th: Dictionary = cfg().get("outcomes", {}).get("thresholds", {"great": 0.8, "good": 0.5, "meh": 0.28})
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
				if not RelationshipService.exclusive_partners(actor).has(target):
					return "You need to be together first."
			"not_bonded":
				if RelationshipService.exclusive_partners(actor).has(target):
					return "You are already together."
			"not_married":
				if RelationshipService.has_flag(actor, target, "spouse"):
					return "Spouses have to divorce instead."
			"knows_career":
				if not RelationshipService.knows_career(actor, target):
					return "You don't know their job yet."
			"knows_aspiration":
				if not RelationshipService.knows_aspiration(actor, target):
					return "You don't know their dreams yet."
			"knows_trait":
				if RelationshipService.known_traits(actor, target).is_empty():
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

# ------------------------------------------------------------------ resolution
static func resolve(actor_id: int, target_id: int, iid: String, d: Dictionary) -> Dictionary:
	var sd: Dictionary = d.get("social", {})
	if sd.is_empty():
		return {}
	var a = SysUtil.folk(actor_id)
	var t = SysUtil.folk(target_id)
	if a == null or t == null:
		return {}
	var mode: String = str(sd.get("mode", "full"))
	var cat: String = str(d.get("category", "friendly"))
	var topic := ""
	var teff: Dictionary = {}
	if bool(sd.get("topical", false)):
		topic = str(Conversation.active_topic.get(actor_id, ""))
		if topic == "":
			topic = Conversation.pick_topic(actor_id, target_id)
		teff = Conversation.topic_effect(actor_id, target_id, topic)
	var req_fail := check_requires(actor_id, target_id, sd.get("requires", []))
	var sc := success_score(a, t, iid, d, sd, teff)
	var tier: String = "meh" if req_fail != "" else tier_for(float(sc["score"]), sd)
	var fx: Dictionary = {} if req_fail != "" else fx_for(sd, tier)
	var label: String = str(fx.get("label", "")) if req_fail == "" else "Nothing came of it"
	var res: Dictionary = {"tier": tier, "label": label, "score": snappedf(float(sc["score"]), 0.001), "mode": mode, "topic": topic, "cat": cat,
		"sentiment": 0.0, "interaction": iid, "actor": actor_id, "target": target_id, "parts": sc["parts"]}
	# ---- relationship changes
	var fr: float = float(fx.get("fr", 0.0))
	var ro: float = float(fx.get("ro", 0.0))
	var tr: float = float(fx.get("tr", 0.0))
	var te: float = float(fx.get("te", 0.0))
	if mode == "extra":
		var base: Dictionary = _classic_deltas(d)
		if not teff.is_empty():
			fr += float(base.get("friendship", 0.0)) * (float(teff["mult"]) - 1.0)
		if bool(sd.get("spark", false)):
			ro += float(base.get("romance", 0.0)) * (RelationshipService.spark(actor_id, target_id) - 0.5) * 0.8
		res["sentiment_adjust"] = clampf((fr + ro) / 8.0, -0.3, 0.3)
	elif not teff.is_empty() and fr > 0.0:
		fr *= float(teff["mult"])
	_rel(actor_id, target_id, "friendship", fr)
	_rel(actor_id, target_id, "romance", ro)
	_rel(actor_id, target_id, "trust", tr)
	_tense(actor_id, target_id, te)
	res["fr"] = fr
	res["ro"] = ro
	res["tr"] = tr
	res["te"] = te
	if mode == "full":
		res["sentiment"] = clampf(float(fx.get("sent", (fr + ro + tr * 0.5 - maxf(te, 0.0) * 0.15) / 6.0)), -1.0, 1.0)
	# ---- buffs / thoughts
	var p: float = float(fx.get("p", 1.0))
	if fx.has("buff") and SysUtil.rng.randf() <= p:
		a.add_buff(str(fx["buff"]))
	if fx.has("tbuff") and SysUtil.rng.randf() <= p:
		t.add_buff(str(fx["tbuff"]))
	if fx.has("say"):
		SimEnv.emit("thought", actor_id, str(fx["say"]))
	elif label != "" and (tier == "great" or tier == "bad"):
		SimEnv.emit("thought", actor_id, label + ("!" if tier == "great" else "..."))
	if fx.has("tsay"):
		SimEnv.emit("thought", target_id, str(fx["tsay"]))
	# ---- getting to know
	for k in fx.get("reveal", []):
		RelationshipService.reveal(actor_id, target_id, str(k), topic)
	for k2 in fx.get("reveal_self", []):
		RelationshipService.reveal(target_id, actor_id, str(k2))
	if tier in ["great", "good"] and cat in ["friendly", "funny", "deep", "group"]:
		_passive_reveal(actor_id, target_id)
	if topic != "" and tier in ["great", "good"]:
		RelationshipService.note_topic(actor_id, target_id, topic)
	# ---- special actions
	if fx.has("act"):
		for act in (fx["act"] if fx["act"] is Array else [fx["act"]]):
			_act(str(act), float(fx.get("arg", 1.0)), a, t, tier, iid)
	_count_tier(tier)
	outcome_log.append({"actor": actor_id, "target": target_id, "iid": iid, "tier": tier, "label": label, "score": res["score"], "day": SysUtil.day()})
	if outcome_log.size() > 300:
		outcome_log = outcome_log.slice(outcome_log.size() - 300)
	return res

static func _count_tier(tier: String) -> void:
	if stats.is_empty():
		reset()
	var tiers: Dictionary = stats["tiers"]
	tiers[tier] = int(tiers.get(tier, 0)) + 1

static func _classic_deltas(d: Dictionary) -> Dictionary:
	var out := {"friendship": 0.0, "romance": 0.0}
	for e in d.get("on_finish", []):
		if e is Dictionary and (e as Dictionary).has("relationship_add"):
			var ra: Array = e["relationship_add"]
			out[str(ra[0])] = float(out.get(str(ra[0]), 0.0)) + float(ra[1]) * float(e.get("chance", 1.0))
	return out

static func _passive_reveal(a: int, t: int) -> void:
	var kc: Dictionary = cfg().get("knowledge", {})
	var p: float = float(kc.get("passive_chance", 0.22)) + maxf(RelationshipService.value(t, a, "friendship"), 0.0) * float(kc.get("friendship_scale", 0.004))
	if SysUtil.rng.randf() < p:
		RelationshipService.reveal(a, t, "trait")
	if SysUtil.rng.randf() < p:
		RelationshipService.reveal(t, a, "trait")

## Directional relationship change: `delta` is what the target feels about the actor; the actor feels a share of it.
static func _rel(actor: int, target: int, track: String, delta: float) -> void:
	if absf(delta) < 0.001:
		return
	if delta > 0.0:
		var m: float = RelationshipService.reaction_factor(target, actor) * trait_mult(target, "pos_mult", 1.0)
		RelationshipService.add_value(target, actor, track, delta * m)
		RelationshipService.add_value(actor, target, track, delta * 0.8 * trait_mult(actor, "pos_mult", 1.0))
	else:
		var amp: float = 1.0 + RelationshipService.grudge(target, actor) * float(cfg().get("history", {}).get("grudge_amplify", 0.5))
		RelationshipService.add_value(target, actor, track, delta * trait_mult(target, "neg_mult", 1.0) * amp)
		RelationshipService.add_value(actor, target, track, delta * 0.35 * trait_mult(actor, "neg_mult", 1.0))

static func _tense(actor: int, target: int, te: float) -> void:
	if absf(te) < 0.001:
		return
	var tc: Dictionary = cfg().get("tension", {})
	if te > 0.0:
		RelationshipService.add_tension(target, actor, te * trait_mult(target, "neg_mult", 1.0))
		RelationshipService.add_tension(actor, target, te * 0.6)
		var ft = SysUtil.folk(target)
		if ft != null and RelationshipService.tension(target, actor) >= float(tc.get("avoid_threshold", 25)):
			ft.remember("folk:%d" % actor, float(tc.get("avoid_memory", -0.25)))
	else:
		RelationshipService.add_tension(target, actor, te)
		RelationshipService.add_tension(actor, target, te)

# ------------------------------------------------------------------ after-the-fact hooks
## Called by RelationshipService after an interaction's history entry was written.
static func after_social(actor: int, target: int, iid: String, d: Dictionary, res: Dictionary) -> void:
	var a = SysUtil.folk(actor)
	var t = SysUtil.folk(target)
	if a == null or t == null:
		return
	if (d.get("tags", []) as Array).has("social"):
		last_social[actor] = SysUtil.now()
		last_social[target] = SysUtil.now()
		a.remove_buff("needs_contact")
		t.remove_buff("needs_contact")
		Emotions.add_hidden(a, "socialized_recently")
		Emotions.add_hidden(t, "socialized_recently")
		if a.has_buff("socialized_recently"):
			a.add_buff("socialized_recently")   # refresh the timer
		if t.has_buff("socialized_recently"):
			t.add_buff("socialized_recently")
	var sd: Dictionary = d.get("social", {})
	var tier: String = str(res.get("tier", "meh"))
	if (bool(sd.get("intimate", false)) or iid == "kiss") and tier != "bad":
		cheat_check(actor, target)
	_witness(actor, target, iid, d)
	refresh_markers(a)
	refresh_markers(t)

static func _witness(actor: int, target: int, iid: String, d: Dictionary) -> void:
	var kinds := {"kiss": "kissing", "sneak_kiss": "stealing a kiss", "cuddle": "cuddling", "flirt": "flirting", "argue": "arguing",
		"yell_at": "shouting at each other", "break_up": "breaking up", "hold_hands": "holding hands", "wink": "making eyes at each other"}
	if not kinds.has(iid):
		return
	var gc: Dictionary = cfg().get("gossip", {})
	var a = SysUtil.folk(actor)
	if a == null:
		return
	for f in WorldIface.all_folk():
		if int(f.id) == actor or int(f.id) == target or SysUtil.is_away(f):
			continue
		if Vector2(f.tile - a.tile).length() > float(gc.get("witness_range", 9)):
			continue
		if SysUtil.rng.randf() < 0.5:
			RelationshipService.add_gossip(int(f.id), actor, "%s and %s were %s" % [SysUtil.folk_name(actor), SysUtil.folk_name(target), kinds[iid]], "observed", -1, target)

# ------------------------------------------------------------------ special actions
static func _act(act: String, arg: float, a, t, tier: String, iid: String) -> void:
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	match act:
		"argue":
			escalate(aid, tid, arg)
		"maybe_argue":
			if SysUtil.rng.randf() < argue_probability(aid, tid, arg):
				escalate(aid, tid, float(cfg().get("arguments", {}).get("maybe", {}).get("amount", 12)))
		"soothe":
			for x in [[aid, tid], [tid, aid]]:
				RelationshipService.add_tension(x[0], x[1], -arg)
			for bid in ["fuming", "offended", "annoyed", "furious"]:
				if t.has_buff(bid) and SysUtil.rng.randf() < 0.5:
					t.remove_buff(bid)
			_check_resolved(aid, tid, "soothe")
		"soothe_self":
			for bid2 in ["anxious_jitters", "embarrassed", "rejected", "guilty_pang", "heartbroken"]:
				if a.has_buff(bid2) and SysUtil.rng.randf() < 0.6:
					a.remove_buff(bid2)
			a.add_to_stat("social", 6.0)
		"forgive":
			_check_resolved(aid, tid, "forgive")
		"makeup":
			_clear_anger(a, t)
			_check_resolved(aid, tid, "makeup")
		"apology":
			_clear_anger(a, t)
			a.remove_buff("guilty_pang")
			RelationshipService.on_apologize(aid, tid)
			_check_resolved(aid, tid, "apology")
		"storm":
			Conversation.leave(aid)
			a.clear_queue()
			t.remember("folk:%d" % aid, -0.2)
			SysUtil.game_event("stormed_off", {"folk_id": aid, "target_id": tid})
		"ask_out":
			if tier == "great" or tier == "good":
				if not RelationshipService.exclusive_partners(aid).has(tid):
					RelationshipService.start_dating(aid, tid)
					_count("dates", 0)
					SysUtil.game_event("date_accepted", {"folk_id": aid, "target_id": tid})
		"date":
			if arg >= 0.0:
				var p: Dictionary = RelationshipService._pair(aid, tid)
				p["dates"] = int(p.get("dates", 0)) + 1
				_count("dates")
				SysUtil.game_event("date_completed", {"folk_id": aid, "target_id": tid, "quality": tier, "dates": int(p["dates"])})
				Emotions.imprint_pair(a, t, 0.35 if tier in ["good", "great"] else 0.1, "date", "a date")
		"make_official":
			if tier == "great" or tier == "good":
				var pp: Dictionary = RelationshipService._pair(aid, tid)
				var fl: Dictionary = pp["flags"]
				if fl.get("dating", false):
					RelationshipService.set_flag(aid, tid, "sweetheart")
				elif fl.get("sweetheart", false):
					var ro: float = minf(RelationshipService.value(aid, tid, "romance"), RelationshipService.value(tid, aid, "romance"))
					var fr: float = minf(RelationshipService.value(aid, tid, "friendship"), RelationshipService.value(tid, aid, "friendship"))
					if ro >= 60.0 and fr >= 40.0:
						RelationshipService.set_flag(aid, tid, "partner")
					else:
						SysUtil.notify("%s and %s are not quite ready for that yet." % [a.name, t.name], "info")
		"breakup":
			if RelationshipService.breakup(aid, tid, "breakup", arg):
				_count("breakups")
		"rekindle":
			if tier == "great" or tier == "good":
				RelationshipService.set_flag(aid, tid, "ex", false)
				RelationshipService.start_dating(aid, tid)
		"confess":
			var cp: Dictionary = RelationshipService._pair(aid, tid)
			cp["confessed"] = aid
			if arg > 0.0:
				SysUtil.game_event("feelings_shared", {"folk_id": aid, "target_id": tid})
		"first_kiss":
			var kp: Dictionary = RelationshipService._pair(aid, tid)
			if not bool(kp.get("first_kiss", false)):
				kp["first_kiss"] = true
				var rc: Dictionary = cfg().get("romance", {})
				Emotions.imprint_pair(a, t, float(rc.get("first_kiss_memory", 0.5)), "first_kiss", "your first kiss")
				SysUtil.game_event("first_kiss", {"folk_id": aid, "target_id": tid})
		"confront":
			_confront(a, t, tier)
		"share_secret":
			var sec: Dictionary = RelationshipService.secret_for_sharing(aid, tid)
			if not sec.is_empty() and arg > 0.0:
				RelationshipService.learn_secret(tid, aid, int(sec["id"]))
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
	var am: Dictionary = cfg().get("arguments", {}).get("maybe", {})
	var compat: float = RelationshipService.compatibility(a, t)
	var mod: float = 0.6 + maxf(-compat, 0.0) * 1.0 + (0.35 if (has_t(a, "hot_headed") or has_t(t, "hot_headed")) else 0.0)
	mod += (RelationshipService.value(t, a, "tension") + RelationshipService.value(a, t, "tension")) * 0.005
	mod *= sqrt(trait_mult(a, "arg_mult", 1.0) * trait_mult(t, "arg_mult", 1.0))
	return clampf(base * mod, 0.0, 0.95) if base > 0.0 else float(am.get("base", 0.12)) * mod

static func _clear_anger(a, t) -> void:
	for f in [a, t]:
		for bid in ["fuming", "furious", "offended", "annoyed"]:
			if f.has_buff(bid):
				f.remove_buff(bid)

# ------------------------------------------------------------------ arguments
static func arg_level(a: int, b: int) -> int:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return 0
	var ar: Dictionary = p.get("arg", {})
	if SysUtil.now() - int(ar.get("t", -99999)) > int(cfg().get("arguments", {}).get("window_min", 90)):
		return 0
	return int(ar.get("level", 0))

## An argument flares up (or escalates when it follows another within the window).
static func escalate(a: int, b: int, amount: float) -> int:
	var ac: Dictionary = cfg().get("arguments", {})
	var p: Dictionary = RelationshipService._pair(a, b)
	var ar: Dictionary = RelationshipService._sub(p, "arg", {"level": 0, "t": -99999, "count": 0})
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
	if has_t(a, "hot_headed") or has_t(b, "hot_headed"):
		mult *= float(ac.get("hot_headed_mult", 1.3))
	var amt: float = amount * mult
	RelationshipService.add_tension(a, b, amt)
	RelationshipService.add_tension(b, a, amt)
	_count("arguments")
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	var tc: Dictionary = cfg().get("tension", {})
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
		if f2 != null and RelationshipService.tension(int(f2.id), int(pair[1])) >= float(tc.get("avoid_threshold", 25)):
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
	var ac: Dictionary = cfg().get("arguments", {})
	var worst: float = maxf(RelationshipService.tension(a, b), RelationshipService.tension(b, a))
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return false
	if worst > float(ac.get("resolve_below", 10)) or not bool(p.get("heated", false)):
		return false
	p.erase("heated")
	var ar: Dictionary = RelationshipService._sub(p, "arg", {"level": 0, "t": -99999, "count": 0})
	ar["level"] = 0
	RelationshipService.add_both(a, b, "friendship", float(ac.get("resolved_bonus_friendship", 3)))
	RelationshipService.add_both(a, b, "trust", float(ac.get("resolved_bonus_trust", 3)))
	for f in [SysUtil.folk(a), SysUtil.folk(b)]:
		if f != null:
			f.add_buff(str(ac.get("resolved_buff", "makeup_glow")))
	SysUtil.notify("%s and %s made up." % [SysUtil.folk_name(a), SysUtil.folk_name(b)], "relationship")
	SysUtil.game_event("argument_resolved", {"folk_id": a, "target_id": b, "how": how})
	return true

## Public: lower tension between a pair (used by apologize events, tests).
static func reconcile(a: int, b: int, amount: float, how: String = "apology") -> bool:
	RelationshipService.add_tension(a, b, -amount)
	RelationshipService.add_tension(b, a, -amount)
	return _check_resolved(a, b, how)

static func _confront(a, t, tier: String) -> void:
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	if tier == "great" or tier == "good":
		RelationshipService.add_tension(aid, tid, -20.0)
		RelationshipService.add_tension(tid, aid, -10.0)
		RelationshipService.add_value(aid, tid, "trust", 6.0)
		a.remove_buff("cheated_on")
		t.add_buff("guilty_pang")
	elif tier == "bad":
		if RelationshipService.breakup(aid, tid, "cheating", 1.2):
			_count("breakups")
		a.remove_buff("cheated_on")

# ------------------------------------------------------------------ cheating
static func cheat_check(a: int, b: int) -> void:
	for pr in [[a, b], [b, a]]:
		var x: int = pr[0]
		var o: int = pr[1]
		for victim in RelationshipService.exclusive_partners(x):
			if int(victim) == o:
				continue
			var fv = SysUtil.folk(int(victim))
			var fx = SysUtil.folk(x)
			var rc: Dictionary = cfg().get("romance", {}).get("cheat", {})
			_count("cheats")
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
	var rc: Dictionary = cfg().get("romance", {}).get("cheat", {})
	RelationshipService.add_value(victim, cheater, "trust", -float(rc.get("trust_loss", 45)))
	RelationshipService.add_value(victim, cheater, "romance", -float(rc.get("romance_loss", 35)))
	RelationshipService.add_value(victim, cheater, "friendship", -float(rc.get("friendship_loss", 10)))
	RelationshipService.add_tension(victim, cheater, float(rc.get("tension", 35)))
	RelationshipService.add_tension(cheater, victim, 15.0)
	RelationshipService.add_history(cheater, victim, "cheated", -1.0, cheater)
	RelationshipService.add_reputation(cheater, float(rc.get("reputation", -6)))
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
	SysUtil.notify("%s found out that %s was cheating with %s!" % [SysUtil.folk_name(victim), SysUtil.folk_name(cheater), SysUtil.folk_name(other)], "bad")
	SysUtil.game_event("cheating_discovered", {"folk_id": victim, "target_id": cheater, "other_id": other})
	var p: float = float(rc.get("auto_breakup", 0.6))
	if has_t(victim, "jealous"):
		p *= 1.3
	if has_t(victim, "forgiving"):
		p *= 0.5
	if has_t(victim, "easygoing"):
		p *= 0.7
	if SysUtil.rng.randf() < p:
		if RelationshipService.breakup(victim, cheater, "cheating", 1.2):
			_count("breakups")

# ------------------------------------------------------------------ gossip / rumors
static func _gossip(a: int, t: int, tier: String, rumor: bool, strength: float) -> void:
	var gc: Dictionary = cfg().get("gossip", {})
	var pick: Dictionary = {}
	var items: Array = RelationshipService.gossip_for(a)
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
		for s in RelationshipService.ensure_secrets(about):
			if int(s["id"]) == int(pick["sid"]):
				sev = float(s["severity"])
	var honest := has_t(t, "honest")
	var gossipy := has_t(t, "gossip")
	_count("gossip")
	if tier == "bad":
		RelationshipService.add_value(t, a, "trust", -3.0)      # they disapprove of gossip
		return
	var closeness: float = clampf(RelationshipService.value(t, about, "friendship") / 100.0, 0.0, 1.0)
	RelationshipService.add_gossip(t, about, str(pick["text"]), str(pick["kind"]), int(pick.get("sid", -1)), a)
	if int(pick.get("sid", -1)) >= 0:
		RelationshipService.learn_secret(t, about, int(pick["sid"]))
	RelationshipService.add_value(t, about, "friendship", -float(gc.get("subject_friendship_loss", 4)) * sev * (1.0 - closeness * 0.5))
	RelationshipService.add_reputation(about, -float(gc.get("subject_reputation_loss", 3)) * sev * strength)
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
	var gc: Dictionary = cfg().get("gossip", {})
	var mult: float = 1.5 if rumor else 1.0
	RelationshipService.add_value(subject, a, "trust", -float(gc.get("trust_loss", 30)) * mult)
	RelationshipService.add_value(subject, a, "friendship", -float(gc.get("friendship_loss", 12)) * mult)
	RelationshipService.add_tension(subject, a, float(gc.get("tension", 25)) * mult)
	RelationshipService.add_reputation(a, -float(gc.get("reputation_loss", 8)) * mult)
	_count("backfires")
	var fa = SysUtil.folk(a)
	var fs = SysUtil.folk(subject)
	if fa != null:
		fa.add_buff("guilty_pang")
		fa.add_buff("reputation_smear")
	if fs != null:
		fs.add_buff("offended")
	SysUtil.notify("%s found out that %s was gossiping about them!" % [SysUtil.folk_name(subject), SysUtil.folk_name(a)], "warn")
	SysUtil.game_event("gossip_backfired", {"folk_id": a, "target_id": listener, "about": subject})

static func _rumor(a: int, t: int, tier: String, strength: float) -> void:
	var gc: Dictionary = cfg().get("gossip", {})
	var best := -1
	var best_v := -9999.0
	for o in RelationshipService.all_known(a):
		if int(o) == t:
			continue
		var v: float = RelationshipService.tension(a, int(o)) - RelationshipService.value(a, int(o), "friendship") * 0.3
		if v > best_v:
			best_v = v
			best = int(o)
	if best < 0:
		return
	RelationshipService.add_gossip(t, best, "%s can't be trusted" % SysUtil.folk_name(best), "rumor", -1, a)
	RelationshipService.add_value(t, best, "friendship", -2.0 * strength)
	RelationshipService.add_reputation(best, -float(gc.get("rumor_reputation_loss", 7)) * strength)
	_count("gossip")
	SysUtil.game_event("rumor_spread", {"folk_id": a, "target_id": t, "about": best})
	var p: float = float(gc.get("rumor_backfire", 0.35)) + (float(gc.get("honest_bonus", 0.2)) if has_t(t, "honest") else 0.0)
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

# ------------------------------------------------------------------ gatherings
## Host invites friends / family on the lot; they walk over and chat, raising a group score used by Story parties.
static func start_gathering(host_id: int) -> Dictionary:
	var gc: Dictionary = cfg().get("gathering", {})
	var host = SysUtil.folk(host_id)
	if host == null:
		return {}
	var cands: Array = []
	for f in WorldIface.all_folk():
		if int(f.id) == host_id or SysUtil.is_away(f) or str(f.age_stage) in ["baby", "toddler"]:
			continue
		var close: float = RelationshipService.value(int(f.id), host_id, "friendship")
		var fam: bool = RelationshipService.has_flag(host_id, int(f.id), "family") or RelationshipService.has_flag(host_id, int(f.id), "partner") or RelationshipService.has_flag(host_id, int(f.id), "spouse")
		if close >= float(gc.get("min_friendship", 12)) or fam:
			cands.append({"f": f, "close": close + (30.0 if fam else 0.0), "fam": fam})
	cands.sort_custom(func(x, y): return float(x["close"]) > float(y["close"]))
	var guests: Array = []
	var fam_n := 0
	for c in cands.slice(0, int(gc.get("max_guests", 5))):
		guests.append(int(c["f"].id))
		if bool(c["fam"]):
			fam_n += 1
	if guests.is_empty():
		SysUtil.notify("%s tried to get everyone together, but nobody could come." % host.name, "info")
		return {}
	var g := {"id": _next_gathering, "host": host_id, "guests": guests, "start": SysUtil.now(), "end": SysUtil.now() + int(gc.get("duration_min", 90)) + 15,
		"score": 0.0, "kind": "family" if fam_n * 2 >= guests.size() else "friends", "done": false}
	_next_gathering += 1
	gatherings.append(g)
	_count("gatherings")
	for gid in guests:
		var gf = SysUtil.folk(int(gid))
		var ir := Interaction.create("chat", gf, host_id, false)
		if ir != null:
			gf.enqueue(ir)
	SysUtil.notify("%s is hosting a %s gathering." % [host.name, g["kind"]], "relationship")
	SysUtil.game_event("gathering_started", {"folk_id": host_id, "guests": guests.duplicate(), "kind": g["kind"], "id": g["id"]})
	return g

static func active_gathering(host_id: int) -> Dictionary:
	for g in gatherings:
		if int(g["host"]) == host_id and not bool(g["done"]):
			return g
	return {}

static func _tick_gatherings() -> void:
	if gatherings.is_empty():
		return
	var gc: Dictionary = cfg().get("gathering", {})
	var now := SysUtil.now()
	for g in gatherings:
		if bool(g["done"]):
			continue
		var host: int = int(g["host"])
		var present := 0
		for gid in g["guests"]:
			if Conversation.same_circle(host, int(gid)):
				present += 1
		if present >= 1:
			g["score"] = float(g["score"]) + float(gc.get("member_score_per_min", 0.2)) * (present + 1)
		if now >= int(g["end"]):
			_finish_gathering(g)
	var keep: Array = []
	for g2 in gatherings:
		if bool(g2["done"]):
			recent_gatherings.append(g2)
			if recent_gatherings.size() > 8:
				recent_gatherings.pop_front()
		else:
			keep.append(g2)
	gatherings = keep

static func _finish_gathering(g: Dictionary) -> void:
	var gc: Dictionary = cfg().get("gathering", {})
	g["done"] = true
	var host: int = int(g["host"])
	var everyone: Array = [host]
	everyone.append_array(g["guests"])
	var part: Array = []
	for pid in everyone:
		if SysUtil.folk(int(pid)) != null and (int(pid) == host or Conversation.same_circle(host, int(pid)) or float(g["score"]) > 4.0):
			part.append(int(pid))
	if part.size() >= int(gc.get("min_members", 3)):
		for i in part.size():
			var f = SysUtil.folk(int(part[i]))
			if f != null:
				f.add_buff(str(gc.get("buff", "group_warmth")))
			for j in range(i + 1, part.size()):
				RelationshipService.add_both(int(part[i]), int(part[j]), "friendship", float(gc.get("friendship_bond", 2.0)))
	var score: float = float(g["score"])
	g["final_score"] = score
	g["participants"] = part
	for sit in Story.situations:
		if (sit["roles"] as Dictionary).has(str(host)) and str(sit["state"]) in ["mingle", "arrive"]:
			sit["score"] = float(sit["score"]) + score * float(gc.get("story_factor", 0.5))
	SysUtil.notify("The %s gathering wraps up. Group score: %d." % [str(g["kind"]), int(round(score))], "relationship")
	SysUtil.game_event("gathering_done", {"folk_id": host, "score": score, "kind": str(g["kind"]), "participants": part.duplicate(), "id": int(g["id"])})

static func group_score(host_id: int) -> float:
	for i in range(gatherings.size() - 1, -1, -1):
		if int(gatherings[i]["host"]) == host_id:
			return float(gatherings[i].get("final_score", gatherings[i]["score"]))
	for j in range(recent_gatherings.size() - 1, -1, -1):
		if int(recent_gatherings[j]["host"]) == host_id:
			return float(recent_gatherings[j].get("final_score", recent_gatherings[j]["score"]))
	return Conversation.group_score(host_id)

static func _karaoke(singer_id: int) -> void:
	var s = SysUtil.folk(singer_id)
	if s == null:
		return
	var sc: float = 0.5 + float(s.skill_level("charisma")) * 0.03 + (0.1 if s.has_trait("musical") else 0.0) + (0.1 if str(s.mood_name) == "confident" else 0.0)
	sc += (SysUtil.rng.randf() * 2.0 - 1.0) * 0.2
	var audience := 0
	for f in WorldIface.all_folk():
		if int(f.id) == singer_id or SysUtil.is_away(f) or Vector2(f.tile - s.tile).length() > 6.0:
			continue
		audience += 1
		f.add_to_stat("fun", 6.0 if sc > 0.4 else 2.0)
		if sc > 0.65:
			f.add_buff("party_buzz")
			RelationshipService.add_value(int(f.id), singer_id, "friendship", 1.0)
	if sc > 0.75:
		s.add_buff("proud_performer")
	elif sc < 0.35:
		s.add_buff("embarrassed")
	SysUtil.game_event("karaoke_done", {"folk_id": singer_id, "audience": audience, "score": sc})

# ------------------------------------------------------------------ markers / goals
static func refresh_markers(f) -> void:
	if f == null:
		return
	var fid: int = int(f.id)
	_set_marker(f, "has_partner", not RelationshipService.exclusive_partners(fid).is_empty())
	var tellable := false
	for it in RelationshipService.gossip_for(fid):
		tellable = true
	_set_marker(f, "has_gossip", tellable)

static func _set_marker(f, buff: String, on: bool) -> void:
	if on:
		Emotions.add_hidden(f, buff)
	elif not on and f.has_buff(buff):
		f.remove_buff(buff)

static func update_goals(f) -> void:
	var gc: Dictionary = cfg().get("goals", {})
	var fid: int = int(f.id)
	# nobody (not even a loner) goes a whole day without any contact: a strong social urge builds up
	var now := SysUtil.now()
	if not last_social.has(fid):
		last_social[fid] = now
	if now - int(last_social[fid]) >= int(gc.get("contact_hours", 14)) * 60 and not f.has_buff("needs_contact"):
		Emotions.add_hidden(f, "needs_contact")
		_nudge_contact(f)
	var kind := ""
	var target := -1
	var text := ""
	# 1) make peace with someone they are tense with
	var worst := 0.0
	var worst_id := -1
	for o in RelationshipService.all_known(fid):
		var tv: float = RelationshipService.tension(fid, int(o))
		if tv > worst and SysUtil.folk(int(o)) != null:
			worst = tv
			worst_id = int(o)
	var willing: bool = not (f.has_trait("grudgeholder") or f.has_trait("stubborn")) or f.has_buff("guilty_pang")
	_set_marker(f, "wants_reconcile", worst >= float(gc.get("reconcile_tension", 22)) and willing)
	if worst >= float(gc.get("reconcile_tension", 22)) and willing:
		kind = "reconcile"
		target = worst_id
		text = "Wants to make peace with %s" % SysUtil.folk_name(worst_id)
		f.remember("folk:%d" % worst_id, 0.45)
	# 2) friends
	var friends: int = RelationshipService.count_bit(fid, "friend", true)
	var want_friends: bool = friends < int(gc.get("friend_target", 3))
	_set_marker(f, "wants_friends", want_friends)
	if want_friends and kind == "":
		var best := -1
		var best_s := -999.0
		for g in WorldIface.all_folk():
			if int(g.id) == fid or SysUtil.is_away(g) or str(g.age_stage) in ["baby", "toddler"]:
				continue
			var bit: String = RelationshipService.bit_for(fid, int(g.id))
			if bit in ["friend", "best_friend", "enemy", "family", "partner", "spouse", "sweetheart", "dating"]:
				continue
			var sc: float = RelationshipService.compatibility(fid, int(g.id)) + SysUtil.rng.randf() * 0.4 - RelationshipService.tension(fid, int(g.id)) * 0.02
			if sc > best_s:
				best_s = sc
				best = int(g.id)
		if best >= 0:
			kind = "make_friend"
			target = best
			text = "Wants to befriend %s" % SysUtil.folk_name(best)
			f.remember("folk:%d" % best, 0.3)
	# 3) company / romance
	_set_marker(f, "wants_company", f.get_stat_value("social") < float(gc.get("company_social_below", 35)))
	var single: bool = not f.has_buff("has_partner")
	var romantic: bool = f.has_trait("romantic") or f.has_trait("charmer")
	_set_marker(f, "wants_romance", romantic and single and str(f.age_stage) in ["adult", "elder", "teen"])
	if kind == "" and f.has_buff("wants_romance"):
		kind = "find_love"
		text = "Looking for love"
	if kind == "":
		goals.erase(fid)
	else:
		goals[fid] = {"kind": kind, "target": target, "text": text}

## A folk with a long contact drought queues a friendly word with someone (runs after their current activity).
static func _nudge_contact(f) -> bool:
	if not f.queue.is_empty() or (f.current != null and str(f.current.target_kind) == "folk"):
		return false
	var fid: int = int(f.id)
	var best = null
	var best_s := -999.0
	for g in WorldIface.all_folk():
		if int(g.id) == fid or SysUtil.is_away(g) or str(g.age_stage) in ["baby", "toddler"] or str(g.age_stage) != str(f.age_stage) and (str(g.age_stage) in ["child"] or str(f.age_stage) in ["child"]):
			continue
		var sc: float = RelationshipService.value(fid, int(g.id), "friendship") * 0.02 + RelationshipService.compatibility(fid, int(g.id)) + SysUtil.rng.randf() * 0.3 - RelationshipService.tension(fid, int(g.id)) * 0.03
		if sc > best_s:
			best_s = sc
			best = g
	if best == null:
		return false
	var bit: String = RelationshipService.bit_for(fid, int(best.id))
	var iid := "chat"
	if bit in ["stranger", "acquaintance"]:
		iid = "greet" if SysUtil.rng.randf() < 0.5 else "ask_about_day"
	var ir := Interaction.create(iid, f, int(best.id), false)
	if ir == null or not ir.can_run(f, null, false):
		return false
	f.enqueue(ir)
	return true

static func goal_text(fid: int) -> String:
	return str(goals.get(fid, {}).get("text", ""))

## Couples sometimes go on a date or show affection when both are idle (non-player priority, so autonomy-like).
static func couples_upkeep() -> int:
	var gc: Dictionary = cfg().get("goals", {})
	var hour: float = SimEnv.hour_f()
	var started := 0
	var seen: Dictionary = {}
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
		var fl: Dictionary = p["flags"]
		if not (fl.get("dating", false) or fl.get("sweetheart", false) or fl.get("partner", false) or fl.get("spouse", false)):
			continue
		var a = SysUtil.folk(int(p["lo"]))
		var b = SysUtil.folk(int(p["hi"]))
		if a == null or b == null or SysUtil.is_away(a) or SysUtil.is_away(b) or not a.is_idle() or not b.is_idle():
			continue
		if seen.has(a.id) or seen.has(b.id):
			continue
		var iid := ""
		if hour >= 17.0 and hour <= 22.0 and SysUtil.rng.randf() < float(gc.get("date_chance_per_hour", 0.12)) and not a.on_cooldown("go_on_date"):
			iid = "go_on_date"
		elif SysUtil.rng.randf() < float(gc.get("affection_chance_per_hour", 0.1)):
			var opts: Array = ["hug", "hold_hands", "kiss", "cuddle", "sweet_nothings"]
			iid = str(SysUtil.pick(opts))
		if iid == "":
			continue
		var ir := Interaction.create(iid, a, int(b.id), false)
		if ir != null and ir.can_run(a, null, false) and not a.on_cooldown(iid):
			a.enqueue(ir)
			seen[a.id] = true
			seen[b.id] = true
			started += 1
	return started

# ------------------------------------------------------------------ clock / events
static func on_minute(_total: int = 0) -> void:
	for f in WorldIface.all_folk():
		Emotions.sync(f)
		if SysUtil.is_resident(f):
			Emotions.record_minute(f)
	Emotions.contagion_tick()
	Conversation.on_minute()
	_tick_gatherings()

static func on_hour(_hour: int = 0) -> void:
	for f in WorldIface.all_folk():
		refresh_markers(f)
		if SysUtil.is_resident(f):
			update_goals(f)
	couples_upkeep()

static func on_day(day: int) -> void:
	var tc: Dictionary = cfg().get("tension", {})
	var today: int = SysUtil.day()
	for key in RelationshipService.pairs.keys():
		var p: Dictionary = RelationshipService.pairs[key]
		var fl: Dictionary = p["flags"]
		var bonded: bool = fl.get("family", false) or fl.get("partner", false) or fl.get("spouse", false) or fl.get("sweetheart", false)
		for dir in [[int(p["lo"]), int(p["hi"])], [int(p["hi"]), int(p["lo"])]]:
			var tv: float = RelationshipService.value(dir[0], dir[1], "tension")
			if tv > 0.0:
				var rate: float = float(tc.get("decay_per_day", 5.0))
				var override: float = -1.0
				for t in RelationshipService.traits_of(dir[0]):
					var gr: Variant = SimEnv.data().trait_def(str(t)).get("social", {}).get("grudge_rate", null)
					if gr != null:
						override = float(gr) if override < 0.0 else (override + float(gr)) * 0.5
				if override >= 0.0:
					rate = override
				if bonded:
					rate *= 1.0 + (1.0 - float(tc.get("bonded_factor", 0.6)))
				RelationshipService.set_value(dir[0], dir[1], "tension", maxf(tv - rate, 0.0))
		if bool(p.get("heated", false)) and maxf(RelationshipService.value(int(p["lo"]), int(p["hi"]), "tension"), RelationshipService.value(int(p["hi"]), int(p["lo"]), "tension")) <= float(cfg().get("arguments", {}).get("resolve_below", 10)):
			p.erase("heated")
		# ex status fades
		if fl.get("ex", false) and today - int((p["since"] as Dictionary).get("ex", today)) >= int(cfg().get("romance", {}).get("ex_days", 20)):
			RelationshipService.set_flag(int(p["lo"]), int(p["hi"]), "ex", false, false)
		# topics are fresh again after a while
		var tcnt: Dictionary = p.get("topics", {})
		for tk in tcnt.keys():
			var nv: float = float(tcnt[tk]) - float(cfg().get("topic_rules", {}).get("recover_per_day", 1.0))
			if nv <= 0.0:
				tcnt.erase(tk)
			else:
				tcnt[tk] = nv
	# reputation drifts back toward neutral
	var rd: float = float(cfg().get("reputation", {}).get("decay_per_day", 1.0))
	for k in RelationshipService.reputation_map.keys():
		RelationshipService.reputation_map[k] = move_toward(float(RelationshipService.reputation_map[k]), 0.0, rd)
	# undiscovered affairs may come out
	var rc: Dictionary = cfg().get("romance", {}).get("cheat", {})
	for af in RelationshipService.affairs.duplicate():
		if SysUtil.rng.randf() < float(rc.get("daily_discover", 0.08)):
			discover_cheating(int(af["victim"]), int(af["cheater"]), int(af["other"]))
	Emotions.on_day(day)

static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	match ev_name:
		"soc_gathering":
			start_gathering(int(payload.get("folk_id", -1)))
		"soc_karaoke":
			_karaoke(int(payload.get("folk_id", -1)))
		"apologize":
			reconcile(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)), 12.0, "apology")
		"wedding":
			Emotions.imprint_pair(SysUtil.folk(int(payload.get("folk_id", -1))), SysUtil.folk(int(payload.get("target_id", -1))), 0.6, "wedding", "the wedding")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	var gl: Array = []
	for g in gatherings:
		if not bool(g["done"]):
			gl.append(g.duplicate(true))
	return {"gatherings": gl, "stats": stats.duplicate(true), "next_gathering": _next_gathering}

static func from_dict(d: Dictionary) -> void:
	gatherings.clear()
	for g in d.get("gatherings", []):
		var e: Dictionary = (g as Dictionary).duplicate(true)
		for k in ["id", "host", "start", "end"]:
			e[k] = int(e.get(k, 0))
		var gs: Array = []
		for x in e.get("guests", []):
			gs.append(int(x))
		e["guests"] = gs
		e["score"] = float(e.get("score", 0.0))
		e["done"] = bool(e.get("done", false))
		gatherings.append(e)
	if d.has("stats"):
		stats = (d["stats"] as Dictionary).duplicate(true)
		for k2 in ["arguments", "gossip", "backfires", "dates", "breakups", "cheats", "gatherings"]:
			stats[k2] = int(stats.get(k2, 0))
		var tiers: Dictionary = stats.get("tiers", {})
		for tk in tiers:
			tiers[tk] = int(tiers[tk])
		stats["tiers"] = tiers
	_next_gathering = int(d.get("next_gathering", 1))
