extends RefCounted
## Skipping school and work (task 19j): the owner's family had 14 "chose to skip" in 168 days, both children on the same morning. Something else of the player's
## queued at shift time was a skip every single time; now it is a decision tied to traits and mood, rare for ordinary folk, and housemates almost never skip together.
## Measured here over 168 days (120 school days): before = every busy morning, after = the numbers printed as SKIPRULES.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_rates(f)
	_same_day(f)
	_save(f)
	return f

func _kid(w: StubWorld, name: String, hid: int, traits: Array, mood: String, idx: int) -> Folk:
	var k := K.make_folk(w, name, traits, hid, Vector2i(12 + idx, 12), "child")
	k.mood_name = mood
	return k

## Both children of every household are "busy" with a player errand on each school morning of 168 days; count who skips.
func _run_days(a: Folk, b: Folk, days: int) -> Array:
	var skips_a := 0
	var skips_b := 0
	var both := 0
	var mornings := 0
	for d in days:
		if d % 7 >= 5:
			continue                                  # weekend
		mornings += 1
		K.set_time(2 + d, 8)
		var sa: bool = SkipRules.chooses_to_skip(a, "school")
		var sb: bool = SkipRules.chooses_to_skip(b, "school")
		skips_a += 1 if sa else 0
		skips_b += 1 if sb else 0
		both += 1 if (sa and sb) else 0
	return [skips_a, skips_b, both, mornings]

func _rates(f: Array) -> void:
	var w := K.setup(71)
	var a := _kid(w, "Ann Rowe", 1, [], "content", 0)
	var b := _kid(w, "Bo Rowe", 1, [], "content", 1)
	var r: Array = _run_days(a, b, 168)
	print("SKIPRULES neutral siblings, 168 days (%d school mornings, before: %d skips each): %d + %d skips, %d on the same morning" % [r[3], r[3], r[0], r[1], r[2]])
	K.expect(f, int(r[0]) + int(r[1]) <= int(r[3]) * 2 / 5, "neutral children skip rarely (%d + %d of %d mornings each)" % [r[0], r[1], r[3]])
	K.expect(f, int(r[2]) == 0, "ordinary siblings never skip on the same morning (%d)" % r[2])
	K.teardown()
	# traits and mood matter
	w = K.setup(72)
	var lazy_a := _kid(w, "Lia Rowe", 1, ["lazy", "hot_headed"], "bored", 0)
	var lazy_b := _kid(w, "Lou Rowe", 2, ["lazy", "hot_headed"], "angry", 1)
	var good_a := _kid(w, "Gus Rowe", 3, ["workaholic", "perfectionist"], "happy", 2)
	var good_b := _kid(w, "Gil Rowe", 4, ["workaholic", "perfectionist"], "focused", 3)
	var n := 500
	var bad_skips := 0
	var good_skips := 0
	var mornings := 0
	for d in n:
		if d % 7 >= 5:
			continue
		mornings += 1
		K.set_time(2 + d, 8)
		for k in [lazy_a, lazy_b]:
			bad_skips += 1 if SkipRules.chooses_to_skip(k, "school") else 0
		for k in [good_a, good_b]:
			good_skips += 1 if SkipRules.chooses_to_skip(k, "school") else 0
	print("SKIPRULES %d mornings: lazy and bored/angry %d skips, hard-working and happy %d" % [mornings, bad_skips, good_skips])
	K.expect(f, bad_skips > good_skips * 4 and bad_skips > mornings / 10, "lazy, hot-headed, bored children skip far more than hard-working happy ones (%d vs %d)" % [bad_skips, good_skips])
	K.expect(f, good_skips <= mornings / 25, "hard-working happy children almost never skip (%d)" % good_skips)
	K.teardown()

## A housemate who skipped today: the second one only skips with a strong reason (a skipping trait AND a bad mood), and then rarely.
func _same_day(f: Array) -> void:
	var w := K.setup(73)
	var calm := _kid(w, "Cal Rowe", 1, ["lazy"], "content", 0)
	var calm_b := _kid(w, "Cat Rowe", 1, ["lazy"], "content", 1)
	var sulk := _kid(w, "Sul Rowe", 2, ["lazy"], "bored", 2)
	var sulk_b := _kid(w, "Sue Rowe", 2, ["lazy"], "bored", 3)
	K.expect(f, not SkipRules.strong_reason(calm) and SkipRules.strong_reason(sulk), "a strong reason needs a skipping trait and a bad mood")
	var calm_pairs := 0
	var sulk_pairs := 0
	var sulk_days := 0
	for d in 600:
		K.set_time(2 + d, 8)
		SkipRules.household_log[1] = {"day": 2 + d, "ids": [int(calm.id)]}        # the first child of house 1 skipped today
		calm_pairs += 1 if SkipRules.chooses_to_skip(calm_b, "school") else 0
		SkipRules.household_log[2] = {"day": 2 + d, "ids": [int(sulk.id)]}
		sulk_days += 1
		sulk_pairs += 1 if SkipRules.chooses_to_skip(sulk_b, "school") else 0
	print("SKIPRULES after a housemate skipped: no strong reason %d of 600, strong reason %d of 600" % [calm_pairs, sulk_pairs])
	K.expect(f, calm_pairs == 0, "without a strong reason the second sibling never joins in (%d)" % calm_pairs)
	K.expect(f, sulk_pairs < sulk_days / 10, "even with a strong reason they rarely join in (%d of %d)" % [sulk_pairs, sulk_days])
	# the first answer of the day stands (the commute asks again)
	K.set_time(900, 8)
	var first: bool = SkipRules.chooses_to_skip(sulk, "school")
	var same := true
	for i in 20:
		same = same and SkipRules.chooses_to_skip(sulk, "school") == first
	K.expect(f, same, "asking again on the same morning gives the same answer")
	K.teardown()

func _save(f: Array) -> void:
	var w := K.setup(74)
	var a := _kid(w, "Ann Rowe", 1, ["lazy"], "bored", 0)
	for d in 30:
		K.set_time(2 + d, 8)
		SkipRules.chooses_to_skip(a, "school")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(SkipRules.to_dict()))
	var before: Dictionary = SkipRules.decided.duplicate(true)
	SkipRules.reset()
	SkipRules.from_dict(snap)
	var same := SkipRules.decided.size() == before.size()
	for fid in before:
		var d2: Dictionary = SkipRules.decided.get(fid, {})
		same = same and not d2.is_empty() and int(d2["day"]) == int(before[fid]["day"]) and bool(d2["skip"]) == bool(before[fid]["skip"]) and str(d2["kind"]) == str(before[fid]["kind"])
	K.expect(f, same and SkipRules.household_log.size() >= 1, "decisions survive a save and load")
	K.expect(f, JSON.stringify(Careers.to_dict().get("skip_rules", {})) != "{}", "and are part of the careers block")
	K.teardown()
