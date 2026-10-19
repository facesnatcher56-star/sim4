extends RefCounted
## Task 15: "nobody left". The last household member dies: the player is asked (relatives first, then someone from town, or a new family) in plain
## words; the town runs on meanwhile; without a UI the first choice is made automatically after two days, so no empty household lasts.

const K := preload("res://tests/succession_kit.gd")
var fails: Array = []
var shown: Array = []             # [{title, text, options, cb}] what the fake prompt was asked

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_prompt_flow()
	_autopilot_town()
	_relative_elsewhere()
	_new_family()
	_little_alone()
	return fails

func _lonely() -> Object:
	var folk: Array = K.new_game()
	Aging.kill(int(folk[1].id), "old age")
	Aging.kill(int(folk[2].id), "old age")
	return folk[0]

func _ids(options: Array) -> Array:
	return options.map(func(o): return str(o["id"]))

func _fake_ui() -> void:
	shown.clear()
	JusticePlayer.ask_fn = func(_pid, title, text, options, cb, _default): shown.append({"title": title, "text": text, "options": options, "cb": cb})

func _prompt_flow() -> void:
	var head = _lonely()
	_fake_ui()
	K.townie("Quill", "adult", 10.0)
	Aging.kill(int(head.id), "old age")
	_check(Succession.is_pending(1) and Succession.empty_household(1), "the last member died: waiting for the player's choice")
	_check(shown.is_empty(), "no window pops up on its own: a toast and a banner tell the player")
	SuccessionNobody.prompt(1)                       # the banner button
	_check(shown.size() == 1, "the choice opens from the banner")
	var ids: Array = _ids(shown[0]["options"]) if not shown.is_empty() else []
	_check(ids == ["town", "new", "later"], "no relatives: someone from town, a new family, decide later: %s" % str(ids))
	var words: String = str(shown[0]["title"]) + " " + str(shown[0]["text"])
	_check(words.find("Mira has died") >= 0 and words.find("Nobody is left") >= 0 and words.find("history") >= 0, "plain words: %s" % words)
	# decide later: the town carries on and the player is reminded in the morning (no window), never two prompts at once
	shown[0]["cb"].call("later")
	_check(Succession.is_pending(1), "decide later keeps the question open")
	Succession.on_day(SysUtil.day() + 1)
	_check(K.HoodKit.has_note("Nobody is playing your household") and shown.size() == 1, "the reminder comes back the next morning")
	SuccessionNobody.prompt(1)
	SuccessionNobody.prompt(1)
	_check(shown.size() == 2, "never two prompts at once")
	# pick someone from town: the list, then the choice
	shown[1]["cb"].call("town")
	_check(shown.size() == 3, "the town list opens")
	var tids: Array = _ids(shown[2]["options"]) if shown.size() > 2 else []
	_check(tids.size() >= 2 and tids[0].begins_with("townie:") and tids[tids.size() - 1] == "back", "the list names the grown-ups of the town: %s" % str(tids))
	var pick: int = int(str(tids[0]).get_slice(":", 1))
	var pick_name: String = Family.name_of(pick)
	shown[2]["cb"].call("townie:%d" % pick)
	var q = K.world().get_folk(pick)
	_check(q != null and int(q.household_id) == 1 and Succession.head_of(1) == pick, "the townie moved into the family home and is the head")
	_check(not Succession.is_pending(1) and not Succession.empty_household(1), "the household is no longer empty")
	var said := false
	for n in K.HoodKit.notes:
		if str(n[0]).find("You now play " + pick_name) >= 0:
			said = true
	_check(said, "the toast says who you play now")
	_check(Family.people.has(int(head.id)) and Story.townies.size() > 0, "the town keeps its history")
	_check(not bool(SuccessionNobody.choose(1, "town")["ok"]), "choosing again when nobody is waiting is refused")
	K.teardown()

