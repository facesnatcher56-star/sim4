extends RefCounted
## Loading an old save wipes romance values, romantic bits, marriages, engagements and hidden affairs of pairs RomanceRules forbids
## (a teen with an adult, siblings), and leaves a legitimate adult couple alone.

const S = preload("res://tests/social_kit.gd")
const SLOT := 94

func run() -> Array:
	var f: Array = []
	var w := S.setup(9104)
	var adult := S.K.make_folk(w, "Ada", [], 1, Vector2i(10, 12))
	var teen := S.K.make_folk(w, "Tess", [], 1, Vector2i(11, 12), "teen")
	var sib := S.K.make_folk(w, "Sam", [], 1, Vector2i(12, 12))
	var sib2 := S.K.make_folk(w, "Sue", [], 1, Vector2i(13, 12))
	var lover := S.K.make_folk(w, "Lee", [], 1, Vector2i(14, 12))
	var mate := S.K.make_folk(w, "Max", [], 1, Vector2i(15, 12))
	var mum := S.K.make_folk(w, "Mum", [], 1, Vector2i(16, 12))
	Family.link_parent(sib.id, mum.id)
	Family.link_parent(sib2.id, mum.id)
	_force(adult, teen, "partner")
	_force(sib, sib2, "spouse")
	Family.spouses[sib.id] = sib2.id
	Family.spouses[sib2.id] = sib.id
	_force(lover, mate, "partner")                                   # the legitimate couple
	RelationshipService.affairs.append({"cheater": adult.id, "other": teen.id, "victim": lover.id, "day": 1})
	RelationshipService.affairs.append({"cheater": lover.id, "other": mate.id, "victim": adult.id, "day": 1})
	S.expect(f, RelationshipService.value(adult.id, teen.id, "romance") == 70.0 and RelationshipBits.has_flag(sib.id, sib2.id, "spouse"), "precondition: the old save holds the forbidden pairs")
	S.expect(f, SaveLoad.save(SLOT, "romance cleanup"), "save works: %s" % SaveLoad.last_error)
	RelationshipService.reset()
	SystemsManager.reset_all()
	for fk in w.all_folk().duplicate():
		fk.current = null
		fk.queue.clear()
		SysUtil.world_remove_folk(fk.id)
	S.expect(f, SaveLoad.load(SLOT), "load works: %s" % SaveLoad.last_error)
	var a2 = w.get_folk(adult.id)
	var t2 = w.get_folk(teen.id)
	var s2 = w.get_folk(sib.id)
	S.expect(f, a2 != null and t2 != null and s2 != null, "folk are back")
	for pr in [[adult.id, teen.id], [sib.id, sib2.id]]:
		var tag: String = "%d/%d" % [pr[0], pr[1]]
		S.expect(f, RelationshipService.value(pr[0], pr[1], "romance") == 0.0 and RelationshipService.value(pr[1], pr[0], "romance") == 0.0, "%s: romance cleared" % tag)
		S.expect(f, RelationshipRomance.romance_stage(pr[0], pr[1]) == "none" and RelationshipRomance.exclusive_partners(pr[0]).is_empty(), "%s: no romantic bit left" % tag)
		S.expect(f, FamilyTree.spouse_of(pr[0]) != pr[1] and RelationshipService.value(pr[0], pr[1], "bond") == 0.0, "%s: no marriage or bond" % tag)
	S.expect(f, RelationshipService.value(adult.id, teen.id, "friendship") > 0.0, "friendship survives")
	S.expect(f, RelationshipService.affairs.size() == 1 and int(RelationshipService.affairs[0]["cheater"]) == lover.id, "only the legitimate affair entry stays (%s)" % str(RelationshipService.affairs))
	S.expect(f, RelationshipBits.has_flag(lover.id, mate.id, "partner") and RelationshipService.value(lover.id, mate.id, "romance") == 70.0, "the adult couple is untouched")
	SaveLoad.delete_slot(SLOT)
	S.teardown()
	return f

## Write an old-save state around the guard: friendship, romance 70 both ways and the bit.
func _force(a: Folk, b: Folk, flag: String) -> void:
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	var p: Dictionary = RelationshipService._pair(a.id, b.id)
	for dir in [[a, b], [b, a]]:
		dir[0].relationships[dir[1].id]["romance"] = 70.0
		(p["vals"]["%d>%d" % [dir[0].id, dir[1].id]] as Dictionary)["romance"] = 70.0
	(p["flags"] as Dictionary)[flag] = true
	(p["since"] as Dictionary)[flag] = 1
	RelationshipRomance._update_bond_tracks(a.id, b.id)
