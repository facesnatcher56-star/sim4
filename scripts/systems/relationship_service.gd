class_name RelationshipService
extends RefCounted
## Relationship layer on top of Folk.get_rel/add_rel (directional friendship + romance, -100..100).
##  * bits (acquaintance, friend, best_friend, enemy, crush, sweetheart, partner, spouse, family) from data/social.json
##  * per-pair shared history (last 30 events) that changes future reactions (grudges / warmth)
##  * trait compatibility, daily decay of unused relationships, jealousy when a bonded partner flirts with someone else
##  * persistent pair store, so relationships with folk who are off the lot (townies, visitors) survive
## Public for UI: bit_for(a,b), history_for(a,b), describe(a,b), compatibility(a,b), value(a,b,track).

## friendship / romance / trust are "feelings" (directional, decay when idle). tension (argument heat, 0..100, decays daily),
## bond (0 none, 1 dating, 2 sweethearts, 3 partners, 4 spouses) and ex (1 after a breakup) are directional status tracks that live
## in Folk.relationships too, so interaction tests can use {relationship_above: [track, v]} on them.
const TRACKS := ["friendship", "romance", "trust", "tension", "bond", "ex"]
const FEELINGS := ["friendship", "romance"]

static var pairs: Dictionary = {}        # "lo_hi" -> {lo, hi, flags:{}, since:{}, history:[], last_contact, vals:{"lo>hi":{friendship,romance}, "hi>lo":{...}}}
static var _targets: Dictionary = {}     # folk_id -> target folk id of the running social interaction
static var _bit_cache: Dictionary = {}   # "a>b" -> bit id
static var secrets: Dictionary = {}      # owner_id -> [{id, kind, text, severity, known_by:[ids]}]
static var reputation_map: Dictionary = {}   # folk_id -> -100..100 standing in town
static var gossip_items: Dictionary = {} # folk_id -> [{about, other, text, kind, sid, day, told:[ids]}]
static var affairs: Array = []           # [{cheater, other, victim, day}] undiscovered cheating

static func reset() -> void:
	pairs.clear()
	_targets.clear()
	_bit_cache.clear()
	secrets.clear()
	reputation_map.clear()
	gossip_items.clear()
	affairs.clear()
	Conversation.reset()
	Emotions.reset()
	SocialDynamics.reset()
	SocialContent.ensure()

static func cfg() -> Dictionary:
	return SysUtil.table("social")

# ------------------------------------------------------------------ pair store
static func _pair(a: int, b: int, create: bool = true) -> Dictionary:
	var key: String = SysUtil.pair_key(a, b)
	if not pairs.has(key):
		if not create:
			return {}
		var lo: int = mini(a, b)
		var hi: int = maxi(a, b)
		pairs[key] = {"lo": lo, "hi": hi, "flags": {}, "since": {}, "history": [], "last_contact": SysUtil.day(),
			"vals": {"%d>%d" % [lo, hi]: {"friendship": 0.0, "romance": 0.0}, "%d>%d" % [hi, lo]: {"friendship": 0.0, "romance": 0.0}}}
	return pairs[key]

static func knows(a: int, b: int) -> bool:
	return pairs.has(SysUtil.pair_key(a, b))

## Directional value of `track` from a's feeling about b.
static func value(a: int, b: int, track: String) -> float:
	var fa = SysUtil.folk(a)
	if fa != null:
		return fa.get_rel(b, track)
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty():
		return 0.0
	return float(((p["vals"] as Dictionary).get("%d>%d" % [a, b], {}) as Dictionary).get(track, 0.0))

## Set a's feeling about b (writes the Folk when it is on the lot, else the store).
static func set_value(a: int, b: int, track: String, v: float) -> void:
	v = clampf(v, -100.0, 100.0)
	if track == "romance" and v > 0.0 and not RomanceRules.allowed(a, b):    # minors and family never gain romance
		v = 0.0
	var p: Dictionary = _pair(a, b)
	var vals: Dictionary = p["vals"]
	var k: String = "%d>%d" % [a, b]
	if not vals.has(k):
		vals[k] = {"friendship": 0.0, "romance": 0.0}
	(vals[k] as Dictionary)[track] = v
	var fa = SysUtil.folk(a)
	if fa != null:
		var cur: float = fa.get_rel(b, track)
		if not is_equal_approx(cur, v):
			fa.add_rel(b, track, v - cur)    # emits relationship_changed -> _sync
	RelationshipBits._refresh_bits(a, b)

static func add_value(a: int, b: int, track: String, delta: float) -> void:
	set_value(a, b, track, value(a, b, track) + delta)

