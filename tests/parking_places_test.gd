extends RefCounted
## Task 42 (fast): every place a car can stand is real (driveway, marked bay, lay-by), on three seeds; every parked vehicle of the layer stands inside one; none touches a footway,
## a crossing, a junction, a road lane or the lawn; houses have a driveway where the lot has room.

const K = preload("res://tests/vehicle_kit.gd")
const P = preload("res://tests/parking_kit.gd")

var fails: Array = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func run() -> Array:
	fails = []
	var homes: int = 0
	var homes_with: int = 0
	var kinds: Dictionary = {}
	for sd in [1, 2, 3]:
		K.game("classic", sd)
		var w = WorldIface.world()
		for lot_id in Neighborhood.lot_ids():
			var rg: Dictionary = w.regions.by_lot(str(lot_id))
			var places: Array = VehicleBays.of(str(lot_id))
			var is_home: bool = str(rg.get("kind", "")) in ["home", "townie_home"]
			if is_home:
				homes += 1
				if not places.is_empty():
					homes_with += 1
			for pl in places:
				kinds[str(pl["kind"])] = int(kinds.get(str(pl["kind"]), 0)) + 1
				_check_place(w, str(lot_id), pl, sd)
			_check_pairs(places, str(lot_id), sd)
	print("  [parking] places by kind %s, homes with a place %d / %d" % [str(kinds), homes_with, homes])
	_check(int(kinds.get("driveway", 0)) >= 6, "houses have driveways (%s)" % str(kinds))
	_check(int(kinds.get("bay", 0)) >= 30, "forecourts have marked bays (%s)" % str(kinds))
	_check(homes_with >= homes - 1, "every house with room has a place of its own (%d / %d)" % [homes_with, homes])
	# the vehicle layer: every parked vehicle stands in a place, in the right way (a day on three seeds: tests/parking_longrun_test.gd)
	var r: Dictionary = P.layer_run(1, [11, 20], 8.0)
	print("  [parking] layer, seed 1: %d parked-car samples, %d outside a place" % [int(r["seen"]), int(r["outside"])])
	fails.append_array(r["fails"])
	_check(int(r["seen"]) >= 8, "the layer parks cars (%d)" % int(r["seen"]))
	K.Kit.teardown()
	return fails


func _check_place(w, lot_id: String, pl: Dictionary, sd: int) -> void:
	var rc: Rect2 = pl["rect"]
	var tag: String = "seed %d %s %s" % [sd, lot_id, str(pl["kind"])]
	for p in P.footprint(pl["pos"], pl["face"]):
		var pp: Vector2 = p
		_check(rc.grow(0.05).has_point(pp), "%s: the car footprint %s is inside its marked area %s" % [tag, str(pp), str(rc)])
		var t := Vector2i(int(floorf(pp.x)), int(floorf(pp.y)))
		var fl: String = w.get_floor(t)
		_check(not (fl in ["sidewalk", "crosswalk", "asphalt", "lawn", "grass", "water", ""]), "%s: footprint tile %s is %s" % [tag, str(t), fl])
		_check(VehicleRoads.junction_at_point(pp) == Vector2i(-1, -1), "%s: footprint inside a junction" % tag)
		_check(w.object_at(t) == null, "%s: an object stands in the car tile %s" % [tag, str(t)])
	if str(pl["kind"]) == "driveway":                  # the front fence is open where the drive goes through
		for y in range(int(rc.position.y) + 1, int(rc.end.y)):
			for x in range(int(rc.position.x), int(rc.end.x)):
				_check(w.wall_at(Vector3i(x, y, 0)) == "", "%s: a wall still crosses the drive at %d,%d" % [tag, x, y])
	# the dropped kerb is the only way over the footway and it is on the lot's own frontage
	var kerb: Rect2 = pl["kerb"]
	_check(float(NeighborhoodLots.rect_of(lot_id).end.y) == kerb.position.y, "%s: the dropped kerb is on the lot's frontage" % tag)


func _check_pairs(places: Array, lot_id: String, sd: int) -> void:
	for i in places.size():
		for j in range(i + 1, places.size()):
			var a: Dictionary = places[i]
			var b: Dictionary = places[j]
			_check(not (a["rect"] as Rect2).grow(-0.05).intersects((b["rect"] as Rect2).grow(-0.05)), "seed %d %s: places %d and %d overlap" % [sd, lot_id, i, j])
