extends RefCounted
## Task 15b: the "nobody left" flow never leaves the household empty (real UI path: ask_fn valid, nobody answers), picks grown-ups over elders, and a
## townie who was out in town takes over with proper autonomy (needs recover over a day).

const K := preload("res://tests/succession_kit.gd")
var fails: Array = []
var shown: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_ui_nobody_answers()
	_pick_for_me_off()
	_adults_before_elders()
	_townie_from_town_lives()
	return fails

func _alone() -> Object:
	var folk: Array = K.new_game()
	Aging.kill(int(folk[1].id), "old age")
	Aging.kill(int(folk[2].id), "old age")
	return folk[0]

func _silent_ui() -> void:
	shown.clear()
	JusticePlayer.ask_fn = func(_pid, title, text, options, cb, _default): shown.append({"title": title, "text": text, "options": options, "cb": cb})

func _empty_days(days: int) -> int:
	var worst: int = 0
	var run_len: int = 0
	for _d in days:
		K.HoodKit.run(1440)
		run_len = run_len + 1 if Succession.empty_household(1) else 0
		worst = maxi(worst, run_len)
	return worst

func _ui_nobody_answers() -> void:
	var head = _alone()
	_silent_ui()
	var elder: Dictionary = K.townie("Old Ivo", "elder", 5.0)         # lowest id, and an elder
	Aging.kill(int(head.id), "old age")
	_check(Succession.is_pending(1) and Succession.empty_household(1), "the last member died: pending")
	var worst: int = _empty_days(SuccessionNobody.AUTO_DAYS + 3)
	_check(not Succession.is_pending(1), "nobody answered, yet the household was settled by itself")
	_check(worst <= SuccessionNobody.AUTO_DAYS + 1, "never empty for more than AUTO_DAYS + 1 days (was %d)" % worst)
	_check(Succession.head_of(1) >= 0 and str(K.world().get_folk(Succession.head_of(1)).age_stage) == "adult", "an adult was chosen, not an elder")
	_check(K.world().get_folk(int(elder["id"])) == null or int(K.world().get_folk(int(elder["id"])).household_id) != 1, "the elder did not move in")
	_check(K.HoodKit.has_note("Nobody is playing your household"), "the player was reminded in plain words")
	K.teardown()

func _pick_for_me_off() -> void:
	var head = _alone()
	_silent_ui()
	SuccessionNobody.auto_pick = false
	K.townie("Quill", "adult", 30.0)
	Aging.kill(int(head.id), "old age")
	K.HoodKit.events.clear()
	K.HoodKit.run(1440 * 5)
	SuccessionNobody.auto_pick = true
	_check(Succession.is_pending(1), "with 'Pick for me' off the household waits for the player")
	var reminders: Array = K.HoodKit.events.filter(func(e): return e[0] == "household_empty")
	_check(reminders.size() >= 4, "...and the banner event comes back every morning (%d)" % reminders.size())
	_check(not reminders.is_empty() and int(reminders[reminders.size() - 1][1]["days_left"]) == -1, "...saying nobody will be picked")
	_check(SuccessionText.nobody_banner(-1).find("running by itself") >= 0 and SuccessionText.nobody_banner(2).find("2 days") >= 0, "banner words")
	K.teardown()

func _adults_before_elders() -> void:
	var head = _alone()
	var elder_rel: Dictionary = K.townie("Elda", "elder", 5.0)
	K.child_of(int(head.id), int(elder_rel["id"]))                   # an elder parent living elsewhere
	var older: Dictionary = K.townie("Odo", "adult", 40.0)
	var younger: Dictionary = K.townie("Yan", "adult", 3.0)
	var ids: Array = SuccessionNobody.townies().map(func(t): return int(t["id"]))
	var first_elder: int = -1
	for i in ids.size():
		if Story.stage_of(Story.townies[ids[i]]) == "elder" and first_elder < 0:
			first_elder = i
	var last_adult: int = -1
	for j in ids.size():
		if Story.stage_of(Story.townies[ids[j]]) == "adult":
			last_adult = j
	_check(first_elder < 0 or last_adult < first_elder, "the town list shows adults before elders")
	_check(ids.find(int(younger["id"])) < ids.find(int(older["id"])), "...youngest grown first")
	Aging.kill(int(head.id), "old age")
	var order: Array = SuccessionPick.order(1)
	_check(not order.is_empty() and int(order[0]["id"]) != int(elder_rel["id"]), "an elder relative does not go ahead of adults from town")
	SuccessionNobody.autopilot(1)
	var h: int = Succession.head_of(1)
	_check(Story.stage_of(Story.townies.get(h, {"age_days": 100.0})) != "elder" and str(K.world().get_folk(h).age_stage) == "adult", "autopilot picked an adult")
	K.teardown()

func _townie_from_town_lives() -> void:
	var head = _alone()
	var t: Dictionary = K.townie("Quill", "adult", 30.0)
	var npc: Folk = Crowd.spawn_npc(t, "park", "park", 100000)       # out in town as an ambient NPC: driven by CrowdDrive, no autonomy
	Aging.kill(int(head.id), "old age")
	var r: Dictionary = SuccessionNobody.choose(1, "townie:%d" % int(t["id"]))
	_check(bool(r["ok"]) and Succession.head_of(1) == int(t["id"]), "a townie who was out in town can take over: %s" % str(r))
	var f = K.world().get_folk(int(t["id"]))
	_check(f != null and int(f.household_id) == 1 and not f.has_meta("visitor") and not f.has_meta("crowd") and not f.has_meta("leave_min"), "no leftover visitor / crowd marks")
	_check(f != null and f.idle_until_min < (1 << 20), "full autonomy is on, not the crowd driver")
	var best: float = -999.0
	var worst: float = 999.0
	var ends: float = 0.0
	for _h in 36:
		K.HoodKit.run(60)
		var b: float = f.needs["bladder"].value
		best = maxf(best, b)
		worst = minf(worst, b)
		ends = b
	# Deterministic for a given master seed (not load dependent), but the dip depends on the seed: over seeds 1-12 the minimum ranges from +46 to -32
	# (cause not investigated), while a stuck crowd driver would sit near -100 and never recover.
	_check(worst > -60.0 and best > 60.0, "bladder stays sane and recovers (min %.0f, max %.0f)" % [worst, best])
	K.teardown()
