class_name PregnancyPostpartum
extends RefCounted
## After the birth (task 18 part 6): recovery (energy and comfort penalties for a few days; longer after a caesarean) and, rarely, postpartum
## depression: sad moods for a while, less likely with the partner and the household around, shorter with a counsellor (the "Talk to a
## Counsellor" action). The newborn-care loop itself is BabyCare (existing); the new-parent moods come from Family.on_birth.
## Data: data/pregnancy.json "postpartum".

static func cfg() -> Dictionary:
	return Pregnancy.cfg("postpartum")

static func recover(id: int, days: float) -> void:
	var m = SysUtil.folk(id)
	if m == null:
		return
	m.add_buff("postpartum_recovery")
	for b in m.buffs:
		if str(b["id"]) == "postpartum_recovery":
			b["remaining"] = days * 1440.0

## Chance of postpartum depression for this mother (the partner and other adults at home lower it).
static func depression_chance(mother_id: int, father_id: int) -> float:
	var m = SysUtil.folk(mother_id)
	var c: Dictionary = cfg()
	var p: float = float(c.get("depression", 0.06))
	if m == null:
		return p
	var helpers: int = 0
	for o in SysUtil.residents():
		if int(o.id) != mother_id and int(o.household_id) == int(m.household_id) and str(o.age_stage) in ["adult", "elder"]:
			helpers += 1
	if father_id >= 0 and SysUtil.folk(father_id) != null:
		p *= 1.0 - float(c.get("partner_help", 0.3))
	return p * (1.0 - float(c.get("support_cut", 0.25)) * float(mini(maxi(helpers - 1, 0), 2)))

## Called at every birth for the mother.
static func after_birth(mother_id: int, father_id: int) -> void:
	var m = SysUtil.folk(mother_id)
	if m == null:
		return
	var c: Dictionary = cfg()
	if not m.has_buff("postpartum_recovery"):
		recover(mother_id, float(c.get("recovery_days", 3)))
	if Pregnancy.rng.randf() < depression_chance(mother_id, father_id):
		m.add_buff("postpartum_low")
		for b in m.buffs:
			if str(b["id"]) == "postpartum_low":
				b["remaining"] = float(c.get("depression_days", 4)) * 1440.0
		SysUtil.notify(Sexes.fill("%s feels very low since the birth. Family, a partner's help and a counsellor can make a difference." % m.name, mother_id), "info")
		SysUtil.game_event("postpartum_low", {"folk_id": mother_id})
