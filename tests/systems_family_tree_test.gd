extends RefCounted
## Family tree + household: relation ids / labels, family bits, tree_for, propose -> engaged -> wedding -> spouse, surname
## sharing, divorce, moving in and out, adoption, death (grief, widowing, descendants in the legacy).

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_relations(f)
	_marriage(f)
	_divorce(f)
	_households(f)
	_adoption(f)
	_death(f)
	return f

func _relations(f: Array) -> void:
	var w := K.setup(41)
	var gp := K.make_folk(w, "Gran Ash", [], 1)
	var gp2 := K.make_folk(w, "Grandad Ash", [], 1)
	var p1 := K.make_folk(w, "Ann Ash", [], 1)
	var p2 := K.make_folk(w, "Bo Brook", [], 1)
	var aunt := K.make_folk(w, "Auntie Ash", [], 2)
	var cousin := K.make_folk(w, "Cuz Ash", [], 2)
	var c1 := K.make_folk(w, "Cal Ash", [], 1)
	var c2 := K.make_folk(w, "Cia Ash", [], 1)
	var half := K.make_folk(w, "Hal Cole", [], 3)
	var gc := K.make_folk(w, "Gus Ash", [], 1)
	Family.link_parent(p1.id, gp.id)
	Family.link_parent(p1.id, gp2.id)
	Family.link_parent(aunt.id, gp.id)
	Family.link_parent(aunt.id, gp2.id)
	Family.link_parent(cousin.id, aunt.id)
	Family.link_parent(c1.id, p1.id)
	Family.link_parent(c1.id, p2.id)
	Family.link_parent(c2.id, p1.id)
	Family.link_parent(c2.id, p2.id)
	Family.link_parent(half.id, p1.id)
	Family.link_parent(gc.id, c1.id)
	var cases: Array = [
		[c1.id, p1.id, "parent", "Parent"], [p1.id, c1.id, "child", "Child"], [c1.id, c2.id, "sibling", "Sibling"],
		[c1.id, half.id, "half_sibling", "Half-sibling"], [c1.id, gp.id, "grandparent", "Grandparent"], [gp.id, c1.id, "grandchild", "Grandchild"],
		[c1.id, aunt.id, "aunt_uncle", "Aunt/Uncle"], [aunt.id, c1.id, "niece_nephew", "Niece/Nephew"], [c1.id, cousin.id, "cousin", "Cousin"],
		[gc.id, gp.id, "great_grandparent", "Great-grandparent"], [gp.id, gc.id, "great_grandchild", "Great-grandchild"],
		[p1.id, aunt.id, "sibling", "Sibling"], [p1.id, p2.id, "", ""], [c1.id, c1.id, "self", "Self"],
	]
	for c in cases:
		K.expect(f, FamilyTree.relation_id(c[0], c[1]) == c[2], "relation_id(%d,%d) = %s, got %s" % [c[0], c[1], c[2], FamilyTree.relation_id(c[0], c[1])])
		K.expect(f, FamilyTree.relation_label(c[0], c[1]) == c[3], "label %s, got %s" % [c[3], FamilyTree.relation_label(c[0], c[1])])
	K.expect(f, FamilyTree.parents_of(c1.id) == [p1.id, p2.id] and FamilyTree.children_of(p1.id) == [c1.id, c2.id, half.id], "parents / children lists: %s %s" % [str(FamilyTree.parents_of(c1.id)), str(FamilyTree.children_of(p1.id))])
	K.expect(f, FamilyTree.siblings_of(c1.id) == [c2.id, half.id], "siblings include half-siblings")
	K.expect(f, FamilyTree.descendants_of(gp.id).size() == 7, "descendants of the grandparent: %s" % str(FamilyTree.descendants_of(gp.id)))
	# bits: family flag on every close relative, friendship floors, kin_bit
	for pair in [[c1.id, p1.id], [c1.id, c2.id], [c1.id, gp.id], [p1.id, c1.id], [gc.id, c1.id], [c2.id, half.id]]:
		K.expect(f, RelationshipBits.has_flag(pair[0], pair[1], "family") and RelationshipBits.bit_for(pair[0], pair[1]) == "family", "family bit between %d and %d" % [pair[0], pair[1]])
	K.expect(f, RelationshipService.value(c1.id, p1.id, "friendship") >= 40.0 and RelationshipService.value(c1.id, c2.id, "friendship") >= 25.0, "friendship floors for parents and siblings")
	K.expect(f, RelationshipService.value(c1.id, gp.id, "friendship") >= 20.0, "friendship floor for grandparents")
	K.expect(f, RelationshipBits.kin_bit(c1.id, p1.id) == "parent" and RelationshipBits.kin_bit(p1.id, c1.id) == "child", "RelationshipBits.kin_bit")
	K.expect(f, not RelationshipBits.has_flag(c1.id, cousin.id, "family"), "cousins are kin but not flagged as close family")
	# in-laws
	RelationshipService.add_both(p2.id, aunt.id, "romance", 80.0)
	Family.spouses[p2.id] = aunt.id
	Family.spouses[aunt.id] = p2.id
	K.expect(f, FamilyTree.relation_id(p1.id, p2.id) == "sibling_in_law", "spouse's sibling is a sibling-in-law (%s)" % FamilyTree.relation_id(p1.id, p2.id))
	K.expect(f, FamilyTree.relation_id(gp.id, p2.id) == "child_in_law", "child-in-law: %s" % FamilyTree.relation_id(gp.id, p2.id))
	K.expect(f, FamilyTree.relation_id(p2.id, gp.id) == "parent_in_law", "parent-in-law")
	Family.spouses.erase(p2.id)
	Family.spouses.erase(aunt.id)
	# the tree
	var t: Dictionary = FamilyTree.tree_for(c1.id)
	K.expect(f, t["name"] == "Cal Ash" and t["parents"].size() == 2, "tree: two parents")
	var pa: Dictionary = {}
	for p in t["parents"]:
		if p["id"] == p1.id:
			pa = p
	K.expect(f, not pa.is_empty() and pa["parents"].size() == 2, "tree: grandparents nested under the parent")
	K.expect(f, t["children"].size() == 1 and t["children"][0]["name"] == "Gus Ash", "tree: children")
	K.expect(f, t["siblings"].size() == 2, "tree: siblings")
	var half_flag: bool = false
	for s in t["siblings"]:
		if s["id"] == half.id and s["half"]:
			half_flag = true
	K.expect(f, half_flag, "tree flags half-siblings")
	K.expect(f, t["age_years"] is int and str(t["stage"]) != "" and t["alive"], "tree nodes carry age / stage / alive")
	# nobody on the lot: only ids known to the service still produce nodes
	var ghost: Dictionary = FamilyTree.tree_for(9999)
	K.expect(f, ghost["parents"].is_empty() and ghost["name"] == "Someone", "unknown ids give an empty tree")
	K.teardown()