## Mutual add (both directions) usable for off-lot folk as well.
static func add_both(a: int, b: int, track: String, delta: float) -> void:
	add_value(a, b, track, delta)
	add_value(b, a, track, delta)

static func touch(a: int, b: int) -> void:
	_pair(a, b)["last_contact"] = SysUtil.day()

## Copy the in-world values of a folk into the store (call before a folk leaves the world).
static func sync_folk(f) -> void:
	var fid: int = int(f.id)
	for other in f.relationships:
		var p: Dictionary = _pair(fid, int(other))
		var k: String = "%d>%d" % [fid, int(other)]
		var rec: Dictionary = (f.relationships[other] as Dictionary)
		var vals: Dictionary = p["vals"]
		if not vals.has(k):
			vals[k] = {"friendship": 0.0, "romance": 0.0}
		for t in TRACKS:
			(vals[k] as Dictionary)[t] = float(rec.get(t, 0.0))

## Push stored values onto a folk that just (re)appeared in the world.
static func restore_folk(f) -> void:
	var fid: int = int(f.id)
	for key in pairs:
		var p: Dictionary = pairs[key]
		if int(p["lo"]) != fid and int(p["hi"]) != fid:
			continue
		var other: int = int(p["hi"]) if int(p["lo"]) == fid else int(p["lo"])
		var vals: Dictionary = (p["vals"] as Dictionary).get("%d>%d" % [fid, other], {})
		if not f.relationships.has(other):
			f.relationships[other] = {}
		for t in TRACKS:
			var rv: float = float(vals.get(t, 0.0))
			if absf(rv) > 0.0001 or (f.relationships[other] as Dictionary).has(t):
				(f.relationships[other] as Dictionary)[t] = rv

static func _sync_pair(a: int, b: int) -> void:
	var fa = SysUtil.folk(a)
	if fa == null:
		return
	var p: Dictionary = _pair(a, b)
	var k: String = "%d>%d" % [a, b]
	if not (p["vals"] as Dictionary).has(k):
		p["vals"][k] = {"friendship": 0.0, "romance": 0.0}
	for t in TRACKS:
		(p["vals"][k] as Dictionary)[t] = fa.get_rel(b, t)

# ------------------------------------------------------------------ history
static func add_history(a: int, b: int, kind: String, sentiment: float, by: int = -1) -> void:
	var p: Dictionary = _pair(a, b)
	var h: Array = p["history"]
	h.append({"day": SysUtil.day(), "kind": kind, "sentiment": snappedf(sentiment, 0.01), "by": by if by >= 0 else a})
	var mx: int = int(cfg().get("history", {}).get("max_events", 30))
	while h.size() > mx:
		h.pop_front()
	p["last_contact"] = SysUtil.day()

static func history_for(a: int, b: int) -> Array:
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty():
		return []
	return (p["history"] as Array).duplicate(true)

static func _age_weight(ev_day: int) -> float:
	var hl: float = maxf(float(cfg().get("history", {}).get("half_life_days", 14)), 0.1)
	return pow(0.5, float(SysUtil.day() - ev_day) / hl)

## How much `a` holds a grudge against `b` (0..1), from recent negative events.
static func grudge(a: int, b: int) -> float:
	var total: float = 0.0
	for ev in history_for(a, b):
		var s: float = float(ev["sentiment"])
		if s < 0.0:
			var mine: float = 0.4 if int(ev["by"]) == a else 1.0
			total += -s * _age_weight(int(ev["day"])) * mine
	return clampf(total, 0.0, 1.0)

static func warmth(a: int, b: int) -> float:
	var total: float = 0.0
	for ev in history_for(a, b):
		var s: float = float(ev["sentiment"])
		if s > 0.0:
			total += s * _age_weight(int(ev["day"])) * 0.5
	return clampf(total, 0.0, 1.0)

## Multiplier (0.2..1.8) on how well a's interactions with b currently land, for UI hints.
static func reaction_factor(a: int, b: int) -> float:
	var h: Dictionary = cfg().get("history", {})
	var f: float = 1.0 + RelationshipBits.compatibility(a, b) * float(cfg().get("compat", {}).get("gain_scale", 0.5))
	f += warmth(a, b) * float(h.get("warmth_boost", 0.3)) - grudge(a, b) * float(h.get("grudge_dampen", 0.6))
	return clampf(f, 0.2, 1.8)

