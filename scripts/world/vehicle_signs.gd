class_name VehicleSigns
extends RefCounted
## What a vehicle does at a junction that is not a cycling light (task 37, data/junctions.json `causes`): stop sign, give-way sign, uncontrolled junction, mini
## roundabout and the night flash of a quiet light. Plain functions over VehicleSim (headless-testable). Each returns the speed limit this junction puts on the vehicle.
## The cause of every behaviour is one line in the data and here:
##   stop      a car waits at a stop sign because cross traffic has priority; it stops, looks for look_s, and goes when the next car on the main street is more than gap_s
##             seconds from the crossing and nobody is in it.
##   yield     a car slows at a give-way sign because the other street has priority; it only stops when a car there would reach the crossing within gap_s seconds.
##   free      at an uncontrolled junction cars slow down and the one that arrived first goes first (VehicleSim._box_conflict, older id), because nothing says otherwise.
##   round     a car entering a mini roundabout gives way to a car already inside and takes the island slowly.
##   flash     a quiet light at night flashes amber on the main road (slow down, look: the same creep as a dead light) and red on the side street (it is a stop sign then).


## Is the crossing free for a vehicle from the side street: nobody inside it, nobody on the other street closer than `gap_s` seconds (at least 2.5 m/s) to it?
static func gap_clear(sim: VehicleSim, v: Dictionary, vis: Dictionary, gap_s: float) -> bool:
	for u in sim.vehicles:
		if u == v or str(u["state"]) == "dead" or str(u["state"]) == "parked":
			continue
		var uv: Array = u["visits"]
		if uv.is_empty():
			continue
		var w: Dictionary = uv[0]
		if int(w["i"]) != int(vis["i"]) or int(w["j"]) != int(vis["j"]) or int(w["axis"]) == int(vis["axis"]):
			continue
		var dist: float = float(w["s_line"]) - (float(u["s"]) + float(u["len"]) * 0.5)
		if dist <= 0.3:
			if float(u["s"]) - float(u["len"]) * 0.5 < float(w["s_clear"]):
				return false                                        # it is in the crossing now
			continue
		if dist < 60.0 and dist / maxf(float(u["v"]), 2.5) < gap_s:
			return false                                            # it will be at the crossing before I am across
	return true


static func limit(sim: VehicleSim, v: Dictionary, vis: Dictionary, d: float, st: String) -> float:
	var dd: float = maxf(d, 0.0)
	var key := "%d,%d" % [int(vis["i"]), int(vis["j"])]
	var t: Dictionary = sim.control.t
	match st:
		"stop", "yield":
			if str(v.get("sign_ok", "")) == key:
				return INF                                          # looked and went: not asked again until it has left this junction
			if d <= -0.4:
				return INF
			var is_stop: bool = st != "yield"
			var cf: Dictionary = t.get("stop" if is_stop else "giveway", {})
			var gap_s: float = float(cf.get("gap_s", 3.0))
			if is_stop:
				if d > 7.0:
					return INF
				if d < 1.0 and float(v["v"]) < 0.3:
					if not v.has("sign_since"):
						v["sign_since"] = sim.vt
					if sim.vt - float(v["sign_since"]) >= float(cf.get("look_s", 0.9)) and gap_clear(sim, v, vis, gap_s):
						v["sign_ok"] = key
						v.erase("sign_since")
						return INF
				return sim._brake(dd)
			# give way: roll up slowly, stop only if the other street is not clear
			if d > 7.0:
				return INF
			if d < 1.5 and gap_clear(sim, v, vis, gap_s):
				v["sign_ok"] = key
				return INF
			return minf(sim._brake(dd), float(cf.get("creep", 2.6)))
		"flash":
			if d > -0.4 and d < 7.0:
				return maxf(sim._brake(dd) * 0.6, float((sim.cfg.get("speeds", {}) as Dictionary).get("creep", 1.6)) * 2.0)
		"free":
			if d > -0.4 and d < 6.0:
				return float((t.get("free", {}) as Dictionary).get("creep", 3.4))
		"round":
			var sp: float = float((t.get("roundabout", {}) as Dictionary).get("speed", 3.4))
			if d < 8.0:
				return sp                                           # the island makes everyone take it slowly; who is inside goes first (box conflict)
	return INF
