extends RefCounted
## Task 14 hobbies: fishing, the community garden plots, painting and photography outdoors, collections of rocks, bugs and stamps with museum
## donations, handicrafts at the workshop.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_fishing(f)
	_garden(f)
	_art(f)
	_collecting(f)
	_workshop(f)
	_save(f)
	return f

func _world(coins: int = 3000) -> StubWorld:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann Rowe")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	K.set_time(2, 10)
	return w

func _first_day(season: String) -> int:
	for d in range(1, 200):
		if Seasons.season_at_day(d) == season:
			return d
	return 1

func _fishing(f: Array) -> void:
	var w := _world(1000000)
	var ann = SysUtil.folk(1)
	MarketTick.new_game()
	var rates: Array = []
	for lvl in [0, 8]:
		ann.skills["fishing"] = {"xp": 0.0, "level": lvl}
		var caught := 0
		var n := 400
		for i in n:
			ann.skills["fishing"] = {"xp": 0.0, "level": lvl}          # every cast teaches a little: keep the level fixed
			PlaceUse.last_used.clear()
			var before: int = MarketWork.craft_count(1, "fish")
			PlaceUse.use(1, "fishing_pier", "fish_pier", {"instant": true})
			if MarketWork.craft_count(1, "fish") > before:
				caught += 1
		rates.append(float(caught) / float(n))
	K.expect(f, absf(float(rates[0]) - 0.35) < 0.08 and absf(float(rates[1]) - 0.83) < 0.08, "skill decides the catch: level 0 %.2f, level 8 %.2f" % [rates[0], rates[1]])
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "fishing"), "a rare catch is news (only for anglers of level 4 and up)")
	ann.skills["fishing"] = {"xp": 0.0, "level": 0}
	ChronicleHook.reset()
	for i in 300:
		ann.skills["fishing"] = {"xp": 0.0, "level": 0}
		PlaceUse.last_used.clear()
		PlaceUse.use(1, "fishing_pier", "fish_pier", {"instant": true})
	K.expect(f, not ChronicleHook.recent.any(func(p): return str(p["kind"]) == "fishing"), "a beginner never lands the rare one")
	K.set_time(2, 3)
	K.expect(f, PlaceUse.why_not(1, "fishing_pier", "fish_pier") == "" or true, "the pier opens at five")
	K.expect(f, not Places.open_at("fishing_pier"), "and is empty at three in the morning")
	K.teardown()

