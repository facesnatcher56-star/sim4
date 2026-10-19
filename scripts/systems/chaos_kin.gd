class_name ChaosKin
extends RefCounted
## Family surprises (task 07b), the good kind. Both only ever involve REAL relatives, never strangers. Numbers: config.chaos.kin.
##  - inheritance: an old townie who is family of somebody in the household (RomanceRules.related: parent, grandparent, sibling, aunt, uncle,
##    cousin ... as recorded in the family tree) and has some savings passes away. The estate goes through BankWill: the will they wrote names
##    a member of the household (we write it for them if they had none); if they named somebody OUTSIDE the household, nothing happens here.
##    The deceased's coins move to the heir's household (a share, capped), the townie dies through Aging.kill so grief, a grave and the
##    chronicle all happen. Without such a relative the incident cannot roll (the `estate_relative` condition).
##  - long-lost family: a sibling the household never knew about turns up. A real sibling in the family tree (shared parent: an existing
##    parent, or a long dead one nobody wrote down), so RomanceRules treats them as family and the usual family bits apply. They visit that day.
## TWINS: surprise twins / triplets wait for task 18 (see ChaosTwinsHook).

static func cfg() -> Dictionary:
	return ChaosState.cfg("kin")

static func _grown(hid: int) -> Array:
	var out: Array = SysUtil.residents().filter(func(f): return int(f.household_id) == hid and str(f.age_stage) in ["adult", "elder"])
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out

# ------------------------------------------------------------------ inheritance
## {townie, heir (Folk)} for the first old relative with an estate, or null.
static func estate_relative(hid: int) -> Variant:
	var c: Dictionary = cfg()
	var members: Array = _grown(hid)
	if members.is_empty():
		return null
	var ids: Array = []
	for m in SysUtil.residents():
		if int(m.household_id) == hid:
			ids.append(int(m.id))
	for t in Story.alive_townies():
		if int(t["coins"]) < int(c.get("min_estate", 150)) or float(t["age_days"]) < float(c.get("min_age_days", 160)):
			continue
		var named: int = BankWill.heir_of(int(t["id"]))
		if named >= 0 and not ids.has(named):
			continue                                        # their will names somebody else
		for m2 in members:
			if RomanceRules.related(int(m2.id), int(t["id"])):
				return {"townie": t, "heir": SysUtil.folk(named) if ids.has(named) else m2}
	return null

static func inheritance(hid: int) -> Dictionary:
	var found: Variant = estate_relative(hid)
	if found == null:
		return {"text": ""}
	var c: Dictionary = cfg()
	var t: Dictionary = found["townie"]
	var heir = found["heir"]
	var tid: int = int(t["id"])
	var nm: String = str(t["name"])
	if not BankWill.has_will(tid):
		BankWill.write(tid, int(heir.id))
	var amount: int = mini(int(float(t["coins"]) * float(c.get("estate_share", 0.8))), int(c.get("max_estate", 2500)))
	t["coins"] = int(t["coins"]) - amount
	BankWill.clear(tid)
	Aging.kill(tid, "old age")
	Economy.deposit(int(heir.household_id), amount, "inheritance from %s" % nm)
	ChaosState.count("inheritance")
	return {"text": "%s, a relative of %s's, passed away peacefully and left %d coins in their will." % [nm, heir.name, amount], "kind": "good"}

# ------------------------------------------------------------------ long-lost family
static func long_lost(hid: int) -> Dictionary:
	var c: Dictionary = cfg()
	var grown: Array = _grown(hid)
	if grown.is_empty() or SysUtil.day() - int(ChaosState.stats.get("kin_day", -9999)) < int(c.get("min_gap_days", 56)):
		return {"text": ""}
	var m = grown[Incidents.rng.randi_range(0, grown.size() - 1)]
	var lo: float = float(Aging.stage_def("adult").get("from_day", 76)) + 2.0
	var hi: float = float(Aging.stage_def("elder").get("from_day", 172)) - 4.0
	var age: float = clampf(Family.age_days_of(int(m.id)) + Incidents.rng.randf_range(-14.0, 14.0), lo, hi)
	var t: Dictionary = Story.add_townie(age)
	var tid: int = int(t["id"])
	var shared: Array = FamilyTree.parents_of(int(m.id))
	var parent: int
	if shared.is_empty():
		parent = Story.next_id                               # a parent nobody wrote down, long gone
		Story.next_id += 1
		Family.note_person(parent, "a parent who is no longer around")
		(Family.people[parent] as Dictionary)["died_day"] = SysUtil.day() - 1
		(Family.people[parent] as Dictionary)["died_age_days"] = 150.0
		Family.link_parent(int(m.id), parent, false, false)
	else:
		parent = int(shared[0])
	Family.note_person(tid, str(t["name"]), SysUtil.day() - int(age))
	Family.link_parent(tid, parent, false, false)
	Family.refresh_bits(tid)
	Family.refresh_bits(int(m.id))
	RelationshipService.add_both(int(m.id), tid, "friendship", float(c.get("friendship", 15)))
	StoryVisits.invite_over(tid, int(m.id), int(c.get("visit_min", 180)))
	ChaosState.stats["kin_day"] = SysUtil.day()
	ChaosState.count("long_lost")
	return {"text": "A stranger at the door says they are %s's long-lost sibling. %s was raised elsewhere and only just found the family. They have come to visit." % [m.name, t["name"]], "kind": "good"}
