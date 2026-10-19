extends RefCounted
## Storyteller deck, twists with choices, ripples, foreshadowing, chains, arcs, cycles, the log and the quiet-gap guard (task 29). Short runs; the rates are in storyteller_longrun_test.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_every_card(f)
	_choices(f)
	_switches(f)
	_ripple_and_chains(f)
	_foreshadow(f)
	_arcs(f)
	_cycles(f)
	_quiet_guard(f)
	_determinism(f)
	return f

func _town(seed_value: int = 2929) -> StubWorld:
	var w := K.setup(seed_value, true)
	K.make_folk(w, "Alma Reed", ["neat"], 1)
	K.make_folk(w, "Bo Reed", [], 1)
	K.mgr.new_game([1])
	Players.set_player(Players.LOCAL, 1, "Reed")
	JusticePlayer.ask_fn = Callable()
	return w

func _every_card(f: Array) -> void:
	_town()
	var played := 0
	var scopes: Dictionary = {}
	var names: Array = StorytellerDeck.cards().keys()
	names.sort()
	var zone: String = CityState.zone_of_household(1)
	for cid in names:
		var c: Dictionary = StorytellerDeck.cards()[cid]
		var key: String = {"home": "h1", "district": "d" + zone, "town": Storyteller.KEY_TOWN}[str(c["scope"])]
		K.set_time(5 + played, 9)
		if not StorytellerDeck.eligible(cid, c, key):
			continue
		var before: int = StorytellerLog.entries.size()
		StorytellerPlay.card(key, cid, {"from_sign": true})
		played += 1
		scopes[str(c["scope"])] = true
		K.expect(f, StorytellerLog.entries.size() > before or c.has("arc") or c.has("cycle"), "card %s leaves a log line" % cid)
	K.expect(f, played >= 30, "most of the deck can be played in a plain town (%d of %d)" % [played, names.size()])
	K.expect(f, scopes.size() == 3, "household, district and town cards all played")
	for line in Storyteller.log_lines(200):
		K.expect(f, str(line).find("{") < 0 and str(line).find("null") < 0, "plain words in the log: %s" % line)
	var panel := StorytellerLogPanel.new()
	panel._ready()
	K.expect(f, panel._body.text.length() > 20 and panel._body.text.find("Day") >= 0, "the log panel shows the lines")
	panel.free()
	K.teardown()

func _choices(f: Array) -> void:
	_town()
	var before: int = Economy.balance(1)
	JusticePlayer.auto = "keep"
	StorytellerPlay.card("h1", "lost_wallet", {"from_sign": true})
	K.expect(f, Economy.balance(1) > before and Storyteller.choices.is_empty(), "keeping the wallet pays and the choice is closed")
	JusticePlayer.auto = "return"
	var before2: int = Economy.balance(1)
	StorytellerPlay.card("h1", "lost_wallet", {"from_sign": true})
	K.expect(f, Economy.balance(1) > before2, "returning it earns a reward")
	# an unanswered choice (a UI that never answers) takes its default after the allowed days
	JusticePlayer.auto = ""
	JusticePlayer.ask_fn = func(_pid, _t, _x, _o, _cb, _d): pass
	StorytellerPlay.card("h1", "neighbour_favour", {"from_sign": true})
	K.expect(f, Storyteller.choices.size() == 1, "an open choice waits for the player")
	var id: int = int(Storyteller.choices[0]["id"])
	var bad: Dictionary = Commands.run({"player_id": 2, "action": "storyteller", "args": {"action": "choose", "id": id, "option": "help"}})
	K.expect(f, not bool(bad["ok"]), "another player cannot answer it")
	K.set_time(40, 9)
	Storyteller.on_day(40)
	K.expect(f, not Storyteller.choices.any(func(r): return int(r["id"]) == id), "an unanswered choice takes its default")
	JusticePlayer.ask_fn = Callable()
	JusticePlayer.auto = ""
	K.teardown()

