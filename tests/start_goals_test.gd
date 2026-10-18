extends RefCounted
## Scenario goals: event / job / cond checks, rewards, the final nudge, and persistence through save and load.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []
var toasts: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _note(text, kind) -> void:
	toasts.append([str(text), str(kind)])

func run() -> Array:
	fails = []
	_solo_goals()
	_event_goals()
	_save_load()
	_tracker_ui()
	_data()
	Kit.teardown()
	return fails

func _solo_goals() -> void:
	var folk: Array = Kit.new_game("solo")
	var ev = SimEnv.events()
	ev.notification.connect(_note)
	var f: Folk = folk[0]
	var funds: int = Economy.balance(1)
	var pts: int = Goals.points(f.id)
	_check(not Scenario.is_done("job"), "goal 1 starts open")
	Careers.hire(f, Careers.career_ids()[0], 1)
	_check(Scenario.is_done("job"), "hiring completes 'Get a job'")
	_check(Scenario.done_count() == 1 and not Scenario.finished, "one of four done")
	_check(Economy.balance(1) == funds + 150, "reward coins paid (%d)" % (Economy.balance(1) - funds))
	_check(Goals.points(f.id) == pts + 25, "reward satisfaction points paid")
	var heard := false
	for t in toasts:
		if str(t[0]).contains("Get a job") and t[1] == "goal":
			heard = true
	_check(heard, "completion toast shown")
	Careers.hire(f, Careers.career_ids()[0], 1)      # again: no double reward
	_check(Economy.balance(1) == funds + 150, "a goal pays once")
	# promotion through the career level (cond check, polled by the 'promoted' event)
	Careers.jobs[f.id]["level"] = 2
	SysUtil.game_event("promoted", {"folk_id": f.id})
	_check(Scenario.is_done("promotion"), "level 2 completes the promotion goal")
	# friend: a friend bit makes the cond true on the next poll (hourly)
	RelationshipService.set_value(f.id, 5000, "friendship", 60.0)
	RelationshipService.set_value(5000, f.id, "friendship", 60.0)
	Kit.run(60)
	# bills: a late bill does not count, an on-time payment does
	Economy.bills.append({"id": 90, "hid": 1, "amount": 10, "base": 10, "issued": 1, "due": 4, "paid": true, "late": true, "fee": 1})
	SysUtil.game_event("bill_paid", {"household_id": 1, "amount": 10})
	_check(not Scenario.is_done("bill"), "a late bill does not count as on time")
	Economy.bills.clear()
	Economy.bills.append({"id": 91, "hid": 1, "amount": 10, "base": 10, "issued": 1, "due": 4, "paid": true, "late": false, "fee": 0})
	SysUtil.game_event("bill_paid", {"household_id": 1, "amount": 10})
	_check(Scenario.is_done("bill"), "an on-time bill completes the bill goal")
	if not Scenario.is_done("friend"):
		ScenarioGoals.complete("friend")
	_check(Scenario.finished and Scenario.done_count() == 4, "all four done -> finished")
	var nudge := false
	for t in toasts:
		if str(t[0]).contains("Getting Started complete") and str(t[0]).contains("aspiration"):
			nudge = true
	_check(nudge, "final 'what next' nudge points to aspirations")
	ev.notification.disconnect(_note)

func _event_goals() -> void:
	Kit.new_game("couple")
	_check(not Scenario.is_done("decorate"), "couple: decorate open")
	SysUtil.game_event("object_bought", {"household_id": 1})
	_check(int(Scenario.progress.get("decorate", 0)) == 1 and not Scenario.is_done("decorate"), "couple: 1 of 2 purchases")
	SysUtil.game_event("object_bought", {"household_id": 1})
	_check(Scenario.is_done("decorate"), "couple: 2 purchases done")
	SysUtil.game_event("pregnant", {"folk_id": 1})
	_check(Scenario.is_done("commit"), "couple: any of engaged / married / pregnant counts")
	var jobs_before: bool = Scenario.is_done("jobs")
	Careers.hire(SysUtil.residents()[0], Careers.career_ids()[0], 1)
	_check(jobs_before == false and not Scenario.is_done("jobs"), "couple: one job is not enough for 'both'")
	Careers.hire(SysUtil.residents()[1], Careers.career_ids()[0], 1)
	_check(Scenario.is_done("jobs"), "couple: both employed")
	Kit.new_game("sandbox", "normal", {}, 5000)
	_check(Scenario.active() and not Scenario.has_goals(), "sandbox: active scenario without goals")
	SysUtil.game_event("hired", {})
	_check(Scenario.done.is_empty() and not Scenario.finished, "sandbox: nothing to complete")

