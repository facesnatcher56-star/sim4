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
	_refresh_bits(a, b)

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

# ------------------------------------------------------------------ bits
static func bit_defs() -> Array:
	return cfg().get("bits", [])

static func has_flag(a: int, b: int, flag: String) -> bool:
	var p: Dictionary = _pair(a, b, false)
	return not p.is_empty() and bool((p["flags"] as Dictionary).get(flag, false))

## a's relationship bit towards b: spouse, partner, sweetheart, family, best_friend, enemy, crush, friend,
## acquaintance, or "stranger".
static func bit_for(a: int, b: int) -> String:
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty():
		return "stranger"
	var fr: float = value(a, b, "friendship")
	var ro: float = value(a, b, "romance")
	for bd in bit_defs():
		var ok: bool = true
		if bd.has("flag") and not bool((p["flags"] as Dictionary).get(str(bd["flag"]), false)):
			ok = false
		if bd.has("friendship_min") and fr < float(bd["friendship_min"]):
			ok = false
		if bd.has("friendship_max") and fr > float(bd["friendship_max"]):
			ok = false
		if bd.has("romance_min") and ro < float(bd["romance_min"]):
			ok = false
		if bd.has("romance_max") and ro > float(bd["romance_max"]):
			ok = false
		if bd.has("trust_min") and value(a, b, "trust") < float(bd["trust_min"]):
			ok = false
		if bd.has("trust_max") and value(a, b, "trust") > float(bd["trust_max"]):
			ok = false
		if ok:
			return str(bd["id"])
	return "stranger"

## Specific kin relation of b to a (parent, child, sibling, grandparent, spouse, ...) from the Family service, "" if none.
static func kin_bit(a: int, b: int) -> String:
	return Family.relation_id(a, b)

static func bit_label(bit: String) -> String:
	for bd in bit_defs():
		if str(bd["id"]) == bit:
			return str(bd.get("label", bit))
	return "Stranger"

static func bit_color(bit: String) -> String:
	for bd in bit_defs():
		if str(bd["id"]) == bit:
			return str(bd.get("color", "#9aa5b1"))
	return "#6b7280"

## Number of folk that `a` regards with the given bit. at_least_rank = also count stronger bits (friend counts best_friend,
## sweetheart, partner, spouse).
static func count_bit(a: int, bit: String, at_least_rank: bool = false) -> int:
	var n: int = 0
	var rank: int = _bit_rank(bit)
	for key in pairs:
		var p: Dictionary = pairs[key]
		var other: int = -1
		if int(p["lo"]) == a:
			other = int(p["hi"])
		elif int(p["hi"]) == a:
			other = int(p["lo"])
		if other < 0:
			continue
		var b: String = bit_for(a, other)
		if b == bit or (at_least_rank and b != "stranger" and b != "enemy" and b != "crush" and b != "family" and _bit_rank(b) >= rank):
			n += 1
	return n

static func _bit_rank(bit: String) -> int:
	match bit:
		"acquaintance": return 1
		"friend": return 2
		"best_friend": return 3
		"sweetheart": return 4
		"dating": return 3
		"confidant": return 3
		"partner": return 5
		"spouse": return 6
		"family": return 3
	return 0

static func others_with_bit(a: int, bit: String) -> Array:
	var out: Array = []
	for key in pairs:
		var p: Dictionary = pairs[key]
		var other: int = -1
		if int(p["lo"]) == a:
			other = int(p["hi"])
		elif int(p["hi"]) == a:
			other = int(p["lo"])
		if other >= 0 and bit_for(a, other) == bit:
			out.append(other)
	return out

static func all_known(a: int) -> Array:
	var out: Array = []
	for key in pairs:
		var p: Dictionary = pairs[key]
		if int(p["lo"]) == a:
			out.append(int(p["hi"]))
		elif int(p["hi"]) == a:
			out.append(int(p["lo"]))
	return out

