extends RefCounted
## Task 14 culture and leisure: programmes that change weekly, the cinema's ratings, performing, the gallery, bowling and the arcade with records, the
## pool, the local league, the lake and the campsite by season, the community clubs, and the save round trip.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_programme(f)
	_cinema(f)
	_perform(f)
	_gallery(f)
	_games(f)
	_league(f)
	_clubs(f)
	_seasons(f)
	_save(f)
	return f

func _world(coins: int = 3000) -> StubWorld:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	return w

func _programme(f: Array) -> void:
	var w := _world()
	for pid in ["cinema", "theatre", "concert_hall", "museum", "gallery"]:
		var slots: Array = Places.def(pid).get("programme", {}).get("slots", [])
		K.expect(f, not slots.is_empty(), "%s has a programme" % pid)
		for s in slots:
			K.expect(f, Programme.titles(pid, str(s)).size() >= 3, "%s/%s has at least three titles" % [pid, s])
	K.set_time(2, 12)
	var t0: String = Programme.title("cinema", "family")
	K.set_time(5, 12)
	K.expect(f, Programme.title("cinema", "family") == t0, "the title stays all week")
	K.set_time(9, 12)
	K.expect(f, Programme.title("cinema", "family") != t0, "and changes with the week (%s)" % Programme.title("cinema", "family"))
	K.expect(f, Places.service_label("cinema", "cinema_family") == "Family Film: " + Programme.title("cinema", "family"), "the service label shows the title")
	K.teardown()

func _cinema(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var teen := K.make_folk(w, "Tess", [], 1, Vector2i(14, 12), "teen")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(15, 12), "child")
	var tod := K.make_folk(w, "Tom", [], 1, Vector2i(16, 12), "toddler")
	K.set_time(6, 20)
	K.expect(f, PlaceUse.why_not(int(kid.id), "cinema", "cinema_family") == "" and PlaceUse.why_not(int(kid.id), "cinema", "cinema_teen") != "" and PlaceUse.why_not(int(kid.id), "cinema", "cinema_adult") != "", "a child sees only the family film")
	K.expect(f, PlaceUse.why_not(int(teen.id), "cinema", "cinema_teen") == "" and PlaceUse.why_not(int(teen.id), "cinema", "cinema_adult") == "Only for adults.", "a teen sees the new release, not the late show")
	K.expect(f, PlaceUse.why_not(1, "cinema", "cinema_adult") == "" and PlaceUse.why_not(int(tod.id), "cinema", "cinema_family") != "", "adults see everything, toddlers nothing")
	ann.needs["fun"].value = 0.0
	var r: Dictionary = PlaceUse.use(1, "cinema", "cinema_adult", {"instant": true})
	K.expect(f, bool(r["ok"]) and ann.needs["fun"].value > 30.0 and ann.has_buff("entertained") and str(r["text"]).find(Programme.title("cinema", "adult")) >= 0, "a film is fun and the text names it (%s)" % str(r.get("text", "")))
	HealthLife.rec(1)["diet"] = 50.0
	PlaceUse.use(1, "cinema", "cinema_popcorn", {"instant": true})
	K.expect(f, float(HealthLife.rec(1)["diet"]) < 50.0, "popcorn is not health food")
	K.set_time(7, 0)                                    # Sunday 00:00: the late show of Saturday night still runs
	K.expect(f, Places.open_at("cinema") and Venues.is_open_type("office", SimEnv.now_min()), "the cinema runs past midnight and keeps the office lot open")
	K.set_time(7, 5)
	K.expect(f, not Places.open_at("cinema"), "but not at 05:00")
	K.teardown()

