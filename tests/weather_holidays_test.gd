extends RefCounted
## Holidays: right days, buffs on/off, notifications, gift interaction, decor bonus, party bonus, injected whims.

const W = preload("res://tests/weather_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_calendar(f)
	_buffs(f)
	_gift_decor_party(f)
	_content(f)
	return f

func _calendar(f: Array) -> void:
	W.setup()
	# year 1: bloom(4) midsummer(11) firefly(14) harvest(19) hollow(21) lights(24) gift(28); new year only from year 2 (day 29)
	var table := {4: "spring_bloom", 11: "midsummer", 14: "firefly_night", 19: "harvest_feast", 21: "hollow_eve", 24: "winter_lights", 28: "gift_day"}
	var found: int = 0
	for day in range(1, 57):
		var h: Dictionary = Holidays.today(day)
		var id: String = str(h.get("id", ""))
		var want: String = str(table.get(day, "")) if day <= 28 else ("new_year" if day == 29 else str(table.get(day - 28, "")))
		W.expect(f, id == want, "day %d expected holiday '%s', got '%s'" % [day, want, id])
		if id != "":
			found += 1
	W.expect(f, found == 7 + 8, "two years hold 15 holiday days, found %d" % found)
	W.expect(f, Holidays.all().size() == 8, "eight holidays defined")
	W.expect(f, Holidays.holiday_day("midsummer", 1) == 11 and Holidays.holiday_day("gift_day", 2) == 56, "holiday_day lookup")
	var nx: Dictionary = Holidays.next_after(5)
	W.expect(f, str(nx.get("id", "")) == "midsummer" and int(nx["day"]) == 11, "next holiday after day 5 is midsummer on 11")
	# a different season length moves holidays with the season
	SimEnv.clock().total_minutes = W.at(1, 8)
	Seasons.set_length(10)
	W.expect(f, str(Holidays.today(10 + 4).get("id", "")) == "midsummer", "midsummer is day 4 of summer whatever the length")
	W.expect(f, str(Holidays.today(40).get("id", "")) == "gift_day", "gift day is the last day of winter")
	W.teardown()

func _buffs(f: Array) -> void:
	var w: StubWorld = W.setup()
	var a: Folk = K.make_folk(w, "Ann")
	SimEnv.clock().total_minutes = W.at(3, 23, 58)
	W.expect(f, not a.has_buff("holiday_today"), "day 3 is no holiday")
	W.run_min(5)                                        # into day 4 = Bloom Festival
	W.expect(f, Holidays.active_id() == "spring_bloom", "Bloom Festival is active on day 4")
	W.expect(f, a.has_buff("festive_bloom") and a.has_buff("holiday_today"), "folk get the holiday buffs")
	W.expect(f, K.has_note("Bloom Festival"), "holiday notification sent")
	W.expect(f, K.count_events("holiday_started") == 1, "holiday_started event")
	var late: Folk = K.make_folk(w, "Late")
	Holidays.sync_folk(late)
	W.expect(f, late.has_buff("festive_bloom"), "folk arriving mid-holiday get the buff too")
	SimEnv.clock().total_minutes = W.at(4, 23, 58)
	W.run_min(5)
	W.expect(f, not a.has_buff("festive_bloom") and not a.has_buff("holiday_today"), "buffs removed when the holiday ends")
	W.expect(f, K.count_events("holiday_ended") == 1, "holiday_ended event")
	# eve notice
	SimEnv.clock().total_minutes = W.at(9, 23, 58)
	W.run_min(5)
	W.expect(f, K.has_note("Tomorrow"), "the day before a holiday we get a heads-up")
	W.teardown()

func _gift_decor_party(f: Array) -> void:
	var w: StubWorld = W.setup()
	var a: Folk = K.make_folk(w, "Ann", [], 1, Vector2i(12, 12))
	var b: Folk = K.make_folk(w, "Bo", [], 1, Vector2i(13, 12))
	SimEnv.clock().total_minutes = W.at(27, 8)
	var gift := Interaction.create("give_holiday_gift", a, b.id)
	gift.target_folk = b
	W.expect(f, not gift.can_run(a, null), "no gift giving on an ordinary day")
	SimEnv.clock().total_minutes = W.at(27, 23, 58)
	W.run_min(5)                                         # day 28 = Gift Day
	W.expect(f, str(Holidays.today().get("id", "")) == "gift_day", "day 28 is Gift Day")
	gift = Interaction.create("give_holiday_gift", a, b.id)
	gift.target_folk = b
	W.expect(f, gift.can_run(a, null), "gift giving unlocked on a holiday")
	Loot.apply(gift.def["on_finish"], {"folk": a, "object": null, "target": b})
	W.expect(f, b.has_buff("holiday_gifted") and b.get_rel(a.id, "friendship") > 0.0, "a gift cheers the receiver")
	# decor bonus: plants / lamps / fireplaces nearby
	W.expect(f, not a.has_buff("festive_home"), "bare room gets no decor bonus yet")
	w.add_object("plant", Vector2i(11, 12))
	w.add_object("lamp", Vector2i(12, 11))
	W.expect(f, Holidays.decor_count(a) >= 2, "decor count sees plant + lamp")
	W.run_min(61)
	W.expect(f, a.has_buff("festive_home"), "decorated home gives festive_home on a holiday")
	# party bonus
	var sit: Dictionary = {"kind": "party", "state": "mingle", "score": 0.0}
	var visit: Dictionary = {"kind": "visit", "state": "mingle", "score": 0.0}
	var keep: Array = Story.situations.duplicate()
	Story.situations.append(sit)
	Story.situations.append(visit)
	W.expect(f, Holidays.party_bonus() > 0.0, "party bonus on a holiday")
	Holidays.on_hour()
	Holidays.on_hour()
	W.expect(f, float(sit["score"]) >= 2.0 * Holidays.party_bonus() - 0.001, "party score gets the holiday bonus each hour (%f)" % float(sit["score"]))
	W.expect(f, float(visit["score"]) == 0.0, "ordinary visits get no bonus")
	Story.situations = keep
	W.teardown()

func _content(f: Array) -> void:
	W.setup()
	var whims: Dictionary = SysUtil.table("goals").get("whims", {})
	for id in Holidays.all():
		W.expect(f, whims.has("hol_" + str(id)), "whim injected for holiday " + str(id))
	W.expect(f, whims.has("wx_dance_in_rain") and whims.has("wx_warm_up"), "weather whims injected")
	var inter: Dictionary = SimEnv.data().interactions()
	for iid in ["sunbathe", "rain_dance", "build_snowfolk", "give_holiday_gift"]:
		W.expect(f, inter.has(iid), "interaction injected: " + iid)
	for bid in ["cold", "hot", "soaked", "sunburn", "fresh_air", "cozy", "wx_wet", "holiday_today", "festive_home"]:
		W.expect(f, not SimEnv.data().buff_def(bid).is_empty(), "buff exists: " + bid)
	W.expect(f, (SimEnv.data().object_def("garden_plot").get("interactions", []) as Array).has("sunbathe"), "garden plot lists sunbathe")
	# every outdoor interaction is blocked in severe weather
	var blocked: bool = true
	for iid2 in inter:
		var d: Dictionary = inter[iid2]
		if (d.get("tags", []) as Array).has("outdoor"):
			var has_test: bool = false
			for t in d.get("tests", []):
				if t is Dictionary and (t as Dictionary).get("lacks_buff", "") == "wx_severe":
					has_test = true
			if not has_test:
				blocked = false
	W.expect(f, blocked, "all outdoor interactions have the severe weather test")
	# idempotent
	var n: int = inter.size()
	WeatherContent.install()
	WeatherContent.install()
	W.expect(f, SimEnv.data().interactions().size() == n, "install is idempotent")
	W.teardown()
