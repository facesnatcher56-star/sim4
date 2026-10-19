extends RefCounted
## RomanceRules, life stages: every ordered pair of stages. Only adult/elder with adult/elder is allowed; for the others the guard,
## every romantic interaction, the romance track, romantic bits, marriage and baby-making all refuse (both directions).

const S = preload("res://tests/social_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := S.setup(9101)
	var stages: Array = Aging.stage_ids()
	var folks: Dictionary = {}
	for i in stages.size():
		folks[stages[i]] = [S.K.make_folk(w, "Stage%d" % i, [], 1 + i, Vector2i(10 + i, 12), str(stages[i])), S.K.make_folk(w, "Other%d" % i, [], 1 + i, Vector2i(10 + i, 13), str(stages[i]))]
	var romantic: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	for iid in defs:
		var d: Dictionary = defs[iid]
		if str(d.get("target", "")) == "folk" and RomanceRules.is_romantic_def(d):
			romantic.append(str(iid))
	S.expect(f, romantic.size() >= 12 and romantic.has("flirt") and romantic.has("kiss") and romantic.has("try_for_baby") and romantic.has("propose"), "romantic defs found (%d)" % romantic.size())
	for sa in stages:
		for sb in stages:
			var a: Folk = folks[sa][0]
			var b: Folk = folks[sb][0 if sa != sb else 1]
			for dir in [[a, b], [b, a]]:
				dir[0].add_rel(dir[1].id, "friendship", 40.0)
			var ok: bool = sa in RomanceRules.ADULT_STAGES and sb in RomanceRules.ADULT_STAGES
			S.expect(f, RomanceRules.allowed(a.id, b.id) == ok, "allowed(%s,%s) should be %s" % [sa, sb, str(ok)])
			var runnable: int = 0
			for iid in romantic:
				if Interaction.def_runnable(defs[iid], a, null, b):
					runnable += 1
			if not ok:
				S.expect(f, runnable == 0, "no romantic interaction runs %s -> %s (%d do)" % [sa, sb, runnable])
				_never_romantic(f, a, b, "%s/%s" % [sa, sb])
	# adults/elders: the guard does not block (a plain flirt is available when nothing else forbids it)
	var ad: Folk = folks["adult"][0]
	var el: Folk = folks["elder"][0]
	S.expect(f, Interaction.def_runnable(defs["wink"], ad, null, el) and Interaction.def_runnable(defs["wink"], el, null, ad), "adult and elder may wink at each other")
	S.teardown()
	return f

func _never_romantic(f: Array, a: Folk, b: Folk, tag: String) -> void:
	RelationshipService.add_both(a.id, b.id, "romance", 80.0)
	S.expect(f, RelationshipService.value(a.id, b.id, "romance") == 0.0 and b.get_rel(a.id, "romance") == 0.0, "%s: romance track stays 0" % tag)
	a.add_rel(b.id, "romance", 30.0)
	S.expect(f, a.get_rel(b.id, "romance") == 0.0, "%s: Folk.add_rel refuses romance" % tag)
	for flag in ["dating", "sweetheart", "partner", "spouse"]:
		RelationshipBits.set_flag(a.id, b.id, flag, true, false)
		S.expect(f, not RelationshipBits.has_flag(a.id, b.id, flag), "%s: no %s bit" % [tag, flag])
	RelationshipRomance.start_dating(a.id, b.id, false)
	S.expect(f, RelationshipRomance.romance_stage(a.id, b.id) == "none" and RelationshipRomance.exclusive_partners(a.id).is_empty(), "%s: romance stage stays none" % tag)
	S.expect(f, FamilyMarriage.propose_marriage(a.id, b.id) == "no_bond" and not FamilyMarriage.marry(a.id, b.id, "", true), "%s: no engagement or wedding" % tag)
	S.expect(f, str(Aging.try_for_baby(a.id, b.id).get("reason", "")) in ["not_allowed", "too_young"] and not Aging.pregnancies.has(a.id), "%s: no baby" % tag)
