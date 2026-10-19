extends RefCounted
## SLOW tier (name ends in _longrun_test): many game years of household chaos with the default Surprises setting. The player's real home
## (FULL: objects, leaks, roaches) and 10 far lots (STATISTICAL) are rolled together; the measured yearly rate per household must be close to
## the data targets (config.chaos.targets in data/incidents/07_chaos.json) and nothing may pile up. The roach rate is per MESSY household-year
## (exposure only counts messy homes) and runs a little above the base because summer is x1.5.

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
	for d in years * YEAR:
		for hr in 24:
			K.set_time(2 + d, hr)
			Incidents.on_hour()
		K.set_time(2 + d, 23, 30)
		Incidents.on_day()
		_tidy(objs)
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
	K.expect(f, Incidents.history(1000).size() <= int(IncidentDefs.cfg("history_cap", 200)), "history stays capped")
	print("    chaos longrun: %d years in %d ms: %s" % [years, Time.get_ticks_msec() - t0, "; ".join(report)])
	Weather.unforce()
	K.teardown()
	return f

## Once a day the household sorts everything out, so the next event is measured from a clean state (the rate check, not the player, is under test).
func _tidy(objs: Dictionary) -> void:
	for hid in ChaosState.leaks.keys():
		ChaosClock.stop_leak(int(hid), "someone")
	ChaosState.jobs.clear()
	ChaosClock.fix_all(1)
	ChaosState.pests.clear()
	DisasterState.lots.clear()
	for id in Hospital.patients.keys():
		Hospital.discharge(int(id))
	for id2 in ["sink", "stove", "counter"]:
		WorldIface.state_set(objs[id2], "dirtiness", 8.0)             # the home is always messy: the roach rate is per messy year
	ChaosClock.sync_markers(1)
