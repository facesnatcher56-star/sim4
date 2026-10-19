extends RefCounted
## Hypothermia and heatstroke: freezing / scorching weather outside builds stages (shivering -> sick -> collapsed -> possible death);
## shelter, warm clothes and water slow or reset it; a housemate or a doctor rescues the collapsed.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_cold(f)
	_heat(f)
	_death(f)
	_shelter(f)
	_stuck(f)
	return f

## A stage buff left behind without exposure behind it (the health record was pruned while the person was out of the world, or reset) is
## cleared within the hour instead of colouring every mood for the rest of their life.
func _stuck(f: Array) -> void:
	var w := K.setup()
	SysContent.install_all()
	var a := _winter(w)
	a.set_meta("outdoors", false)
	a.add_buff("shivering")
	a.add_buff("hypothermia")
	Health.records.erase(a.id)
	Health.on_hour()
	K.expect(f, not a.has_buff("shivering") and not a.has_buff("hypothermia"), "a stage buff with no exposure behind it is cleared by the hourly sweep")
	K.teardown()

func _winter(w: StubWorld) -> Folk:
	Incidents.reset()
	IncidentDefs.config["health"]["exposure"]["cold"]["hard_below"] = -100.0       # always 1 minute per minute: easy to count
	Weather.force("cold_snap")
	K.set_time(24, 3, 0)                       # winter, small hours: the coldest time
	var a := K.make_folk(w, "Ada", [], 1)
	a.set_meta("outdoors", true)
	return a

func _cold(f: Array) -> void:
	var w := K.setup()
	SysContent.install_all()
	var a := _winter(w)
	K.expect(f, Weather.feels_like() < float(Health.cfg("exposure")["cold"]["below"]), "the test weather is freezing (%.1f)" % Weather.feels_like())
	var dir = K.director()
	dir.autonomy_enabled = false
	K.run(dir, 100)
	K.expect(f, not a.has_buff("shivering") and Health.stage_of(a)["cold"] == 0, "100 minutes in the cold: fine so far")
	Health.rec_of(a.id)["cold_min"] = 170.0
	K.run(dir, 15)
	K.expect(f, a.has_buff("shivering") and K.has_note("shivering") and Health.stage_of(a)["cold"] == 1, "stage 1: shivering, warned")
	Health.rec_of(a.id)["cold_min"] = 350.0
	K.run(dir, 15)
	K.expect(f, a.has_buff("hypothermia") and a.has_buff("sick") and K.has_note("dangerously cold"), "stage 2: hypothermia + unwell")
	K.expect(f, Health.speed_mult(a) < 0.85, "hypothermia slows them down")
	K.expect(f, not Health.is_collapsed(a), "not collapsed yet")
	# shelter resets it
	a.set_meta("outdoors", false)
	K.run(dir, 130)
	K.expect(f, not a.has_buff("hypothermia") and not a.has_buff("shivering") and float(Health.rec_of(a.id).get("cold_min", 0.0)) < 100.0, "indoors it wears off")
	K.teardown()
	# warm clothes: slower build-up
	var w2 := K.setup()
	SysContent.install_all()
	var b := _winter(w2)
	b.add_buff("bundled_up")
	var dir2 = K.director()
	dir2.autonomy_enabled = false
	K.run(dir2, 200)
	K.expect(f, float(Health.rec_of(b.id)["cold_min"]) < 100.0, "warm clothes: 200 minutes out only builds %.0f" % float(Health.rec_of(b.id)["cold_min"]))
	K.teardown()
	# collapse, then a housemate / doctor
	var w3 := K.setup()
	SysContent.install_all()
	var c := _winter(w3)
	var d := K.make_folk(w3, "Di", [], 1, Vector2i(14, 12))
	var dir3 = K.director()
	dir3.autonomy_enabled = false
	Health.rec_of(c.id)["cold_min"] = 590.0
	K.run(dir3, 20)
	K.expect(f, Health.is_collapsed(c) and HealthCollapse.kind_of(c) == "cold" and K.has_note("collapsed in the cold"), "stage 3: collapsed in the cold")
	for i in 70:
		d.needs["hunger"].set_value(50.0)
		K.run(dir3, 1)
	K.expect(f, not Health.is_collapsed(c) and c.has_buff("bundled_up"), "Di helped Ada up and put a coat on them")
	K.expect(f, float(Health.rec_of(c.id)["cold_min"]) < 450.0, "and the cold eased (%.0f)" % float(Health.rec_of(c.id)["cold_min"]))
	K.teardown()

