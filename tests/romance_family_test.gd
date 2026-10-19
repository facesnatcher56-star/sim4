extends RefCounted
## RomanceRules, family: parent/child (also adoptive and step), grandparent/grandchild, siblings and half-siblings, aunt or uncle and
## niece or nephew, cousins and a household `family` flag are never allowed, in both directions. Unrelated adults and co-parents are.

const S = preload("res://tests/social_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := S.setup(9102)
	var n: Dictionary = {}
	for nm in ["gp", "gp2", "mum", "dad", "aunt", "cousin", "kid", "sib", "half", "gkid", "adopted", "step", "stranger", "flagged", "friend"]:
		n[nm] = S.K.make_folk(w, nm, [], 1, Vector2i(10 + n.size(), 12))
	var id := func(x: String) -> int: return (n[x] as Folk).id
	Family.link_parent(id.call("mum"), id.call("gp"))
	Family.link_parent(id.call("mum"), id.call("gp2"))
	Family.link_parent(id.call("aunt"), id.call("gp"))
	Family.link_parent(id.call("aunt"), id.call("gp2"))
	Family.link_parent(id.call("cousin"), id.call("aunt"))
	for k in ["kid", "sib"]:
		Family.link_parent(id.call(k), id.call("mum"))
		Family.link_parent(id.call(k), id.call("dad"))
	Family.link_parent(id.call("half"), id.call("mum"))
	Family.link_parent(id.call("gkid"), id.call("kid"))
	Family.link_parent(id.call("adopted"), id.call("dad"), true)
	Family.spouses[id.call("mum")] = id.call("step")      # kid's step-parent is mum's new spouse
	Family.spouses[id.call("step")] = id.call("mum")
	RelationshipBits.set_flag(id.call("flagged"), id.call("friend"), "family", true, false)
	var never: Array = [["kid", "mum"], ["kid", "dad"], ["gkid", "mum"], ["kid", "gp"], ["gkid", "gp"], ["kid", "sib"], ["kid", "half"], ["kid", "aunt"],
		["gkid", "aunt"], ["kid", "cousin"], ["adopted", "dad"], ["adopted", "kid"], ["kid", "step"], ["mum", "gp"], ["mum", "aunt"], ["flagged", "friend"]]
	for pr in never:
		var a: int = id.call(pr[0])
		var b: int = id.call(pr[1])
		for dir in [[a, b], [b, a]]:
			S.expect(f, not RomanceRules.allowed(dir[0], dir[1]), "family pair %s/%s is never allowed (%d>%d)" % [pr[0], pr[1], dir[0], dir[1]])
			RelationshipService.add_both(dir[0], dir[1], "romance", 90.0)
			S.expect(f, RelationshipService.value(dir[0], dir[1], "romance") == 0.0, "%s/%s: romance stays 0" % [pr[0], pr[1]])
			RelationshipBits.set_flag(dir[0], dir[1], "partner", true, false)
			S.expect(f, not RelationshipBits.has_flag(dir[0], dir[1], "partner"), "%s/%s: no partner bit" % [pr[0], pr[1]])
			S.expect(f, FamilyMarriage.propose_marriage(dir[0], dir[1]) == "no_bond" and not FamilyMarriage.marry(dir[0], dir[1], "", true), "%s/%s: no marriage" % [pr[0], pr[1]])
			S.expect(f, str(Aging.try_for_baby(dir[0], dir[1]).get("reason", "")) == "not_allowed", "%s/%s: no baby" % [pr[0], pr[1]])
			for iid in ["flirt", "kiss", "ask_out"]:
				S.expect(f, not Interaction.def_runnable(SimEnv.data().interaction_def(iid), n[pr[0]] if dir[0] == a else n[pr[1]], null, n[pr[1]] if dir[0] == a else n[pr[0]]), "%s/%s: %s not runnable" % [pr[0], pr[1], iid])
	# the people they ARE allowed with
	var yes: Array = [["mum", "dad"], ["stranger", "kid"], ["stranger", "mum"], ["friend", "stranger"], ["step", "dad"]]
	for pr in yes:
		S.expect(f, RomanceRules.allowed(id.call(pr[0]), id.call(pr[1])), "%s and %s may be romantic" % [pr[0], pr[1]])
	S.expect(f, RomanceRules.allowed(id.call("mum"), id.call("step")), "a couple (parent and their spouse) stays allowed")
	RelationshipService.add_both(id.call("stranger"), id.call("friend"), "romance", 60.0)
	S.expect(f, RelationshipService.value(id.call("stranger"), id.call("friend"), "romance") == 60.0, "unrelated adults still gain romance")
	S.teardown()
	return f
