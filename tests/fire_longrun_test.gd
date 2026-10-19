extends RefCounted
## SLOW tier: fire rates over many game years. (1) the statistical version over 40 far lots with the default Surprises setting: measured events
## per year against the data (kitchen 0.3 unskilled ...), a fire that spreads about 0.05 / lot-year and a fire death about 0.005 / lot-year, almost
## only in houses without a smoke alarm; (2) the FULL simulation (real objects, folk reactions) run many times: a small kitchen fire spreads in
## about one case in ten for an unskilled cook, much less with skill, an extinguisher or a sprinkler; a sleeper in a burning room dies about
## one time in four without a smoke alarm and (almost) never with one.

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")
const YEAR := 28
const DAILY := ["kitchen_fire", "fireplace_fire", "electrical_fire", "candle_fire"]

var _tally: Dictionary = {}          # id -> {outcome index -> count}
var _fire_deaths: int = 0

func run() -> Array:
	var f: Array = []
	var t0: int = Time.get_ticks_msec()
	_statistical(f)
	var t1: int = Time.get_ticks_msec()
	_full_kitchen(f)
	var t2: int = Time.get_ticks_msec()
	_full_sleeper(f)
	print("    fire longrun timing: statistical %d ms, kitchen trials %d ms, sleeper trials %d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])
	return f

func _near_rel(measured: float, target: float, tol: float) -> bool:
	return absf(measured / maxf(target, 0.00001) - 1.0) <= tol

func _on_event(ev: String, p: Dictionary) -> void:
	if ev == "incident" and bool(p.get("statistical", false)) and not bool(p.get("forced", false)):
		var id: String = str(p["id"])
		if not _tally.has(id):
			_tally[id] = {}
		_tally[id][int(p["outcome"])] = int((_tally[id] as Dictionary).get(int(p["outcome"]), 0)) + 1
	elif ev == "died" and str(p.get("cause", "")) == "fire":
		_fire_deaths += 1

func _fill_town(lots: int) -> void:
	for n in range(1, lots + 1):
		for _i in 2:
			var t: Dictionary = Story.add_townie()
			t["lot"] = n

func _statistical(f: Array) -> void:
	var w := FK.setup()
	_tally.clear()
	_fire_deaths = 0
	SimEnv.events().game_event.connect(_on_event)
	var lots: int = 50
	_fill_town(lots)
	Fire.on_minute()
	var years: int = TestFixture.pick(40, 25)
	var expected: Dictionary = {}
	var triggered0: Dictionary = {}
	for id in DAILY + ["lightning_fire"]:
		expected[id] = 0.0
	var dead_total: int = 0
	var day: int = 3
	for y in years:
		for d in YEAR:
			K.set_time(day, 3)
			Fire.on_day(day)
			var subs: Array = IncidentChecks.lot_subjects()
			for id2 in DAILY:
				var def: Dictionary = IncidentDefs.defs[id2]
				for s in subs:
					if id2 == "candle_fire":      # only holidays count
						if not Holidays.today(day).is_empty():
							expected[id2] = float(expected[id2]) + IncidentRisk.rate_to_chance(IncidentRisk.effective_rate(def, s), "day")
					elif d == 0:      # the expectation is sampled on the first day of each year (and scaled): evaluating it for every roll is slow
						expected[id2] = float(expected[id2]) + IncidentRisk.rate_to_chance(IncidentRisk.effective_rate(def, s), "day") * float(YEAR)
					IncidentChecks._roll(id2, def, s)
			day += 1
		# keep the town populated (a death empties a house)
		var alive: Array = Story.alive_townies()
		var per_lot: Dictionary = {}
		for t2 in alive:
			per_lot[int(t2["lot"])] = int(per_lot.get(int(t2["lot"]), 0)) + 1
		for n in range(1, lots + 1):
			while int(per_lot.get(n, 0)) < 2:
				var nt: Dictionary = Story.add_townie()
				nt["lot"] = n
				per_lot[n] = int(per_lot.get(n, 0)) + 1
	# lightning: stormy hours only (hour check; the storm share of the year is 3-4 percent, so measure per stormy hour)
	Weather.force("thunderstorm")
	var storm_hours: int = TestFixture.pick(2800, 2000)
	var ldef: Dictionary = IncidentDefs.defs["lightning_fire"]
	for h in storm_hours:
		for s2 in IncidentChecks.lot_subjects():
			if h % 20 == 0:
				expected["lightning_fire"] = float(expected["lightning_fire"]) + IncidentRisk.rate_to_chance(IncidentRisk.effective_rate(ldef, s2), "hour") * 20.0
			IncidentChecks._roll("lightning_fire", ldef, s2)
	Weather.force("sunny")
	var lot_years: float = float(lots * years)
	var spreads: int = 0
	var noalarm: int = 0
	var alarm: int = 0
	var parts: Array = []
	for id3 in expected:
		var trig: int = int(Incidents.stat(id3)["triggered"])
		var exp_n: float = float(expected[id3])
		parts.append("%s %d/%.0f" % [id3, trig, exp_n])
		K.expect(f, exp_n < 5.0 or _near_rel(float(trig), exp_n, 0.3), "%s: %d events, %.0f expected from the data (rate x risk x exposure)" % [id3, trig, exp_n])
		var tl: Dictionary = _tally.get(id3, {})
		for oi in tl:
			if int(oi) >= 1 and id3 != "lightning_fire":
				spreads += int(tl[oi])
			if int(oi) == 3:
				noalarm += int(tl[oi])
			if int(oi) == 4:
				alarm += int(tl[oi])
	var spread_rate: float = float(spreads) / lot_years
	var death_rate: float = float(_fire_deaths) / lot_years
	K.expect(f, spread_rate > 0.02 and spread_rate < 0.12, "a fire that spreads: %.3f per lot-year (target about 0.05; %d fires in %.0f lot-years)" % [spread_rate, spreads, lot_years])
	K.expect(f, death_rate > 0.001 and death_rate < 0.012, "a fire death: %.4f per lot-year (target about 0.005; %d deaths)" % [death_rate, _fire_deaths])
	K.expect(f, noalarm >= 2 * alarm and noalarm >= 3, "deaths are almost only in houses without a smoke alarm (%d without, %d with)" % [noalarm, alarm])
	K.expect(f, Fire.fires.is_empty() and Fire.blazes.is_empty() and Fire.crew.is_empty(), "no real fires linger (statistical mode touches no objects)")
	K.expect(f, Incidents.history(1000).size() <= int(IncidentDefs.cfg("history_cap", 200)), "history stays capped")
	K.expect(f, ChronicleHook.recent.size() <= 40, "chronicle recent list stays capped")
	print("    fire longrun statistical: %d years x %d lots; %s; spreads %.3f/lot-yr, deaths %.4f/lot-yr (%d)" % [years, lots, ", ".join(PackedStringArray(parts)), spread_rate, death_rate, _fire_deaths])
	SimEnv.events().game_event.disconnect(_on_event)
	FK.teardown()

# ------------------------------------------------------------------ the full simulation
func _kitchen_trial(seed_v: int, extra: Array, skill: int) -> bool:
	var w := FK.setup()
	Fire.rng.seed = seed_v
	var cook := K.make_folk(w, "Cook", [], 1, Vector2i(12, 13))
	cook.skills["cooking"]["level"] = skill
	var o := FK.house(w, extra)
	Fire.ignite(o["stove"], "cooking", {"culprit": cook.id})
	FK.run_until_out(120)
	var spread: bool = int(Fire.stats["spread_blazes"]) > 0
	FK.teardown()
	return spread

func _full_kitchen(f: Array) -> void:
	var n: int = TestFixture.pick(80, 50)
	var res: Dictionary = {}
	var cases := {"bare": [[], 0], "skilled": [[], 3], "extinguisher": [[["fire_extinguisher", Vector2i(15, 13)]], 0], "sprinkler": [[["sprinkler", Vector2i(13, 14)]], 0]}
	for k in cases:
		var c: int = 0
		for i in n:
			if _kitchen_trial(5000 + i, cases[k][0], int(cases[k][1])):
				c += 1
		res[k] = float(c) / float(n)
	K.expect(f, float(res["bare"]) >= 0.04 and float(res["bare"]) <= 0.32, "unskilled cook, nothing at hand: %.0f%% of kitchen fires spread (target about 10-15%%)" % (100.0 * float(res["bare"])))
	K.expect(f, float(res["skilled"]) < float(res["bare"]) or float(res["bare"]) < 0.05, "cooking skill 3 spreads less (%.0f%%)" % (100.0 * float(res["skilled"])))
	K.expect(f, float(res["extinguisher"]) <= float(res["bare"]) + 0.03, "an extinguisher at hand does not make it worse (%.0f%%)" % (100.0 * float(res["extinguisher"])))
	K.expect(f, float(res["sprinkler"]) <= 0.03, "a sprinkler stops almost all of them (%.0f%%)" % (100.0 * float(res["sprinkler"])))
	print("    fire longrun kitchen (n=%d): bare %.0f%%, skilled %.0f%%, extinguisher %.0f%%, sprinkler %.0f%% spread" % [n, 100.0 * float(res["bare"]), 100.0 * float(res["skilled"]), 100.0 * float(res["extinguisher"]), 100.0 * float(res["sprinkler"])])

func _sleeper_trial(seed_v: int, extra: Array) -> int:
	var w := FK.setup()
	Fire.rng.seed = seed_v
	var sl := K.make_folk(w, "Sleepy", [], 1, Vector2i(12, 19))
	var o := FK.house(w, extra)
	sl.needs["energy"].set_value(15.0)
	sl.enqueue(Interaction.create("sleep_bed", sl, o["bed"].id, true))
	FK.dir.tick_minute(1)
	FK.run(2)
	Fire.ignite(o["bed"], "candle", {"force": true})
	FK.run_until_out(150)
	var dead: int = int(Fire.stats["deaths"])
	FK.teardown()
	return dead

func _full_sleeper(f: Array) -> void:
	var n: int = TestFixture.pick(28, 24)
	var no_alarm: int = 0
	var with_alarm: int = 0
	var sprink: int = 0
	for i in n:
		no_alarm += _sleeper_trial(7000 + i, [])
		with_alarm += _sleeper_trial(7000 + i, [["smoke_alarm", Vector2i(14, 17)]])
		sprink += _sleeper_trial(7000 + i, [["sprinkler", Vector2i(12, 17)]])
	K.expect(f, no_alarm >= 1 and no_alarm <= int(0.6 * n), "a sleeper in a burning room, no alarm: %d/%d die (about 1 in 4)" % [no_alarm, n])
	K.expect(f, with_alarm == 0, "with a smoke alarm nobody dies (%d/%d)" % [with_alarm, n])
	K.expect(f, sprink == 0, "with a sprinkler nobody dies (%d/%d)" % [sprink, n])
	print("    fire longrun sleeper (n=%d): no alarm %d dead, alarm %d, sprinkler %d" % [n, no_alarm, with_alarm, sprink])