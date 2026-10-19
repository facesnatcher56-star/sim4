class_name StoryGrowth
extends RefCounted
## Town growth (statistical, once a day): townie couples have babies and new singles, couples and families move into empty homes, so the
## town stays steady or grows while elders die (data/story.json "growth"). Every romantic bit asks RomanceRules.allowed.

static func cfg() -> Dictionary:
	return Story.cfg().get("growth", {})

static func population() -> int:
	return Story.alive_townies().size()

static func on_day() -> void:
	PregnancyTownie.on_day()
	_births()
	_arrivals()

# ------------------------------------------------------------------ births
static func _births() -> void:
	var g: Dictionary = cfg()
	var pop_max: int = int(Story.cfg().get("max_population", 24))
	var today: int = SysUtil.day()
	for key in RelationshipService.pairs.keys():
		if population() >= pop_max:
			return
		var p: Dictionary = RelationshipService.pairs[key]
		var a: int = int(p["lo"])
		var b: int = int(p["hi"])
		if not (Story.townies.has(a) and Story.townies.has(b)):
			continue
		var ta: Dictionary = Story.townies[a]
		var tb: Dictionary = Story.townies[b]
		if not (bool(ta["alive"]) and bool(tb["alive"])):
			continue
		var fl: Dictionary = p["flags"]
		if not (fl.get("spouse", false) or fl.get("partner", false)):
			continue
		if not _can_parent(ta) or not _can_parent(tb) or not RomanceRules.allowed(a, b):
			continue
		if today - maxi(int(ta.get("last_baby_day", -99)), int(tb.get("last_baby_day", -99))) < int(g.get("baby_gap_days", 20)):
			continue
		if int(ta.get("kids", 0)) + int(tb.get("kids", 0)) >= int(g.get("max_kids", 3)):
			continue
		PregnancyTownie.consider(ta, tb, float(g.get("baby_chance", 0.05)))

static func _can_parent(t: Dictionary) -> bool:
	return Story.stage_of(t) == "adult"

static func _born(ta: Dictionary, tb: Dictionary, sex: String = "") -> void:
	var a: int = int(ta["id"])
	var b: int = int(tb["id"])
	var baby: Dictionary = Story.add_townie(0.0, "", [], "", 1, sex)
	baby["name"] = "%s %s" % [Names.pick_first([], null, Sexes.of_townie(baby)), Story.name_of(a).split(" ")[-1]]
	baby["lot"] = int(ta.get("lot", 1))
	RelationshipBits.set_flag(int(baby["id"]), a, "family", true, false)
	RelationshipBits.set_flag(int(baby["id"]), b, "family", true, false)
	baby["appearance"] = Genetics.inherit(Family.person_info(a), Family.person_info(b), null, {"sex": Sexes.of_townie(baby)})["appearance"]
	Family.note_townie_birth(int(baby["id"]), a, b)
	var today: int = SysUtil.day()
	for t in [ta, tb]:
		t["last_baby_day"] = today
		t["kids"] = int(t.get("kids", 0)) + 1
	Story._log("%s and %s had a baby, %s." % [ta["name"], tb["name"], baby["name"]])
	ChronicleHook.note("birth", "%s was born to %s and %s." % [baby["name"], ta["name"], tb["name"]], [int(baby["id"]), a, b], "town:%d" % int(ta.get("lot", 0)), 2, true)

# ------------------------------------------------------------------ arrivals
static func _arrivals() -> void:
	var g: Dictionary = cfg()
	var c: Dictionary = Story.cfg()
	var pop: int = population()
	if pop >= int(c.get("max_population", 24)):
		return
	var deficit: int = maxi(int(c.get("townie_count", 12)) - pop, 0)
	var chance: float = float(g.get("arrive_chance", 0.15)) + float(g.get("arrive_per_missing", 0.05)) * deficit
	if not SysUtil.chance(minf(chance, 0.9)):
		return
	var roll: float = SysUtil.rng.randf()
	if roll < float(g.get("family_share", 0.2)):
		_arrive_group(true)
	elif roll < float(g.get("family_share", 0.2)) + float(g.get("couple_share", 0.3)):
		_arrive_group(false)
	else:
		_arrive_single()

static func _job() -> String:
	var careers: Array = Story.cfg().get("careers", [])
	return str(SysUtil.pick(careers)) if not careers.is_empty() else ""

static func _adult_age() -> float:
	var from_d: float = float(Aging.stage_def("adult").get("from_day", 44))
	var to_d: float = float(Aging.stage_def("elder").get("from_day", 140))
	return SysUtil.rng.randf_range(from_d + 2.0, from_d + (to_d - from_d) * 0.6)

static func _arrive_single() -> void:
	var n: Dictionary = Story.add_townie(_adult_age())
	n["career"] = _job()
	Story._log("%s moved to town." % n["name"])
	SysUtil.game_event("townie_arrived", {"townie_id": int(n["id"]), "folk_id": -1})

static func _arrive_group(with_child: bool) -> void:
	var sa: String = Sexes.roll()
	var a: Dictionary = Story.add_townie(_adult_age(), "", [], "", 1, sa)
	var b: Dictionary = Story.add_townie(_adult_age(), "", [], "", 1, Sexes.other(sa) if SysUtil.chance(0.9) else sa)
	var surname: String = str(a["name"]).split(" ")[-1]
	b["name"] = "%s %s" % [str(b["name"]).split(" ")[0], surname]
	a["career"] = _job()
	b["career"] = _job() if SysUtil.chance(0.6) else ""
	b["lot"] = int(a["lot"])
	var ia: int = int(a["id"])
	var ib: int = int(b["id"])
	var married: bool = SysUtil.chance(0.6)
	if RomanceRules.allowed(ia, ib):
		RelationshipService.add_both(ia, ib, "friendship", 60.0)
		RelationshipService.add_both(ia, ib, "romance", 75.0)
		RelationshipBits.set_flag(ia, ib, "partner", true, false)
		if married:
			RelationshipBits.set_flag(ia, ib, "spouse", true, false)
	if not with_child:
		Story._log("%s and %s moved to town." % [a["name"], b["name"]])
		SysUtil.game_event("townie_arrived", {"townie_id": ia, "folk_id": -1})
		return
	var kid_from: float = float(Aging.stage_def("child").get("from_day", 20))
	var kid: Dictionary = Story.add_townie(kid_from + SysUtil.rng.randf_range(1.0, 12.0), "", [])
	kid["name"] = "%s %s" % [Names.pick_first([], null, Sexes.of_townie(kid)), surname]
	kid["lot"] = int(a["lot"])
	RelationshipBits.set_flag(int(kid["id"]), ia, "family", true, false)
	RelationshipBits.set_flag(int(kid["id"]), ib, "family", true, false)
	kid["appearance"] = Genetics.inherit(Family.person_info(ia), Family.person_info(ib), null, {"sex": Sexes.of_townie(kid)})["appearance"]
	Family.note_townie_birth(int(kid["id"]), ia, ib)
	for t in [a, b]:
		t["kids"] = 1
		t["last_baby_day"] = SysUtil.day()
	Story._log("The %s family (%s and %s, with %s) moved to town." % [surname, a["name"], b["name"], kid["name"]])
	SysUtil.game_event("townie_arrived", {"townie_id": ia, "folk_id": -1})
