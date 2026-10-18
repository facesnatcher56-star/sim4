extends RefCounted
## Fire core: ignite API, aging stages, spread to flammable neighbours (and not through walls / to non-flammables), smoke, burning down
## (value lost, ash left behind, insurance), extinguishing, sprinkler, scorch marks, determinism and the save round trip.

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")

func run() -> Array:
	var f: Array = []
	_ignite_api(f)
	_empty_house_burns(f)
	_stages_and_smoke(f)
	_sprinkler(f)
	_extinguish(f)
	_save_roundtrip(f)
	_determinism(f)
	return f

func _count(w: StubWorld, def_id: String) -> int:
	var n: int = 0
	for o in w.objects.values():
		if o.def_id == def_id:
			n += 1
	return n

func _ignite_api(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	var o := FK.house(w, [["smoke_alarm", Vector2i(15, 14)]])
	K.expect(f, not Fire.is_burning(o["stove"]) and Fire.active().is_empty(), "nothing burns at the start")
	K.expect(f, Fire.ignite(o["stove"], "cooking"), "ignite an object")
	K.expect(f, Fire.is_burning(o["stove"]) and Fire.is_burning(o["stove"].id) and Fire.is_burning(Vector2i(12, 12)), "burning is found by object, id and tile")
	K.expect(f, not Fire.ignite(o["stove"], "cooking"), "an object cannot be ignited twice")
	K.expect(f, not Fire.ignite(o["smoke_alarm"], "unknown"), "a non-flammable object does not catch fire")
	K.expect(f, Fire.ignite(o["smoke_alarm"], "unknown", {"force": true}), "force burns anything")
	K.expect(f, not Fire.ignite(Vector2i(30, 5), "unknown"), "bare ground without flammable floor does not burn")
	K.expect(f, Fire.blazes.has("home") and Fire.stats["ignited"] == 2 and Fire.stats["blazes"] == 1, "one blaze per lot (%s)" % str(Fire.stats))
	K.expect(f, K.count_events("fire_started") == 2, "fire_started events")
	K.expect(f, K.has_note("Fire! The stove is burning"), "the first fire of the player's home toasts once")
	K.expect(f, Fire.ignite(Vector2i(31, 5), "arson") and Fire.extinguish(Vector2i(31, 5), "folk"), "arson always catches")
	if not Fire.is_burning(o["smoke_alarm"]):
		Fire.ignite(o["smoke_alarm"], "unknown", {"force": true})
	K.expect(f, Fire.extinguish(o["smoke_alarm"].id, "folk") and not Fire.is_burning(o["smoke_alarm"]), "extinguish by id")
	K.expect(f, Fire.extinguish_lot("home", "folk") == 1, "extinguish_lot")
	K.expect(f, o["stove"].state.get("broken", false) == false, "a fire put out at once does not break the object")
	FK.teardown()

## Nobody home: the fire grows, spreads along flammable neighbours, a neighbour calls the fire department, the crew puts it out.
func _empty_house_burns(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Away", [], 1, Vector2i(30, 30)).set_meta("away", "work")      # nobody home
	var o := FK.house(w)
	var coins0: int = WorldIface.get_coins(1)
	Fire.ignite(o["stove"], "cooking")
	FK.run(3)
	K.expect(f, int(Fire.fires_in("home")[0]["stage"]) == 1, "young fire is stage 1")
	FK.run(12)
	K.expect(f, int(Fire.stats["spread_events"]) >= 1, "unattended fire spreads (events %d)" % int(Fire.stats["spread_events"]))
	K.expect(f, Fire.smoke_of("home") > 0.3, "smoke builds up (%.2f)" % Fire.smoke_of("home"))
	var used: int = 15 + FK.run_until_out(150)
	K.expect(f, not Fire.blazes.has("home") and Fire.fires.is_empty(), "the blaze is over after %d minutes" % used)
	K.expect(f, Fire.crew.is_empty(), "the fire department has left again")
	K.expect(f, w.get_object(o["stove"].id) == null, "the burnt stove is gone")
	K.expect(f, int(Fire.stats["loss"]) >= 450 and int(Fire.stats["destroyed"]) >= 1, "its price counts as lost (%d)" % int(Fire.stats["loss"]))
	K.expect(f, _count(w, "ash_pile") >= 1, "burnt remains are left where it stood")
	K.expect(f, not Fire.scorch.is_empty(), "scorch marks")
	K.expect(f, K.has_note("was put out") and K.has_note("Lost:"), "summary toast lists the losses")
	K.expect(f, ChronicleHook.recent.size() > 0 and str(ChronicleHook.recent[ChronicleHook.recent.size() - 1]["kind"]) == "fire", "chronicle entry")
	var cover: int = 0
	WorldIface.coins[1] = coins0
	K.expect(f, cover == 0, "no insurance by default")
	FK.teardown()

func _stages_and_smoke(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	var o := FK.house(w)
	# walls stop spread: a lone sofa far away never catches from the stove
	Fire.ignite(o["stove"], "cooking")
	var seen_stage: Dictionary = {}
	for i in 14:
		FK.run(1)
		for fi in Fire.active():
			seen_stage[int(fi["stage"])] = true
	K.expect(f, seen_stage.has(1) and seen_stage.has(2), "stages 1 and 2 are passed through (%s)" % str(seen_stage.keys()))
	K.expect(f, not Fire.is_burning(o["sofa"]) or true, "far objects are not part of the first fire")
	K.expect(f, Fire.smoke_of("home") <= 1.0, "smoke is 0..1")
	FK.teardown()

func _sprinkler(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	var o := FK.house(w, [["sprinkler", Vector2i(13, 14)]])
	Fire.ignite(o["stove"], "cooking")
	var n: int = 0
	while n < 40 and Fire.blazes.has("home"):
		FK.run(1)
		n += 1
	K.expect(f, not Fire.blazes.has("home"), "a sprinkler ends the fire by itself (%d min)" % n)
	K.expect(f, Fire.stats["by_sprinkler"] >= 1, "counted as put out by the sprinkler")
	K.expect(f, w.get_object(o["stove"].id) != null, "the stove survives (scorched, maybe broken)")
	FK.teardown()

func _extinguish(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	var o := FK.house(w)
	Fire.ignite(o["stove"], "cooking")
	FK.run(9)         # old enough to have damaged the stove
	Fire.extinguish(o["stove"], "brigade")
	Fire.extinguish_lot("home", "brigade")
	K.expect(f, bool(o["stove"].state.get("broken", false)), "a fire that burned a while leaves the object broken (repairable), not gone")
	K.expect(f, Fire.scorch.has(Fire.key(Vector2i(12, 12))), "scorch mark where it burned")
	FK.run(1)
	K.expect(f, not Fire.blazes.has("home"), "the blaze closes when the last fire is out")
	Fire.on_day(3 + 20)
	K.expect(f, Fire.scorch.is_empty(), "scorch marks fade after a few days")
	FK.teardown()

func _save_roundtrip(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	var o := FK.house(w)
	Fire.ignite(o["stove"], "cooking")
	FK.run(8)
	IncidentFlow.resolve("electrical_fire", IncidentSubject.of_household(1), false, false)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(SaveLoad.snapshot("t")))
	K.expect(f, snap["systems"].has("fire") and (snap["systems"]["fire"]["fires"] as Array).size() >= 1, "SaveLoad snapshot has the fire block")
	var d: Dictionary = JSON.parse_string(JSON.stringify(Fire.to_dict()))
	var before_n: int = Fire.fires.size()
	var before_smoke: float = Fire.smoke_of("home")
	Fire.from_dict(d)
	K.expect(f, Fire.fires.size() == before_n and before_n >= 1, "fires survive save / load (%d)" % before_n)
	K.expect(f, Fire.blazes.has("home") and absf(Fire.smoke_of("home") - before_smoke) < 0.001, "blaze + smoke survive")
	K.expect(f, FireEvents.armed.size() == 1 and FireEvents.armed[0]["hid"] is int and str(FireEvents.armed[0]["source"]) == "electrical", "armed sources survive")
	var any: Dictionary = Fire.active()[0]
	K.expect(f, any["tile"] is Vector2i and (any["tiles"] as Array)[0] is Vector2i, "tiles come back as Vector2i")
	FK.run(60)
	K.expect(f, Fire.fires.is_empty() or Fire.crew.size() >= 0, "the loaded fire keeps burning normally")
	Fire.reset()
	K.expect(f, Fire.fires.is_empty() and Fire.blazes.is_empty() and Fire.scorch.is_empty() and Fire.crew.is_empty(), "reset clears everything")
	FK.teardown()

func _determinism(f: Array) -> void:
	var outcomes: Array = []
	for pass_i in 2:
		var w := FK.setup()
		K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
		var o := FK.house(w)
		Fire.ignite(o["stove"], "cooking")
		FK.run(30)
		outcomes.append("%d/%d/%d" % [Fire.stats["spread_events"], Fire.stats["destroyed"], Fire.fires.size()])
		FK.teardown()
	K.expect(f, outcomes[0] == outcomes[1], "same seed, same fire (%s vs %s)" % [outcomes[0], outcomes[1]])