func _switches(f: Array) -> void:
	_town()
	PregnancyLoss.set_mature(false)
	var c: Dictionary = StorytellerDeck.card("old_flame")
	K.expect(f, not StorytellerDeck.eligible("old_flame", c, "h1"), "Mature life events off removes the old flame")
	PregnancyLoss.set_mature(true)
	K.expect(f, StorytellerDeck.eligible("old_flame", c, "h1"), "and on brings it back")
	Storyteller.set_cat("social", false)
	var seen: Dictionary = {}
	for i in 60:
		var cid: String = StorytellerDeck.pick("h1", ["small", "medium"][i % 2])
		if cid != "":
			seen[str(StorytellerDeck.card(cid)["cat"])] = true
	K.expect(f, not seen.has("social") and not seen.is_empty(), "a switched-off category is never drawn")
	for cat in StorytellerCmd.CATS:
		Storyteller.set_cat(cat, false)
	K.expect(f, StorytellerDeck.pick("h1", "small") == "" and StorytellerDeck.pick("d" + CityState.zone_of_household(1), "medium") == "", "with every category off nothing is drawn")
	K.teardown()

func _ripple_and_chains(f: Array) -> void:
	_town()
	var zone: String = CityState.zone_of_household(1)
	var other_zone: String = ""
	for z in CityState.zone_ids():
		if StorytellerDistrict.distance(str(z), zone) > 0:
			other_zone = str(z)
	K.set_time(6, 9)
	var n0: int = Storyteller.ripple_count(1)
	StorytellerPlay.card("d" + zone, "protest", {"from_sign": true})
	K.expect(f, Storyteller.ripple_count(1) == n0 + 1 and K.has_note("protest"), "an event in the household's district reaches it (toast, count)")
	StorytellerPlay.card("d" + other_zone, "protest", {"from_sign": true})
	K.expect(f, Storyteller.ripple_count(1) == n0 + 1, "the same event across town is only news")
	K.expect(f, int(Storyteller.ripples[1]["town"]) >= 2, "the news reaches the household either way")
	var tid: int = int(Story.alive_townies()[0]["id"])
	Story.townies[tid]["lot"] = 2
	RelationshipService.add_both(1, tid, "friendship", 40.0)
	var ctx: Dictionary = {"key": "d" + zone, "hid": 0, "folk_id": -1, "other": -1, "lot": 2, "zone": zone, "who": tid, "stat": true}
	StorytellerRipple.spread("crash_avenue", StorytellerDeck.card("crash_avenue"), ctx, {})
	K.expect(f, int(Storyteller.ripples[1].get("know", 0)) >= 1, "a friend's trouble reaches the household")
	K.expect(f, Storyteller.queue.any(func(r): return r["kind"] == "thanks"), "and a thank-you visit is planned")
	Storyteller.queue.clear()
	var hits := 0
	for i in 40:
		StorytellerQueue.chain_from("street_burglary", {"zone": zone, "lot": 2, "who": tid})
		hits = Storyteller.queue.size()
	K.expect(f, hits > 3 and hits < 40, "a burglary sometimes starts a neighbourhood watch (%d of 40)" % hits)
	K.set_time(60, 9)
	StorytellerQueue.on_day(60)
	K.expect(f, int(Storyteller.stats.get("chains", 0)) >= 1, "chain events play after their delay")
	var w0: float = StorytellerChaos.heat_mult(zone, ["rumbling"])
	StorytellerChaos.add_heat(zone, "rumbling", 2.0)
	K.expect(f, StorytellerChaos.heat_mult(zone, ["rumbling"]) > w0, "heat makes related events likelier")
	K.teardown()

func _foreshadow(f: Array) -> void:
	_town()
	Storyteller.set_personality("custom", {"frequency": 0.5, "severity": 0.0, "balance": 0.5, "mercy": 0.5})     # foreshadow chance 1.0
	K.set_time(8, 9)
	var r: Dictionary = StorytellerPlay.card("h1", "layoff_card", {})
	var signs: Array = StorytellerLog.entries.filter(func(e): return e["kind"] == "sign")
	K.expect(f, bool(r.get("scheduled", false)) and signs.size() == 1, "a big bad event comes with a sign first")
	K.expect(f, str(signs[0]["text"]).to_lower().find("layoff") < 0 and str(signs[0]["text"]).to_lower().find("laid") < 0, "the sign does not give it away")
	K.expect(f, Storyteller.queue.size() == 1 and StorytellerLog.entries.filter(func(e): return e["kind"] == "event").is_empty(), "the event itself is not in the log yet")
	for d in range(9, 13):
		K.set_time(d, 9)
		StorytellerQueue.on_day(d)
	K.expect(f, Storyteller.queue.is_empty(), "the card played within a few days")
	K.teardown()

