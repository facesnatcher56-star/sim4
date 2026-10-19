extends RefCounted
## Story pacing: drama decays, calm raises / drama lowers the odds of whitelisted story kinds only (never deaths, crimes, disasters),
## long-running threads (cheating aftermath, an ex at the door, a friend who comes to say thanks), folk taking job offers on their own,
## and forecasts worded by real chance.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_levels(f)
	_whitelist(f)
	_threads(f)
	_opportunity(f)
	_forecast(f)
	_weather_seed(f)
	_jobless_find_work(f)
	_milestones(f)
	return f

func _levels(f: Array) -> void:
	K.setup()
	K.set_time(10, 8)
	var calm: float = StoryPacing.mult("flirt", 1)
	K.expect(f, calm > 1.2 and calm <= 1.0 + float(StoryPacing.cfg()["max_boost"]) + 0.001, "a calm household gets more story chances (x%.2f)" % calm)
	StoryPacing.add_beat(1, 30.0)
	K.expect(f, StoryPacing.mult("flirt", 1) < 1.0 and StoryPacing.mult("flirt", 1) >= 1.0 - float(StoryPacing.cfg()["max_cut"]) - 0.001, "too much drama eases off (x%.2f)" % StoryPacing.mult("flirt", 1))
	var spike: float = StoryPacing.drama(1)
	K.set_time(14, 8)
	K.expect(f, StoryPacing.drama(1) < spike * 0.3, "drama decays (%.1f -> %.1f)" % [spike, StoryPacing.drama(1)])
	K.set_time(20, 8)
	K.expect(f, StoryPacing.mult("flirt", 1) > 1.0, "after the spike calm returns and the odds with it")
	K.expect(f, StoryPacing.beat_count(1, 7) == 0 and StoryPacing.beat_count(1, 30) == 1, "weekly beat counts")
	K.teardown()

func _whitelist(f: Array) -> void:
	var w := K.setup()
	K.set_time(10, 8)
	var h := K.make_folk(w, "Hera", [], 1)
	var subj = IncidentSubject.of_folk(h)
	for bad in ["murder", "kitchen_fire", "street_robbery", "tornado", "death", "burglary", "assault", "catch_flu"]:
		K.expect(f, is_equal_approx(StoryPacing.incident_mult(bad, subj), 1.0), "%s is never changed by pacing" % bad)
	K.expect(f, StoryPacing.incident_mult("minor_fall", subj) > 1.0, "a small mishap becomes likelier in a calm week")
	K.expect(f, is_equal_approx(StoryPacing.mult("death", 1), 1.0) and is_equal_approx(StoryPacing.mult("crime", 1), 1.0), "no multiplier for deaths and crimes")
	for iid in (StoryPacing.cfg()["kinds"]["mishap"]["incidents"] as Array):
		var d: Dictionary = IncidentDefs.get_def(str(iid))
		var txt: String = JSON.stringify(d)
		K.expect(f, txt.find("\"kill\"") < 0 and txt.find("death") < 0, "whitelisted mishap %s cannot kill" % iid)
	K.teardown()

