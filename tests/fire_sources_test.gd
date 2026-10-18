extends RefCounted
## The six sources of fire (kitchen, fireplace, electrical + botched repairs, holiday candles, lightning): rates and risk multipliers from
## the data, forced incidents start a fire at once, un-forced ones are ARMED and start at the next fitting moment; prevention shows in tooltips.

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")

func run() -> Array:
	var f: Array = []
	_schema(f)
	_rates(f)
	_kitchen(f)
	_fireplace(f)
	_electrical(f)
	_candle(f)
	_lightning(f)
	_tooltips(f)
	return f

func _near(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

func _schema(f: Array) -> void:
	var w := FK.setup()
	var mine: Array = []
	for id in ["kitchen_fire", "fireplace_fire", "electrical_fire", "candle_fire", "lightning_fire"]:
		mine.append_array(IncidentDefs.validate_def(id, IncidentDefs.defs[id]))
	K.expect(f, mine.is_empty(), "fire incident data is valid: %s" % str(mine))
	K.expect(f, Incidents.handler("fire_arm").is_valid() and Incidents.handler("fire_aftermath").is_valid(), "handlers resolve")
	for id in ["kitchen_fire", "fireplace_fire", "electrical_fire", "candle_fire", "lightning_fire"]:
		K.expect(f, IncidentDefs.defs.has(id), "incident %s exists" % id)
	K.expect(f, DeathCauses.has_cause("fire"), "death cause fire exists")
	K.expect(f, w.get_def_ok("sprinkler") if w.has_method("get_def_ok") else not SimEnv.data().object_def("sprinkler").is_empty(), "sprinkler object installed")
	K.expect(f, not SimEnv.data().object_def("ash_pile").is_empty() and not SimEnv.data().interactions().get("use_extinguisher", {}).is_empty(), "burnt remains + extinguisher interaction installed")
	FK.teardown()

func _rates(f: Array) -> void:
	var w := FK.setup()
	var cook := K.make_folk(w, "Cook", [], 1, Vector2i(30, 30))
	FK.house(w, [["fireplace", Vector2i(20, 12)]])
	var hh := IncidentSubject.of_household(1)
	K.expect(f, _near(Incidents.effective_rate("kitchen_fire", hh), 0.3), "unskilled household: kitchen fire 0.3/yr (%.3f)" % Incidents.effective_rate("kitchen_fire", hh))
	cook.skills["cooking"]["level"] = 2
	K.expect(f, _near(Incidents.effective_rate("kitchen_fire", hh), 0.18), "some practice: x0.6")
	cook.skills["cooking"]["level"] = 4
	K.expect(f, _near(Incidents.effective_rate("kitchen_fire", hh), 0.036), "skill 4+: much less (%.3f)" % Incidents.effective_rate("kitchen_fire", hh))
	cook.skills["cooking"]["level"] = 0
	cook.traits.append("clumsy")
	K.expect(f, _near(Incidents.effective_rate("kitchen_fire", hh), 0.45), "clumsy cook x1.5")
	K.expect(f, _near(Incidents.effective_rate("electrical_fire", hh), 0.07 * 1.6), "low handiness raises the electrical risk")
	cook.skills["handiness"]["level"] = 3
	K.expect(f, _near(Incidents.effective_rate("electrical_fire", hh), 0.07), "handy household: base electrical rate")
	K.expect(f, _near(Incidents.effective_rate("fireplace_fire", hh), 0.06) or _near(Incidents.effective_rate("fireplace_fire", hh), 0.12), "fireplace fire needs a fireplace")
	K.expect(f, Incidents.effective_rate("lightning_fire", hh) == 0.0, "no lightning fires on a sunny day")
	Weather.force("thunderstorm")
	K.expect(f, _near(Incidents.effective_rate("lightning_fire", hh), 0.5), "thunderstorm: lightning can strike")
	Weather.force("sunny")
	K.expect(f, Incidents.effective_rate("candle_fire", hh) == 0.0, "candle fires only on holidays")
	cook.add_buff("holiday_today")
	K.expect(f, _near(Incidents.effective_rate("candle_fire", hh), 0.14), "holiday: candle fires possible")
	K.expect(f, Incidents.effective_rate("kitchen_fire", IncidentSubject.of_household(2)) == 0.0, "a household with no stove has no kitchen fire")
	FK.teardown()

func _kitchen(f: Array) -> void:
	var w := FK.setup()
	var cook := K.make_folk(w, "Cook", [], 1, Vector2i(13, 14))
	var o := FK.house(w)
	var r: Dictionary = Incidents.force("kitchen_fire", {"lot": "home:1"})
	K.expect(f, bool(r["ok"]) and Fire.is_burning(o["stove"]), "forced kitchen fire burns the stove at once (%s)" % str(r))
	K.expect(f, int(Incidents.stat("kitchen_fire")["forced"]) == 1, "forced counter")
	Fire.reset()
	# un-forced: armed, starts while somebody cooks
	var res: Dictionary = IncidentFlow.resolve("kitchen_fire", IncidentSubject.of_household(1), false, false)
	K.expect(f, bool(res["ok"]) and FireEvents.armed.size() == 1 and Fire.active().is_empty(), "a rolled kitchen fire is armed, not started")
	K.expect(f, int(Incidents.stat("kitchen_fire")["triggered"]) == 1, "triggered counter")
	FK.run(60)
	K.expect(f, Fire.active().is_empty(), "nothing happens while nobody cooks")
	cook.needs["hunger"].set_value(10.0)
	K.expect(f, FK.dir.command(cook.id, "cook_meal", o["stove"].id), "the cook starts a meal")
	var n: int = 0
	while n < 40 and Fire.active().is_empty():
		FK.run(1)
		n += 1
	K.expect(f, Fire.is_burning(o["stove"]) and n >= 2, "the pan catches fire a few minutes into the meal (after %d min)" % n)
	K.expect(f, FireEvents.armed.is_empty(), "the armed source is used up")
	FK.teardown()
	# armed but nobody ever cooks: it fizzles
	var w2 := FK.setup()
	K.make_folk(w2, "Cook", [], 1, Vector2i(13, 14))
	FK.house(w2)
	IncidentFlow.resolve("kitchen_fire", IncidentSubject.of_household(1), false, false)
	K.expect(f, int(FireEvents.armed[0]["until"]) - SysUtil.now() >= 3 * 1440, "it stays armed for days")
	FireEvents.armed[0]["until"] = SysUtil.now() + 30
	FK.run(40)
	K.expect(f, Fire.active().is_empty() and FireEvents.armed.is_empty() and int(Fire.stats["averted"]) == 1, "an armed kitchen fire fizzles when nobody cooks for days")
	FK.teardown()

func _fireplace(f: Array) -> void:
	var w := FK.setup()
	var mia := K.make_folk(w, "Mia", [], 1, Vector2i(14, 20))
	var o := FK.house(w, [["fireplace", Vector2i(20, 12)], ["rug", Vector2i(20, 14)]])
	o["fireplace"].state["lit"] = true
	Incidents.force("fireplace_fire", {"lot": "home:1"})
	K.expect(f, Fire.active().size() == 1 and bool(o["fireplace"].state["lit"]), "forced fireplace fire: a spark catches (%d fires)" % Fire.active().size())
	Fire.reset()
	# armed: attended fireplace never ignites, an unattended one does after a while
	IncidentFlow.resolve("fireplace_fire", IncidentSubject.of_household(1), false, false)
	mia.tile = Vector2i(19, 13)
	FK.run(45)
	K.expect(f, Fire.active().is_empty(), "somebody sitting by the fire keeps it safe")
	mia.tile = Vector2i(14, 20)
	FK.run(30)
	K.expect(f, not Fire.active().is_empty(), "left burning alone for a while, it sets something alight")
	K.expect(f, FireRules.hover_text(o["fireplace"]).find("burning alone") >= 0, "fireplace tooltip warns")
	FK.teardown()

func _electrical(f: Array) -> void:
	var w := FK.setup()
	var mia := K.make_folk(w, "Mia", [], 1, Vector2i(16, 14))
	var o := FK.house(w)
	Incidents.force("electrical_fire", {"lot": "home:1"})
	K.expect(f, Fire.active().size() == 1, "forced electrical fire")
	Fire.reset()
	IncidentFlow.resolve("electrical_fire", IncidentSubject.of_household(1), false, false)
	K.expect(f, FireEvents.armed.size() == 1, "armed")
	mia.needs["fun"].set_value(5.0)
	FK.dir.command(mia.id, "watch_tv", o["tv"].id)
	FK.run(12)
	K.expect(f, K.count_events("fire_started") >= 1 and str(K.last_event("fire_started")["object"]) == "tv", "using an electrical device starts a fire in it")
	Fire.reset()
	# botched repair
	o["stove"].state["broken"] = true
	IncidentFlow.resolve("electrical_fire", IncidentSubject.of_household(1), false, false)
	mia.clear_queue()
	mia.cancel_current("test")
	FK.dir.command(mia.id, "repair_object", o["stove"].id)
	FK.run(12)
	K.expect(f, K.count_events("fire_started") >= 2 and str(K.last_event("fire_started")["source"]) == "repair", "a repair can go wrong (source repair)")
	FK.teardown()

func _candle(f: Array) -> void:
	var w := FK.setup()
	var mia := K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	mia.add_buff("holiday_today")
	FK.house(w)
	K.set_time(3, 8)
	IncidentFlow.resolve("candle_fire", IncidentSubject.of_household(1), false, false)
	K.expect(f, FireEvents.armed.size() == 1, "candle fire armed")
	var at: int = int(FireEvents.armed[0]["ignite_at"])
	K.expect(f, (at % 1440) >= 18 * 60 and (at % 1440) <= 23 * 60, "it happens on the holiday evening (%02d:%02d)" % [(at % 1440) / 60, at % 60])
	FK.run(at - SysUtil.now() + 1)
	K.expect(f, not Fire.active().is_empty() and str(Fire.active()[0]["source"]) == "candle", "a candle sets the room alight")
	FK.teardown()

func _lightning(f: Array) -> void:
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30))
	FK.house(w)
	Incidents.force("lightning_fire", {"lot": "home:1"})
	K.expect(f, Fire.active().size() == 1 and str(Fire.active()[0]["source"]) == "lightning", "lightning strikes at once")
	FK.teardown()

