extends RefCounted
## Task 37 (data + headless sim): the junctions of the lattice differ. Traffic lights only on the main roads; stop and give-way signs on the side streets; uncontrolled
## junctions and mini roundabouts; zebra crossings only where people cross; every light has its own timing and they are not in step; a pedestrian phase where there is a
## crossing; quiet lights flash at night. A car at a stop sign stops, looks and goes when the gap is long enough, and the main road does not stop for it.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var ctl := VehicleControl.new()
	var nx: int = VehicleRoads.xs().size()
	var ny: int = VehicleRoads.ys().size()
	var kinds := {}
	var signals: Array = []
	var arms_total: int = 0
	var arms_zebra: int = 0
	for i in nx:
		for j in ny:
			var k: String = ctl.kind(i, j)
			kinds[k] = int(kinds.get(k, 0)) + 1
			if k == "signal":
				signals.append(Vector2i(i, j))
				_check(ctl.is_main_row(j) or ctl.is_main_col(i), "traffic lights only on a main road: junction %d,%d is a light" % [i, j])
			if k == "stop" or k == "giveway":
				_check(int(ctl.info(i, j)["minor"]) >= 0, "a sign junction %d,%d says which street gives way" % [i, j])
			_check(ctl.cause(i, j) != "", "junction %d,%d has a cause line" % [i, j])
			arms_total += 4
			arms_zebra += ctl.zebra_arms(i, j).size()
	print("  [junctions] %s; lights %d; zebra arms %d of %d" % [str(kinds), signals.size(), arms_zebra, arms_total])
	for k2 in ["signal", "stop", "giveway", "free", "roundabout"]:
		_check(int(kinds.get(k2, 0)) >= 1, "the town has at least one %s junction" % k2)
	_check(signals.size() >= 3 and signals.size() <= 9, "a handful of lights, not one at every junction (%d of %d)" % [signals.size(), nx * ny])
	_check(arms_zebra * 4 < arms_total, "painted crossings are on a minority of the arms (%d of %d)" % [arms_zebra, arms_total])
	for lot_id in ["school", "market"]:
		var fr: Dictionary = VehicleRoads.frontage(lot_id)
		var near: bool = false
		for i2 in nx:
			for j2 in ny:
				if j2 == int(fr["jr"]) and ctl.zebra_arms(i2, j2).size() > 0 and absf(VehicleRoads.junction_center(i2, j2).x - float(fr["gate"])) < 40.0:
					near = true
		_check(near, "a painted crossing near the %s" % lot_id)
	# timings differ
	var cycles := {}
	var offs := {}
	for s in signals:
		var d: Dictionary = ctl.info(s.x, s.y)
		cycles[snappedf(float(d["cycle"]), 0.1)] = true
		offs[snappedf(float(d["offset"]), 0.1)] = true
		_check(float(d["g_main"]) > float(d["g_side"]), "the main road has the longer green at %d,%d" % [s.x, s.y])
	_check(cycles.size() >= signals.size() - 1 and offs.size() >= signals.size() - 1, "every light has its own cycle and offset (%d cycles, %d offsets for %d lights)" % [cycles.size(), offs.size(), signals.size()])
	# are the lights in step? Over two minutes: how many of them show the same pair of states (north-south, east-west) at once
	var all_same: int = 0
	var mean_share: float = 0.0
	var n: int = 0
	for step in 240:
		var t: float = float(step) * 0.5
		var tally := {}
		for s2 in signals:
			var key: String = ctl.state(s2.x, s2.y, 0, t, 12.0) + "/" + ctl.state(s2.x, s2.y, 1, t, 12.0)
			tally[key] = int(tally.get(key, 0)) + 1
		var top: int = 0
		for key2 in tally:
			top = maxi(top, int(tally[key2]))
		if top == signals.size():
			all_same += 1
		mean_share += float(top) / float(maxi(signals.size(), 1))
		n += 1
	print("  [junctions] lights showing the same pair of states at once: on average %.0f%% of them, all of them in %.0f%% of the samples" % [100.0 * mean_share / float(n), 100.0 * float(all_same) / float(n)])
	_check(float(all_same) / float(n) < 0.12, "the lights are not in step (all alike in %.0f%% of the samples)" % [100.0 * float(all_same) / float(n)])
	# pedestrian phase and night flash
	var ped_found := false
	var flash_found := false
	for s3 in signals:
		var d2: Dictionary = ctl.info(s3.x, s3.y)
		if float(d2["ped"]) > 0.0:
			ped_found = true
			var saw := false
			for step2 in 400:
				var t2: float = float(step2) * 0.1
				if ctl.ped_phase(s3.x, s3.y, t2, 12.0):
					saw = true
					_check(ctl.state(s3.x, s3.y, 0, t2, 12.0) == "red" and ctl.state(s3.x, s3.y, 1, t2, 12.0) == "red", "both streets are red while people cross at %d,%d" % [s3.x, s3.y])
			_check(saw, "a light with a crossing has a pedestrian phase at %d,%d" % [s3.x, s3.y])
		if str(d2["class"]) == "minor":
			flash_found = true
			_check(ctl.state(s3.x, s3.y, int(d2["main"]), 5.0, 2.0) == "flash" and ctl.state(s3.x, s3.y, 1 - int(d2["main"]), 5.0, 2.0) == "stop", "a quiet light flashes amber on the main road and red on the side street at night (%d,%d)" % [s3.x, s3.y])
		else:
			_check(ctl.state(s3.x, s3.y, 0, 5.0, 2.0) in ["green", "red"], "the big crossing keeps its cycle at night")
	_check(ped_found and flash_found, "there are lights with a crossing and quiet lights")
	_stop_sign_behaviour()
	return fails