func _pair(w: StubWorld, hid_b: int = 1, romance: float = 85.0) -> Array:
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(12, 12))
	var b := K.make_folk(w, "Bo Vale", [], hid_b, Vector2i(13, 12))
	Aging.set_age_days(a, 92.0)
	Aging.set_age_days(b, 92.0)
	RelationshipService.add_both(a.id, b.id, "romance", romance)
	RelationshipService.add_both(a.id, b.id, "friendship", 70.0)
	RelationshipBits.set_flag(a.id, b.id, "partner", true, false)
	return [a, b]

func _marriage(f: Array) -> void:
	var w := K.setup(42)
	var pr: Array = _pair(w, 2)
	var a: Folk = pr[0]
	var b: Folk = pr[1]
	WorldIface.coins[2] = 500
	# a sweetheart proposal still makes partners (old path)
	var s1 := K.make_folk(w, "Sy", [], 1)
	var s2 := K.make_folk(w, "Sam", [], 1)
	RelationshipService.add_both(s1.id, s2.id, "romance", 65.0)
	RelationshipService.add_both(s1.id, s2.id, "friendship", 50.0)
	RelationshipBits.set_flag(s1.id, s2.id, "sweetheart", true, false)
	K.expect(f, FamilyMarriage.on_propose(s1.id, s2.id) == "accepted" and RelationshipBits.has_flag(s1.id, s2.id, "partner"), "a sweetheart proposal makes them partners")
	K.expect(f, FamilyMarriage.on_propose(s1.id, s2.id) == "too_soon", "...but 65 romance is not enough for an engagement")
	# not ready yet
	var lo1 := K.make_folk(w, "Lo", [], 1)
	var lo2 := K.make_folk(w, "Li", [], 1)
	RelationshipService.add_both(lo1.id, lo2.id, "romance", 55.0)
	RelationshipService.add_both(lo1.id, lo2.id, "friendship", 60.0)
	RelationshipBits.set_flag(lo1.id, lo2.id, "partner", true, false)
	K.expect(f, FamilyMarriage.on_propose(lo1.id, lo2.id) == "too_soon" and not FamilyMarriage.is_engaged(lo1.id, lo2.id), "too soon when romance is below the marriage bar")
	# proper flow, through the interaction ids
	K.expect(f, not Interaction.create("have_wedding", a, b.id, true).can_run(a), "no wedding before an engagement")
	var dir = K.director()
	dir.autonomy_enabled = false
	K.expect(f, dir.command(a.id, "propose", b.id), "propose is a pie-menu interaction")
	K.run(dir, 40)
	K.expect(f, FamilyMarriage.is_engaged(a.id, b.id) and a.has_buff("engaged") and b.has_buff("engaged"), "proposal -> engaged")
	K.expect(f, FamilyTree.fiance_of(a.id) == b.id and FamilyTree.relation_id(a.id, b.id) == "fiance", "fiance relation")
	K.expect(f, not FamilyTree.spouse_of(a.id) == b.id and K.has_note("are engaged"), "not married yet, engagement announced")
	K.expect(f, FamilyMarriage.on_propose(a.id, b.id) == "already_engaged", "cannot propose twice")
	K.expect(f, FamilyTree.partner_of(a.id)["status"] == "fiance", "partner_of reports the engagement")
	K.expect(f, dir.command(a.id, "have_wedding", b.id), "the wedding interaction is available when engaged")
	K.run(dir, 80)
	K.expect(f, FamilyTree.spouse_of(a.id) == b.id and FamilyTree.spouse_of(b.id) == a.id, "wedding -> spouses")
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "spouse" and RelationshipBits.bit_for(b.id, a.id) == "spouse", "spouse relationship bit")
	K.expect(f, a.has_buff("married") and b.has_buff("married") and a.has_buff("newlywed") and not a.has_buff("engaged"), "married buffs replace the engagement")
	K.expect(f, FamilyTree.relation_label(a.id, b.id) == "Spouse", "label Spouse")
	K.expect(f, K.count_events("married") == 1 and K.has_note("are married"), "married event + notification")
	K.expect(f, b.name == "Bo Rowe", "default: the partner takes the actor's surname (%s)" % b.name)
	K.expect(f, b.household_id == 1 and WorldIface.get_coins(1) >= 500 and WorldIface.get_coins(2) == 0, "the spouse moves into the household with their funds (hid %d, coins %d)" % [b.household_id, WorldIface.get_coins(1)])
	K.expect(f, FamilyMarriage.on_propose(a.id, b.id) == "already_married", "cannot propose to a spouse")
	K.expect(f, not Interaction.create("have_wedding", a, b.id, true).can_run(a), "no second wedding")
	# surname options
	for mode in [["none", "Cy Dunn", "Di Rowe"], ["target", "Cy Rowe", "Di Rowe"], ["hyphen", "Cy Dunn", "Di Dunn-Rowe"]]:
		var c1 := K.make_folk(w, "Cy Dunn", [], 1)
		var c2 := K.make_folk(w, "Di Rowe", [], 1)
		FamilyMarriage.apply_surname(c1.id, c2.id, mode[0])
		K.expect(f, c1.name == mode[1] and c2.name == mode[2], "surname mode %s -> %s / %s" % [mode[0], c1.name, c2.name])
	# engagement falls apart when the love is gone
	var e1 := K.make_folk(w, "Ev", [], 1)
	var e2 := K.make_folk(w, "Ed", [], 1)
	RelationshipService.add_both(e1.id, e2.id, "romance", 80.0)
	RelationshipService.add_both(e1.id, e2.id, "friendship", 80.0)
	RelationshipBits.set_flag(e1.id, e2.id, "partner", true, false)
	K.expect(f, FamilyMarriage.propose_marriage(e1.id, e2.id) == "engaged", "second couple engaged")
	RelationshipService.add_both(e1.id, e2.id, "romance", -70.0)
	Family.on_day(9)
	K.expect(f, not FamilyMarriage.is_engaged(e1.id, e2.id) and not e1.has_buff("engaged") and K.has_note("called off"), "engagement is called off when romance collapses")
	K.teardown()