func _autopilot_town() -> void:
	var head = _lonely()
	K.townie("Quill", "adult", 10.0)
	K.townie("Child", "child")
	var first: int = int(SuccessionNobody.townies()[0]["id"])
	Aging.kill(int(head.id), "old age")
	var day: int = SysUtil.day()
	_check(Succession.is_pending(1), "pending without a UI too")
	Succession.on_day(day + 1)
	_check(Succession.is_pending(1), "one day later: still waiting")
	Succession.on_day(day + SuccessionNobody.AUTO_DAYS)
	_check(not Succession.is_pending(1) and Succession.head_of(1) == first, "without a UI the first grown townie is chosen after %d days" % SuccessionNobody.AUTO_DAYS)
	K.teardown()

func _relative_elsewhere() -> void:
	var head = _lonely()
	_fake_ui()
	var rel: Dictionary = K.townie("Rhea", "adult", 20.0)
	K.child_of(int(head.id), int(rel["id"]))                  # Rhea is Mira's parent, lives elsewhere
	Aging.kill(int(head.id), "old age")
	_check(Succession.is_pending(1), "only a far relative, empty house: the player is asked")
	SuccessionNobody.prompt(1)
	var ids: Array = _ids(shown[0]["options"]) if not shown.is_empty() else []
	_check(ids.size() == 4 and ids[0] == "relative:%d" % int(rel["id"]), "the relative is offered first: %s" % str(ids))
	_check(str(shown[0]["options"][0]["label"]).find("Rhea") >= 0 and str(shown[0]["options"][0]["label"]).find("lives elsewhere") >= 0, "the label says who and where: %s" % str(shown[0]["options"][0]["label"]))
	JusticePlayer.ask_fn = Callable()
	SuccessionNobody.autopilot(1)
	_check(Succession.head_of(1) == int(rel["id"]) and K.household_count() == 1, "autopilot prefers the relative")
	K.teardown()

func _new_family() -> void:
	var head = _lonely()
	K.townie("Quill", "adult")
	Aging.kill(int(head.id), "old age")
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": -1, "action": "choose_successor", "args": {"choice": "new"}})
	_check(bool(r["ok"]), "choose_successor new: %s" % str(r))
	var h: int = Succession.head_of(1)
	var f = K.world().get_folk(h)
	_check(f != null and int(f.household_id) == 1 and h != int(head.id), "a new family lives in the old home")
	_check(not Succession.is_pending(1) and K.household_count() == 1, "not pending, one new person")
	_check(Aging.records.has(h) and Story.townies.size() > 0 and Family.people.has(int(head.id)), "registered in the systems; the town and its history are kept")
	# a made household
	K.teardown()
	var head2 = _lonely()
	Aging.kill(int(head2.id), "old age")
	var hh: Dictionary = {"name": "Newcomers", "folk": [{"name": "Nell", "stage": "adult", "rel": "none", "traits": ["neat", "active", "social"]}, {"name": "Nico", "stage": "child", "rel": "child", "traits": ["neat", "active"]}]}
	var r2: Dictionary = SuccessionNobody.choose(1, "new", hh)
	_check(bool(r2["ok"]) and K.household_count() == 2 and Family.name_of(Succession.head_of(1)) == "Nell", "a household made in the creator moves in: %s" % str(r2))
	K.teardown()

func _little_alone() -> void:
	var folk: Array = K.new_game()
	Aging.kill(int(folk[1].id), "old age")
	Aging.kill(int(folk[2].id), "old age")
	var baby = K.housemate("Bee", "toddler", 1.0)
	var rel: Dictionary = K.townie("Rhea", "adult", 20.0)
	K.child_of(int(folk[0].id), int(rel["id"]))
	Aging.kill(int(folk[0].id), "old age")
	_check(not Succession.is_pending(1), "a toddler is at home and a relative can come: no question, the relative moves in")
	_check(Succession.head_of(1) == int(rel["id"]) and K.household_count() == 2, "the relative heads the home with the toddler")
	K.teardown()
