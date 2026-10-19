class_name StorySingles
extends RefCounted
## Story pacing for single adults, once a day (data/story_pacing.json "singles"). Calm households get a gentle nudge, never a forced
## outcome: a single adult is brought together with a compatible single (a townie comes to visit and they warm to each other), or, more
## rarely, a close friend moves in or the household takes in an orphan. Every romantic step asks RomanceRules.allowed(a, b).

static func cfg() -> Dictionary:
	return StoryPacing.cfg().get("singles", {})

static func on_day(_day: int) -> void:
	var c: Dictionary = cfg()
	if c.is_empty() or not StoryPacing.enabled:
		return
	for f in SysUtil.residents():
		if str(f.age_stage) not in RomanceRules.ADULT_STAGES or SysUtil.is_away(f) or not is_single(int(f.id)):
			continue
		var hid: int = int(f.household_id)
		if SysUtil.chance(float(c.get("date_chance", 0.1)) * StoryPacing.mult("flirt", hid)):
			if _nudge_date(c, f):
				continue
		var m: float = StoryPacing.mult("commitment", hid)
		if SysUtil.chance(float(c.get("move_in_chance", 0.03)) * m) and _friend_moves_in(c, f):
			continue
		if SysUtil.chance(float(c.get("adopt_chance", 0.015)) * m):
			_adopt(c, f)

static func is_single(id: int) -> bool:
	return RelationshipBits.romantic_partners(id).is_empty() and FamilyTree.fiance_of(id) < 0

## Adult people (townies, other households) the person could be matched with: single, allowed, not barred by a protective order.
static func candidates(f) -> Array:
	var out: Array = []
	for t in Story.free_townies():
		var tid: int = int(t["id"])
		if is_single(tid) and RomanceRules.allowed(int(f.id), tid) and not JusticeOrders.bars(tid, int(f.id)):
			out.append(tid)
	for o in SysUtil.residents():
		if int(o.household_id) != int(f.household_id) and is_single(int(o.id)) and RomanceRules.allowed(int(f.id), int(o.id)):
			out.append(int(o.id))
	return out

static func _nudge_date(c: Dictionary, f) -> bool:
	var ids: Array = candidates(f)
	var weights: Array = []
	for id in ids:
		weights.append(1.0 + maxf(RelationshipService.value(int(f.id), int(id), "friendship"), 0.0) / 20.0 + maxf(RelationshipBits.compatibility(int(f.id), int(id)), 0.0))
	var pick = SysUtil.pick_weighted(ids, weights)
	if pick == null or not RomanceRules.allowed(int(f.id), int(pick)):
		return false
	var p: int = int(pick)
	RelationshipService.add_both(int(f.id), p, "friendship", float(c.get("friendship", 8.0)))
	RelationshipService.add_both(int(f.id), p, "romance", float(c.get("romance", 10.0)))
	if Story.townies.has(p):
		StoryVisits.invite_over(p, int(f.id))
	SysUtil.notify("%s and %s keep finding reasons to talk." % [f.name, SysUtil.folk_name(p)], "story")
	SysUtil.game_event("singles_nudge", {"folk_id": int(f.id), "target_id": p})
	return true

static func _room(c: Dictionary, f) -> bool:
	var n: int = 0
	for o in SysUtil.residents():
		if int(o.household_id) == int(f.household_id):
			n += 1
	return n < int(c.get("max_household", 4))

static func _friend_moves_in(c: Dictionary, f) -> bool:
	if not _room(c, f):
		return false
	var best: int = -1
	var best_fr: float = float(c.get("move_in_friendship", 40.0))
	for t in Story.free_townies():
		if Story.stage_of(t) not in ["adult", "elder"]:
			continue
		var fr: float = RelationshipService.value(int(f.id), int(t["id"]), "friendship")
		if fr >= best_fr:
			best_fr = fr
			best = int(t["id"])
	return best >= 0 and FamilyHousehold.invite_to_household(best, int(f.household_id))

static func _adopt(c: Dictionary, f) -> bool:
	if not _room(c, f) or WorldIface.get_coins(int(f.household_id)) < int(c.get("adopt_min_coins", 1500)) or not Aging.children_of(int(f.id)).is_empty():
		return false
	var kids: Array = FamilyHousehold.adoptable(false)
	if kids.is_empty():
		return false
	return bool(FamilyHousehold.adopt(int(kids[0]["id"]), int(f.id)).get("ok", false))