func _arcs(f: Array) -> void:
	_town()
	K.expect(f, StorytellerArcs.can_start("feud", "h1"), "a household can start a feud")
	StorytellerPlay.card("h1", "arc_feud", {})
	K.expect(f, StorytellerArcs.has_arc("h1") and not StorytellerArcs.can_start("admirer", "h1"), "at most one big arc per household")
	K.expect(f, StorytellerArcs.can_start("town_crisis", Storyteller.KEY_TOWN), "the town has its own slot")
	StorytellerPlay.card(Storyteller.KEY_TOWN, "arc_town_crisis", {})
	K.expect(f, StorytellerArcs.has_arc(Storyteller.KEY_TOWN) and not StorytellerArcs.can_start("business", Storyteller.KEY_TOWN), "and only one town arc")
	JusticePlayer.auto = "talk"
	for d in range(10, 60):
		K.set_time(d, 9)
		StorytellerArcs.on_day(d)
		StorytellerQueue.on_day(d)
	K.expect(f, StorytellerArcs.finished >= 2 and not StorytellerArcs.has_arc("h1"), "arcs play out to a resolution (%d finished)" % StorytellerArcs.finished)
	var arc_lines: Array = StorytellerLog.entries.filter(func(e): return e["kind"] == "arc")
	K.expect(f, arc_lines.size() >= 6, "setup, escalation, climax and resolution are logged (%d lines)" % arc_lines.size())
	JusticePlayer.auto = ""
	StorytellerPlay.card("h1", "arc_feud", {})
	var mid: Dictionary = JSON.parse_string(JSON.stringify(StorytellerArcs.to_dict()))
	StorytellerArcs.from_dict(mid)
	K.expect(f, StorytellerArcs.has_arc("h1"), "a running arc survives save and load")
	Storyteller.set_cat("arcs", false)
	StorytellerArcs.active.clear()
	K.expect(f, not StorytellerArcs.can_start("feud", "h1"), "arcs can be switched off")
	K.teardown()

func _cycles(f: Array) -> void:
	_town()
	K.set_time(5, 9)
	var base: float = Storyteller.incident_mult("burglary")
	StorytellerPlay.card(Storyteller.KEY_TOWN, "cycle_crime_wave", {})
	K.expect(f, StorytellerCycles.active_id() == "crime_wave" and Storyteller.incident_mult("burglary") > base, "a crime wave raises burglary odds")
	K.expect(f, Storyteller.incident_mult("murder") <= float(Storyteller.cfg()["hard_cap"]), "but never murder beyond the cap")
	K.expect(f, not StorytellerCycles.can_start("flu_season"), "one era at a time")
	K.expect(f, K.has_note("crime is up"), "the era is announced")
	K.set_time(40, 9)
	Storyteller.on_day(40)
	K.expect(f, StorytellerCycles.active_id() == "" and is_equal_approx(Storyteller.incident_mult("burglary"), base), "and ends")
	K.set_time(48, 9)
	StorytellerPlay.card(Storyteller.KEY_TOWN, "cycle_heat_wave", {})
	K.expect(f, Weather.forced == "heatwave", "a heat wave holds the weather")
	K.set_time(70, 9)
	Storyteller.on_day(70)
	K.expect(f, Weather.forced == "", "and lets it go")
	K.teardown()

func _quiet_guard(f: Array) -> void:
	for pid in ["calm", "classic", "chaotic"]:
		_town(77)
		Storyteller.set_personality(pid)
		var maxq: int = int(Storyteller.param("max_quiet_days", 5))
		var worst := 0
		for d in range(2, 90):
			K.set_time(d, 9)
			Storyteller.on_day(d)
			worst = maxi(worst, d - int(StorytellerBudget.entry("h1")["last_notable"]))
		K.expect(f, worst <= maxq, "%s: the household never waits more than %d days for something notable (worst %d)" % [pid, maxq, worst])
		K.teardown()

func _determinism(f: Array) -> void:
	var runs: Array = []
	for i in 2:
		SimSeed.apply(555)
		_town(555)
		for d in range(2, 40):
			K.set_time(d, 9)
			Storyteller.on_day(d)
		runs.append(JSON.stringify(Storyteller.to_dict()))
		K.teardown()
	K.expect(f, runs[0] == runs[1] and runs[0].length() > 200, "same seed, same story")