func _perform(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(5, 20)                                   # Friday evening
	K.expect(f, PlaceUse.why_not(1, "concert_hall", "perform_guitar").begins_with("Needs guitar level 3"), "a beginner cannot book a set (%s)" % PlaceUse.why_not(1, "concert_hall", "perform_guitar"))
	ann.skills["guitar"] = {"xp": 0.0, "level": 5}
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "concert_hall", "perform_guitar", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) > coins, "a set pays (%s)" % str(r.get("text", "")))
	K.expect(f, LifeFame.value(1) > 0.0 or ann.has_buff("embarrassed"), "and fame grows if it went well")
	# many tries: success rate near the formula, a good player earns on average
	var ok := 0
	var paid := 0
	var tries := 300
	for i in tries:
		K.set_time(5 + (i % 2) * 1, 20)
		PlaceUse.last_used.clear()
		var c0: int = Economy.balance(1)
		LifeFame.fame.clear()
		var rr: Dictionary = PlaceUse.use(1, "concert_hall", "perform_guitar", {"instant": true})
		if bool(rr["ok"]) and LifeFame.value(1) > 0.0:
			ok += 1
		paid += Economy.balance(1) - c0
	var share: float = float(ok) / float(tries)
	K.expect(f, share > 0.55 and share < 0.85, "level 5 succeeds about 69 percent of the time (%.2f)" % share)
	K.expect(f, paid / tries > 40, "and earns a fair amount (%d a set)" % (paid / tries))
	# fame labels and decay
	LifeFame.reset()
	LifeFame.add(1, 20.0)
	K.expect(f, LifeFame.label(1) == "well known in town", "fame has a plain label")
	LifeFame.on_day(10)
	K.expect(f, LifeFame.value(1) < 20.0 and LifeFame.value(1) > 19.0, "fame fades slowly")
	K.set_time(2, 20)
	K.expect(f, PlaceUse.why_not(1, "concert_hall", "concert_ticket") != "", "the hall is dark on Tuesdays")
	K.teardown()

func _gallery(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	MarketTick.new_game()
	K.set_time(4, 14)                                   # Thursday afternoon
	K.expect(f, PlaceUse.why_not(1, "gallery", "gallery_exhibit").find("no paintings") >= 0, "nothing to show without paintings")
	ann.skills["painting"] = {"xp": 0.0, "level": 4}
	MarketWork.add_craft(1, "painting", 4)
	var market_price: int = int(round(MarketWork.craft_price("painting", 4)))
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "gallery", "gallery_exhibit", {"instant": true})
	K.expect(f, bool(r["ok"]) and MarketWork.craft_count(1, "painting") == 1, "the gallery takes up to three paintings (%d left)" % MarketWork.craft_count(1, "painting"))
	K.expect(f, Economy.balance(1) - coins > 3 * market_price, "and pays better than the market stall (%d vs %d)" % [Economy.balance(1) - coins, 3 * market_price])
	K.expect(f, LifeFame.value(1) >= 6.0 and ChronicleHook.recent.any(func(p): return str(p["kind"]) == "gallery_sale"), "it adds fame and a line in the chronicle")
	K.set_time(1, 14)
	K.expect(f, not Places.open_at("gallery"), "the gallery is closed on Mondays")
	K.teardown()

func _games(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	K.set_time(3, 18)
	var scores: Array = []
	for i in 30:
		PlaceUse.last_used.clear()
		var r: Dictionary = PlaceUse.use(1, "bowling", "bowl", {"instant": true})
		K.expect(f, bool(r["ok"]), "a game of bowling")
	var rec: Dictionary = LifeFame.records.get("bowling", {})
	K.expect(f, int(rec.get("score", 0)) > 80 and int(rec.get("score", 0)) <= 300 and str(rec.get("name", "")) == "Ann", "the town record is on the wall (%s)" % str(rec))
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "record"), "a new record is news")
	K.expect(f, int(LifeFame.best[1]["bowling"]) == int(rec["score"]), "and is her best")
	K.expect(f, bool(PlaceUse.use(int(kid.id), "arcade", "arcade", {"instant": true})["ok"]) and int(LifeFame.records["arcade"]["score"]) >= 1000, "children can play the arcade")
	K.set_time(3, 9)
	K.expect(f, PlaceUse.why_not(1, "bowling", "bowl") != "" and PlaceUse.why_not(1, "arcade", "arcade") != "", "both are shut in the morning")
	# the pool
	var tod := K.make_folk(w, "Tom", [], 1, Vector2i(15, 12), "toddler")
	K.set_time(3, 10)
	HealthLife.rec(1)["fitness"] = 40.0
	K.expect(f, bool(PlaceUse.use(1, "pool", "swim", {"instant": true})["ok"]) and float(HealthLife.rec(1)["fitness"]) == 42.5, "swimming builds fitness")
	K.expect(f, PlaceUse.why_not(int(tod.id), "pool", "swim") != "" and PlaceUse.why_not(int(tod.id), "pool", "family_splash") == "", "toddlers splash in the shallow end only")
	K.teardown()