# ------------------------------------------------------------------ event handlers
static func on_relationship_changed(a: int, b: int, _track: String) -> void:
	_sync_pair(a, b)
	touch(a, b)
	RelationshipBits._refresh_bits(a, b)

static func on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	SocialContent.ensure()
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if str(d.get("target", "object")) == "folk" and target_id >= 0:
		_targets[folk_id] = target_id
	else:
		_targets.erase(folk_id)
	Emotions.on_started(folk_id, iid, target_id)
	Conversation.on_started(folk_id, iid, target_id)

static func _loot_deltas(d: Dictionary) -> Dictionary:
	var out: Dictionary = {"friendship": 0.0, "romance": 0.0, "trust": 0.0}
	for e in d.get("on_finish", []):
		if e is Dictionary and (e as Dictionary).has("relationship_add"):
			var ra: Array = e["relationship_add"]
			var chance: float = float(e.get("chance", 1.0))
			out[str(ra[0])] = float(out.get(str(ra[0]), 0.0)) + float(ra[1]) * chance
	return out

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	SocialContent.ensure()
	Emotions.on_finished(folk_id, iid, success)
	Conversation.on_finished(folk_id, iid, success)
	if not _targets.has(folk_id):
		return
	var t: int = int(_targets[folk_id])
	_targets.erase(folk_id)
	if not success:
		return
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var h: Dictionary = cfg().get("history", {})
	# New-style social interactions (def has a "social" block) resolve their own outcome: success tiers, side effects, knowledge...
	var res: Dictionary = SocialDynamics.resolve(folk_id, t, iid, d)
	var full: bool = not res.is_empty() and str(res.get("mode", "full")) == "full"
	var deltas: Dictionary = _loot_deltas(d)
	var kinds: Dictionary = h.get("kinds", {})
	var sentiment: float
	if full:
		sentiment = float(res["sentiment"])
	elif kinds.has(iid):
		sentiment = float(kinds[iid])
	else:
		sentiment = clampf((float(deltas["friendship"]) + float(deltas["romance"])) / 6.0, -1.0, 1.0)
	if not res.is_empty() and res.has("sentiment_adjust") and not full:
		sentiment = clampf(sentiment + float(res["sentiment_adjust"]), -1.0, 1.0)
	# Reaction adjustment based on history before this event is logged.
	var gscale: float = float(cfg().get("compat", {}).get("gain_scale", 0.5))
	for track in (FEELINGS if not full else []):
		var delta: float = float(deltas[track])
		if absf(delta) < 0.001:
			continue
		for dir in [[folk_id, t], [t, folk_id]]:
			var x: int = dir[0]
			var y: int = dir[1]
			var g: float = grudge(y, x)       # does the receiver hold a grudge against the giver?
			var w: float = warmth(y, x)
			var extra: float
			if delta > 0.0:
				extra = delta * (RelationshipBits.compatibility(x, y) * gscale + w * float(h.get("warmth_boost", 0.3)) - g * float(h.get("grudge_dampen", 0.6)))
			else:
				extra = delta * (g * float(h.get("grudge_amplify", 0.5)) - RelationshipBits.compatibility(x, y) * gscale * 0.3)
			if absf(extra) > 0.01:
				add_value(y, x, track, extra)   # the receiver's view of the giver
	add_history(folk_id, t, iid, sentiment, folk_id)
	if not res.is_empty():
		RelationshipRomance._tag_last_history(folk_id, t, str(res.get("tier", "")), str(res.get("label", "")))
	touch(folk_id, t)
	# Memory feeds autonomy (Folk.memory_bias on "folk:<id>" keys).
	var ms: float = float(h.get("memory_scale", 0.35))
	var fa = SysUtil.folk(folk_id)
	var ft = SysUtil.folk(t)
	if ft != null and absf(sentiment) >= 0.3:
		ft.remember("folk:%d" % folk_id, sentiment * ms)
	if fa != null and absf(sentiment) >= 0.3:
		fa.remember("folk:%d" % t, sentiment * ms * 0.5)
	RelationshipBits.auto_status(folk_id, t)
	_check_jealousy(folk_id, t, iid)
	SocialDynamics.after_social(folk_id, t, iid, d, res)
	SysUtil.game_event("social_done", {"folk_id": folk_id, "target_id": t, "interaction": iid, "sentiment": sentiment,
		"tier": str(res.get("tier", "")), "outcome": str(res.get("label", ""))})