func _heat(f: Array) -> void:
	var w := K.setup()
	SysContent.install_all()
	Incidents.reset()
	IncidentDefs.config["health"]["exposure"]["heat"]["hard_above"] = 100.0
	Weather.force("heatwave")
	K.set_time(10, 14, 0)                      # summer afternoon
	var a := K.make_folk(w, "Ada", [], 1)
	a.set_meta("outdoors", true)
	K.expect(f, Weather.feels_like() > float(Health.cfg("exposure")["heat"]["above"]), "the test weather is scorching (%.1f)" % Weather.feels_like())
	var dir = K.director()
	dir.autonomy_enabled = false
	Health.rec_of(a.id)["heat_min"] = 170.0
	K.run(dir, 15)
	K.expect(f, a.has_buff("overheating") and K.has_note("overheating"), "stage 1: overheating")
	Health.rec_of(a.id)["heat_min"] = 350.0
	K.run(dir, 15)
	K.expect(f, a.has_buff("heat_exhaustion") and a.has_buff("sick"), "stage 2: heat exhaustion")
	var before: float = float(Health.rec_of(a.id)["heat_min"])
	K.set_time(10, 14, 0)
	HealthExposure.cool_down(a)                # drink_water on_finish
	K.expect(f, float(Health.rec_of(a.id)["heat_min"]) <= before - 119.0 and a.has_buff("cooled_down"), "a drink of water takes 2 hours off the heat clock")
	K.teardown()
	# the interactions exist and are offered to the right people
	var w2 := K.setup()
	SysContent.install_all()
	Incidents.reset()
	var b := K.make_folk(w2, "Bo", [], 1)
	var sink = w2.add_object("sink", Vector2i(16, 12))
	var dresser = w2.add_object("dresser", Vector2i(18, 12))
	var drink := Interaction.create("drink_water", b, sink.id, false)
	K.expect(f, drink != null and not drink.can_run(b, null, false), "no drink offered when not hot")
	b.add_buff("overheating")
	K.expect(f, drink.can_run(b, null, false), "drink offered to someone overheating")
	var coat := Interaction.create("put_on_coat", b, dresser.id, false)
	K.expect(f, not coat.can_run(b, null, false), "coat not offered when warm")
	b.add_buff("shivering")
	K.expect(f, coat.can_run(b, null, false), "coat offered to someone shivering")
	K.teardown()

func _death(f: Array) -> void:
	var w := K.setup()
	SysContent.install_all()
	var a := _winter(w)
	IncidentDefs.config["health"]["exposure"]["cold"]["death_per_hour"] = 1.0
	var r: Dictionary = Health.rec_of(a.id)
	r["cold_min"] = 1079.0
	HealthExposure.hourly(a, r)
	K.expect(f, w.get_folk(a.id) != null, "just under 18 hours of freezing: alive")
	r["cold_min"] = 1080.0
	HealthExposure.hourly(a, r)
	K.expect(f, w.get_folk(a.id) == null and str(K.last_event("died").get("cause", "")) == "hypothermia", "past it: death by hypothermia")
	K.teardown()
	var w2 := K.setup()
	SysContent.install_all()
	Incidents.reset()
	Incidents.set_level("off")
	var b := K.make_folk(w2, "Bo", [], 1)
	IncidentDefs.config["health"]["exposure"]["heat"]["death_per_hour"] = 1.0
	Health.rec_of(b.id)["heat_min"] = 960.0
	HealthExposure.hourly(b, Health.rec_of(b.id))
	K.expect(f, w2.get_folk(b.id) == null and str(K.last_event("died").get("cause", "")) == "heatstroke", "heatstroke too, and Surprises Off does not prevent it")
	K.teardown()

## Freezing: a person who has been out in the cold for an hour is sent indoors (and a collapse in the open is helped long before the cold kills).
func _shelter(f: Array) -> void:
	var w := K.setup()
	SysContent.install_all()
	var a := _winter(w)
	var sent: Array = []
	HealthShelter.seek_hook = func(x): sent.append(int(x.id)); x.set_meta("outdoors", false)
	var dir = K.director()
	dir.autonomy_enabled = false
	K.run(dir, 50)
	K.expect(f, sent.is_empty(), "50 minutes out: still fine")
	K.run(dir, 30)
	K.expect(f, sent == [int(a.id)], "after an hour in the freezing cold they are sent indoors, before shivering (sent %s, cold %.0f)" % [str(sent), float(Health.rec_of(a.id).get("cold_min", 0.0))])
	K.expect(f, not a.has_buff("shivering"), "and they never shiver")
	HealthShelter.seek_hook = Callable()
	K.teardown()
	# the town reaches a collapsed elder in the open within the hour, well before the cold can kill them
	var w2 := K.setup()
	SysContent.install_all()
	var e := _winter(w2)
	e.age_stage = "elder"
	var dir2 = K.director()
	dir2.autonomy_enabled = false
	Health.rec_of(e.id)["cold_min"] = 470.0
	var died: bool = false
	K.run(dir2, 20)
	K.expect(f, Health.is_collapsed(e), "the elder collapses in the cold")
	var t0: int = SysUtil.now()
	for i in 90:
		K.run(dir2, 1)
		if not Health.is_collapsed(e):
			break
	K.expect(f, not Health.is_collapsed(e) and SysUtil.now() - t0 <= 75, "town help reaches them within an hour (%d min)" % (SysUtil.now() - t0))
	K.expect(f, SysUtil.folk(int(e.id)) != null or Hospital.is_in(e), "still alive")
	K.teardown()