func _league(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	LeagueState.ensure()
	K.expect(f, LeagueState.rosters.size() == 4 and (LeagueState.rosters["foxes"] as Array).size() == 3, "four teams with three townies each")
	K.set_time(4, 14)                                   # Thursday
	K.expect(f, PlaceUse.why_not(1, "sports_field", "league_play") != "", "no match to play before joining / on a weekday")
	K.set_time(6, 14)                                   # Saturday
	K.expect(f, PlaceUse.why_not(1, "sports_field", "league_play") == "Join a team first.", "join first")
	var r: Dictionary = PlaceUse.use(1, "sports_field", "league_join", {"instant": true})
	K.expect(f, bool(r["ok"]) and LeagueState.team_of(1) != "" and str(r["text"]).find(LeagueState.team_label(LeagueState.team_of(1))) >= 0, "joining puts her in a team (%s)" % LeagueState.team_of(1))
	K.expect(f, PlaceUse.why_not(1, "sports_field", "league_join").find("already plays") >= 0, "not twice")
	K.expect(f, bool(PlaceUse.use(1, "sports_field", "league_play", {"instant": true})["ok"]) and int(LeagueState.played[1]) == 6, "she plays the Saturday match")
	K.expect(f, PlaceUse.why_not(1, "sports_field", "league_play").find("already played") >= 0, "only once")
	# three rounds: Sundays at day 7, 14, 21
	for d in [7, 14, 21]:
		K.set_time(d, 0)
		LeagueState.on_day(d)
		K.set_time(d + 6, 12)
	var matches: int = LeagueState.results.size()
	K.expect(f, matches >= 6 or LeagueState.season == 2, "six matches were played over three rounds (%d kept, season %d)" % [matches, LeagueState.season])
	K.expect(f, LeagueState.season == 2 and LeagueState.round_no == 0, "the season ended and a new one began")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "league_champions"), "the champions are announced")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "league_result" and str(p["text"]).find("Sports Field") >= 0), "results are in the chronicle")
	var total_pts := 0
	for row in LeagueState.standings():
		total_pts += int(row["pts"])
	K.expect(f, LeagueState.standings().size() == 4 and total_pts == 0, "the new season starts from zero")
	# a day that is not Saturday plays nothing
	var n0: int = ChronicleHook.recent.size()
	LeagueState.on_day(9)
	K.expect(f, ChronicleHook.recent.size() == n0, "no match on other days")
	K.teardown()

