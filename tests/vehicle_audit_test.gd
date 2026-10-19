extends RefCounted
## Task 12b, the vehicle half of the visual audit (fast): over two minutes of play no folk stands inside a vehicle, no moving vehicle leaves the road, no two vehicles overlap.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []

func run() -> Array:
	fails = []
	K.game("classic")
	SimEnv.clock().advance_minutes(5 * 60)
	var r: Dictionary = K.audit(120.0, 1)
	print("  [vehicles] audit: %d samples, up to %d vehicles, folk in a vehicle %d, off road %d, overlaps %d, ghosted %d %s" % [r["samples"], r["max_vehicles"], r["folk_in_vehicle"], r["off_road"], r["overlaps"], r["ghosted"], str(r["detail"])])
	if int(r["max_vehicles"]) < 6:
		fails.append("the town has vehicles to audit (%d)" % int(r["max_vehicles"]))
	if int(r["folk_in_vehicle"]) > 0:
		fails.append("folk standing inside a vehicle: %d %s" % [int(r["folk_in_vehicle"]), str(r["detail"])])
	if int(r["off_road"]) > 0:
		fails.append("vehicles off the road: %d" % int(r["off_road"]))
	if int(r["overlaps"]) > 0:
		fails.append("vehicles overlapping: %d" % int(r["overlaps"]))
	K.Kit.teardown()
	return fails
