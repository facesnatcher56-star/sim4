class_name PregnancyComplication
extends RefCounted
## Complications at birth (task 18 part 5), rare and much rarer at the hospital: an emergency caesarean (a longer recovery), a premature
## baby (extra care for a couple of days), and the mother's death, extremely rare. Rates scale with the pregnancy's risk (PregnancyRisk).
## Data: data/pregnancy.json "birth". Non-graphic: a notification and a buff, never a description.

static func cfg() -> Dictionary:
	return Pregnancy.cfg("birth")

## Roll for this birth. Returns "none" | "caesarean" | "premature" | "mother_died". place: home | hospital.
static func roll(_mother_id: int, r: Dictionary, place: String) -> String:
	var c: Dictionary = cfg()
	var mult: float = PregnancyRisk.multiplier(r)
	var safe: float = float(c.get("hospital_mult", 0.5)) if place == "hospital" else 1.0
	var death: float = float(c.get("mother_death_hospital" if place == "hospital" else "mother_death_home", 0.0006)) * mult
	if Pregnancy.rng.randf() < death:
		return "mother_died"
	if Pregnancy.rng.randf() < float(c.get("complication", 0.05)) * mult * safe:
		return "caesarean" if Pregnancy.rng.randf() < float(c.get("caesarean_share", 0.6)) else "premature"
	return "none"

## Apply the outcome to the mother and babies. Returns true when the mother died.
static func apply(kind: String, mother_id: int, babies: Array) -> bool:
	var m = SysUtil.folk(mother_id)
	if m == null or kind == "none":
		return false
	var c: Dictionary = cfg()
	SysUtil.game_event("birth_complication", {"folk_id": mother_id, "kind": kind})
	match kind:
		"caesarean":
			PregnancyPostpartum.recover(mother_id, float(c.get("caesarean_days", 6)))
			SysUtil.notify("%s needed an emergency caesarean. Mother and baby are fine, and %s needs a longer rest." % [m.name, Sexes.they(mother_id)], "info")
		"premature":
			for b in babies:
				b.add_buff("extra_care")
			SysUtil.notify("The baby came early and needs a little extra care for a few days.", "info")
		"mother_died":
			Aging.kill(mother_id, "childbirth")
			return true
	return false