## Notable bit changes announce themselves.
static func _refresh_bits(a: int, b: int) -> void:
	for dir in [[a, b], [b, a]]:
		var x: int = dir[0]
		var y: int = dir[1]
		var k: String = "%d>%d" % [x, y]
		var now_bit: String = bit_for(x, y)
		var old_bit: String = str(_bit_cache.get(k, "stranger"))
		if now_bit == old_bit:
			continue
		_bit_cache[k] = now_bit
		SysUtil.game_event("relationship_bit_changed", {"folk_id": x, "target_id": y, "bit": now_bit, "old": old_bit})
		if now_bit in ["friend", "best_friend", "enemy", "sweetheart", "partner", "spouse"] and SysUtil.folk(x) != null:
			if _bit_rank(now_bit) > _bit_rank(old_bit) or now_bit == "enemy":
				SysUtil.notify("%s now sees %s as: %s" % [SysUtil.folk_name(x), SysUtil.folk_name(y), bit_label(now_bit)], "relationship")

# ------------------------------------------------------------------ flags / status changes
static func set_flag(a: int, b: int, flag: String, on: bool = true, announce: bool = true) -> void:
	var p: Dictionary = _pair(a, b)
	var fl: Dictionary = p["flags"]
	if on:
		if flag in ["spouse", "partner", "sweetheart"]:
			for other_flag in ["spouse", "partner", "sweetheart", "dating", "ex"]:
				fl.erase(other_flag)
		elif flag == "dating":
			if fl.get("spouse", false) or fl.get("partner", false) or fl.get("sweetheart", false):
				return
			fl.erase("ex")
		elif flag == "ex":
			for other_flag2 in ["spouse", "partner", "sweetheart", "dating"]:
				fl.erase(other_flag2)
		fl[flag] = true
		(p["since"] as Dictionary)[flag] = SysUtil.day()
	else:
		fl.erase(flag)
	_update_bond_tracks(a, b)
	_refresh_bits(a, b)
	SocialDynamics.refresh_markers(SysUtil.folk(a))
	SocialDynamics.refresh_markers(SysUtil.folk(b))
	if on and announce and flag == "dating":
		SysUtil.notify("%s and %s are now dating!" % [SysUtil.folk_name(a), SysUtil.folk_name(b)], "relationship")
		SysUtil.game_event("relationship_status", {"folk_id": a, "target_id": b, "status": flag})
	if on and announce and flag in ["sweetheart", "partner", "spouse"]:
		SysUtil.notify("%s and %s are now %s!" % [SysUtil.folk_name(a), SysUtil.folk_name(b), bit_label(flag).to_lower() + "s"], "relationship")
		SysUtil.game_event("relationship_status", {"folk_id": a, "target_id": b, "status": flag})

## Who is `a` bonded to romantically (spouse > partner > sweetheart)?
static func romantic_partners(a: int) -> Array:
	var out: Array = []
	for key in pairs:
		var p: Dictionary = pairs[key]
		var other: int = -1
		if int(p["lo"]) == a:
			other = int(p["hi"])
		elif int(p["hi"]) == a:
			other = int(p["lo"])
		if other < 0:
			continue
		var fl: Dictionary = p["flags"]
		if fl.get("spouse", false) or fl.get("partner", false) or fl.get("sweetheart", false):
			out.append(other)
	return out

static func _is_bonded(a: int) -> bool:
	return not romantic_partners(a).is_empty()

## Auto-promote mutual crushes to sweethearts and long-time sweethearts to partners.
static func auto_status(a: int, b: int) -> void:
	var c: Dictionary = cfg()
	var sw: Dictionary = c.get("sweetheart", {})
	var p: Dictionary = _pair(a, b)
	var fl: Dictionary = p["flags"]
	if fl.get("spouse", false) or fl.get("partner", false):
		return
	var r1: float = value(a, b, "romance")
	var r2: float = value(b, a, "romance")
	var f1: float = value(a, b, "friendship")
	var f2: float = value(b, a, "friendship")
	if not fl.get("sweetheart", false):
		if minf(r1, r2) >= float(sw.get("romance_min", 45)) and minf(f1, f2) >= float(sw.get("friendship_min", 25)):
			if not _is_bonded(a) and not _is_bonded(b):
				set_flag(a, b, "sweetheart")
	else:
		var pt: Dictionary = c.get("partner", {})
		var since: int = int((p["since"] as Dictionary).get("sweetheart", SysUtil.day()))
		if minf(r1, r2) >= float(pt.get("romance_min", 70)) and minf(f1, f2) >= float(pt.get("friendship_min", 50)) \
				and SysUtil.day() - since >= int(pt.get("days_as_sweethearts", 4)):
			set_flag(a, b, "partner")

