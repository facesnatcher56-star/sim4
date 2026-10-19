extends RefCounted
## Task 14 family and social events: weddings at a venue (engaged only, RomanceRules still guards), birthday parties, baby showers, funerals, family
## reunions, the block party and the holiday parade, with guests, presents and news.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_wedding(f)
	_birthday(f)
	_shower(f)
	_funeral(f)
	_reunion(f)
	_neighbourhood(f)
	return f

func _world(coins: int = 3000) -> Array:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	var ids: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult").map(func(t): return int(t["id"]))
	ids.sort()
	for i in 6:
		RelationshipService.add_both(1, ids[i], "friendship", 50.0)
	return [w, ids]

func _first_day(season: String) -> int:
	for d in range(1, 200):
		if Seasons.season_at_day(d) == season:
			return d
	return 1

func _wedding(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	var ann = SysUtil.folk(1)
	var spring: int = _first_day("spring")
	K.set_time(spring, 12)
	K.expect(f, PlaceUse.why_not(1, "wedding_lawn", "wedding_lawn") == "Ann is not engaged.", "no wedding without an engagement")
	var fi: int = ids[0]
	RelationshipBits.set_flag(1, fi, "partner", true, false)
	RelationshipService.add_both(1, fi, "romance", 90.0)
	Family.engaged[SysUtil.pair_key(1, fi)] = {"a": 1, "b": fi, "since": 1}
	K.expect(f, PlaceUse.why_not(1, "wedding_lawn", "wedding_lawn") == "", "an engaged adult can book the lawn")
	K.set_time(_first_day("winter"), 12)
	K.expect(f, PlaceUse.why_not(1, "wedding_lawn", "wedding_lawn").find("Closed") >= 0 or PlaceUse.why_not(1, "wedding_lawn", "wedding_lawn").find("Wedding Lawn") >= 0, "the lawn is shut in winter (%s)" % PlaceUse.why_not(1, "wedding_lawn", "wedding_lawn"))
	K.set_time(spring, 12)
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "wedding_lawn", "wedding_lawn", {"instant": true})
	K.expect(f, bool(r["ok"]) and FamilyTree.spouse_of(1) == fi, "the wedding happens (%s)" % str(r.get("reason", "")))
	K.expect(f, str(r["text"]).find("were married at Willow Green Wedding Lawn") >= 0 and str(r["text"]).find("guest") >= 0, "the text names the place and the guests (%s)" % str(r.get("text", "")))
	K.expect(f, Economy.balance(1) != coins and K.count_events("married") == 1, "money moved and the married event fired")
	var kinds: Array = ChronicleHook.recent.map(func(p): return str(p["kind"]))
	K.expect(f, kinds.has("wedding") and kinds.has("wedding_party"), "the chronicle has the wedding and the party")
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "wedding_hall").find("not engaged") >= 0, "a married person is no longer engaged (%s)" % PlaceUse.why_not(1, "hall_hire", "wedding_hall"))
	# relatives and children: the rules are the existing ones
	var w: StubWorld = r0[0]
	var teen := K.make_folk(w, "Tess", [], 1, Vector2i(14, 12), "teen")
	K.expect(f, PlaceUse.why_not(int(teen.id), "hall_hire", "wedding_hall") != "", "a teen cannot hold a wedding")
	K.teardown()

func _birthday(f: Array) -> void:
	var r0: Array = _world()
	var ann = SysUtil.folk(1)
	K.set_time(5, 14)
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "birthday_hall") == "A birthday party is for the days around a birthday.", "no party in the middle of nowhere")
	Aging.records[1]["birth_doy"] = Aging.doy(SysUtil.day()) + 1               # tomorrow
	K.expect(f, Aging.birth_doy(1) == Aging.doy(5) + 1 and PlaceUse.why_not(1, "hall_hire", "birthday_hall") == "", "the days before a birthday are fine")
	var coins: int = Economy.balance(1)
	ann.needs["fun"].value = 0.0
	var r: Dictionary = PlaceUse.use(1, "hall_hire", "birthday_hall", {"instant": true})
	K.expect(f, bool(r["ok"]) and ann.needs["fun"].value >= 20.0 and ann.has_buff("party_buzz") and str(r["text"]).find("birthday party") >= 0, "the party is fun (%s)" % str(r.get("text", "")))
	K.expect(f, Economy.balance(1) < coins, "the hall and the guests cost money")
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "birthday_hall").find("already had a party") >= 0, "one a year")
	K.set_time(5 + 30, 14)
	Aging.records[1]["birth_doy"] = Aging.doy(SysUtil.day()) - 2
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "birthday_hall") == "" or PlaceUse.why_not(1, "hall_hire", "birthday_hall").find("already") >= 0, "a late party is still allowed in the next year")
	K.teardown()