func _divorce(f: Array) -> void:
	var w := K.setup(43)
	var pr: Array = _pair(w, 1)
	var a: Folk = pr[0]
	var b: Folk = pr[1]
	WorldIface.coins[1] = 1000
	FamilyMarriage.propose_marriage(a.id, b.id)
	K.expect(f, FamilyMarriage.marry(a.id, b.id), "married")
	var kid := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(14, 12), "child")
	Family.link_parent(kid.id, a.id)
	Family.link_parent(kid.id, b.id)
	var before_ids: Array = []
	for fk in w.all_folk():
		before_ids.append(fk.id)
	var dir = K.director()
	dir.autonomy_enabled = false
	K.expect(f, not Interaction.create("divorce", kid, a.id, true).can_run(kid), "only spouses can divorce")
	K.expect(f, dir.command(a.id, "divorce", b.id), "divorce interaction")
	K.run(dir, 30)
	K.expect(f, FamilyTree.spouse_of(a.id) < 0 and not RelationshipBits.has_flag(a.id, b.id, "spouse"), "no longer spouses")
	K.expect(f, not a.has_buff("married") and a.has_buff("divorced") and (w.get_folk(b.id) == null or b.has_buff("divorced")), "divorced buff, married marker gone")
	K.expect(f, (Family.exes.get(a.id, []) as Array).has(b.id) and FamilyTree.relation_id(a.id, b.id) == "ex_spouse", "recorded as ex-spouses")
	K.expect(f, RelationshipService.value(a.id, b.id, "romance") < 20.0, "the romance is gone (%.0f)" % RelationshipService.value(a.id, b.id, "romance"))
	K.expect(f, w.get_folk(b.id) == null and Story.townies.has(b.id) and bool(Story.townies[b.id]["alive"]), "the one who did not initiate moves out and becomes a townie with the same id")
	K.expect(f, int(Story.townies[b.id]["coins"]) == 500 and WorldIface.get_coins(1) == 500, "funds are split (%d / %d)" % [int(Story.townies[b.id]["coins"]), WorldIface.get_coins(1)])
	K.expect(f, FamilyTree.parents_of(kid.id).has(b.id) and RelationshipBits.bit_for(kid.id, b.id) == "family", "the child keeps both parents in the tree")
	K.expect(f, K.has_note("got divorced") and K.count_events("divorced") == 1, "divorce announced")
	K.expect(f, FamilyMarriage.divorce(a.id, b.id) == false, "cannot divorce twice")
	K.teardown()

