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
	for t in RelationshipBits.traits_of(fid):
		var sd: Dictionary = SimEnv.data().trait_def(str(t)).get("social", {})
		if sd.has(key):
			m *= float(sd[key])
	return m

## Sum of traits' social[group][cat] + social[group]["all"] (e.g. give / receive modifiers).
static func trait_add(fid: int, group: String, cat: String) -> float:
	var s := 0.0
	for t in RelationshipBits.traits_of(fid):
		var g: Dictionary = SimEnv.data().trait_def(str(t)).get("social", {}).get(group, {})
		s += float(g.get(cat, 0.0)) + float(g.get("all", 0.0))
	return s

static func has_t(fid: int, tr: String) -> bool:
	return RelationshipBits.traits_of(fid).has(tr)

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
	var req_fail := SocialScoring.check_requires(actor_id, target_id, sd.get("requires", []))
	if req_fail == "" and RomanceRules.is_romantic_def(d) and not RomanceRules.allowed(actor_id, target_id):
		req_fail = "not_allowed"
	var sc := SocialScoring.success_score(a, t, iid, d, sd, teff)
	var tier: String = "meh" if req_fail != "" else SocialScoring.tier_for(float(sc["score"]), sd)
	var fx: Dictionary = {} if req_fail != "" else SocialScoring.fx_for(sd, tier)
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
			ro += float(base.get("romance", 0.0)) * (RelationshipRomance.spark(actor_id, target_id) - 0.5) * 0.8
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
		RelationshipKnowledge.reveal(actor_id, target_id, str(k), topic)
	for k2 in fx.get("reveal_self", []):
		RelationshipKnowledge.reveal(target_id, actor_id, str(k2))
	if tier in ["great", "good"] and cat in ["friendly", "funny", "deep", "group"]:
		_passive_reveal(actor_id, target_id)
	if topic != "" and tier in ["great", "good"]:
		RelationshipKnowledge.note_topic(actor_id, target_id, topic)
	# ---- special actions
	if fx.has("act"):
		for act in (fx["act"] if fx["act"] is Array else [fx["act"]]):
			SocialActions._act(str(act), float(fx.get("arg", 1.0)), a, t, tier, iid)
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
		RelationshipKnowledge.reveal(a, t, "trait")
	if SysUtil.rng.randf() < p:
		RelationshipKnowledge.reveal(t, a, "trait")

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
		RelationshipRomance.add_tension(target, actor, te * trait_mult(target, "neg_mult", 1.0))
		RelationshipRomance.add_tension(actor, target, te * 0.6)
		var ft = SysUtil.folk(target)
		if ft != null and RelationshipRomance.tension(target, actor) >= float(tc.get("avoid_threshold", 25)):
			ft.remember("folk:%d" % actor, float(tc.get("avoid_memory", -0.25)))
	else:
		RelationshipRomance.add_tension(target, actor, te)
		RelationshipRomance.add_tension(actor, target, te)

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
		SocialConflict.cheat_check(actor, target)
	_witness(actor, target, iid, d)
	SocialGatherings.refresh_markers(a)
	SocialGatherings.refresh_markers(t)

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
			RelationshipKnowledge.add_gossip(int(f.id), actor, "%s and %s were %s" % [SysUtil.folk_name(actor), SysUtil.folk_name(target), kinds[iid]], "observed", -1, target)

# ------------------------------------------------------------------ clock / events
const STRANGER_PERIOD := 5

static func on_minute(_total: int = 0) -> void:
	var t := PerfProf.start()
	var now: int = SysUtil.now()
	for f in WorldIface.all_folk():
		if SysUtil.is_resident(f):
			Emotions.sync(f)
			Emotions.record_minute(f)
		elif int(f.household_id) > 0 or not f.has_meta("visitor") or (now + int(f.id)) % STRANGER_PERIOD == 0:
			Emotions.sync(f)             # strangers' moods only change when SimDirector ticks them (every STRANGER_PERIOD minutes)
	PerfProf.stop("social/sync+record", t)
	t = PerfProf.start()
	Emotions.contagion_tick()
	PerfProf.stop("social/contagion", t)
	t = PerfProf.start()
	Conversation.on_minute()
	PerfProf.stop("social/conversation", t)
	t = PerfProf.start()
	SocialGatherings._tick_gatherings()
	PerfProf.stop("social/gatherings", t)

static func on_hour(_hour: int = 0) -> void:
	for f in WorldIface.all_folk():
		SocialGatherings.refresh_markers(f)
		if SysUtil.is_resident(f):
			SocialGatherings.update_goals(f)
	SocialGatherings.couples_upkeep()

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
				for t in RelationshipBits.traits_of(dir[0]):
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
			RelationshipBits.set_flag(int(p["lo"]), int(p["hi"]), "ex", false, false)
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
			SocialConflict.discover_cheating(int(af["victim"]), int(af["cheater"]), int(af["other"]))
	Emotions.on_day(day)

static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	match ev_name:
		"soc_gathering":
			SocialGatherings.start_gathering(int(payload.get("folk_id", -1)))
		"soc_karaoke":
			SocialGatherings._karaoke(int(payload.get("folk_id", -1)))
		"apologize":
			SocialConflict.reconcile(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)), 12.0, "apology")
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

# ---- thin delegates (called from UI / views)
static func escalate(a: int, b: int, amount: float) -> int:
	return SocialConflict.escalate(a, b, amount)

static func goal_text(fid: int) -> String:
	return SocialGatherings.goal_text(fid)

static func reason_unavailable(actor, target, iid: String, include_cooldown: bool = true) -> String:
	return SocialScoring.reason_unavailable(actor, target, iid, include_cooldown)
