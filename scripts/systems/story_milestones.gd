class_name StoryMilestones
extends RefCounted
## Life milestones of couples in the household, once a day, as slow existing events with small chances (data/story_pacing.json
## "milestones"), raised by StoryPacing when the household has been calm: a long-term couple moves towards an engagement, a wedding
## or a baby, or (when the bond has faded) towards a breakup. Never forced: every step needs the couple's own conditions to hold.

static func cfg() -> Dictionary:
	return StoryPacing.cfg().get("milestones", {})

static func on_day(_day: int) -> void:
	var c: Dictionary = cfg()
	if c.is_empty() or not StoryPacing.enabled:
		return
	var seen: Dictionary = {}
	for f in SysUtil.residents():
		if str(f.age_stage) not in ["adult", "elder"] or SysUtil.is_away(f):
			continue
		for other in RelationshipBits.all_known(int(f.id)):
			var o = SysUtil.folk(int(other))
			if o == null or not SysUtil.is_resident(o) or int(o.household_id) != int(f.household_id) or str(o.age_stage) not in ["adult", "elder"]:
				continue
			var key: String = SysUtil.pair_key(int(f.id), int(other))
			if seen.has(key):
				continue
			seen[key] = true
			_couple(c, f, o)

static func _days_as(a: int, b: int, flag: String) -> int:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return 0
	return SysUtil.day() - int((p.get("since", {}) as Dictionary).get(flag, SysUtil.day()))

static func _couple(c: Dictionary, f, o) -> void:
	var a: int = int(f.id)
	var b: int = int(o.id)
	var hid: int = int(f.household_id)
	var m: float = StoryPacing.mult("commitment", hid)
	if RelationshipBits.has_flag(a, b, "spouse") or RelationshipBits.has_flag(a, b, "partner") or FamilyMarriage.is_engaged(a, b):
		Intimacy.daily_couple(a, b)             # quiet evenings together: an unplanned pregnancy is possible, rarely
	if RelationshipBits.has_flag(a, b, "spouse"):
		if FamilyTree.spouse_of(a) == b and SysUtil.chance(float(c.get("baby_chance", 0.04)) * m):
			Aging.try_for_baby(a, b)
		return
	if FamilyMarriage.is_engaged(a, b):
		var since: int = SysUtil.day() - int((Family.engaged.get(SysUtil.pair_key(a, b), {}) as Dictionary).get("since", SysUtil.day()))
		if since >= int(c.get("min_engaged_days", 2)) and SysUtil.chance(float(c.get("marry_chance", 0.2)) * m):
			FamilyMarriage.marry(a, b)
			SysUtil.notify("%s and %s had a small wedding at home." % [f.name, o.name], "relationship")
		return
	if RelationshipBits.has_flag(a, b, "partner"):
		var ro: float = minf(RelationshipService.value(a, b, "romance"), RelationshipService.value(b, a, "romance"))
		var fr: float = minf(RelationshipService.value(a, b, "friendship"), RelationshipService.value(b, a, "friendship"))
		if ro < float(c.get("breakup_romance_below", 30)) or fr < float(c.get("breakup_friendship_below", 20)):
			if SysUtil.chance(float(c.get("breakup_chance", 0.05)) * StoryPacing.mult("conflict", hid)):
				RelationshipRomance.breakup(a, b, "breakup", 1.0)
			return
		if _days_as(a, b, "partner") >= int(c.get("min_partner_days", 3)) and ro >= 60.0 and SysUtil.chance(float(c.get("propose_chance", 0.15)) * m):
			var res: String = FamilyMarriage.propose_marriage(a, b)
			if res == "too_soon":
				RelationshipService.add_both(a, b, "romance", 4.0)        # time spent together: they get closer
		elif _days_as(a, b, "partner") >= int(c.get("min_partner_days", 3)) and SysUtil.chance(float(c.get("bond_chance", 0.25)) * m):
			RelationshipService.add_both(a, b, "romance", 4.0)
			RelationshipService.add_both(a, b, "friendship", 2.0)
