extends RefCounted
## Task 12b slow tier: the vehicle audit over twenty minutes of play at speed 1 and ten at speed 2, morning rush to the evening.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []

func run() -> Array:
	fails = []
	K.game("classic")
	SimEnv.clock().advance_minutes(60)
	var totals := {"folk_in_vehicle": 0, "off_road": 0, "overlaps": 0, "ghosted": 0}
	for pass_i in 2:
		var r: Dictionary = K.audit(600.0 if pass_i == 0 else 300.0, 1 + pass_i)
		print("  [vehicles] long audit pass %d: %d samples, up to %d vehicles, folk in a vehicle %d, off road %d, overlaps %d, ghosted %d %s" % [pass_i, r["samples"], r["max_vehicles"], r["folk_in_vehicle"], r["off_road"], r["overlaps"], r["ghosted"], str(r["detail"])])
		for k in totals:
			totals[k] += int(r[k])
	for k2 in totals:
		var allowed: int = 3 if k2 == "folk_in_vehicle" else 0      # a folk that appears (arrival, spawn) on the gate tile of a car standing in the gateway: a few samples in 15 minutes
		if int(totals[k2]) > allowed:
			fails.append("%s: %d (allowed %d)" % [k2, int(totals[k2]), allowed])
	K.Kit.teardown()
	return fails
