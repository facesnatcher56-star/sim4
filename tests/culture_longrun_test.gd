extends RefCounted
## Task 14 food, nightlife and culture over years of game time (SLOW tier). Measured:
##   league: each team wins about a quarter of the seasons (strength differences are small), a resident who plays every Saturday lifts their team
##   place news: lines per game year across the whole town (a handful a week, not a flood)
##   restaurant specials: every dish of a course is special about equally often
##   places: staffed nearly all the time, closed for a day only now and then

const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	_league(f)
	_news_and_menu(f)
	return f

func _world() -> StubWorld:
	var w := K.setup(1416)
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = 1000000
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	return w

func _seasons(n: int, player_plays: bool) -> Dictionary:
	LeagueState.reset()
	LifeFame.reset()
	LeagueState.ensure()
	var team := ""
	if player_plays:
		team = LeagueState.join(1)
	var d := 7
	var done := 0
	while done < n:
		K.set_time(d - 1, 12)                          # the Saturday before
		if player_plays:
			LeagueState.played[1] = d - 1
		var s0: int = LeagueState.season
		K.set_time(d, 0)
		LeagueState.on_day(d)
		if LeagueState.season != s0:
			done += 1
		d += 7
	return {"team": team}

func _league(f: Array) -> void:
	var w := _world()
	var seasons: int = TestFixture.pick(300, 120)
	# count champions through the game event
	var wins: Dictionary = {}
	SimEnv.events().game_event.connect(func(n, p): if n == "league_season_end": wins[str(p["champion"])] = int(wins.get(str(p["champion"]), 0)) + 1)
	_seasons(seasons, false)
	var share_max := 0.0
	var share_min := 1.0
	for t in LeagueState.teams():
		var share: float = float(wins.get(str(t["id"]), 0)) / float(seasons)
		share_max = maxf(share_max, share)
		share_min = minf(share_min, share)
	K.expect(f, share_max < 0.40 and share_min > 0.12, "every team wins some seasons: %.2f to %.2f" % [share_min, share_max])
	# a resident who plays every week raises their team's share
	wins.clear()
	var info: Dictionary = _seasons(seasons, true)
	var mine: float = float(wins.get(str(info["team"]), 0)) / float(seasons)
	var base_share: float = 0.25
	K.expect(f, mine > base_share, "a player on the team lifts it above a quarter (%.2f)" % mine)
	print("culture_longrun: league shares %.2f..%.2f without a player, %.2f with one playing every week" % [share_min, share_max, mine])
	K.teardown()

func _news_and_menu(f: Array) -> void:
	var w := _world()
	var years: int = TestFixture.pick(8, 3)
	var days: int = years * YEAR
	var news := 0
	var specials: Dictionary = {}
	var closed := 0
	var unstaffed := 0
	for d in range(2, days + 2):
		K.set_time(d, 6)
		var n0: int = ChronicleHook.recent.size()
		var before: Array = ChronicleHook.recent.duplicate()
		LifeTick.on_day(d)
		for p in ChronicleHook.recent:
			if not before.has(p) and str(p["kind"]) == "place_news":
				news += 1
		var sp: Dictionary = FoodMenu.specials("restaurant", d)
		for c in sp:
			var key: String = "%s/%s" % [c, sp[c]]
			specials[key] = int(specials.get(key, 0)) + 1
		for pid in Places.all():
			if PlaceStaff.closed_today(pid):
				closed += 1
			if not PlaceStaff.staffed(pid):
				unstaffed += 1
	var per_year: float = float(news) / float(years)
	K.expect(f, per_year > 12.0 and per_year < 80.0, "place news per game year across the town is a few a week (%.1f)" % per_year)
	var mains: Array = []
	for k in specials:
		if str(k).begins_with("main/"):
			mains.append(int(specials[k]))
	K.expect(f, mains.size() == 4, "all four mains get their turn as the special (%d)" % mains.size())
	for m in mains:
		K.expect(f, float(m) / float(days) > 0.12 and float(m) / float(days) < 0.4, "each main is the special about a quarter of the days (%.2f)" % (float(m) / float(days)))
	var place_days: int = Places.all().size() * days
	K.expect(f, float(unstaffed) / float(place_days) < 0.02, "places are almost always staffed (%.4f)" % (float(unstaffed) / float(place_days)))
	K.expect(f, float(closed) / float(place_days) > 0.0005 and float(closed) / float(place_days) < 0.03, "and close for a day only now and then (%.4f)" % (float(closed) / float(place_days)))
	print("culture_longrun: %d places, news %.1f per game year, closed %.4f unstaffed %.4f of place-days" % [Places.all().size(), per_year, float(closed) / float(place_days), float(unstaffed) / float(place_days)])
	K.teardown()