## Explicit proposal: sweetheart -> partner, partner -> spouse. Returns "accepted" | "declined" | "too_soon" | "no_bond".
static func propose(a: int, b: int) -> String:
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty():
		return "no_bond"
	var fl: Dictionary = p["flags"]
	var ro: float = minf(value(a, b, "romance"), value(b, a, "romance"))
	var fr: float = minf(value(a, b, "friendship"), value(b, a, "friendship"))
	if fl.get("partner", false):
		if ro >= 80.0 and fr >= 60.0:
			set_flag(a, b, "spouse")
			SysUtil.game_event("married", {"folk_id": a, "target_id": b})
			return "accepted"
		return "declined" if ro < 60.0 else "too_soon"
	var need: float = float(cfg().get("partner", {}).get("romance_min", 70))
	if fl.get("sweetheart", false) or ro >= float(cfg().get("sweetheart", {}).get("romance_min", 45)):
		if ro >= need - 10.0 and fr >= 40.0 and compatibility(a, b) > -0.5:
			set_flag(a, b, "partner")
			return "accepted"
		return "too_soon" if ro >= 30.0 else "declined"
	return "no_bond"

# ------------------------------------------------------------------ compatibility
static func traits_of(id: int) -> Array:
	var f = SysUtil.folk(id)
	if f != null:
		return f.traits
	return Story.traits_of(id)

## -1..1, from trait pairs in data/social.json.
static func compatibility(a: int, b: int) -> float:
	var pairs_t: Dictionary = cfg().get("compat", {}).get("pairs", {})
	var total: float = 0.0
	for ta in traits_of(a):
		for tb in traits_of(b):
			var v: float = 0.0
			if pairs_t.has("%s:%s" % [ta, tb]):
				v = float(pairs_t["%s:%s" % [ta, tb]])
			elif pairs_t.has("%s:%s" % [tb, ta]):
				v = float(pairs_t["%s:%s" % [tb, ta]])
			total += v
	total += _trait_social_compat(a, b)
	return clampf(total, -1.0, 1.0)

static func compat_label(c: float) -> String:
	if c >= 0.6:
		return "soulmates"
	if c >= 0.25:
		return "get along well"
	if c > -0.25:
		return "neutral"
	if c > -0.6:
		return "clash a bit"
	return "oil and water"

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
	var f: float = 1.0 + compatibility(a, b) * float(cfg().get("compat", {}).get("gain_scale", 0.5))
	f += warmth(a, b) * float(h.get("warmth_boost", 0.3)) - grudge(a, b) * float(h.get("grudge_dampen", 0.6))
	return clampf(f, 0.2, 1.8)

# ------------------------------------------------------------------ describe (UI text)
static func describe(a: int, b: int) -> String:
	var na: String = SysUtil.folk_name(a)
	var nb: String = SysUtil.folk_name(b)
	var bit: String = bit_for(a, b)
	var s: String = "%s -> %s: %s (friendship %d, romance %d)." % [na, nb, bit_label(bit), int(value(a, b, "friendship")), int(value(a, b, "romance"))]
	var rev: String = bit_for(b, a)
	if rev != bit:
		s += " They see %s as: %s." % [na, bit_label(rev)]
	s += " Together they %s." % compat_label(compatibility(a, b))
	var counts: Dictionary = {}
	for ev in history_for(a, b):
		counts[str(ev["kind"])] = int(counts.get(str(ev["kind"]), 0)) + 1
	if not counts.is_empty():
		var parts: Array = []
		for k in counts:
			parts.append("%d %s" % [counts[k], str(k).replace("_", " ")])
		s += " History: " + ", ".join(parts) + "."
	if grudge(a, b) > 0.3:
		s += " %s holds a grudge." % na
	elif warmth(a, b) > 0.3:
		s += " %s feels warmly towards %s." % [na, nb]
	s += " Trust %d." % int(value(a, b, "trust"))
	if value(a, b, "tension") >= 10.0:
		s += " Tension %d." % int(value(a, b, "tension"))
	var stage: String = romance_stage(a, b)
	if stage != "none":
		s += " Romance: %s (spark %s)." % [stage_label(stage).to_lower(), spark_hearts(a, b)]
	return s

