class_name RelationshipService
extends RefCounted
## Relationship layer on top of Folk.get_rel/add_rel (directional friendship + romance, -100..100).
##  * bits (acquaintance, friend, best_friend, enemy, crush, sweetheart, partner, spouse, family) from data/social.json
##  * per-pair shared history (last 30 events) that changes future reactions (grudges / warmth)
##  * trait compatibility, daily decay of unused relationships, jealousy when a bonded partner flirts with someone else
##  * persistent pair store, so relationships with folk who are off the lot (townies, visitors) survive
## Public for UI: bit_for(a,b), history_for(a,b), describe(a,b), compatibility(a,b), value(a,b,track).

const TRACKS := ["friendship", "romance"]

static var pairs: Dictionary = {}        # "lo_hi" -> {lo, hi, flags:{}, since:{}, history:[], last_contact, vals:{"lo>hi":{friendship,romance}, "hi>lo":{...}}}
static var _targets: Dictionary = {}     # folk_id -> target folk id of the running social interaction
static var _bit_cache: Dictionary = {}   # "a>b" -> bit id

static func reset() -> void:
	pairs.clear()
	_targets.clear()
	_bit_cache.clear()

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
		if ok:
			return str(bd["id"])
	return "stranger"

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
			for other_flag in ["spouse", "partner", "sweetheart"]:
				fl.erase(other_flag)
		fl[flag] = true
		(p["since"] as Dictionary)[flag] = SysUtil.day()
	else:
		fl.erase(flag)
	_refresh_bits(a, b)
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
	return s

# ------------------------------------------------------------------ event handlers
static func on_relationship_changed(a: int, b: int, _track: String) -> void:
	_sync_pair(a, b)
	touch(a, b)
	_refresh_bits(a, b)

static func on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if str(d.get("target", "object")) == "folk" and target_id >= 0:
		_targets[folk_id] = target_id
	else:
		_targets.erase(folk_id)

static func _loot_deltas(d: Dictionary) -> Dictionary:
	var out: Dictionary = {"friendship": 0.0, "romance": 0.0}
	for e in d.get("on_finish", []):
		if e is Dictionary and (e as Dictionary).has("relationship_add"):
			var ra: Array = e["relationship_add"]
			var chance: float = float(e.get("chance", 1.0))
			out[str(ra[0])] = float(out.get(str(ra[0]), 0.0)) + float(ra[1]) * chance
	return out

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if not _targets.has(folk_id):
		return
	var t: int = int(_targets[folk_id])
	_targets.erase(folk_id)
	if not success:
		return
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var h: Dictionary = cfg().get("history", {})
	var deltas: Dictionary = _loot_deltas(d)
	var kinds: Dictionary = h.get("kinds", {})
	var sentiment: float
	if kinds.has(iid):
		sentiment = float(kinds[iid])
	else:
		sentiment = clampf((float(deltas["friendship"]) + float(deltas["romance"])) / 6.0, -1.0, 1.0)
	# Reaction adjustment based on history before this event is logged.
	var gscale: float = float(cfg().get("compat", {}).get("gain_scale", 0.5))
	for track in TRACKS:
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
	SysUtil.game_event("social_done", {"folk_id": folk_id, "target_id": t, "interaction": iid, "sentiment": sentiment})

static func _check_jealousy(actor: int, target: int, iid: String) -> void:
	var j: Dictionary = cfg().get("jealousy", {})
	if not bool(j.get("enabled", true)) or not (j.get("triggers", []) as Array).has(iid):
		return
	var fa = SysUtil.folk(actor)
	for partner_id in romantic_partners(actor):
		if int(partner_id) == target:
			continue
		var fp = SysUtil.folk(int(partner_id))
		if fp == null or SysUtil.is_away(fp):
			continue
		if fa != null and Vector2(fp.tile - fa.tile).length() > float(j.get("range", 14)):
			continue
		add_value(int(partner_id), actor, "romance", -float(j.get("romance_loss", 8)))
		add_value(int(partner_id), actor, "friendship", -float(j.get("friendship_loss", 4)))
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
		var idle: int = today - int(p["last_contact"])
		for dir in [[int(p["lo"]), int(p["hi"])], [int(p["hi"]), int(p["lo"])]]:
			for track in TRACKS:
				var spec: Dictionary = dc.get(track, {})
				if idle < int(spec.get("idle_days", 2)):
					continue
				var v: float = value(dir[0], dir[1], track)
				if absf(v) < 0.01:
					continue
				var step: float = (float(spec.get("per_day", 1.0)) if v > 0.0 else float(spec.get("negative_per_day", 0.4))) * factor
				var nv: float = move_toward(v, 0.0, step)
				set_value(dir[0], dir[1], track, nv)
		auto_status(int(p["lo"]), int(p["hi"]))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"pairs": pairs.duplicate(true)}

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
	for key in pairs:
		var p2: Dictionary = pairs[key]
		for dir in [[int(p2["lo"]), int(p2["hi"])], [int(p2["hi"]), int(p2["lo"])]]:
			_bit_cache["%d>%d" % [dir[0], dir[1]]] = bit_for(dir[0], dir[1])
