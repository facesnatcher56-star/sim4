class_name Straying
extends RefCounted
## Does a person who is already committed (spouse, partner, sweetheart, dating) look at somebody else? Only now and then, and
## for reasons: a romantic or charming nature, an unhappy or cooling relationship, a real crush on the other person, or a
## storyteller nudge (the "tempted" buff). Single people are never limited. Autonomy.gather asks `may_flirt` before it offers a
## romantic interaction towards someone who is not the person's partner (RomanceRules.allowed is still asked as well).
## Deterministic: the answer is a hash of (person, other, window of days), so it holds steady for a few days (a "stretch of
## temptation" for that one pair) and needs no saved state. Data: data/straying.json.
## Hook for the storyteller: `Straying.tempt(folk_id)` (fx "tempt" in data/storyteller_cards.json) gives the buff for a week.

static func cfg() -> Dictionary:
	return SysUtil.table("straying")

## May `a` (with the cached committed partners `partners`) autonomously go romantic with `b`?
static func may_flirt(a: int, b: int, partners: Array) -> bool:
	if partners.is_empty() or partners.has(b):
		return true
	var c: Dictionary = cfg()
	if c.is_empty():
		return true
	var fa = SysUtil.folk(a)
	if fa != null and fa.has_buff(str(c.get("tempted_buff", "tempted"))):
		return true
	return roll(a, b, SysUtil.day()) < chance(a, b, partners)

## Uniform 0..1, steady for a pair within a window of days.
static func roll(a: int, b: int, day: int) -> float:
	var w: int = day / maxi(int(cfg().get("window_days", 3)), 1)
	var h: int = ((a + 1) * 73856093) ^ ((b + 1) * 19349663) ^ ((w + 1) * 83492791)
	h = (h ^ (h >> 13)) & 0x7fffffff
	h = (h * 1103515245 + 12345) & 0x7fffffff
	return float(h % 10000) / 10000.0

## Chance that a stretch of temptation opens for this pair (per window of days).
static func chance(a: int, b: int, partners: Array) -> float:
	var c: Dictionary = cfg()
	var p: float = float(c.get("base", 0.004))
	var fa = SysUtil.folk(a)
	if fa != null:
		var tm: Dictionary = c.get("trait_mult", {})
		for t in tm:
			if fa.has_trait(str(t)):
				p *= float(tm[t])
	var weakest: float = 100.0
	var bm: float = 1.0
	for pid in partners:
		weakest = minf(weakest, RelationshipService.value(a, int(pid), "romance"))
		for fl in c.get("bond_mult", {}):
			if RelationshipBits.has_flag(a, int(pid), str(fl)):
				bm = maxf(bm, float(c["bond_mult"][fl]))
	p *= bm
	var m: Dictionary = c.get("marriage", {})
	if weakest < float(m.get("romance_low", 30)):
		p *= float(m.get("low_mult", 8.0))
	elif weakest < float(m.get("romance_mid", 60)):
		p *= float(m.get("mid_mult", 2.0))
	var cr: Dictionary = c.get("crush", {})
	if RelationshipService.value(a, b, "romance") > float(cr.get("romance_above", 40)):
		p *= float(cr.get("mult", 3.0))
	return minf(p, float(c.get("max", 0.5)))

## Storyteller hook: the person is tempted for a week (may flirt with anyone allowed).
static func tempt(folk_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f != null and not RelationshipRomance.exclusive_partners(folk_id).is_empty():
		f.add_buff(str(cfg().get("tempted_buff", "tempted")))