# ------------------------------------------------------------------ event handlers
static func on_relationship_changed(a: int, b: int, _track: String) -> void:
	_sync_pair(a, b)
	touch(a, b)
	_refresh_bits(a, b)

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
				extra = delta * (compatibility(x, y) * gscale + w * float(h.get("warmth_boost", 0.3)) - g * float(h.get("grudge_dampen", 0.6)))
			else:
				extra = delta * (g * float(h.get("grudge_amplify", 0.5)) - compatibility(x, y) * gscale * 0.3)
			if absf(extra) > 0.01:
				add_value(y, x, track, extra)   # the receiver's view of the giver
	add_history(folk_id, t, iid, sentiment, folk_id)
	if not res.is_empty():
		_tag_last_history(folk_id, t, str(res.get("tier", "")), str(res.get("label", "")))
	touch(folk_id, t)
	# Memory feeds autonomy (Folk.memory_bias on "folk:<id>" keys).
	var ms: float = float(h.get("memory_scale", 0.35))
	var fa = SysUtil.folk(folk_id)
	var ft = SysUtil.folk(t)
	if ft != null and absf(sentiment) >= 0.3:
		ft.remember("folk:%d" % folk_id, sentiment * ms)
	if fa != null and absf(sentiment) >= 0.3:
		fa.remember("folk:%d" % t, sentiment * ms * 0.5)
	auto_status(folk_id, t)
	_check_jealousy(folk_id, t, iid)
	SocialDynamics.after_social(folk_id, t, iid, d, res)
	SysUtil.game_event("social_done", {"folk_id": folk_id, "target_id": t, "interaction": iid, "sentiment": sentiment,
		"tier": str(res.get("tier", "")), "outcome": str(res.get("label", ""))})

static func _check_jealousy(actor: int, target: int, iid: String) -> void:
	var j: Dictionary = cfg().get("jealousy", {})
	if not bool(j.get("enabled", true)) or not (j.get("triggers", []) as Array).has(iid):
		return
	var fa = SysUtil.folk(actor)
	for partner_id in exclusive_partners(actor):
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
static func on_day(_day: int) -> void:
	var dc: Dictionary = cfg().get("decay", {})
	var today: int = SysUtil.day()
	for key in pairs.keys():
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
		auto_status(int(p["lo"]), int(p["hi"]))
	SocialDynamics.on_day(_day)

# ------------------------------------------------------------------ social depth: trust / tension / knowledge / secrets / romance
static func _sub(p: Dictionary, key: String, default: Variant) -> Variant:
	if not p.has(key):
		p[key] = default
	return p[key]

## Trait conflicts / affinities (data/traits.json) feed compatibility on top of the social.json pair table.
static func _trait_social_compat(a: int, b: int) -> float:
	var total: float = 0.0
	var data = SimEnv.data()
	for x in traits_of(a):
		var xd: Dictionary = data.trait_def(str(x))
		for y in traits_of(b):
			var yd: Dictionary = data.trait_def(str(y))
			if (xd.get("conflicts", []) as Array).has(str(y)) or (yd.get("conflicts", []) as Array).has(str(x)):
				total -= 0.4
			if (xd.get("affinities", []) as Array).has(str(y)) or (yd.get("affinities", []) as Array).has(str(x)):
				total += 0.35
	return total

static func tension(a: int, b: int) -> float:
	return value(a, b, "tension")

