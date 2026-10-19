class_name PregnancyBirth
extends RefCounted
## The birth itself (task 18). `deliver(mother, father)` creates the baby / twins / triplets from the pregnancy record (sexes were decided at
## conception, so an ultrasound could tell), with inherited looks and traits, the family links, a hospital bed when there is a ward, the
## notification and the chronicle line. Labour, naming and complications are layered on top (PregnancyLabour, PregnancyNaming).

static func deliver(mother_id: int, father_id: int) -> Array:
	var m = SysUtil.folk(mother_id)
	var r: Dictionary = Pregnancy.rec(mother_id)
	if m == null:
		return []
	var pc: Dictionary = Aging.cfg().get("pregnancy", {})
	var sexes: Array = r.get("kid_sexes", [])
	if sexes.is_empty():
		sexes = [Sexes.roll()]
	var babies: Array = []
	for i in sexes.size():
		babies.append(_make_baby(m, mother_id, father_id, str(sexes[i]), pc))
	m.remove_buff("pregnant")
	m.remove_buff("feeling_off")
	m.remove_buff("bed_rest")
	var first = babies[0]
	for b in babies:
		Family.on_birth(b, mother_id, father_id)
		for pid2 in [mother_id, father_id]:
			RelationshipBits.set_flag(int(b.id), int(pid2), "family", true, false)
			RelationshipService.add_both(int(b.id), int(pid2), "friendship", 40.0)
	RelationshipBits.set_flag(mother_id, father_id, "family", true, false)
	var in_hospital: bool = HospitalWard.lot_id() != "" and SysUtil.chance(float(Hospital.cfg().get("birth", {}).get("chance", 0.7))) and HospitalWard.birth(m, first)
	var names: Array = babies.map(func(b): return str(b.name))
	var label: String = names[0] if names.size() == 1 else ("%s and %s" % [names[0], names[1]] if names.size() == 2 else "%s, %s and %s" % [names[0], names[1], names[2]])
	var kind: String = "" if names.size() == 1 else (" Twins!" if names.size() == 2 else " Triplets!")
	SysUtil.notify("%s %s born to %s%s!%s" % [label, "was" if names.size() == 1 else "were", m.name, " at the hospital" if in_hospital else "", kind], "birthday")
	for b2 in babies:
		SysUtil.game_event("baby_born", {"folk_id": mother_id, "baby_id": b2.id, "target_id": father_id, "hospital": in_hospital, "multiple": names.size()})
	Fertility.rest_for(mother_id, int(Pregnancy.cfg("conception").get("after_birth_days", 4)))
	PregnancyLeave.on_birth(mother_id, father_id)
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