static func _check_jealousy(actor: int, target: int, iid: String) -> void:
	var j: Dictionary = cfg().get("jealousy", {})
	if not bool(j.get("enabled", true)) or not (j.get("triggers", []) as Array).has(iid):
		return
	var fa = SysUtil.folk(actor)
	for partner_id in RelationshipRomance.exclusive_partners(actor):
		if int(partner_id) == target:
			continue
		var fp = SysUtil.folk(int(partner_id))
		if fp == null or SysUtil.is_away(fp):
			continue
		if fa != null and Vector2(fp.tile - fa.tile).length() > float(j.get("range", 14)):
			continue
		var jm: float = SocialDynamics.trait_mult(int(partner_id), "jealousy_mult", 1.0)
		add_value(int(partner_id), actor, "romance", -float(j.get("romance_loss", 8)) * jm)
		add_value(int(partner_id), actor, "friendship", -float(j.get("friendship_loss", 4)) * jm)
		if fp.has_trait("jealous"):
			fp.add_buff(str(j.get("buff_jealous", "jealous_pang")))
		fp.add_buff(str(j.get("buff_hot", "furious")) if fp.has_trait("hot_headed") else str(j.get("buff", "annoyed")))
		add_history(actor, int(partner_id), "jealous", float(cfg().get("history", {}).get("kinds", {}).get("jealous", -0.7)), actor)
		SysUtil.notify("%s is jealous: %s was flirting with %s!" % [fp.name, SysUtil.folk_name(actor), SysUtil.folk_name(target)], "relationship")
		SysUtil.game_event("jealousy", {"folk_id": int(partner_id), "target_id": actor, "other_id": target})

## apologize game_event: soften the grudge between the pair.
static func on_apologize(actor: int, target: int) -> void:
	var relief: float = float(cfg().get("apologize", {}).get("grudge_relief", 0.5))
	var p: Dictionary = _pair(actor, target)
	for ev in p["history"]:
		if float(ev["sentiment"]) < 0.0:
			ev["sentiment"] = snappedf(float(ev["sentiment"]) * (1.0 - relief), 0.01)
	add_history(actor, target, "apologize", float(cfg().get("history", {}).get("kinds", {}).get("apologize", 0.6)), actor)
	var ft = SysUtil.folk(target)
	if ft != null:
		ft.remember("folk:%d" % actor, 0.25)

## Decay unused relationships toward zero. Bonded pairs (family, partner...) fade much slower.
static func on_day_sched(_day: int) -> void:
	if DaySlices.enabled():          # the scheduler's row: one pair per call, spread over the day (DaySlices)
		DaySlices.begin("relationships", pairs.keys(), Callable(RelationshipService, "day_pair"))
		SocialDynamics.day_rest(_day)
		return
	on_day(_day)

static func on_day(_day: int) -> void:
	for key in pairs.keys():
		decay_pair(key)
	SocialDynamics.on_day(_day)

## The daily decay + social upkeep of ONE pair (the body of the old loops).
static func day_pair(key) -> void:
	if not pairs.has(key):
		return
	decay_pair(key)
	SocialDynamics.pair_day(key)

static func decay_pair(key) -> void:
	var dc: Dictionary = cfg().get("decay", {})
	var today: int = SysUtil.day()
	if true:
		var p: Dictionary = pairs[key]
		var fl: Dictionary = p["flags"]
		var bonded: bool = fl.get("family", false) or fl.get("spouse", false) or fl.get("partner", false) or fl.get("sweetheart", false)
		var factor: float = float(dc.get("bonded_factor", 0.25)) if bonded else 1.0
		var last_contact: int = int(p["last_contact"])
		var idle: int = today - last_contact
		for dir in [[int(p["lo"]), int(p["hi"])], [int(p["hi"]), int(p["lo"])]]:
			for track in TRACKS:
				if not dc.has(track):
					continue
				var spec: Dictionary = dc.get(track, {})
				if idle < int(spec.get("idle_days", 2)):
					continue
				var v: float = value(dir[0], dir[1], track)
				if absf(v) < 0.01:
					continue
				var step: float = (float(spec.get("per_day", 1.0)) if v > 0.0 else float(spec.get("negative_per_day", 0.4))) * factor
				var nv: float = move_toward(v, 0.0, step)
				set_value(dir[0], dir[1], track, nv)
		p["last_contact"] = last_contact   # decay itself is not "contact": idle time keeps counting
		RelationshipBits.auto_status(int(p["lo"]), int(p["hi"]))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"pairs": pairs.duplicate(true), "social": social_to_dict()}