static func add_tension(a: int, b: int, delta: float) -> void:
	var v: float = clampf(value(a, b, "tension") + delta, 0.0, 100.0)
	set_value(a, b, "tension", v)
	if v >= float(cfg().get("arguments", {}).get("resolve_below", 10)) * 2.0:
		_pair(a, b)["heated"] = true

static func trust(a: int, b: int) -> float:
	return value(a, b, "trust")

## Keep the directional `bond` / `ex` status tracks in step with the pair flags.
static func _update_bond_tracks(a: int, b: int) -> void:
	var p: Dictionary = _pair(a, b)
	var fl: Dictionary = p["flags"]
	var rank: float = 0.0
	if fl.get("spouse", false):
		rank = 4.0
	elif fl.get("partner", false):
		rank = 3.0
	elif fl.get("sweetheart", false):
		rank = 2.0
	elif fl.get("dating", false):
		rank = 1.0
	var ex: float = 1.0 if fl.get("ex", false) else 0.0
	for dir in [[a, b], [b, a]]:
		if not is_equal_approx(value(dir[0], dir[1], "bond"), rank):
			set_value(dir[0], dir[1], "bond", rank)
		if not is_equal_approx(value(dir[0], dir[1], "ex"), ex):
			set_value(dir[0], dir[1], "ex", ex)

## Folk `a` is romantically attached to (spouse / partner / sweetheart / dating). romantic_partners() keeps its old meaning.
static func exclusive_partners(a: int) -> Array:
	var out: Array = []
	for key in pairs:
		var p: Dictionary = pairs[key]
		var other: int = -1
		if int(p["lo"]) == a:
			other = int(p["hi"])
		elif int(p["hi"]) == a:
			other = int(p["lo"])
		if other < 0:
			continue
		var fl: Dictionary = p["flags"]
		if fl.get("spouse", false) or fl.get("partner", false) or fl.get("sweetheart", false) or fl.get("dating", false):
			out.append(other)
	return out

static func is_ex(a: int, b: int) -> bool:
	return has_flag(a, b, "ex")

## State machine for a pair's romance: none -> crush -> flirting -> dating -> sweethearts -> partners -> engaged -> married,
## with `ex` after a breakup. Symmetric (uses the weaker side for flirting).
static func romance_stage(a: int, b: int) -> String:
	var p: Dictionary = _pair(a, b, false)
	var rc: Dictionary = cfg().get("romance", {})
	if not p.is_empty():
		var fl: Dictionary = p["flags"]
		if fl.get("spouse", false):
			return "married"
		if Family.fiance_of(a) == b:
			return "engaged"
		if fl.get("partner", false):
			return "partners"
		if fl.get("sweetheart", false):
			return "sweethearts"
		if fl.get("dating", false):
			return "dating"
		if fl.get("ex", false):
			return "ex"
	var r1: float = value(a, b, "romance")
	var r2: float = value(b, a, "romance")
	if maxf(r1, r2) < float(rc.get("crush_min", 20)):
		return "none"
	if minf(r1, r2) >= float(rc.get("crush_min", 20)) and maxf(r1, r2) >= float(rc.get("flirt_min", 30)):
		return "flirting"
	return "crush"

static func stage_label(stage: String) -> String:
	return {"none": "No spark yet", "crush": "Crush", "flirting": "Flirting", "dating": "Dating", "sweethearts": "Sweethearts", "partners": "Partners",
		"engaged": "Engaged", "married": "Married", "ex": "Exes"}.get(stage, stage.capitalize())

## Chemistry 0..1: a stable per-pair roll nudged by trait compatibility. Romantic interactions use it as a bonus / penalty.
static func spark(a: int, b: int) -> float:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var h: int = posmod(lo * 73856093 ^ hi * 19349663, 1000)
	var roll: float = float(h) / 999.0
	return clampf(0.5 + compatibility(a, b) * 0.35 + (roll - 0.5) * 0.5, 0.0, 1.0)

static func spark_hearts(a: int, b: int) -> String:
	var n: int = int(round(spark(a, b) * 5.0))
	return "♥".repeat(n) + "♡".repeat(5 - n)

