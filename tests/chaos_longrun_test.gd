extends RefCounted
## SLOW tier (name ends in _longrun_test): many game years of household chaos with the default Surprises setting. The player's real home
## (FULL: objects, leaks, roaches) and 10 far lots (STATISTICAL) are rolled together; the measured yearly rate per household must be close to
## the data targets (config.chaos.targets in data/incidents/07_chaos.json) and nothing may pile up. The roach rate is per MESSY household-year
## (exposure only counts messy homes) and runs a little above the base because summer is x1.5. The stub clock walks through all four seasons
## (7 days each), the test checks that, that the summer boost is exactly x1.5 in the dice, and splits the measured roach events by season.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	var h: Dictionary = C.setup()
	StoryPacing.enabled = false
	Weather.force("sunny")
	Story.generate_townies()
	for n in range(1, 11):
		for _i in 2:
			var t: Dictionary = Story.add_townie()
			t["lot"] = n
	var objs: Dictionary = h["objs"]
	var years: int = TestFixture.pick(24, 12)
	var t0: int = Time.get_ticks_msec()
	var by_season := {}                                   # season -> {days, events, exposure}
	for d in years * YEAR:
		var roach0: Dictionary = Incidents.stat("roach_infestation").duplicate()
		for hr in 24:
			K.set_time(2 + d, hr)
			Incidents.on_hour()
		K.set_time(2 + d, 23, 30)
		Incidents.on_day()
		_tidy(objs)
		var roach1: Dictionary = Incidents.stat("roach_infestation")
		var sn: String = Seasons.season_at_day(2 + d)
		var row: Dictionary = by_season.get(sn, {"days": 0, "events": 0, "exposure": 0.0})
		row["days"] = int(row["days"]) + 1
		row["events"] = int(row["events"]) + int(roach1["triggered"]) - int(roach0["triggered"])
		row["exposure"] = float(row["exposure"]) + float(roach1["exposure"]) - float(roach0["exposure"])
		by_season[sn] = row
		if ChaosState.leaks.size() > 1 or ChaosState.jobs.size() > 3:
			f.append("chaos state piles up: %d leaks, %d jobs" % [ChaosState.leaks.size(), ChaosState.jobs.size()])
			break
	var targets: Dictionary = ChaosState.cfg("targets")
	var report: Array = []
	for id in ["burst_pipe", "toilet_overflow", "appliance_breakdown", "roach_infestation"]:
		var c: Dictionary = Incidents.stat(id)
		var r: float = Incidents.measured_rate(id)
		var target: float = float(targets[id])
		var hi: float = 1.45 if id == "roach_infestation" else 1.0          # summer x1.5 on roaches
		var ok: bool = int(c["triggered"]) >= 15 and r >= target * 0.7 and r <= target * hi * 1.3
		K.expect(f, ok, "%s: %d events in %.0f household-years = %.3f/yr (target %.2f%s)" % [id, int(c["triggered"]), float(c["exposure"]), r, target, " per messy year, x1.5 in summer" if id == "roach_infestation" else ""])
		report.append("%s %d/%.0fy=%.3f" % [id, int(c["triggered"]), float(c["exposure"]), r])
	_seasons(f, by_season, objs)
	K.expect(f, Incidents.history(1000).size() <= int(IncidentDefs.cfg("history_cap", 200)), "history stays capped")
	print("    chaos longrun: %d years in %d ms: %s" % [years, Time.get_ticks_msec() - t0, "; ".join(report)])
	Weather.unforce()
	K.teardown()
	return f

## The seasons really change in the stub clock, the summer boost is x1.5 in the dice, and summer carries about a third of the roach events
## (a quarter of the days at x1.5 against the rest at x1 is 1/3 of the events).
func _seasons(f: Array, by_season: Dictionary, objs: Dictionary) -> void:
	K.expect(f, by_season.size() == 4, "all four seasons came by in the stub clock: %s" % str(by_season.keys()))
	var subj := IncidentSubject.of_household(1)
	var rates := {}
	for d in range(100, 128):                             # one full year of day numbers
		var sn: String = Seasons.season_at_day(d)
		if not rates.has(sn):
			K.set_time(d, 12)
			WorldIface.state_set(objs["sink"], "dirtiness", 8.0)
			ChaosState.pests.clear()
			rates[sn] = Incidents.effective_rate("roach_infestation", subj)
	K.expect(f, rates.size() == 4 and absf(float(rates["summer"]) / float(rates["winter"]) - 1.5) < 0.001, "summer roach risk is x1.5 winter's (%.2f vs %.2f a year)" % [float(rates.get("summer", 0)), float(rates.get("winter", 0))])
	var total := 0
	for sn2 in by_season:
		total += int(by_season[sn2]["events"])
	var share: float = float(by_season.get("summer", {}).get("events", 0)) / maxf(float(total), 1.0)
	var line: Array = []
	for sn3 in ["spring", "summer", "autumn", "winter"]:
		var r: Dictionary = by_season.get(sn3, {"days": 0, "events": 0, "exposure": 0.0})
		line.append("%s %d ev/%.0fy=%.2f" % [sn3, int(r["events"]), float(r["exposure"]), float(r["events"]) / maxf(float(r["exposure"]), 0.0001)])
	K.expect(f, total >= 15 and share >= 0.2 and share <= 0.5, "summer carries %.0f percent of roach events (expected about 33): %s" % [share * 100.0, "; ".join(line)])
	print("    roach events by season: %s" % "; ".join(line))

## Once a day the household sorts everything out, so the next event is measured from a clean state (the rate check, not the player, is under test).
func _tidy(objs: Dictionary) -> void:
	for hid in ChaosState.leaks.keys():
		ChaosClock.stop_leak(int(hid), "someone")
	ChaosState.jobs.clear()
	ChaosClock.fix_all(1)
	ChaosState.pests.clear()
	ChaosState.gas.clear()                                          # the 07b incidents roll too: put their state back as well
	ChaosState.theft.clear()
	DisasterState.lots.clear()
	for id in Hospital.patients.keys():
		Hospital.discharge(int(id))
	for id2 in ["sink", "stove", "counter"]:
		WorldIface.state_set(objs[id2], "dirtiness", 8.0)             # the home is always messy: the roach rate is per messy year
	ChaosClock.sync_markers(1)