static func social_to_dict() -> Dictionary:
	var sec: Dictionary = {}
	for k in secrets:
		sec[str(k)] = (secrets[k] as Array).duplicate(true)
	var rep: Dictionary = {}
	for k2 in reputation_map:
		rep[str(k2)] = reputation_map[k2]
	var gos: Dictionary = {}
	for k3 in gossip_items:
		gos[str(k3)] = (gossip_items[k3] as Array).duplicate(true)
	return {"secrets": sec, "reputation": rep, "gossip": gos, "affairs": affairs.duplicate(true), "emotions": Emotions.to_dict(),
		"dyn": SocialDynamics.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	pairs = (d.get("pairs", {}) as Dictionary).duplicate(true)
	for key in pairs:
		var p: Dictionary = pairs[key]
		p["lo"] = int(p["lo"])
		p["hi"] = int(p["hi"])
		p["last_contact"] = int(p["last_contact"])
		for ev in p["history"]:
			ev["day"] = int(ev["day"])
			ev["by"] = int(ev["by"])
		var since: Dictionary = p.get("since", {})
		for k in since:
			since[k] = int(since[k])
		if p.has("dates"):
			p["dates"] = int(p["dates"])
	var so: Dictionary = d.get("social", {})
	for k in so.get("secrets", {}):
		var list: Array = []
		for s in so["secrets"][k]:
			var e: Dictionary = (s as Dictionary).duplicate(true)
			e["id"] = int(e["id"])
			e["known_by"] = SysUtil.to_ints(e.get("known_by", []))
			list.append(e)
		secrets[int(k)] = list
	for k2 in so.get("reputation", {}):
		reputation_map[int(k2)] = float(so["reputation"][k2])
	for k3 in so.get("gossip", {}):
		var gl: Array = []
		for g in so["gossip"][k3]:
			var ge: Dictionary = (g as Dictionary).duplicate(true)
			ge["about"] = int(ge["about"])
			ge["other"] = int(ge.get("other", -1))
			ge["sid"] = int(ge.get("sid", -1))
			ge["day"] = int(ge.get("day", 0))
			ge["told"] = SysUtil.to_ints(ge.get("told", []))
			gl.append(ge)
		gossip_items[int(k3)] = gl
	for af in so.get("affairs", []):
		var ae: Dictionary = (af as Dictionary).duplicate()
		for kk in ["cheater", "other", "victim", "day"]:
			ae[kk] = int(ae.get(kk, 0))
		affairs.append(ae)
	Emotions.from_dict(so.get("emotions", {}))
	SocialDynamics.from_dict(so.get("dyn", {}))
	for key in pairs:
		var p2: Dictionary = pairs[key]
		for dir in [[int(p2["lo"]), int(p2["hi"])], [int(p2["hi"]), int(p2["lo"])]]:
			_bit_cache["%d>%d" % [dir[0], dir[1]]] = RelationshipBits.bit_for(dir[0], dir[1])

# ---- thin delegates (called from UI / views)
static func _tag_last_history(a: int, b: int, tier: String, text: String) -> void:
	RelationshipRomance._tag_last_history(a, b, tier, text)

static func all_known(a: int) -> Array:
	return RelationshipBits.all_known(a)

static func bit_color(bit: String) -> String:
	return RelationshipBits.bit_color(bit)

static func bit_for(a: int, b: int) -> String:
	return RelationshipBits.bit_for(a, b)

static func bit_label(bit: String) -> String:
	return RelationshipBits.bit_label(bit)

static func compat_label(c: float) -> String:
	return RelationshipBits.compat_label(c)

static func compatibility(a: int, b: int) -> float:
	return RelationshipBits.compatibility(a, b)

static func describe(a: int, b: int) -> String:
	return RelationshipBits.describe(a, b)

static func history_snippets(a: int, b: int, n: int = 3) -> Array:
	return RelationshipKnowledge.history_snippets(a, b, n)

static func known_summary(a: int, b: int) -> Dictionary:
	return RelationshipKnowledge.known_summary(a, b)

static func note_topic(a: int, b: int, topic: String) -> void:
	RelationshipKnowledge.note_topic(a, b, topic)

static func reveal(a: int, b: int, kind: String, detail: String = "") -> String:
	return RelationshipKnowledge.reveal(a, b, kind, detail)

static func romance_stage(a: int, b: int) -> String:
	return RelationshipRomance.romance_stage(a, b)

static func spark_hearts(a: int, b: int) -> String:
	return RelationshipRomance.spark_hearts(a, b)

static func stage_label(stage: String) -> String:
	return RelationshipRomance.stage_label(stage)

static func start_dating(a: int, b: int, announce: bool = true) -> void:
	RelationshipRomance.start_dating(a, b, announce)