static func start_dating(a: int, b: int, announce: bool = true) -> void:
	set_flag(a, b, "dating", true, announce)
	var p: Dictionary = _pair(a, b)
	if not p.has("dates"):
		p["dates"] = 0

static func dates_count(a: int, b: int) -> int:
	return int(_pair(a, b, false).get("dates", 0))

## End a dating / sweetheart / partner relationship (spouses must divorce). Returns false when there is nothing to end.
static func breakup(initiator: int, other: int, cause: String = "breakup", severity: float = 1.0) -> bool:
	var p: Dictionary = _pair(initiator, other, false)
	if p.is_empty():
		return false
	var fl: Dictionary = p["flags"]
	if fl.get("spouse", false) or not (fl.get("partner", false) or fl.get("sweetheart", false) or fl.get("dating", false)):
		return false
	var rc: Dictionary = cfg().get("romance", {})
	set_flag(initiator, other, "ex", true, false)
	var cap: float = float(rc.get("breakup_romance_cap", 5))
	for dir in [[initiator, other], [other, initiator]]:
		if value(dir[0], dir[1], "romance") > cap:
			set_value(dir[0], dir[1], "romance", cap)
	p["dates"] = 0
	add_history(initiator, other, "break_up", -1.0, initiator)
	var fi = SysUtil.folk(initiator)
	var fo = SysUtil.folk(other)
	if cause == "cheating":
		if fi != null:
			fi.add_buff("heartbroken")
		if fo != null:
			fo.add_buff("guilty_pang")
	SysUtil.notify("%s and %s broke up%s." % [SysUtil.folk_name(initiator), SysUtil.folk_name(other), " (cheating)" if cause == "cheating" else ""], "relationship")
	SysUtil.game_event("breakup", {"folk_id": initiator, "target_id": other, "cause": cause, "severity": severity})
	if fi != null and fo != null:
		Emotions.imprint_pair(fi, fo, -0.5 * minf(severity, 1.4), "breakup", "the breakup")
	return true

## Mark the last shared-history entry with the outcome tier / label of the interaction that just ran.
static func _tag_last_history(a: int, b: int, tier: String, text: String) -> void:
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty() or (p["history"] as Array).is_empty():
		return
	var ev: Dictionary = (p["history"] as Array).back()
	if tier != "":
		ev["tier"] = tier
	if text != "":
		ev["label"] = text

# ---- knowledge ("getting to know")
static func _know(a: int, b: int) -> Dictionary:
	var p: Dictionary = _pair(a, b)
	var ks: Dictionary = _sub(p, "knows", {})
	var key: String = "%d>%d" % [a, b]
	if not ks.has(key):
		ks[key] = {"traits": [], "career": false, "aspiration": false, "interests": []}
	return ks[key]

static func knows_everything(a: int, b: int) -> bool:
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty():
		return false
	var fl: Dictionary = p["flags"]
	for bit in cfg().get("knowledge", {}).get("full_bits", []):
		if fl.get(str(bit), false):
			return true
	return false

static func knows_trait(a: int, b: int, t: String) -> bool:
	if knows_everything(a, b):
		return true
	return (_know(a, b)["traits"] as Array).has(t)

static func knows_career(a: int, b: int) -> bool:
	return knows_everything(a, b) or bool(_know(a, b)["career"])

static func knows_aspiration(a: int, b: int) -> bool:
	return knows_everything(a, b) or bool(_know(a, b)["aspiration"])

static func knows_interest(a: int, b: int, topic: String) -> bool:
	return knows_everything(a, b) or (_know(a, b)["interests"] as Array).has(topic)

static func known_traits(a: int, b: int) -> Array:
	var out: Array = []
	for t in traits_of(b):
		if knows_trait(a, b, str(t)):
			out.append(str(t))
	return out

static func unknown_trait_count(a: int, b: int) -> int:
	return traits_of(b).size() - known_traits(a, b).size()