func _households(f: Array) -> void:
	var w := K.setup(44)
	var a := K.make_folk(w, "Ann Rowe", ["social"], 1)
	Story.generate_townies(6)
	var t: Dictionary = Story.alive_townies()[3]
	var tid: int = int(t["id"])
	t["age_days"] = 92.0
	RelationshipService.add_both(a.id, tid, "friendship", 50.0)
	K.expect(f, w.get_folk(tid) == null, "the townie is off the lot")
	var app_before: Dictionary = (t["appearance"] as Dictionary).duplicate(true)
	var ok: bool = FamilyHousehold.invite_to_household(tid, 1)
	var nf = w.get_folk(tid)
	K.expect(f, ok and nf != null and nf.household_id == 1 and nf.id == tid, "townie moves in with the same id")
	if nf != null:
		K.expect(f, nf.name == t["name"] and nf.traits == t["traits"] and nf.age_stage == "adult", "keeps name / traits / stage")
		K.expect(f, nf.appearance["skin"] == app_before["skin"], "keeps the appearance")
		K.expect(f, RelationshipService.value(nf.id, a.id, "friendship") >= 49.0, "relationships carry over (%.0f)" % RelationshipService.value(nf.id, a.id, "friendship"))
		K.expect(f, Aging.records.has(tid) and absf(Aging.age_days(tid) - float(t["age_days"])) < 0.5, "registered with the townie's age")
		K.expect(f, not bool(t["alive"]) and bool(t.get("moved_in", false)), "townie entry retired")
		K.expect(f, Folk._next_id < 900, "folk id counter is not pushed into the townie id range (%d)" % Folk._next_id)
		K.expect(f, SysUtil.is_resident(nf) and K.has_note("moved in"), "now a resident")
	K.expect(f, not FamilyHousehold.invite_to_household(tid, 1), "already living there")
	# move out again
	K.expect(f, FamilyHousehold.move_out(tid, 0.0), "moves out")
	K.expect(f, w.get_folk(tid) == null and bool(Story.townies[tid]["alive"]) and Story.townies[tid]["name"] == t["name"], "back to being a townie")
	K.expect(f, not Aging.records.has(tid), "no longer aged by the household systems")
	# a visitor on the lot asks to move in (interaction -> event -> service)
	var vt: Dictionary = Story.alive_townies()[4]
	var vid: int = int(vt["id"])
	vt["age_days"] = 102.0
	var keep: int = Folk._next_id
	var v := Folk.create(str(vt["name"]), (vt["traits"] as Array).duplicate(), vid)
	Folk._next_id = keep
	v.household_id = -1
	v.age_stage = "adult"
	v.set_meta("visitor", true)
	v.set_meta("townie_id", vid)
	w.add_folk(v, Vector2i(12, 14))
	Aging.apply_stage_buff(v)
	var dir = K.director()
	dir.autonomy_enabled = false
	K.expect(f, not Interaction.create("ask_to_move_in", a, v.id, true).can_run(a), "strangers cannot be asked to move in")
	RelationshipService.add_both(a.id, vid, "friendship", 20.0)
	dir.command(a.id, "ask_to_move_in", vid)
	K.run(dir, 30)
	K.expect(f, v.household_id == 1 or w.get_folk(vid).household_id != 1, "friendship 20 is below the bar: still a visitor or declined")
	RelationshipService.add_both(a.id, vid, "friendship", 30.0)
	dir.command(a.id, "ask_to_move_in", vid)
	K.run(dir, 30)
	var resident = w.get_folk(vid)
	K.expect(f, resident != null and resident.household_id == 1 and not resident.has_meta("visitor"), "a good friend moves in: visitor becomes a resident")
	K.expect(f, resident != null and Aging.records.has(vid) and Aging.age_days(vid) > 60.0, "visitor gets an aging record")
	K.teardown()

