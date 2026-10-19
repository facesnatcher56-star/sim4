class_name Conception
extends RefCounted
## Whether and how a couple conceives (task 18 part 2). The ONLY door to a new pregnancy: `Aging.try_for_baby`, the "Get intimate" actions and
## the daily couple dice all land here.
## Hard rules, in this order, every time:
##   1. RomanceRules.allowed(a, b)  (adults only, never family) - never bypassed;
##   2. one female and one male - the FEMALE is always the carrier, whichever folk started the action; a same-sex couple cannot conceive
##      (they can adopt, or use the clinic route);
##   3. both fertile enough: elders and non-adults have none (Fertility), the infertile do not conceive;
##   4. no pregnancy running, not in the after-birth pause.
## Then a dice: planned "try" = success_chance (data/aging.json) x couple fertility; intimate = unprotected / protected chance x couple fertility.
## Determinism: Pregnancy.rng (seeded by SimSeed.apply). Tier behaviour: event driven; the daily couple dice run for the controlled
## households' couples only (StoryMilestones), townies use PregnancyTownie.

## {ok, reason, carrier, other}. Checks only: no dice, no side effects.
static func check(a: int, b: int) -> Dictionary:
	if SysUtil.folk(a) == null or SysUtil.folk(b) == null:
		return {"ok": false, "reason": "missing"}
	if not RomanceRules.allowed(a, b):
		return {"ok": false, "reason": "not_allowed" if RomanceRules.is_adult(a) and RomanceRules.is_adult(b) else "too_young"}
	var sa: String = Sexes.of(a)
	var sb: String = Sexes.of(b)
	if sa == sb:
		return {"ok": false, "reason": "same_sex"}
	var carrier: int = a if sa == Sexes.FEMALE else b
	var other: int = b if carrier == a else a
	if Fertility.by_age(carrier) <= 0.0 or Fertility.by_age(other) <= 0.0:
		return {"ok": false, "reason": "too_young" if RomanceRules.stage_of(carrier) in ["baby", "toddler", "child", "teen"] or RomanceRules.stage_of(other) in ["baby", "toddler", "child", "teen"] else "too_old"}
	if Aging.pregnancies.has(carrier):
		return {"ok": false, "reason": "already_pregnant"}
	return {"ok": true, "reason": "ok", "carrier": carrier, "other": other}

## The pair's chance factor 0..1 (both partners count; the carrier more).
static func couple_fertility(carrier: int, other: int) -> float:
	return Fertility.of(carrier) * (0.5 + 0.5 * Fertility.of(other))

## Can this pair ever conceive right now (for buttons and tooltips)? Plain-word reason when not.
static func why_not(a: int, b: int) -> String:
	var c: Dictionary = check(a, b)
	if bool(c["ok"]):
		return ""
	return {"same_sex": "They cannot have a baby together. They could adopt.", "too_old": "Too old to have a baby.", "too_young": "Too young for that.",
		"not_allowed": "They are family.", "already_pregnant": "A baby is already on the way.", "missing": "Needs a partner who is here."}.get(str(c["reason"]), "Not possible.")

# ------------------------------------------------------------------ planned: "Try for Baby"
## `actor_id` and `partner_id` in either order. Returns {ok, reason, carrier?}.
static func try_for_baby(actor_id: int, partner_id: int) -> Dictionary:
	var pc: Dictionary = Aging.cfg().get("pregnancy", {})
	var c: Dictionary = check(actor_id, partner_id)
	if not bool(c["ok"]):
		return c
	var carrier: int = int(c["carrier"])
	var other: int = int(c["other"])
	if SysUtil.day() < int(Aging.cooldowns.get(carrier, 0)) or Fertility.resting(carrier):
		return {"ok": false, "reason": "cooldown"}
	var rom: float = minf(RelationshipService.value(actor_id, partner_id, "romance"), RelationshipService.value(partner_id, actor_id, "romance"))
	if rom < float(pc.get("min_romance", 45)):
		return {"ok": false, "reason": "not_romantic_enough"}
	if not (RelationshipBits.bit_for(actor_id, partner_id) in ["sweetheart", "partner", "spouse"]):
		return {"ok": false, "reason": "not_a_couple"}
	Aging.cooldowns[carrier] = SysUtil.day() + int(pc.get("cooldown_days", 4))
	var p: float = minf(float(pc.get("success_chance", 0.45)) * couple_fertility(carrier, other), 1.0)
	if Pregnancy.rng.randf() >= p:
		Fertility.note_failed_try(carrier)
		Fertility.note_failed_try(other)
		return {"ok": false, "reason": "no_luck", "carrier": carrier}
	return _conceive(carrier, other, true)

# ------------------------------------------------------------------ unplanned: "Get intimate"
## One quiet evening together (nothing is shown beyond a short scene). protection: "none" | "protected". A pregnancy can follow, rarely.
static func intimate(a: int, b: int, protection: String) -> Dictionary:
	var c: Dictionary = check(a, b)
	if not bool(c["ok"]):
		return c
	var carrier: int = int(c["carrier"])
	var other: int = int(c["other"])
	var cc: Dictionary = Pregnancy.cfg("conception")
	var base: float = float(cc.get("protected_chance", 0.01)) if protection == "protected" else float(cc.get("unprotected_chance", 0.1))
	if Fertility.resting(carrier):
		return {"ok": false, "reason": "cooldown"}
	if Pregnancy.rng.randf() >= minf(base * couple_fertility(carrier, other), 1.0):
		return {"ok": false, "reason": "no_luck", "carrier": carrier}
	return _conceive(carrier, other, false)

## Which protection a couple uses on a quiet evening of their own: traits shift the share (data conception.protected_share*).
static func pick_protection(a: int, b: int) -> String:
	var cc: Dictionary = Pregnancy.cfg("conception")
	var share: float = float(cc.get("protected_share", 0.75))
	var ts: Dictionary = cc.get("protected_share_traits", {})
	for id in [a, b]:
		var f = SysUtil.folk(id)
		if f == null:
			continue
		for t in f.traits:
			if ts.has(str(t)):
				share = minf(share, float(ts[str(t)]))
	return "protected" if Pregnancy.rng.randf() < share else "none"

static func _conceive(carrier: int, other: int, planned: bool) -> Dictionary:
	var r: Dictionary = Pregnancy.start(carrier, other, planned)
	Paternity.at_conception(carrier, other, r)
	return {"ok": true, "reason": "pregnant", "carrier": carrier}