## `a` learns something about `b`. kind: trait | career | aspiration | interest | all. Returns what was learned ("" = nothing new).
static func reveal(a: int, b: int, kind: String, detail: String = "") -> String:
	if a == b:
		return ""
	var k: Dictionary = _know(a, b)
	var got: String = ""
	match kind:
		"trait":
			var cand: Array = []
			for t in traits_of(b):
				if not (k["traits"] as Array).has(str(t)):
					cand.append(str(t))
			if not cand.is_empty():
				var pick: String = str(SysUtil.pick(cand))
				(k["traits"] as Array).append(pick)
				got = "trait:" + pick
		"career":
			if not bool(k["career"]):
				k["career"] = true
				got = "career"
		"aspiration":
			if not bool(k["aspiration"]):
				k["aspiration"] = true
				got = "aspiration"
		"interest":
			var ints: Array = Conversation.interests_of(b)
			var cand2: Array = []
			for t2 in ints:
				if not (k["interests"] as Array).has(str(t2)):
					cand2.append(str(t2))
			if not cand2.is_empty():
				var pick2: String = detail if cand2.has(detail) else str(SysUtil.pick(cand2))
				(k["interests"] as Array).append(pick2)
				got = "interest:" + pick2
		"all":
			for t3 in traits_of(b):
				if not (k["traits"] as Array).has(str(t3)):
					(k["traits"] as Array).append(str(t3))
			k["career"] = true
			k["aspiration"] = true
			for t4 in Conversation.interests_of(b):
				if not (k["interests"] as Array).has(str(t4)):
					(k["interests"] as Array).append(str(t4))
			got = "all"
	if got != "":
		SysUtil.game_event("knowledge_revealed", {"folk_id": a, "target_id": b, "what": got})
	return got

## UI summary of what `a` knows about `b`: unknown things are "?".
static func known_summary(a: int, b: int) -> Dictionary:
	var tl: Array = []
	for t in traits_of(b):
		var known: bool = knows_trait(a, b, str(t))
		tl.append({"id": str(t), "label": str(SimEnv.data().trait_def(str(t)).get("label", str(t).capitalize())) if known else "?", "known": known})
	var career: String = "?"
	if knows_career(a, b):
		career = Careers.title_of(b) if Careers.has_job(b) else "Unemployed"
		if career == "":
			career = "Unemployed"
	var asp: String = "?"
	if knows_aspiration(a, b):
		asp = Goals.aspiration_label(b)
		if asp == "":
			asp = "None yet"
	var ints: Array = []
	for t2 in Conversation.interests_of(b):
		if knows_interest(a, b, str(t2)):
			ints.append(Conversation.topic_label(str(t2)))
	var total: float = float(tl.size()) + 2.0
	var got: float = 0.0
	for e in tl:
		if bool(e["known"]):
			got += 1.0
	if career != "?":
		got += 1.0
	if asp != "?":
		got += 1.0
	return {"traits": tl, "career": career, "aspiration": asp, "interests": ints, "progress": got / maxf(total, 1.0), "everything": knows_everything(a, b)}

# ---- secrets / gossip / reputation
static func ensure_secrets(owner: int) -> Array:
	if secrets.has(owner):
		return secrets[owner]
	var pool: Array = cfg().get("secrets", [])
	var list: Array = []
	if not pool.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = owner * 7919 + 13
		var tr: Array = traits_of(owner)
		var used: Array = []
		for n in 2:
			var items: Array = []
			var weights: Array = []
			for i in pool.size():
				if used.has(i):
					continue
				var w: float = 1.0
				for t in pool[i].get("traits", []):
					if tr.has(str(t)):
						w += 3.0
				items.append(i)
				weights.append(w)
			var total: float = 0.0
			for w2 in weights:
				total += float(w2)
			var roll: float = r.randf() * total
			var chosen: int = int(items[items.size() - 1])
			for j in items.size():
				roll -= float(weights[j])
				if roll <= 0.0:
					chosen = int(items[j])
					break
			used.append(chosen)
			var sd: Dictionary = pool[chosen]
			list.append({"id": n, "kind": str(sd["kind"]), "text": str(sd["text"]), "severity": float(sd.get("severity", 0.4)), "known_by": []})
	secrets[owner] = list
	return list

