extends RefCounted
## Helpers for share_* tests (no run(): skipped by the runner).

const K = preload("res://tests/systems_kit.gd")
const TMP := "user://share_test_tmp"

static func prepare() -> void:
	ShareFile.dir_override = TMP
	ShareState.seen_path = "user://share_seen_test.json"
	DirAccess.make_dir_recursive_absolute(TMP)
	clean()

static func clean() -> void:
	var d := DirAccess.open(TMP)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + "/" + f))
	if FileAccess.file_exists(ShareState.seen_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ShareState.seen_path))

static func finish() -> void:
	clean()
	ShareFile.dir_override = ""
	ShareState.seen_path = "user://share_seen.json"
	ShareImport.first_slot = 1
	ShareImport.last_slot = SaveSlots.SLOTS
	ShareState.reset()

## A small town: household 1 = Ann + Bo (spouses) + their child Kid, with skills, an aspiration, memories and chronicle lines.
static func world(seed_value: int = 4242) -> StubWorld:
	var w := K.setup(seed_value)
	Genetics.seed_rng(seed_value)
	Story.generate_townies()
	var ann := K.make_folk(w, "Ann Vale", ["glutton", "neat"])
	var bo := K.make_folk(w, "Bo Vale", ["lazy"])
	var kid := K.make_folk(w, "Kid Vale", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid, 15.0)
	Genetics.ensure_all()
	ann.add_skill_xp("cooking", 130.0)
	ann.remember("good_meal", 0.4)
	Goals.set_aspiration(ann.id, "master_chef")
	RelationshipService.add_both(ann.id, bo.id, "friendship", 60.0)
	RelationshipService.add_both(ann.id, bo.id, "romance", 70.0)
	RelationshipBits.set_flag(ann.id, bo.id, "spouse", true, false)
	Family.link_parent(kid.id, ann.id)
	Family.link_parent(kid.id, bo.id)
	K.set_time(5, 9)
	ChronicleHook.reset()
	ChronicleHook.note("wedding", "Ann Vale and Bo Vale got married.", [ann.id, bo.id], "", 2, true)
	ChronicleHook.note("birth", "Kid Vale was born to Ann Vale and Bo Vale.", [kid.id], "", 2, true)
	return w

static func ids_of_household() -> Array:
	var ids: Array = []
	for f in SysUtil.residents():
		ids.append(int(f.id))
	ids.sort()
	return ids

## A valid raw household dictionary exported from the small town.
static func raw_household() -> Dictionary:
	return ShareExport.household(ids_of_household(), "The Vale family")