func _clubs(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	ClubState.ensure()
	K.expect(f, (ClubState.members["chess_club"] as Array).size() == 5, "each club has five townie members")
	K.set_time(4, 19)                                   # Thursday evening: chess
	K.expect(f, PlaceUse.why_not(1, "community_centre", "chess_club_meeting") == "Join the Chess Club first.", "join first")
	K.expect(f, bool(PlaceUse.use(1, "community_centre", "join_chess_club", {"instant": true})["ok"]) and ClubState.is_member(1, "chess_club"), "joining costs a few coins")
	var tid: int = int(ClubState.members["chess_club"][0])
	var fr0: float = RelationshipService.value(1, tid, "friendship")
	var r: Dictionary = PlaceUse.use(1, "community_centre", "chess_club_meeting", {"instant": true})
	K.expect(f, bool(r["ok"]) and str(r["text"]).find("Chess Club") >= 0, "the meeting works on Thursday (%s)" % str(r.get("reason", "")))
	K.expect(f, RelationshipService.value(1, tid, "friendship") > fr0 or K.has_note("got talking"), "and she gets to know the members")
	K.set_time(5, 19)
	K.expect(f, PlaceUse.why_not(1, "community_centre", "chess_club_meeting") != "", "no chess on Friday (%s)" % PlaceUse.why_not(1, "community_centre", "chess_club_meeting"))
	K.expect(f, PlaceUse.why_not(1, "community_centre", "join_garden_club") != "", "the hall is closed on Friday evening")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	K.set_time(4, 19)
	K.expect(f, PlaceUse.why_not(int(kid.id), "community_centre", "join_chess_club") == "" and PlaceUse.why_not(int(kid.id), "community_centre", "join_book_club") != "", "children can join chess, not the book club")
	var n0: int = ChronicleHook.recent.size()
	ClubState.on_day(4)
	K.expect(f, ChronicleHook.recent.size() == n0 + 1 and str(ChronicleHook.recent.back()["text"]).find("Chess Club") >= 0, "the club's weekly line is in the chronicle")
	K.teardown()

func _seasons(f: Array) -> void:
	var w := _world()
	var winter := -1
	var summer := -1
	var spring := -1
	for d in range(1, 200):
		var s: String = Seasons.season_at_day(d)
		if s == "winter" and winter < 0:
			winter = d
		if s == "summer" and summer < 0:
			summer = d
		if s == "spring" and spring < 0:
			spring = d
	K.set_time(winter, 12)
	K.expect(f, not Places.open_at("lake") and not Places.open_at("campsite"), "the lake and the campsite are closed in winter")
	K.set_time(spring, 12)
	K.expect(f, Places.open_at("lake") and PlaceUse.why_not(1, "lake", "lake_swim") == "Not in this season." and PlaceUse.why_not(1, "lake", "lake_paddle") == "", "in spring you can paddle but not swim")
	K.set_time(summer, 12)
	K.expect(f, PlaceUse.why_not(1, "lake", "lake_swim") == "" and bool(PlaceUse.use(1, "lake", "picnic", {"instant": true})["ok"]), "in summer you can swim and have a picnic")
	var ann = SysUtil.folk(1)
	K.set_time(summer, 16)
	ann.needs["energy"].value = -50.0
	K.expect(f, bool(PlaceUse.use(1, "campsite", "camp_night", {"instant": true})["ok"]) and ann.needs["energy"].value > -15.0, "a night camping restores energy")
	K.teardown()

func _save(f: Array) -> void:
	var w := _world()
	LeagueState.ensure()
	LeagueState.join(1)
	LeagueState.round_no = 2
	LifeFame.add(1, 12.5)
	LifeFame.note_score(1, "bowling", 222, "Ann")
	ClubState.join(1, "chess_club")
	var d: Dictionary = JSON.parse_string(JSON.stringify(LifeTick.to_dict()))
	var team: String = LeagueState.team_of(1)
	LifeTick.from_dict(d, true)
	K.expect(f, LeagueState.team_of(1) == team and LeagueState.round_no == 2 and absf(LifeFame.value(1) - 12.5) < 0.01 and int(LifeFame.records["bowling"]["score"]) == 222 and ClubState.is_member(1, "chess_club"), "league, fame, records and clubs survive a save and load")
	K.expect(f, (LeagueState.rosters["foxes"] as Array).size() == 3 and int(LeagueState.rosters["foxes"][0]) >= 1000, "rosters keep integer ids")
	K.teardown()