## A secret of `owner` that `to_id` does not know yet ({} if none).
static func secret_for_sharing(owner: int, to_id: int) -> Dictionary:
	for s in ensure_secrets(owner):
		if not (s["known_by"] as Array).has(to_id):
			return s
	return {}

static func knows_secret(learner: int, owner: int, sid: int) -> bool:
	for s in ensure_secrets(owner):
		if int(s["id"]) == sid:
			return (s["known_by"] as Array).has(learner)
	return false

static func secrets_known_by(learner: int) -> Array:
	var out: Array = []
	for owner in secrets:
		for s in secrets[owner]:
			if (s["known_by"] as Array).has(learner):
				out.append({"owner": int(owner), "text": str(s["text"]), "kind": str(s["kind"]), "id": int(s["id"])})
	return out

static func learn_secret(learner: int, owner: int, sid: int) -> void:
	for s in ensure_secrets(owner):
		if int(s["id"]) == sid and not (s["known_by"] as Array).has(learner):
			(s["known_by"] as Array).append(learner)
			add_gossip(learner, owner, "%s %s" % [SysUtil.folk_name(owner), str(s["text"])], "secret", sid)
			SysUtil.game_event("secret_learned", {"folk_id": learner, "target_id": owner, "secret": sid})
			return

static func add_gossip(holder: int, about: int, text: String, kind: String, sid: int = -1, other: int = -1) -> void:
	if holder == about:
		return
	var list: Array = gossip_items.get(holder, [])
	for it in list:
		if int(it["about"]) == about and str(it["text"]) == text:
			return
	list.append({"about": about, "other": other, "text": text, "kind": kind, "sid": sid, "day": SysUtil.day(), "told": []})
	var mx: int = int(cfg().get("gossip", {}).get("max_items", 6))
	while list.size() > mx:
		list.pop_front()
	gossip_items[holder] = list

static func gossip_for(holder: int) -> Array:
	return gossip_items.get(holder, [])

static func reputation(id: int) -> float:
	return float(reputation_map.get(id, 0.0))

static func add_reputation(id: int, delta: float) -> void:
	var rc: Dictionary = cfg().get("reputation", {})
	reputation_map[id] = clampf(reputation(id) + delta, float(rc.get("min", -100)), float(rc.get("max", 100)))

# ---- conversation topic counters
static func topic_count(a: int, b: int, topic: String) -> float:
	var p: Dictionary = _pair(a, b, false)
	if p.is_empty():
		return 0.0
	return float((p.get("topics", {}) as Dictionary).get(topic, 0.0))

static func note_topic(a: int, b: int, topic: String) -> void:
	if topic == "":
		return
	var p: Dictionary = _pair(a, b)
	var tc: Dictionary = _sub(p, "topics", {})
	tc[topic] = minf(float(tc.get(topic, 0.0)) + 1.0, float(cfg().get("topic_rules", {}).get("max_count", 8)))

## Test helper: forget the topic counters of a pair.
static func pair_reset_topics_for_test(a: int, b: int) -> void:
	var p: Dictionary = _pair(a, b, false)
	if not p.is_empty():
		p["topics"] = {}

# ---- shared-history snippets for the UI
static func history_snippets(a: int, b: int, n: int = 3) -> Array:
	var out: Array = []
	var h: Array = history_for(a, b)
	for i in range(h.size() - 1, maxi(h.size() - 1 - n, -1), -1):
		var ev: Dictionary = h[i]
		var who: String = "You" if int(ev["by"]) == a else SysUtil.folk_name(int(ev["by"]))
		var what: String = str(SimEnv.data().interaction_def(str(ev["kind"])).get("label", str(ev["kind"]).replace("_", " ").capitalize()))
		var lab: String = str(ev.get("label", ""))
		out.append("Day %d: %s - %s%s" % [int(ev["day"]), who, what, (" (" + lab + ")") if lab != "" else ""])
	return out

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

static func _ints(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		out.append(int(x))
	return out

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
			e["known_by"] = _ints(e.get("known_by", []))
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
			ge["told"] = _ints(ge.get("told", []))
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
			_bit_cache["%d>%d" % [dir[0], dir[1]]] = bit_for(dir[0], dir[1])
