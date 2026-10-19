extends RefCounted
## Colds, flu and food poisoning: catching (forced), spreading by contact (exposure marker -> risk multiplier), season and hygiene risk,
## immunity, rest and medicine, the doctor, food poisoning from spoiled food, worsening (death only for untreated elders), far townies.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_cold(f)
	_spread(f)
	_risk(f)
	_flu(f)
	_medicine(f)
	_worsens(f)
	_food(f)
	_townies(f)
	_timer(f)
	return f

## Medicine leaves a fractional timer; the rest bonus of a resting patient must not push it below zero: a negative timer is Folk's "no timer",
## and the cold (uncomfortable 2, contagious) would never end. Also: an older save with such a timer heals on the next hourly check.
func _timer(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	Incidents.force("catch_cold", {"folk_id": a.id})
	HealthIllness.cure(a, 0.4)
	for b in a.buffs:
		if str(b["id"]) in ["common_cold", "sick"]:
			b["remaining"] = 0.5
	a.posture = "lie"
	HealthIllness.tick_minute(a, Health.rec_of(a.id))
	a.tick_buffs(1.0)
	K.expect(f, not a.has_buff("common_cold") and not a.has_buff("sick"), "half a minute of cold left while resting: it runs out, the timer never goes negative")
	Health.on_hour()
	K.expect(f, not Health.is_ill(a), "and the illness record is closed")
	var b2 := K.make_folk(w, "Bea", [], 1)
	Incidents.force("catch_cold", {"folk_id": b2.id})
	for bb in b2.buffs:
		if str(bb["id"]) in ["common_cold", "sick"]:
			bb["remaining"] = -0.3
	Health.on_hour()
	K.expect(f, not b2.has_buff("common_cold") and not b2.has_buff("sick") and not Health.is_ill(b2), "a negative illness timer (older save) ends the illness on the hour")
	K.teardown()

func _world() -> StubWorld:
	var w := K.setup()
	SysContent.install_all()
	Incidents.reset()
	Weather.force("sunny")
	K.set_time(6, 9, 0)
	return w

func _cold(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var res: Dictionary = Incidents.force("catch_cold", {"folk_id": a.id})
	K.expect(f, bool(res["ok"]) and a.has_buff("common_cold") and a.has_buff("sick") and Health.is_ill(a), "a cold: buff + unwell marker + record")
	K.expect(f, K.has_note("has caught a cold"), "toast for the player's own people")
	K.expect(f, Health.illness_of(a)["kind"] == "cold", "illness_of says cold")
	K.expect(f, a.decay_mult("energy") > 1.1 and a.decay_mult("hygiene") > 1.1, "needs drain faster with a cold")
	K.expect(f, Mood.compute(a)["mood"] in ["uncomfortable", "sad"], "mood penalty (%s)" % str(Mood.compute(a)["mood"]))
	K.expect(f, Hospital.status_chips(a).any(func(c): return c["text"] == "Cold"), "folk panel chip names the illness")
	# a cold is over after about two days and leaves a few days of immunity
	K.set_time(6, 9, 0)
	a.tick_buffs(48.0 * 60.0 + 5.0)
	Health.on_hour()
	K.expect(f, not a.has_buff("common_cold") and not a.has_buff("sick") and not Health.is_ill(a), "recovered after two days")
	K.expect(f, a.has_buff("immune_cold") and K.has_note("feeling better"), "feeling better, and resistant for a while")
	K.expect(f, Incidents.effective_rate("catch_cold", a) == 0.0, "no cold again while resistant")
	K.teardown()

func _spread(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(14, 12))
	var c := K.make_folk(w, "Cy", [], 2, Vector2i(14, 12))        # another household, but they are about to chat
	var d := K.make_folk(w, "Di", [], 3, Vector2i(60, 60))        # far away, no contact
	var base: float = Incidents.effective_rate("catch_cold", b)
	Incidents.force("catch_cold", {"folk_id": a.id})
	Health.on_hour()
	K.expect(f, b.has_buff("exposed_cold") and not c.has_buff("exposed_cold") and not d.has_buff("exposed_cold"), "housemates are exposed; strangers are not")
	var risen: float = Incidents.effective_rate("catch_cold", b)
	K.expect(f, risen > base * 10.0, "being exposed multiplies the chance (%.2f -> %.2f a year)" % [base, risen])
	K.expect(f, Incidents.effective_rate("catch_cold", d) == base, "a stranger keeps the base rate")
	SysUtil.game_event("social_done", {"folk_id": a.id, "target_id": c.id, "interaction": "chat"})
	Health.on_hour()
	K.expect(f, c.has_buff("exposed_cold") and not d.has_buff("exposed_cold"), "talking to the ill person exposes you too")
	K.expect(f, Incidents.effective_rate("catch_cold", a) == 0.0, "the ill person cannot catch it twice")
	K.teardown()

func _risk(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	K.set_time(2, 9, 0)              # spring
	var spring: float = Incidents.effective_rate("catch_cold", a)
	K.set_time(24, 9, 0)             # winter
	var winter: float = Incidents.effective_rate("catch_cold", a)
	K.set_time(10, 9, 0)             # summer
	var summer: float = Incidents.effective_rate("catch_cold", a)
	K.expect(f, winter > spring * 1.5 and summer < spring, "more often in winter (%.2f), less in summer (%.2f); spring %.2f" % [winter, summer, spring])
	K.set_time(24, 9, 0)
	a.needs["hygiene"].set_value(-50.0)
	K.expect(f, Incidents.effective_rate("catch_cold", a) > winter * 1.3, "low hygiene raises it")
	a.needs["hygiene"].set_value(60.0)
	a.add_buff("bundled_up")
	K.expect(f, Incidents.effective_rate("catch_cold", a) < winter, "warm clothes lower it")
	a.remove_buff("bundled_up")
	Incidents.set_level("off")
	K.expect(f, Incidents.effective_rate("catch_cold", a) == 0.0 and Incidents.effective_rate("catch_flu", a) == 0.0, "Surprises Off: illness dice are off")
	K.teardown()

func _flu(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	Incidents.force("catch_flu", {"folk_id": a.id})
	K.expect(f, a.has_buff("flu") and Health.illness_of(a)["kind"] == "flu", "flu")
	K.expect(f, Health.work_block(a, "coder") != "", "cannot work with the flu")
	K.expect(f, Health.speed_mult(a) < 1.0, "flu slows walking")
	K.expect(f, Health.blocks_activity(a, ["exercise"]) != "", "no exercise with the flu")
	K.expect(f, Health.work_block(K.make_folk(w, "Bo", [], 1), "coder") == "", "healthy people work")
	# a cold is milder: still allowed to work
	var b := K.make_folk(w, "Bo2", [], 1)
	Incidents.force("catch_cold", {"folk_id": b.id})
	K.expect(f, Health.work_block(b, "coder") == "", "a cold does not stop work")
	# rest speeds recovery
	var before: float = _remaining(a, "flu")
	a.posture = "lie"
	for i in 60:
		HealthIllness.tick_minute(a, Health.rec_of(a.id))
	K.expect(f, before - _remaining(a, "flu") >= 59.0, "lying down recovers twice as fast")
	K.teardown()

func _remaining(f, buff: String) -> float:
	for b in f.buffs:
		if str(b["id"]) == buff:
			return float(b["remaining"])
	return 0.0

func _medicine(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var sink = w.add_object("sink", Vector2i(16, 12))
	WorldIface.coins[1] = 100
	var med := Interaction.create("take_medicine", a, sink.id, false)
	K.expect(f, not med.can_run(a, null, false), "no medicine offered when healthy")
	Incidents.force("catch_flu", {"folk_id": a.id})
	K.expect(f, med.can_run(a, null, false), "medicine offered when ill")
	var left_before: float = _remaining(a, "flu")
	var dir = K.director()
	dir.autonomy_enabled = false
	K.expect(f, dir.command(a.id, "take_medicine", sink.id), "the player can send them to take medicine")
	K.run(dir, 20)
	K.expect(f, a.has_buff("medicated") and WorldIface.get_coins(1) == 85, "medicated, 15 coins spent")
	K.expect(f, _remaining(a, "flu") < left_before * 0.7, "the flu is shortened")
	# first aid for an injury
	Health.injure(a, 1, "a trip")
	var aid_before: float = _remaining(a, "injured")
	K.expect(f, dir.command(a.id, "treat_injury", sink.id), "first aid command")
	K.run(dir, 20)
	K.expect(f, _remaining(a, "injured") < aid_before * 0.8, "first aid shortens the injury")
	K.teardown()
	# a doctor treats everything
	var w2 := _world()
	var b := K.make_folk(w2, "Bo", [], 1)
	WorldIface.coins[1] = 500
	Incidents.force("catch_flu", {"folk_id": b.id})
	Health.injure(b, 1, "a trip")
	var res: Dictionary = Incidents.call_doctor(b.id)
	K.expect(f, res["treated"].has("illness") and res["treated"].has("injury") and b.has_buff("medicated"), "the doctor treats illness and injury")
	K.expect(f, _remaining(b, "flu") < 96.0 * 60.0 * 0.3, "and cuts the illness down a lot")
	K.teardown()

func _worsens(f: Array) -> void:
	var w := _world()
	var e := K.make_folk(w, "Eli", [], 1, Vector2i(12, 12), "elder")
	var a := K.make_folk(w, "Ada", [], 1, Vector2i(14, 12))
	Incidents.force("catch_flu", {"folk_id": e.id})
	Incidents.force("catch_flu", {"folk_id": a.id})
	var def: Dictionary = IncidentDefs.get_def("illness_worsens")
	K.expect(f, Incidents.effective_rate("illness_worsens", e) > Incidents.effective_rate("illness_worsens", a) * 3.0, "elders are at higher risk")
	# death is only ever picked for untreated elders
	var adult_deaths: int = 0
	var elder_deaths: int = 0
	var treated_deaths: int = 0
	for i in 300:
		if IncidentEffects.pick(def["outcomes"], IncidentSubject.of_folk(a)).get("index", -1) == 0:
			adult_deaths += 1
		if IncidentEffects.pick(def["outcomes"], IncidentSubject.of_folk(e)).get("index", -1) == 0:
			elder_deaths += 1
	e.add_buff("medicated")
	for i in 300:
		if IncidentEffects.pick(def["outcomes"], IncidentSubject.of_folk(e)).get("index", -1) == 0:
			treated_deaths += 1
	K.expect(f, adult_deaths == 0 and treated_deaths == 0 and elder_deaths > 30 and elder_deaths < 130, "only untreated elders can die of it (%d of 300 picks)" % elder_deaths)
	e.remove_buff("medicated")
	# warning first, then medicine or a doctor defuses
	WorldIface.coins[1] = 500
	K.notes.clear()
	Incidents.force("illness_worsens", {"folk_id": e.id, "warn": true})
	K.expect(f, Incidents.active().size() == 1 and K.has_note("getting worse"), "a warning toast comes first")
	Incidents.call_doctor(e.id)
	K.set_time(6, 20, 0)
	Incidents.on_minute()
	K.expect(f, w.get_folk(e.id) != null and Incidents.stat("illness_worsens")["averted"] == 1 and Incidents.active().is_empty(), "the doctor defused it")
	# without help the elder can be lost
	Incidents.force("illness_worsens", {"folk_id": e.id, "outcome": 0})
	K.expect(f, w.get_folk(e.id) == null and str(K.last_event("died").get("cause", "")) == "flu", "forced fatal outcome kills (cause flu, not a long illness)")
	K.teardown()

func _food(f: Array) -> void:
	var w := _world()
	var a := K.make_folk(w, "Ada", [], 1)
	var fridge = w.add_object("fridge", Vector2i(16, 12))
	WorldIface.state_set(fridge, "spoiled", 0.0)
	Health.on_interaction_started(a.id, "grab_snack", fridge.id)
	K.expect(f, Incidents.active().is_empty() and int(Health.counters.get("spoiled_meals", 0)) == 0, "fresh fridge: no risk")
	IncidentDefs.config["health"]["food_poisoning"]["snack_per_item"] = 1.0
	IncidentDefs.config["health"]["food_poisoning"]["max"] = 1.0
	WorldIface.state_set(fridge, "spoiled", 3.0)
	K.notes.clear()
	Health.on_interaction_started(a.id, "grab_snack", fridge.id)
	K.expect(f, Incidents.active().size() == 1 and K.has_note("queasy"), "eating from a fridge with spoiled food: a warning first")
	K.set_time(6, 9, 10)
	Incidents.on_minute()
	K.expect(f, not a.has_buff("food_poisoning"), "not yet (25 minute warning)")
	K.set_time(6, 9, 40)
	Incidents.on_minute()
	K.expect(f, a.has_buff("food_poisoning") and a.has_buff("sick") and K.has_note("food poisoning"), "food poisoning follows")
	K.expect(f, a.decay_mult("hunger") > 1.5 and a.decay_mult("bladder") > 1.4, "hungry and sick")
	# medicine in the warning window defuses it
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(14, 12))
	Health.on_interaction_started(b.id, "grab_snack", fridge.id)
	b.add_buff("medicated")
	K.set_time(6, 11, 0)
	Incidents.on_minute()
	K.expect(f, not b.has_buff("food_poisoning"), "medicine taken in time prevents it")
	# Surprises Off: no illness dice, including this one
	Incidents.set_level("off")
	var c := K.make_folk(w, "Cy", [], 1, Vector2i(15, 12))
	Health.on_interaction_started(c.id, "grab_snack", fridge.id)
	K.expect(f, not Incidents.active().any(func(p): return int(p["sid"]) == c.id), "Surprises Off: no food poisoning rolls")
	# tossing the spoiled food (existing chore) removes the risk
	Incidents.set_level("rare")
	WorldIface.state_set(fridge, "spoiled", 0.0)
	var d := K.make_folk(w, "Di", [], 1, Vector2i(16, 14))
	Health.on_interaction_started(d.id, "grab_snack", fridge.id)
	K.expect(f, not Incidents.active().any(func(p): return int(p["sid"]) == d.id), "after tossing spoiled food: safe")
	K.teardown()

func _townies(f: Array) -> void:
	var w := _world()
	K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	var ids: Array = Story.townies.keys()
	ids.sort()
	var t: int = int(ids[0])
	var r1: Dictionary = Incidents.force("catch_cold", {"townie_id": t, "folk_id": t})
	K.expect(f, bool(r1["ok"]) and r1["mode"] == "statistical" and str(r1["summary"]).find("cold") >= 0, "far townies catch colds statistically: %s" % str(r1.get("summary", "")))
	var r2: Dictionary = Incidents.force("townie_stomach_bug", {"townie_id": t})
	K.expect(f, bool(r2["ok"]) and r2["mode"] == "statistical", "stomach bug for a far townie: %s" % str(r2.get("summary", "")))
	var r3: Dictionary = Incidents.force("illness_worsens", {"folk_id": t, "outcome": 0})
	K.expect(f, bool(r3["ok"]) and Hospital.is_in(t), "worsening townie goes to hospital (statistical)")
	K.teardown()
