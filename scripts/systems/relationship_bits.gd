class_name RelationshipBits
extends RefCounted
## Relationship bits (labels), flags/status changes, compatibility and the describe text.

# ------------------------------------------------------------------ bits
static func bit_defs() -> Array:
	return RelationshipService.cfg().get("bits", [])

static func has_flag(a: int, b: int, flag: String) -> bool:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	return not p.is_empty() and bool((p["flags"] as Dictionary).get(flag, false))

## a's relationship bit towards b: spouse, partner, sweetheart, family, best_friend, enemy, crush, friend,
## acquaintance, or "stranger".
static func bit_for(a: int, b: int) -> String:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return "stranger"
	var fr: float = RelationshipService.value(a, b, "friendship")
	var ro: float = RelationshipService.value(a, b, "romance")
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
		if bd.has("trust_min") and RelationshipService.value(a, b, "trust") < float(bd["trust_min"]):
			ok = false
		if bd.has("trust_max") and RelationshipService.value(a, b, "trust") > float(bd["trust_max"]):
			ok = false
		if ok:
			return str(bd["id"])
	return "stranger"

## Specific kin relation of b to a (parent, child, sibling, grandparent, spouse, ...) from the Family service, "" if none.
static func kin_bit(a: int, b: int) -> String:
	return FamilyTree.relation_id(a, b)

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
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
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
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
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
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
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
		var old_bit: String = str(RelationshipService._bit_cache.get(k, "stranger"))
		if now_bit == old_bit:
			continue
		RelationshipService._bit_cache[k] = now_bit
		SysUtil.game_event("relationship_bit_changed", {"folk_id": x, "target_id": y, "bit": now_bit, "old": old_bit})
		if now_bit in ["friend", "best_friend", "enemy", "sweetheart", "partner", "spouse"] and SysUtil.folk(x) != null:
			if _bit_rank(now_bit) > _bit_rank(old_bit) or now_bit == "enemy":
				RelationshipToasts.announce(x, y, now_bit)

# ------------------------------------------------------------------ flags / status changes
static func set_flag(a: int, b: int, flag: String, on: bool = true, announce: bool = true) -> void:
	if on and RomanceRules.ROMANTIC_FLAGS.has(flag) and flag != "ex" and not RomanceRules.allowed(a, b):
		return
	var p: Dictionary = RelationshipService._pair(a, b)
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
	RelationshipRomance._update_bond_tracks(a, b)
	_refresh_bits(a, b)
	SocialGatherings.refresh_markers(SysUtil.folk(a))
	SocialGatherings.refresh_markers(SysUtil.folk(b))
	if on and announce and flag == "dating":
		RelNotify.say([a, b], "%s and %s are now dating!" % [SysUtil.folk_name(a), SysUtil.folk_name(b)], "relationship")
		SysUtil.game_event("relationship_status", {"folk_id": a, "target_id": b, "status": flag})
	if on and announce and flag in ["sweetheart", "partner", "spouse"]:
		SysUtil.notify("%s and %s are now %s!" % [SysUtil.folk_name(a), SysUtil.folk_name(b), bit_label(flag).to_lower() + "s"], "relationship")
		SysUtil.game_event("relationship_status", {"folk_id": a, "target_id": b, "status": flag})

## Who is `a` bonded to romantically (spouse > partner > sweetheart)?
static func romantic_partners(a: int) -> Array:
	var out: Array = []
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
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
	if not RomanceRules.allowed(a, b):
		return
	var c: Dictionary = RelationshipService.cfg()
	var sw: Dictionary = c.get("sweetheart", {})
	var p: Dictionary = RelationshipService._pair(a, b)
	var fl: Dictionary = p["flags"]
	if fl.get("spouse", false) or fl.get("partner", false):
		return
	var r1: float = RelationshipService.value(a, b, "romance")
	var r2: float = RelationshipService.value(b, a, "romance")
	var f1: float = RelationshipService.value(a, b, "friendship")
	var f2: float = RelationshipService.value(b, a, "friendship")
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
	if not RomanceRules.allowed(a, b):
		return "no_bond"
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return "no_bond"
	var fl: Dictionary = p["flags"]
	var ro: float = minf(RelationshipService.value(a, b, "romance"), RelationshipService.value(b, a, "romance"))
	var fr: float = minf(RelationshipService.value(a, b, "friendship"), RelationshipService.value(b, a, "friendship"))
	if fl.get("partner", false):
		if ro >= 80.0 and fr >= 60.0:
			set_flag(a, b, "spouse")
			SysUtil.game_event("married", {"folk_id": a, "target_id": b})
			return "accepted"
		return "declined" if ro < 60.0 else "too_soon"
	var need: float = float(RelationshipService.cfg().get("partner", {}).get("romance_min", 70))
	if fl.get("sweetheart", false) or ro >= float(RelationshipService.cfg().get("sweetheart", {}).get("romance_min", 45)):
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
	var pairs_t: Dictionary = RelationshipService.cfg().get("compat", {}).get("pairs", {})
	var total: float = 0.0
	for ta in traits_of(a):
		for tb in traits_of(b):
			var v: float = 0.0
			if pairs_t.has("%s:%s" % [ta, tb]):
				v = float(pairs_t["%s:%s" % [ta, tb]])
			elif pairs_t.has("%s:%s" % [tb, ta]):
				v = float(pairs_t["%s:%s" % [tb, ta]])
			total += v
	total += RelationshipRomance._trait_social_compat(a, b)
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

# ------------------------------------------------------------------ describe (UI text)
static func describe(a: int, b: int) -> String:
	var na: String = SysUtil.folk_name(a)
	var nb: String = SysUtil.folk_name(b)
	var bit: String = bit_for(a, b)
	var s: String = "%s -> %s: %s (friendship %d, romance %d)." % [na, nb, bit_label(bit), int(RelationshipService.value(a, b, "friendship")), int(RelationshipService.value(a, b, "romance"))]
	var rev: String = bit_for(b, a)
	if rev != bit:
		s += " They see %s as: %s." % [na, bit_label(rev)]
	s += " Together they %s." % compat_label(compatibility(a, b))
	var counts: Dictionary = {}
	for ev in RelationshipService.history_for(a, b):
		counts[str(ev["kind"])] = int(counts.get(str(ev["kind"]), 0)) + 1
	if not counts.is_empty():
		var parts: Array = []
		for k in counts:
			parts.append("%d %s" % [counts[k], str(k).replace("_", " ")])
		s += " History: " + ", ".join(parts) + "."
	if RelationshipService.grudge(a, b) > 0.3:
		s += " %s holds a grudge." % na
	elif RelationshipService.warmth(a, b) > 0.3:
		s += " %s feels warmly towards %s." % [na, nb]
	s += " Trust %d." % int(RelationshipService.value(a, b, "trust"))
	if RelationshipService.value(a, b, "tension") >= 10.0:
		s += " Tension %d." % int(RelationshipService.value(a, b, "tension"))
	var stage: String = RelationshipRomance.romance_stage(a, b)
	if stage != "none":
		s += " Romance: %s (spark %s)." % [RelationshipRomance.stage_label(stage).to_lower(), RelationshipRomance.spark_hearts(a, b)]
	return s