## A car on the side street at the stop sign of junction (1,1) stops at the line, looks, and goes when the main street is clear; the main street does not stop.
func _stop_sign_behaviour() -> void:
	var sim := VehicleSim.new(SysUtil.table("vehicles"))
	sim.hour = 12.0
	var ctl: VehicleControl = sim.control
	var ji := Vector2i(2, 2)             # a stop sign: the side street (north-south) gives way to the main road
	_check(ctl.kind(ji.x, ji.y) == "stop" and int(ctl.info(ji.x, ji.y)["minor"]) == 1, "junction 2,2 is a stop sign with the north-south street giving way")
	var c: Vector2 = VehicleRoads.junction_center(ji.x, ji.y)
	var side := VehiclePath.make([Vector2(c.x - 1.0, c.y - 40.0), Vector2(c.x - 1.0, c.y + 40.0)], 0.0)
	var main := VehiclePath.make([Vector2(c.x + 60.0, c.y - 1.0), Vector2(c.x - 60.0, c.y - 1.0)], 0.0)
	# 1. nobody on the main street: it stops, then goes
	var a: Dictionary = sim.add("car", "", side, {"visits": [[ji.x, ji.y, VehicleRoads.S, VehicleRoads.S]], "s": 10.0})
	var min_v_at_line: float = 99.0
	var stopped_since: float = -1.0
	var went_at: float = -1.0
	for _s in 900:
		sim.step(0.05)
		var gap_to_line: float = float((a["visits"] as Array)[0]["s_line"]) - (float(a["s"]) + float(a["len"]) * 0.5) if not (a["visits"] as Array).is_empty() else -9.0
		if gap_to_line < 1.2 and gap_to_line > -0.2:
			min_v_at_line = minf(min_v_at_line, float(a["v"]))
			if float(a["v"]) < 0.1 and stopped_since < 0.0:
				stopped_since = sim.vt
		if stopped_since >= 0.0 and went_at < 0.0 and float(a["v"]) > 1.0:
			went_at = sim.vt
		if float(a["s"]) > 60.0:
			break
	_check(min_v_at_line < 0.1, "the car stops at the stop sign (slowest %.2f m/s)" % min_v_at_line)
	_check(went_at > 0.0 and went_at - stopped_since >= 0.8, "it looks for a moment before it goes (%.1f s)" % (went_at - stopped_since))
	_check(float(a["s"]) > 50.0, "and then it drives on across the main road")
	# 2. a car on the main street arrives together with it: the side street waits, the main street does not slow down
	sim = VehicleSim.new(SysUtil.table("vehicles"))
	sim.hour = 12.0
	var b: Dictionary = sim.add("car", "", side, {"visits": [[ji.x, ji.y, VehicleRoads.S, VehicleRoads.S]], "s": 22.0})
	var m: Dictionary = sim.add("car", "", main, {"visits": [[ji.x, ji.y, VehicleRoads.W, VehicleRoads.W]], "s": 28.0})
	m["v"] = 7.0
	var m_min: float = 99.0
	var overlap: bool = false
	var b_first: bool = false
	for _s2 in 900:
		sim.step(0.05)
		if float(m["s"]) < 60.0 and float(m["s"]) > 31.0:
			m_min = minf(m_min, float(m["v"]))
		if VehicleSim.overlaps(b, m):
			overlap = true
		if float(b["s"]) > 41.0 and float(m["s"]) < 58.0:
			b_first = true
		if float(b["s"]) > 60.0 and float(m["s"]) > 60.0:
			break
	_check(not overlap, "the side street car and the main street car never touch")
	_check(m_min > 3.0, "the main street has priority: it does not stop for the stop sign car (slowest %.1f m/s)" % m_min)
	_check(not b_first, "the side street car waits until the main street car is across")
