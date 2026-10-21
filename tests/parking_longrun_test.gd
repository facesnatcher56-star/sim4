extends RefCounted
## Task 42 (slow): across three seeds and a game day (a sample every three hours, each a short run of the vehicle layer) every parked vehicle stands inside a driveway, a marked bay or a lay-by,
## with its whole footprint on paved ground and 0 overlaps with footway, crossing, junction or lane tiles; the layer parks cars at houses too.

const P = preload("res://tests/parking_kit.gd")

var fails: Array = []


func run() -> Array:
	fails = []
	var drive: int = 0
	for sd in [1, 2, 3]:
		var r: Dictionary = P.layer_run(sd, [0, 3, 6, 9, 12, 15, 18, 21], 14.0)
		print("  [parking] seed %d: %d parked-car samples over a day, %d at driveways, %d outside a place" % [sd, int(r["seen"]), int(r["parked_at_driveway"]), int(r["outside"])])
		fails.append_array(r["fails"])
		drive += int(r["parked_at_driveway"])
		if int(r["seen"]) < 20:
			fails.append("seed %d: the layer parks cars all day (%d)" % [sd, int(r["seen"])])
	if drive < 3:
		fails.append("cars park in driveways (%d samples)" % drive)
	return fails