func _tooltips(f: Array) -> void:
	var w := FK.setup()
	var cook := K.make_folk(w, "Cook", [], 1, Vector2i(30, 30))
	var o := FK.house(w, [["smoke_alarm", Vector2i(15, 14)], ["fire_extinguisher", Vector2i(16, 14)], ["sprinkler", Vector2i(17, 14)]])
	var t: String = FireRules.hover_text(o["stove"])
	K.expect(f, t.find("Low cooking skill: fire risk") >= 0, "stove tooltip: low cooking skill is a fire risk (%s)" % t)
	cook.skills["cooking"]["level"] = 5
	SysUtil.seed_rng(1)
	K.set_time(3, 13)       # the tooltip is cached per game minute
	K.expect(f, FireRules.hover_text(o["stove"]).find("low fire risk") >= 0, "skilled cooks: low risk text")
	K.expect(f, FireRules.hover_text(o["smoke_alarm"]).find("Wakes sleepers") >= 0, "smoke alarm tooltip")
	o["smoke_alarm"].state["battery"] = 0.0
	K.set_time(3, 14)
	K.expect(f, FireRules.hover_text(o["smoke_alarm"]).find("Battery flat") >= 0, "flat battery warning")
	K.expect(f, FireRules.hover_text(o["stove"]).find("No working smoke alarm") >= 0, "stove tooltip warns when the alarm is dead")
	K.expect(f, FireRules.hover_text(o["fire_extinguisher"]).find("Charge") >= 0 and FireRules.hover_text(o["sprinkler"]).find("by itself") >= 0, "extinguisher + sprinkler tooltips")
	FK.teardown()
