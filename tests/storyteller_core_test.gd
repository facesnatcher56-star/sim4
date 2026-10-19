extends RefCounted
## Storyteller core (task 29): personalities and Custom sliders, host-only commands, categories, the capped hard-rule multipliers, save/load of the whole state.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_personalities(f)
	_command(f)
	_hard_caps(f)
	_save_load(f)
	return f

func _world() -> StubWorld:
	var w := K.setup(2929, true)
	K.make_folk(w, "Alma Reed", ["neat"], 1)
	K.mgr.new_game([1])
	Players.set_player(Players.LOCAL, 1, "Reed")
	return w

func _personalities(f: Array) -> void:
	_world()
	K.expect(f, Storyteller.personality_id() == "classic", "Classic is the default")
	var q: Dictionary = {}
	for id in ["calm", "classic", "chaotic", "custom"]:
		Storyteller.set_personality(id)
		q[id] = Storyteller.params()
	K.expect(f, int(q["calm"]["max_quiet_days"]) == 10 and int(q["classic"]["max_quiet_days"]) == 5 and int(q["chaotic"]["max_quiet_days"]) == 3, "max quiet days 10 / 5 / 3")
	K.expect(f, float(q["calm"]["walk"]["mean"]) < float(q["classic"]["walk"]["mean"]) and float(q["classic"]["walk"]["mean"]) < float(q["chaotic"]["walk"]["mean"]), "the walk mean rises Calm < Classic < Chaotic")
	Storyteller.set_personality("custom", {"frequency": 1.0, "severity": 1.0, "balance": 0.0, "mercy": 0.0})
	var hi: Dictionary = Storyteller.params()
	Storyteller.set_personality("custom", {"frequency": 0.0, "severity": 0.0, "balance": 1.0, "mercy": 1.0})
	var lo: Dictionary = Storyteller.params()
	K.expect(f, float(hi["walk"]["mean"]) > float(lo["walk"]["mean"]) and float(hi["good_share"]) < float(lo["good_share"]) and float(hi["mercy"]) < float(lo["mercy"]), "Custom sliders move frequency, balance and mercy")
	K.expect(f, float(hi["hard_mult"]) <= float(Storyteller.cfg()["hard_cap"]) + 0.0001, "Custom can never exceed the hard cap")
	K.expect(f, not Storyteller.set_personality("nonsense"), "an unknown personality is refused")
	K.teardown()

func _command(f: Array) -> void:
	_world()
	var r: Dictionary = Commands.run({"player_id": 2, "action": "storyteller", "args": {"action": "configure", "personality": "chaotic"}})
	K.expect(f, not bool(r["ok"]) and Storyteller.personality_id() == "classic", "a non-host cannot change the storyteller")
	r = Commands.run({"player_id": Players.LOCAL, "action": "storyteller", "args": {"action": "configure", "personality": "chaotic", "off": ["crime", "arcs"]}})
	K.expect(f, bool(r["ok"]) and Storyteller.personality_id() == "chaotic", "the host can")
	K.expect(f, not Storyteller.cat_on("crime") and not Storyteller.cat_on("arcs") and Storyteller.cat_on("money"), "categories switch off one by one")
	Commands.run({"player_id": Players.LOCAL, "action": "storyteller", "args": {"action": "configure", "off": []}})
	K.expect(f, Storyteller.cat_on("crime"), "and back on")
	K.teardown()

func _hard_caps(f: Array) -> void:
	_world()
	var cap: float = float(Storyteller.cfg()["hard_cap"])
	for id in ["calm", "classic", "chaotic"]:
		Storyteller.set_personality(id)
		var m: float = Storyteller.incident_mult("murder")
		K.expect(f, m <= cap + 0.0001, "%s: murder multiplier %.2f within the cap" % [id, m])
		for h in ["serial_killer", "tornado", "flood", "earthquake"]:
			K.expect(f, Storyteller.incident_mult(h) <= cap + 0.0001, "%s: %s within the cap" % [id, h])
		K.expect(f, Storyteller.hard_mult() <= cap + 0.0001, "%s: hard_mult within the cap" % id)
	Storyteller.set_personality("calm")
	K.expect(f, Storyteller.hard_mult() < 1.0, "Calm lowers the rare worst things")
	Storyteller.set_personality("classic")
	K.expect(f, is_equal_approx(Storyteller.incident_mult("murder"), 1.0) and is_equal_approx(Storyteller.incident_mult("burglary"), 1.0), "Classic leaves them as they were")
	Storyteller.enabled = false
	Storyteller.set_personality("chaotic")
	K.expect(f, is_equal_approx(Storyteller.incident_mult("burglary"), 1.0), "switched off, no multipliers")
	K.teardown()
	# the deck itself has no murder, serial killer, child abuse or disaster card
	for cid in StorytellerDeck.cards():
		var c: Dictionary = StorytellerDeck.cards()[cid]
		var inc: String = str(c.get("incident", ""))
		K.expect(f, not (Storyteller.cfg()["hard_incidents"] as Array).has(inc), "card %s is not a hard incident" % cid)
		K.expect(f, JSON.stringify(c).find("abuse") < 0 and JSON.stringify(c).find("murder") < 0, "card %s mentions no abuse or murder" % cid)

func _save_load(f: Array) -> void:
	var w := _world()
	Storyteller.set_personality("custom", {"frequency": 0.8, "severity": 0.3, "balance": 0.6, "mercy": 0.2})
	Storyteller.set_cat("work", false)
	for d in range(2, 30):
		K.set_time(d, 8)
		Storyteller.on_day(d)
	var before: String = JSON.stringify(Storyteller.to_dict())
	var j = JSON.parse_string(before)
	Storyteller.from_dict(j)
	var after: String = JSON.stringify(Storyteller.to_dict())
	if after != before:
		var i := 0
		while i < mini(after.length(), before.length()) and after[i] == before[i]:
			i += 1
		print("DIFF at ", i, " before: ", before.substr(maxi(i - 80, 0), 160), " after: ", after.substr(maxi(i - 80, 0), 160))
	K.expect(f, after == before, "the budget, arcs, queue and log survive a JSON round trip")
	K.expect(f, Storyteller.personality_id() == "custom" and not Storyteller.cat_on("work"), "personality, sliders and switched-off categories are saved")
	var rs: float = Storyteller.rng.randf()
	Storyteller.from_dict(j)
	K.expect(f, is_equal_approx(Storyteller.rng.randf(), rs), "the random stream resumes where it was")
	K.teardown()
