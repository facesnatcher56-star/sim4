extends RefCounted
## Story pacing for singles: a calm single adult is nudged towards a compatible single (never a minor or relative), a partnered adult is
## left alone, and rarer continuations exist (a close friend moves in, the household adopts an orphan).

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_dating(f)
	_continuations(f)
	_stages(f)
	return f

func _adult_townies() -> Array:
	return Story.free_townies().filter(func(t): return Story.stage_of(t) == "adult").map(func(t): return int(t["id"]))

func _dating(f: Array) -> void:
	var w := K.setup()
	K.set_time(10, 9)
	Story.generate_townies(12)
	var a := K.make_folk(w, "Single", [], 1)
	var cfg: Dictionary = StoryPacing.cfg()["singles"]
	cfg["date_chance"] = 1.0
	var ids: Array = StorySingles.candidates(a)
	K.expect(f, not ids.is_empty(), "a single adult has people to meet (%d)" % ids.size())
	for id in ids:
		K.expect(f, RomanceRules.allowed(a.id, int(id)), "every candidate passes the romance guard")
	# a relative and a partnered townie are never picked
	var kin: int = _adult_townies()[0]
	RelationshipBits.set_flag(a.id, kin, "family", true, false)
	K.expect(f, not StorySingles.candidates(a).has(kin), "a relative is never a candidate")
	var before: float = 0.0
	for id2 in StorySingles.candidates(a):
		before += RelationshipService.value(a.id, int(id2), "romance")
	StorySingles.on_day(10)
	var after: float = 0.0
	for id3 in StorySingles.candidates(a):
		after += RelationshipService.value(a.id, int(id3), "romance")
	K.expect(f, after > before and K.count_events("singles_nudge") == 1, "a calm single is nudged towards somebody (%.0f -> %.0f)" % [before, after])
	# partnered adults are left alone
	var b := K.make_folk(w, "Taken", [], 2)
	var p: int = int(StorySingles.candidates(b)[0])
	RelationshipBits.set_flag(b.id, p, "partner", true, false)
	var n: int = K.count_events("singles_nudge")
	StorySingles.on_day(11)
	var nudged_b: bool = K.count_events("singles_nudge") > n and str(K.last_event("singles_nudge").get("folk_id", "")) == str(b.id)
	K.expect(f, not nudged_b, "a household with a partner is not nudged")
	K.teardown()

func _continuations(f: Array) -> void:
	var w := K.setup()
	K.set_time(10, 9)
	Story.generate_townies(12)
	var a := K.make_folk(w, "Lonely", [], 1)
	var cfg: Dictionary = StoryPacing.cfg()["singles"]
	cfg["date_chance"] = 0.0
	cfg["move_in_chance"] = 1.0
	cfg["adopt_chance"] = 0.0
	var friend: int = _adult_townies()[0]
	RelationshipService.add_both(a.id, friend, "friendship", 70.0)
	StorySingles.on_day(10)
	var moved = w.get_folk(friend)
	K.expect(f, moved != null and int(moved.household_id) == 1, "a close friend moves in")
	cfg["move_in_chance"] = 0.0
	cfg["adopt_chance"] = 1.0
	FamilyHousehold.spawn_orphans(2)
	WorldIface.coins[1] = 5000
	var kids_before: int = Aging.children_of(a.id).size()
	StorySingles.on_day(11)
	K.expect(f, Aging.children_of(a.id).size() == kids_before + 1, "a well-off single household adopts an orphan")
	K.teardown()

func _stages(f: Array) -> void:
	var w := K.setup()
	K.set_time(10, 9)
	Story.generate_townies(12)
	var a := K.make_folk(w, "Adultsingle", [], 1)
	var elder_ids: Array = []
	for t in Story.free_townies():
		if Story.stage_of(t) == "elder":
			elder_ids.append(int(t["id"]))
	K.expect(f, not elder_ids.is_empty(), "the town has an elder")
	for id in StorySingles.candidates(a):
		K.expect(f, not elder_ids.has(int(id)), "an adult is never matched with an elder")
	var e := K.make_folk(w, "Elderlysingle", [], 2, Vector2i(14, 12), "elder")
	for id2 in StorySingles.candidates(e):
		K.expect(f, Story.stage_of(Story.townies[int(id2)]) == "elder" if Story.townies.has(int(id2)) else str(SysUtil.folk(int(id2)).age_stage) == "elder", "an elder is only matched with an elder")
	K.teardown()