func _adoption(f: Array) -> void:
	var w := K.setup(45)
	var a := K.make_folk(w, "Ann Rowe", [], 1)
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 12))
	K.mgr.new_game([1])
	Family.spouses[a.id] = b.id
	Family.spouses[b.id] = a.id
	var list: Array = FamilyHousehold.adoptable(true)
	K.expect(f, list.size() == 3, "orphans appear when asked for (%d)" % list.size())
	var ok_stage: bool = true
	for t in list:
		if not (Story.stage_of(t) in ["baby", "toddler", "child"]):
			ok_stage = false
	K.expect(f, ok_stage, "only children can be adopted")
	var tid: int = int(list[0]["id"])
	var res: Dictionary = FamilyHousehold.adopt(tid, a.id)
	K.expect(f, res["ok"], "adoption works: %s" % str(res))
	var kid = w.get_folk(tid)
	K.expect(f, kid != null and kid.household_id == 1, "child joins the household")
	if kid != null:
		K.expect(f, kid.name.ends_with("Rowe"), "takes the family name (%s)" % kid.name)
		K.expect(f, FamilyTree.parents_of(tid).has(a.id) and FamilyTree.parents_of(tid).has(b.id), "both spouses become parents")
		K.expect(f, FamilyTree.relation_id(tid, a.id) == "adoptive_parent" and FamilyTree.relation_id(a.id, tid) == "adopted_child", "adoptive relation ids")
		K.expect(f, RelationshipBits.bit_for(tid, a.id) == "family", "family bit")
		K.expect(f, Aging.records.has(tid) and kid.has_buff("stage_" + kid.age_stage), "aging registered with the right stage")
		K.expect(f, Genetics.is_valid(kid.appearance), "has an appearance")
	K.expect(f, FamilyHousehold.adoptable().size() == 2 and K.has_note("was adopted"), "adoptable list shrinks, adoption announced")
	# teens / adults cannot be adopted; kids cannot adopt
	var teen: Dictionary = Story.add_townie(61.4)
	teen["orphan"] = true
	K.expect(f, FamilyHousehold.adopt(int(teen["id"]), a.id)["reason"] == "too_old", "teens are too old")
	var kid2 := K.make_folk(w, "Kid", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid2, 25.6)
	K.expect(f, FamilyHousehold.adopt(int(list[1]["id"]), kid2.id)["reason"] == "too_young", "children cannot adopt")
	# the self interaction, via the event bus
	var dir = K.director()
	dir.autonomy_enabled = false
	K.expect(f, dir.command(a.id, "adopt_child", -1), "adopt_child is an interaction id")
	K.run(dir, 40)
	K.expect(f, FamilyTree.children_of(a.id).size() == 2, "a second child was adopted (%d)" % FamilyTree.children_of(a.id).size())
	K.expect(f, not Interaction.create("adopt_child", kid2, -1, true).can_run(kid2), "children cannot adopt")
	K.teardown()