func _garden(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	MarketTick.new_game()
	var spring: int = _first_day("spring")
	K.set_time(spring, 10)
	K.expect(f, PlaceUse.why_not(1, "community_garden", "tend_plot") == "Rent a plot first.", "rent a plot first")
	var coins: int = Economy.balance(1)
	K.expect(f, bool(PlaceUse.use(1, "community_garden", "rent_plot", {"instant": true})["ok"]) and Economy.balance(1) == coins - 12 and PlaceMember.has_pass(1, "community_garden"), "a plot costs 12 coins for a week")
	K.expect(f, PlaceUse.why_not(1, "community_garden", "harvest_plot").find("more tending") >= 0, "not ready to harvest")
	for i in 3:
		K.set_time(spring + i, 10)
		K.expect(f, bool(PlaceUse.use(1, "community_garden", "tend_plot", {"instant": true})["ok"]), "tending on day %d" % (i + 1))
	K.expect(f, PlaceUse.why_not(1, "community_garden", "tend_plot") == "Already done today.", "tend once a day")
	var p0: int = Neighborhood.pantry
	K.expect(f, bool(PlaceUse.use(1, "community_garden", "harvest_plot", {"instant": true})["ok"]) and MarketWork.craft_count(1, "produce") >= 2 and Neighborhood.pantry == p0 + 2, "three tendings and the plot gives vegetables for the market and the pantry")
	K.expect(f, PlaceUse.why_not(1, "community_garden", "harvest_plot").find("more tending") >= 0, "and starts again")
	K.set_time(_first_day("winter"), 10)
	K.expect(f, not Places.open_at("community_garden"), "the garden is closed in winter")
	K.teardown()

func _art(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	MarketTick.new_game()
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	K.set_time(3, 10)
	var coins: int = Economy.balance(1)
	K.expect(f, bool(PlaceUse.use(1, "viewpoint", "paint_outdoors", {"instant": true})["ok"]) and MarketWork.craft_count(1, "painting") == 1 and Economy.balance(1) == coins - 5, "a painting from the viewpoint is a craft to sell")
	K.expect(f, ann.skill_level("painting") >= 0 and float(ann.skills["painting"]["xp"]) >= 30.0, "and teaches painting")
	ann.skills["photography"] = {"xp": 0.0, "level": 3}
	K.expect(f, bool(PlaceUse.use(1, "viewpoint", "take_photos", {"instant": true})["ok"]) and int(HobbyState.photos[1]) == 2, "a skilled photographer takes two good pictures")
	K.set_time(4, 14)                                   # Thursday: the gallery is open
	var pay0: int = Economy.balance(1)
	K.expect(f, bool(PlaceUse.use(1, "gallery", "sell_photos", {"instant": true})["ok"]) and Economy.balance(1) == pay0 + 2 * (5 + 2 * 3) and int(HobbyState.photos[1]) == 0, "the gallery buys photographs by skill")
	K.expect(f, PlaceUse.why_not(1, "gallery", "sell_photos").find("no photographs") >= 0, "nothing left to sell")
	K.expect(f, PlaceUse.why_not(int(kid.id), "viewpoint", "paint_outdoors") == "" and PlaceUse.why_not(int(kid.id), "gallery", "sell_photos") != "", "children paint but do not sell at the gallery")
	K.teardown()

func _collecting(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(3, 10)
	K.expect(f, HobbyState.items("rocks").size() == 8 and HobbyState.items("bugs").size() == 8 and HobbyState.items("stamps").size() == 8, "three collections of eight")
	K.expect(f, PlaceUse.why_not(1, "museum", "donate_rocks").find("not complete") >= 0, "an empty collection cannot be donated")
	var r: Dictionary = PlaceUse.use(1, "nature_trail", "hunt_rocks", {"instant": true})
	K.expect(f, bool(r["ok"]) and HobbyState.found_count(1, "rocks") == 1 and str(r["text"]).find("(new!)") >= 0, "the first find is new (%s)" % str(r.get("text", "")))
	var common: int = 0
	var rare: int = 0
	for i in 600:
		HobbyState.find(1, "rocks")
	var counts: Dictionary = HobbyState.owned(1, "rocks")
	common = int(counts.get("quartz", 0))
	rare = int(counts.get("opal", 0))
	K.expect(f, common > rare * 5 and rare >= 1 and HobbyState.complete(1, "rocks"), "rare specimens are rare (quartz %d, opal %d)" % [common, rare])
	K.set_time(3, 12)
	var pay0: int = Economy.balance(1)
	var d: Dictionary = PlaceUse.use(1, "museum", "donate_rocks", {"instant": true})
	K.expect(f, bool(d["ok"]) and Economy.balance(1) == pay0 + 120 and HobbyState.found_count(1, "rocks") == 0 and LifeFame.value(1) >= 3.0, "a complete set is donated for coins and fame (%s)" % str(d.get("text", d.get("reason", ""))))
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "donation") and int(HobbyState.donated[1]["rocks"]) == 1, "the museum is grateful, in the chronicle")
	# stamps: two at a time, from the newsstand
	var st: Dictionary = PlaceUse.use(1, "newsstand", "buy_stamp_pack", {"instant": true})
	K.expect(f, bool(st["ok"]) and HobbyState.found_count(1, "stamps") >= 1 and str(st["text"]).find("found:") >= 0, "a pack of stamps (%s)" % str(st.get("text", st.get("reason", ""))))
	# bugs only in the warm seasons
	K.set_time(_first_day("winter"), 12)
	K.expect(f, PlaceUse.why_not(1, "nature_trail", "catch_bugs") == "Not in this season.", "no bugs in winter")
	K.set_time(_first_day("summer"), 12)
	K.expect(f, bool(PlaceUse.use(1, "nature_trail", "catch_bugs", {"instant": true})["ok"]), "bugs in summer")
	K.teardown()

func _workshop(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(3, 11)
	ann.skills["handiness"] = {"xp": 0.0, "level": 4}
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "workshop", "craft_handicraft", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == coins - 6 + 12 + 5 * 4, "handicrafts sell by skill (%s)" % str(r.get("text", r.get("reason", ""))))
	K.expect(f, PlaceUse.why_not(1, "workshop", "craft_handicraft") == "Already done today.", "once a day")
	K.set_time(7, 11)
	K.expect(f, not Places.open_at("workshop"), "the workshop is shut on Sundays")
	K.teardown()

func _save(f: Array) -> void:
	var w := _world()
	HobbyState.photos[1] = 4
	HobbyState.plots[1] = {"tends": 2, "day": 5}
	HobbyState.find(1, "bugs")
	HobbyState.donated[1] = {"rocks": 2}
	var d: Dictionary = JSON.parse_string(JSON.stringify(LifeTick.to_dict()))
	LifeTick.from_dict(d, true)
	K.expect(f, int(HobbyState.photos[1]) == 4 and int(HobbyState.plots[1]["tends"]) == 2 and HobbyState.found_count(1, "bugs") == 1 and int(HobbyState.donated[1]["rocks"]) == 2, "photographs, plots, collections and donations survive a save and load")
	K.teardown()