func _save_load() -> void:
	var folk: Array = Kit.new_game("solo", "hard")
	Careers.hire(folk[0], Careers.career_ids()[0], 1)
	var funds: int = Economy.balance(1)
	var snap: Dictionary = SaveLoad.snapshot("scenario")
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	_check(parsed is Dictionary and (parsed["systems"] as Dictionary).has("scenario"), "scenario block is in the save")
	Kit.new_game("family", "relaxed")
	_check(Scenario.active_id == "family" and Scenario.difficulty == "relaxed", "another game in between")
	_check(SaveLoad.restore(parsed), "restore ok")
	_check(Scenario.active_id == "solo" and Scenario.difficulty == "hard", "scenario + difficulty restored (%s/%s)" % [Scenario.active_id, Scenario.difficulty])
	_check(Scenario.is_done("job") and Scenario.done_count() == 1, "completed goals restored")
	_check(Economy.balance(1) == funds, "funds restored")
	_check(Scenario.bill_multiplier() == 1.3, "hard bill multiplier is live after loading")
	# goals keep working after the load
	var f = SysUtil.residents()[0]
	Careers.jobs[f.id]["level"] = 2
	SysUtil.game_event("promoted", {"folk_id": f.id})
	_check(Scenario.is_done("promotion"), "goals still tracked after loading")
	# an old save without the block loads as 'no scenario'
	var old: Dictionary = JSON.parse_string(JSON.stringify(snap))
	(old["systems"] as Dictionary).erase("scenario")
	_check(SaveLoad.restore(old) and not Scenario.active() and Scenario.bill_multiplier() == 1.0, "old saves load without a scenario")

func _tracker_ui() -> void:
	Kit.new_game("solo")
	var tr := ScenarioTracker.new()
	Kit.root().add_child(tr)
	_check(tr.visible, "tracker visible for solo")
	_check(tr.box.get_child_count() >= 5, "tracker lists the goals + a hint (%d rows)" % tr.box.get_child_count())
	tr.collapsed = true
	tr.refresh()
	_check(tr.box.get_child_count() == 1, "collapsed tracker is just the header")
	tr.collapsed = false
	for g in Scenario.goals():
		ScenarioGoals.complete(str(g["id"]))
	_check(tr.celebrating and tr.visible, "finishing shows the 'what next' card")
	var asked: Array = []
	tr.goals_requested.connect(func(): asked.append(1))
	var open_btn: Button = null
	for b in tr.box.find_children("*", "Button", true, false):
		if (b as Button).text == "Open Goals":
			open_btn = b
	_check(open_btn != null, "'Open Goals' button on the nudge card")
	if open_btn != null:
		open_btn.pressed.emit()
		_check(asked.size() == 1, "'Open Goals' asks the HUD for the goals dialog")
	tr.dismissed = true
	tr.refresh()
	_check(not tr.visible, "'Got it' hides the card")
	tr.reset_for_game()
	_check(not tr.visible, "a finished scenario stays hidden in a later session")
	Kit.new_game("sandbox")
	tr.reset_for_game()
	_check(not tr.visible, "no tracker without goals (Free Play)")
	tr.queue_free()

func _data() -> void:
	for sc in Scenario.scenarios():
		var seen := {}
		for g in sc.get("goals", []):
			var id: String = str(g["id"])
			_check(not seen.has(id), "%s: goal id %s unique" % [sc["id"], id])
			seen[id] = true
			var ck: Dictionary = g.get("check", {})
			_check(ck.has("event") or ck.has("events") or ck.has("jobs") or ck.has("cond"), "%s/%s: known check kind" % [sc["id"], id])
			_check(str(g.get("label", "")) != "" and str(g.get("hint", "")) != "", "%s/%s: label and hint" % [sc["id"], id])
			_check(int((g.get("reward", {}) as Dictionary).get("coins", 0)) > 0, "%s/%s: pays a reward" % [sc["id"], id])
		_check(str(sc.get("start_id", "")) != "" and not Neighborhood.start_def(str(sc["start_id"])).is_empty(), "%s: start_id exists" % sc["id"])
		_check((sc.get("tips", []) as Array).size() >= 3, "%s: has onboarding tips" % sc["id"])
		_check(HouseholdSetup.validate(HouseholdSetup.make_household(str(sc["id"]))) == "", "%s: preset household is valid" % sc["id"])
