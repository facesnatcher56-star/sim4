class_name PregnancyBirth
extends RefCounted
## The birth itself (task 18 parts 5-6). `deliver(mother, father)` is the end of labour (PregnancyLabour.finish): it creates the baby / twins /
## triplets from the pregnancy record (sexes were decided at conception, so an ultrasound could tell) with inherited looks and traits, the
## family links, a hospital stay when the labour was planned there, the notification, and then the after-birth layers in this order:
## partner present or absent, recovery and postpartum depression, leave, the rest period, paternity doubt, congratulations and small gifts
## from family and friends, the naming prompt for the player's folk, and last the complication (rare, safer at the hospital).
## The chronicle line comes from the baby_born event (ChronicleHook).

static func deliver(mother_id: int, father_id: int) -> Array:
	var m = SysUtil.folk(mother_id)
	var r: Dictionary = Pregnancy.rec(mother_id)
	if m == null:
		return []
	var pc: Dictionary = Aging.cfg().get("pregnancy", {})
	var place: String = str((r.get("labour", {}) as Dictionary).get("place", "home"))
	var kind: String = PregnancyComplication.roll(mother_id, r, place)
	var sexes: Array = r.get("kid_sexes", [])
	if sexes.is_empty():
		sexes = [Sexes.roll()]
	var babies: Array = []
	for i in sexes.size():
		babies.append(_make_baby(m, mother_id, father_id, str(sexes[i]), pc))
	m.remove_buff("pregnant")
	m.remove_buff("feeling_off")
	m.remove_buff("bed_rest")
	m.remove_buff("in_labour")
	var first = babies[0]
	for b in babies:
		Family.on_birth(b, mother_id, father_id)
		for pid2 in [mother_id, father_id]:
			RelationshipBits.set_flag(int(b.id), int(pid2), "family", true, false)
			RelationshipService.add_both(int(b.id), int(pid2), "friendship", 40.0)
	RelationshipBits.set_flag(mother_id, father_id, "family", true, false)
	var in_hospital: bool = place == "hospital" and HospitalWard.lot_id() != "" and HospitalWard.birth(m, first)
	var names: Array = babies.map(func(b): return str(b.name))
	var label: String = names[0] if names.size() == 1 else ("%s and %s" % [names[0], names[1]] if names.size() == 2 else "%s, %s and %s" % [names[0], names[1], names[2]])
	var multi: String = "" if names.size() == 1 else (" Twins!" if names.size() == 2 else " Triplets!")
	SysUtil.notify("%s %s born to %s%s!%s" % [label, "was" if names.size() == 1 else "were", m.name, " at the hospital" if in_hospital else "", multi], "birthday")
	for b2 in babies:
		SysUtil.game_event("baby_born", {"folk_id": mother_id, "baby_id": b2.id, "target_id": father_id, "hospital": in_hospital, "multiple": names.size()})
	Fertility.rest_for(mother_id, int(Pregnancy.cfg("conception").get("after_birth_days", 4)))
	PregnancyLeave.on_birth(mother_id, father_id)
	PregnancyLabour.partner_at_birth(mother_id, father_id)
	PregnancyPostpartum.after_birth(mother_id, father_id)
	Paternity.after_birth(mother_id, r, babies)
	_congratulate(m, babies)
	PregnancyNaming.offer(mother_id, babies)
	PregnancyComplication.apply(kind, mother_id, babies)
	return babies

static func _make_baby(m, mother_id: int, father_id: int, sex: String, pc: Dictionary):
	var gen: Dictionary = Genetics.inherit(Family.person_info(mother_id), Family.person_info(father_id), null,
		{"chance": float(pc.get("inherit_chance", 0.35)), "cap": int(pc.get("max_inherited", 2)), "sex": sex})
	var baby_name: String = Names.pick_first([], SysUtil.rng, sex) + " " + Aging._surname(str(m.name))
	var baby := Folk.create(baby_name, [], -1, sex)
	baby.appearance = gen["appearance"]
	baby.household_id = int(m.household_id)
	baby.age_stage = "baby"
	Aging.register(baby, 0.0, [mother_id, father_id])
	(Aging.records[int(baby.id)] as Dictionary)["inherited"] = gen["traits"]
	for pid in [mother_id, father_id]:
		if Aging.records.has(pid):
			(Aging.records[pid]["children"] as Array).append(int(baby.id))
	SysUtil.world_add_folk(baby, m.tile)
	baby.level = int(m.level)                      # born on the mother's floor
	return baby

## Family and friends who live elsewhere send congratulations and a small gift (a few coins) to the household.
static func _congratulate(m, babies: Array) -> void:
	var c: Dictionary = Pregnancy.cfg("birth")
	var gifts: int = 0
	for o in SysUtil.residents():
		if int(o.household_id) == int(m.household_id) or str(o.age_stage) in ["baby", "toddler"]:
			continue
		var oid: int = int(o.id)
		if FamilyTree.is_kin(oid, int(m.id)) or RelationshipService.value(oid, int(m.id), "friendship") >= 30.0:
			RelationshipService.add_value(oid, int(m.id), "friendship", 3.0)
			o.add_buff("cheered_up")
			if gifts < int(c.get("gift_max", 3)):
				gifts += 1
				WorldIface.add_coins(int(m.household_id), int(c.get("gift_coins", 25)))
	if gifts > 0:
		SysUtil.notify("Friends and family sent their congratulations and small gifts for the new arrival%s." % ("s" if babies.size() > 1 else ""), "relationship")
