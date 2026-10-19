extends RefCounted
## After a story nudge the household adult and the townie keep meeting, and in most seeds they reach sweethearts within about 14 days.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var wins: int = 0
	var seeds: Array = [11, 22, 33, 44, 55, 66, 77, 88]
	for s in seeds:
		if _one_seed(f, int(s)):
			wins += 1
	K.expect(f, wins >= 6, "a nudged adult and townie reach sweethearts within 14 days in most seeds (%d of %d)" % [wins, seeds.size()])
	return f

func _one_seed(f: Array, seed_value: int) -> bool:
	var w := K.setup(seed_value)
	K.set_time(10, 9)
	Story.generate_townies(12)
	var a := K.make_folk(w, "Nudged", ["romantic"], 1)
	var cfg: Dictionary = StoryPacing.cfg()["singles"]
	cfg["date_chance"] = 1.0
	cfg["move_in_chance"] = 0.0
	cfg["adopt_chance"] = 0.0
	StorySingles.on_day(10)
	var target: int = int(K.last_event("singles_nudge").get("target_id", -1))
	K.expect(f, target >= 0 and StoryPursuit.active(a.id, target), "seed %d: the nudge starts a pursuit" % seed_value)
	cfg["date_chance"] = 0.0
	var got: bool = false
	for d in range(11, 26):
		K.set_time(d, 9)
		StorySingles.on_day(d)
		if RelationshipBits.has_flag(a.id, target, "sweetheart"):
			got = true
			break
	K.expect(f, not got or RomanceRules.allowed(a.id, target), "seed %d: only allowed pairs get together" % seed_value)
	K.teardown()
	return got