func _threads(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Wren", [], 1)
	var b := K.make_folk(w, "Mira", [], 1)
	K.set_time(10, 12)
	SysUtil.game_event("breakup", {"folk_id": a.id, "target_id": b.id, "cause": "cheating", "severity": 1.2})
	K.expect(f, StoryThreads.pending.size() == 1, "a cheating breakup starts a thread")
	K.expect(f, StoryPacing.beat_count(1, 1) >= 1, "the breakup is a story beat")
	for d in range(10, 15):
		K.set_time(d, 12)
		StoryThreads.on_day(d)
	K.expect(f, StoryThreads.pending.is_empty(), "the thread played out")
	K.expect(f, K.has_note("forgive") or K.has_note("got back at"), "revenge or forgiveness shows up")
	# an ex who is a townie turns up at the door
	var tid: int = int(Story.add_townie(60.0, "Rufus Hale")["id"])
	StoryThreads.reset()
	var before: int = Story.situations.size()
	SysUtil.game_event("breakup", {"folk_id": a.id, "target_id": tid, "cause": "breakup", "severity": 1.0})
	K.expect(f, StoryThreads.pending.size() == 1, "an ex who lives in town starts a thread")
	for d in range(15, 30):
		K.set_time(d, 12)
		StoryThreads.on_day(d)
	K.expect(f, Story.situations.size() > before and K.has_note("Rufus Hale"), "the ex turns up (visit scheduled)")
	# a townie who fell ill, known to the household, comes to say thanks
	var sid: int = int(Story.add_townie(60.0, "Gus Wick")["id"])
	RelationshipService.add_both(a.id, sid, "friendship", 30.0)
	StoryThreads.reset()
	ChronicleHook.note("townie_stomach_bug", "Gus Wick had a stomach bug.", [sid], "town:1", 1, false)
	K.expect(f, StoryThreads.pending.size() == 1, "a known townie's illness starts a thank-you thread")
	K.teardown()

func _opportunity(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Pia", [], 1)
	var b := K.make_folk(w, "Quill", [], 1, Vector2i(14, 12))
	K.mgr.new_game([1])
	WorldIface.coins[1] = 20          # short of money = looking for work
	Careers.confirm_offers = true
	Careers.make_offer(a, "coder", 1)
	Careers.make_offer(b, "coder", 1)
	K.expect(f, OpportunityTaker.fit_chance(a, "coder") > 0.1 and OpportunityTaker.fit_chance(a, "coder") <= 0.85, "fit chance in range")
	b.queue.append(null)       # the player is directing Quill: never takes an offer on their own
	for i in 40:
		OpportunityTaker.on_day(10 + i)
		if Careers.jobs.has(int(a.id)):
			break
	b.queue.clear()
	K.expect(f, Careers.jobs.has(int(a.id)), "a jobless folk takes a fitting offer on their own")
	K.expect(f, K.has_note("Pia took the"), "the household is told which job")
	K.expect(f, not Careers.jobs.has(int(b.id)), "no offer is taken while the player is giving orders")
	Careers.quit_job(a)
	K.expect(f, not Careers.jobs.has(int(a.id)), "the household can quit the job")
	Careers.confirm_offers = false
	K.teardown()

func _forecast(f: Array) -> void:
	K.setup()
	DisasterState.reset()
	Incidents.set_level("rare")
	var tornado_summer: float = DisasterOdds.day_chance("tornado", "thunderstorm", "summer")
	var hail_summer: float = DisasterOdds.day_chance("hailstorm", "thunderstorm", "summer")
	K.expect(f, DisasterOdds.day_chance("tornado", "sunny", "summer") == 0.0 and DisasterOdds.day_chance("tornado", "thunderstorm", "winter") == 0.0, "no tornado chance without storms in season")
	K.expect(f, tornado_summer > 0.0 and tornado_summer < 0.1 and hail_summer > tornado_summer, "tornado %.3f is rarer than hail %.3f" % [tornado_summer, hail_summer])
	var ws: Array = DisasterOdds.watches_for("thunderstorm", "summer")
	K.expect(f, ws.size() == 1 and str(ws[0]["text"]).find("chance of") >= 0, "storm watch is worded by likelihood: %s" % str(ws))
	K.expect(f, DisasterOdds.words(0.03) == "a slight chance of" and DisasterOdds.words(0.5) == "likely:", "likelihood words")
	K.expect(f, DisasterOdds.watches_for("sunny", "summer").is_empty() and DisasterOdds.watches_for("rain", "winter").is_empty(), "no watch on ordinary days")
	DisasterState.rain_days = 3
	K.expect(f, DisasterOdds.day_chance("flood", "rain", "spring") > 0.0, "flood chance appears after days of rain")
	DisasterState.rain_days = 0
	K.expect(f, DisasterOdds.day_chance("flood", "rain", "spring") == 0.0, "but not without them")
	K.teardown()
	_forecast_matches_incidents(f)

## The forecast chance equals what the incident machinery would really roll over that day (all weather / season / streak combos),
## so a "likely" warning is followed by the event at least as often as it claims.
func _forecast_matches_incidents(f: Array) -> void:
	var w := K.setup()
	DisasterState.reset()
	var worst := 0.0
	var checked := 0
	var likely_chances: Array = []
	for season_day in [3, 10, 17, 24]:             # one day in each of the four seasons
		for wx in ["sunny", "rain", "thunderstorm", "snow", "windy", "heatwave"]:
			for streak in [0, 3]:
				DisasterState.rain_days = streak
				DisasterState.dry_days = streak
				K.set_time(season_day, 12)
				Weather.force(wx)
				var season: String = Seasons.season_at_day(season_day)
				for iid in ["tornado", "hailstorm", "flood", "blizzard", "wildfire"]:
					var def: Dictionary = IncidentDefs.get_def(iid)
					var dummy = IncidentSubject.of_town_lot(0)
					var p_hour: float = 0.0
					if IncidentCond.check(def.get("conditions", []), dummy):
						p_hour = IncidentRisk.rate_to_chance(IncidentRisk.effective_rate(def, dummy), str(def["check"]))
					var real: float = 1.0 - pow(1.0 - p_hour, 24.0)
					var claimed: float = DisasterOdds.day_chance(iid, wx, season)
					worst = maxf(worst, absf(real - claimed))
					checked += 1
					if claimed >= 0.4:
						likely_chances.append(claimed)
	Weather.unforce()
	K.expect(f, checked >= 200 and worst < 0.0005, "forecast chance equals the real daily chance in %d cases (worst gap %.5f)" % [checked, worst])
	K.expect(f, likely_chances.is_empty(), "nothing is called likely unless it really is (>= 40%%): %d cases" % likely_chances.size())
	K.teardown()


## Weather follows the game's world seed: different seeds, different first month; the same seed repeats exactly.
func _weather_seed(f: Array) -> void:
	K.setup()
	var runs: Dictionary = {}
	for sd in [11, 22, 11]:
		Neighborhood.world_seed = sd
		Weather.new_game()
		var seq: Array = []
		for day in range(1, 29):
			K.set_time(day, 12)
			seq.append(Weather.current())
		runs[str(sd) + "_" + str(runs.size())] = seq
	var keys: Array = runs.keys()
	K.expect(f, runs[keys[0]] != runs[keys[1]], "two world seeds give different first-month weather")
	K.expect(f, runs[keys[0]] == runs[keys[2]], "the same world seed gives identical weather")
	Neighborhood.world_seed = 0
	K.teardown()

## No job in sight for two jobless adults: over 56 days at least one takes a job on their own (offers come from Careers.on_day).
func _jobless_find_work(f: Array) -> void:
	var w := K.setup(77, true)
	var a := K.make_folk(w, "Una", [], 1)
	var b := K.make_folk(w, "Vik", ["lazy"], 1, Vector2i(14, 12))
	K.mgr.new_game([1])
	WorldIface.coins[1] = 20
	Careers.confirm_offers = true
	for d in range(2, 58):
		K.set_time(d, 6)
		Careers.on_day(d)
		OpportunityTaker.on_day(d)
	K.expect(f, Careers.jobs.has(int(a.id)) or Careers.jobs.has(int(b.id)), "in 56 days at least one jobless adult takes a job")
	Careers.confirm_offers = false
	K.teardown()

## A couple that starts together moves towards engagement and marriage on its own (calm household), and a faded bond can end.
func _milestones(f: Array) -> void:
	var w := K.setup(5, true)
	var a := K.make_folk(w, "Una", [], 1)
	var b := K.make_folk(w, "Vik", [], 1, Vector2i(14, 12))
	K.mgr.new_game([1])
	HouseholdSetup._bond(a.id, b.id)
	RelationshipBits.set_flag(a.id, b.id, "partner", true, false)
	var engaged_day := -1
	var married_day := -1
	for d in range(2, 90):
		K.set_time(d, 6)
		StoryMilestones.on_day(d)
		if engaged_day < 0 and FamilyMarriage.is_engaged(a.id, b.id):
			engaged_day = d
		if married_day < 0 and FamilyTree.spouse_of(a.id) == b.id:
			married_day = d
			break
	K.expect(f, engaged_day > 0, "the couple got engaged (day %d)" % engaged_day)
	K.expect(f, married_day > engaged_day, "and married (day %d)" % married_day)
	K.expect(f, K.has_note("small wedding"), "the wedding is announced")
	K.teardown()
	# a faded bond may end in a breakup, never instantly
	var w2 := K.setup(6, true)
	var c := K.make_folk(w2, "Wil", [], 1)
	var d2 := K.make_folk(w2, "Xia", [], 1, Vector2i(14, 12))
	K.mgr.new_game([1])
	RelationshipBits.set_flag(c.id, d2.id, "partner", true, false)
	RelationshipService.set_value(c.id, d2.id, "romance", 10.0)
	RelationshipService.set_value(d2.id, c.id, "romance", 10.0)
	var ended := false
	for dd in range(2, 120):
		K.set_time(dd, 6)
		StoryMilestones.on_day(dd)
		if not RelationshipBits.has_flag(c.id, d2.id, "partner"):
			ended = true
			break
	K.expect(f, ended, "a faded relationship ends in a breakup")
	K.teardown()
