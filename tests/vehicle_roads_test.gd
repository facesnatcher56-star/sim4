extends RefCounted
## Task 12b: the road graph of the vehicle layer: frontages, lane geometry (right-hand traffic), routes between lots, path maths.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	K.game()
	var home: Dictionary = VehicleRoads.frontage("home")
	var cafe: Dictionary = VehicleRoads.frontage("cafe")
	_check(not home.is_empty() and not cafe.is_empty(), "lots have a frontage")
	_check(absf(float(home["lane_z"]) - (float(home["hy"]) + 3.0 - float(SysUtil.table("vehicles")["lane"]))) < 0.001 and float(home["lane_z"]) < float(home["hy"]) + 3.0, "the lane in front of a lot is on the lot side of the centre line")
	# right-hand traffic: the right of heading west is north, of heading east is south
	_check(VehicleRoads.right_of(Vector2(-1, 0)) == Vector2(0, -1) and VehicleRoads.right_of(Vector2(1, 0)) == Vector2(0, 1), "right of the heading")
	# a route from the home lot to the cafe: starts and ends in the lane heading west, every point on asphalt
	var r: Dictionary = VehicleRoads.lane_route(home, float(home["gate"]) - 3.0, cafe, float(cafe["gate"]) + 3.0)
	var path: VehiclePath = VehiclePath.make(r["pts"], 1.8)
	_check(path.length > 20.0, "route has length (%.0f)" % path.length)
	var w = WorldIface.world()
	var bad := 0
	var s := 0.0
	while s < path.length:
		var p: Vector2 = path.at(s)
		var f: String = w.get_floor(Vector2i(int(floorf(p.x)), int(floorf(p.y))))
		if f != "asphalt" and f != "crosswalk":
			bad += 1
		s += 0.5
	_check(bad == 0, "every point of the lane route is on the road (%d off)" % bad)
	# the start heads west
	_check(path.dir_at(0.1).x < -0.9, "the first leg heads west")
	# same block, further west: a straight run, no junction
	var st: Dictionary = VehicleRoads.lane_route(home, float(home["gate"]), home, float(home["gate"]) - 8.0)
	_check((st["visits"] as Array).is_empty(), "a short run west in the same block passes no junction")
	# the way back round the block: loops through junctions
	var loop: Dictionary = VehicleRoads.lane_route(home, float(home["gate"]), home, float(home["gate"]) + 3.0)
	_check((loop["visits"] as Array).size() >= 4, "going back east means round the block (%d junctions)" % (loop["visits"] as Array).size())
	# path maths
	var vp: VehiclePath = VehiclePath.make([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)], 2.0)
	_check(absf(vp.length - 20.0) < 1.5 and vp.length < 20.0, "rounded corner is a little shorter (%.2f)" % vp.length)
	_check(vp.at(0.0) == Vector2(0, 0) and vp.at(vp.length).distance_to(Vector2(10, 10)) < 0.01, "path ends")
	# bays are open ground inside lots
	var any_bay := 0
	for lot_id in Neighborhood.lot_ids():
		for bay in VehicleBays.of(str(lot_id)):
			any_bay += 1
			var rc: Rect2i = NeighborhoodLots.rect_of(str(lot_id))
			_check(rc.has_point(Vector2i(int((bay["pos"] as Vector2).x), int((bay["pos"] as Vector2).y))), "%s bay is inside the lot" % lot_id)
	var per: Array = []
	for lot_id2 in Neighborhood.lot_ids():
		per.append("%s=%d" % [lot_id2, VehicleBays.of(str(lot_id2)).size()])
	print("  [vehicles] %d bays over %d lots: %s" % [any_bay, Neighborhood.lot_ids().size(), ", ".join(per)])
	_check(any_bay >= 6, "the map has places to park (%d)" % any_bay)
	K.Kit.teardown()
	return fails