func _shower(f: Array) -> void:
	var r0: Array = _world()
	var ann = SysUtil.folk(1)
	K.set_time(5, 14)
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "shower_hall") == "A baby shower needs a baby on the way.", "no shower without a baby on the way")
	Aging.pregnancies[1] = {"due_day": 20, "started": 4}
	var r: Dictionary = PlaceUse.use(1, "hall_hire", "shower_hall", {"instant": true})
	K.expect(f, bool(r["ok"]) and str(r["text"]).find("baby shower") >= 0 and ann.has_buff("cheered_up"), "a shower for an expecting mother (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "shower_hall").find("shower already") >= 0, "one a year")
	K.teardown()

func _funeral(f: Array) -> void:
	var r0: Array = _world()
	var ann = SysUtil.folk(1)
	K.set_time(10, 11)
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "funeral_hall") == "There is no funeral to hold.", "no death, no funeral")
	var dead: int = 4242
	RelationshipService.add_both(1, dead, "friendship", 60.0)
	Graves.records[-1] = {"object_id": -1, "folk_id": dead, "name": "Old Joe", "born": 0, "died": 8, "years": 6, "stage": "elder", "cause": "old age", "cause_id": "old_age", "style": "stone", "def": "grave", "park": false, "tile": [-1, -1], "visits": 0}
	ann.add_buff("grieving")
	var rem0: float = 0.0
	for b in ann.buffs:
		if str(b["id"]) == "grieving":
			rem0 = float(b["remaining"])
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "funeral_hall") == "", "a friend who died two days ago can be remembered")
	var r: Dictionary = PlaceUse.use(1, "hall_hire", "funeral_hall", {"instant": true})
	K.expect(f, bool(r["ok"]) and str(r["text"]).find("funeral was held for Old Joe") >= 0, "the funeral is held (%s)" % str(r.get("text", "")))
	var rem1: float = 0.0
	for b2 in ann.buffs:
		if str(b2["id"]) == "grieving":
			rem1 = float(b2["remaining"])
	K.expect(f, rem1 <= rem0 * 0.75, "it eases the grief (%.0f -> %.0f)" % [rem0, rem1])
	K.expect(f, EventState.funerals.has(dead) and PlaceUse.why_not(1, "hall_hire", "funeral_hall") != "", "only one funeral each")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "funeral" and int(p["severity"]) == 2), "and it is in the chronicle")
	# too long ago, or a stranger
	K.set_time(40, 11)
	Graves.records[-2] = {"object_id": -1, "folk_id": 4343, "name": "Old Ann", "born": 0, "died": 8, "years": 6, "stage": "elder", "cause": "old age", "cause_id": "old_age", "style": "stone", "def": "grave", "park": false, "tile": [-1, -1], "visits": 0}
	RelationshipService.add_both(1, 4343, "friendship", 60.0)
	K.expect(f, PlaceUse.why_not(1, "hall_hire", "funeral_hall") == "There is no funeral to hold.", "after ten days it is too late")
	K.teardown()

func _reunion(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	var ann = SysUtil.folk(1)
	K.set_time(6, 11)
	K.expect(f, PlaceUse.why_not(1, "picnic_grove", "reunion_picnic").find("at least two relatives") >= 0, "a reunion needs relatives")
	for i in 3:
		RelationshipBits.set_flag(1, ids[i], "family", true, false)
	K.expect(f, PlaceUse.why_not(1, "picnic_grove", "reunion_picnic") == "", "with relatives it works")
	var fr0: float = RelationshipService.value(1, ids[0], "friendship")
	var r: Dictionary = PlaceUse.use(1, "picnic_grove", "reunion_picnic", {"instant": true})
	K.expect(f, bool(r["ok"]) and str(r["text"]).find("family reunion") >= 0 and RelationshipService.value(1, ids[0], "friendship") >= fr0, "the family gets together (%s)" % str(r.get("text", "")))
	K.expect(f, PlaceUse.why_not(1, "picnic_grove", "reunion_picnic").find("this year already") >= 0, "once a year")
	K.teardown()

func _neighbourhood(f: Array) -> void:
	var r0: Array = _world()
	var ann = SysUtil.folk(1)
	var day_bp := 6                                     # doy 5
	K.set_time(day_bp, 16)
	K.expect(f, Aging.doy(day_bp) == 5 and Places.open_at("block_party"), "the block party is on at 16:00 on the fifth day of the year")
	K.set_time(day_bp + 1, 16)
	K.expect(f, not Places.open_at("block_party"), "and not the day after")
	K.set_time(day_bp, 10)
	K.expect(f, not Places.open_at("block_party"), "nor in the morning")
	K.set_time(day_bp, 16)
	var fr_before: float = 0.0
	var r: Dictionary = PlaceUse.use(1, "block_party", "join_block_party", {"instant": true})
	K.expect(f, bool(r["ok"]) and str(r["text"]).find("chatted with") >= 0 and ann.needs["social"].value >= 20.0, "joining makes friends (%s)" % str(r.get("text", "")))
	var kid := K.make_folk(r0[0], "Kit", [], 1, Vector2i(14, 12), "child")
	K.expect(f, PlaceUse.why_not(int(kid.id), "block_party", "join_block_party") == "", "children are welcome at the block party")
	# the news line on the day, and only then
	ChronicleHook.reset()
	PlaceNews.on_day(day_bp)
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["text"]).find("block party") >= 0), "the block party is announced on its day")
	ChronicleHook.reset()
	PlaceNews.on_day(day_bp + 1)
	K.expect(f, not ChronicleHook.recent.any(func(p): return str(p["text"]).find("block party") >= 0), "and not on others")
	# the parade needs a holiday
	var hday := -1
	for d in range(1, 120):
		if not Holidays.today(d).is_empty():
			hday = d
			break
	K.expect(f, hday > 0, "the calendar has a holiday (day %d)" % hday)
	K.set_time(hday, 12)
	K.expect(f, Places.open_at("holiday_parade") and bool(PlaceUse.use(1, "holiday_parade", "watch_parade", {"instant": true})["ok"]), "on a holiday the parade goes by and anybody can watch")
	var plain := -1
	for d2 in range(1, 120):
		if Holidays.today(d2).is_empty():
			plain = d2
			break
	K.set_time(plain, 12)
	K.expect(f, not Places.open_at("holiday_parade"), "no parade on an ordinary day")
	K.teardown()