func _death(f: Array) -> void:
	var w := K.setup(46)
	var a := K.make_folk(w, "Ann Rowe", [], 1)
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 12))
	var kid := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(14, 12), "adult")
	var gkid := K.make_folk(w, "Gil Rowe", [], 2, Vector2i(15, 12), "adult")
	RelationshipService.add_both(a.id, b.id, "romance", 85.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 80.0)
	RelationshipBits.set_flag(a.id, b.id, "partner", true, false)
	FamilyMarriage.propose_marriage(a.id, b.id)
	FamilyMarriage.marry(a.id, b.id)
	Family.link_parent(kid.id, a.id)
	Family.link_parent(kid.id, b.id)
	Family.link_parent(gkid.id, kid.id)
	Aging.set_age_days(a, 182.0)
	var legacy: Dictionary = Aging.kill(a.id, "old age")
	K.expect(f, b.has_buff("widowed") and not b.has_buff("married"), "the spouse is widowed")
	K.expect(f, kid.has_buff("bereaved") and b.has_buff("grieving"), "children are bereaved, everyone close grieves")
	K.expect(f, FamilyTree.spouse_of(b.id) < 0 and FamilyTree.spouse_of(a.id) < 0, "marriage link is cleared")
	K.expect(f, not Family.is_alive(a.id) and Family.name_of(a.id) == "Ann Rowe", "the dead stay in the tree with their name")
	K.expect(f, FamilyTree.parents_of(kid.id).has(a.id) and FamilyTree.tree_for(kid.id)["parents"].size() == 2, "the tree still shows the late parent")
	var late: Dictionary = {}
	for p in FamilyTree.tree_for(kid.id)["parents"]:
		if p["id"] == a.id:
			late = p
	K.expect(f, not late.is_empty() and late["alive"] == false, "marked as not alive in the tree")
	K.expect(f, int(legacy["descendants"]) == 2, "legacy counts descendants (%s)" % str(legacy.get("descendants")))
	K.expect(f, str(legacy["summary"]).find("descendants in all") >= 0 and legacy["children"] == 1, "summary mentions descendants: %s" % legacy["summary"])
	K.expect(f, K.has_note("widow"), "widowing announced")
	K.teardown()
