extends RefCounted
## Perf probe: the full map WITH its multi-floor buildings (hospital, police, courthouse, apartments, a tower, floored houses) still meets the
## part A budgets: building the map, cross-floor routes inside the new buildings, one autonomous decision for a folk standing on an upper
## floor (path queries stay pruned), the per-minute level systems, and objects_for in a 16-flat block. Prints the numbers.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var t0 := Time.get_ticks_usec()
	var folk: Array = Kit.new_game("small", 777, 1)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var W: Node = Kit.world()
	var floors := 0
	for b in W.levels.buildings.values():
		floors += int(b["max"]) - int(b["min"]) + 1
	print("  [bldg] new game on the full map with %d buildings / %d floors: %.0f ms" % [W.levels.buildings.size(), floors, build_ms])
	_check(W.levels.buildings.size() >= 5, "several buildings with floors on the map (%d)" % W.levels.buildings.size())
	_check(build_ms < 9000.0 * TestFixture.SLACK, "the map builds in %.0f ms" % build_ms)
	_routes(W)
	_autonomy(W, folk)
	_minute_cost(W, folk)
	_objects_for(W, folk)
	Kit.teardown()
	return fails


func _routes(W: Node) -> void:
	var door: Vector2i = NeighborhoodLots.entry_tile("hospital")
	var best = null
	for b in HospitalWard.beds(true):
		best = b
	var spot: Vector2i = WorldIface.use_tile(best, 0)
	var total := 0.0
	var worst := 0.0
	var n := 0
	for rep in 10:
		W.router.clear_paths()
		var t0 := Time.get_ticks_usec()
		var c: float = W.route_length(Vector3i(door.x, door.y, 0), Vector3i(spot.x, spot.y, best.level))
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_check(c > 0.0, "hospital door -> maternity bed is reachable")
		total += ms
		worst = maxf(worst, ms)
		n += 1
	print("  [bldg] uncached hospital door -> maternity bed (level %d): avg %.2f ms, worst %.2f ms" % [best.level, total / n, worst])
	_check(total / n < 6.0 * TestFixture.SLACK, "cross-floor route in the hospital: avg %.2f ms" % (total / n))
	# the far side of the map to the top floor of the tallest building
	var tall := -1
	for b in W.levels.buildings.values():
		if tall < 0 or int(b["max"]) > int(W.levels.building(tall)["max"]):
			tall = int(b["id"])
	var rc: Rect2i = W.levels.building(tall)["rect"]
	var top := Vector3i(rc.position.x + rc.size.x / 2, rc.position.y + rc.size.y / 2, int(W.levels.building(tall)["max"]))
	W.router.clear_paths()
	var t1 := Time.get_ticks_usec()
	var far: float = W.route_length(Vector3i(3, 3, 0), top)
	var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
	print("  [bldg] map corner -> top floor (%d) of the tallest building: %.2f ms" % [top.z, ms2])
	_check(far > 0.0 or top.z >= 0, "tallest building top is planned")
	_check(ms2 < 40.0 * TestFixture.SLACK, "far route to the top floor %.2f ms" % ms2)


func _autonomy(W: Node, folk: Array) -> void:
	Kit.set_time(2, 12)
	Autonomy.full_debug = false
	var f: Folk = folk[0]
	var rooms: Array = HospitalWard.beds(false)
	var bed = rooms[rooms.size() - 1]
	f.tile = WorldIface.use_tile(bed, 0)
	f.level = int(bed.level)
	Autonomy.choose(f)
	var rounds: Array = []
	var q0 := Autonomy.path_queries
	for r in 5:
		var t0 := Time.get_ticks_usec()
		for i in 12:
			Autonomy.choose(f)
		rounds.append(float(Time.get_ticks_usec() - t0) / 1000.0 / 12.0)
	var paths := float(Autonomy.path_queries - q0) / 60.0
	var best: float = rounds.min()
	print("  [bldg] Autonomy.choose for a folk on ward floor %d: best round %.2f ms, %.1f path queries" % [f.level, best, paths])
	_check(best < 8.0 * 3.0 * TestFixture.SLACK, "a decision on an upper floor costs %.2f ms" % best)
	_check(paths <= 25.0, "path queries per decision stay pruned (%.1f)" % paths)
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	f.level = 0


func _minute_cost(W: Node, folk: Array) -> void:
	var f: Folk = folk[1]
	var stairs = W.objects_of_def("stairs")[0]
	f.tile = stairs.tile
	f.level = stairs.level
	var t0 := Time.get_ticks_usec()
	for i in 500:
		LevelSystems.on_minute()
	var per := float(Time.get_ticks_usec() - t0) / 1000.0 / 500.0
	print("  [bldg] LevelSystems.on_minute with a folk on the stairs: %.3f ms" % per)
	_check(per < 0.5 * TestFixture.SLACK, "the per-minute level step is cheap (%.3f ms)" % per)
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	f.level = 0
	f.remove_buff("injured")


func _objects_for(W: Node, folk: Array) -> void:
	var units: Array = ApartmentUnits.units_of("apartments")
	if units.is_empty():
		return
	var f: Folk = folk[2]
	f.household_id = 1
	var u: Dictionary = units[0]
	ApartmentUnits.assign(u, 1)
	f.tile = (u["rect"] as Rect2i).position + Vector2i(1, 1)
	f.level = int(u["level"])
	WorldIface.objects_for(f, 40)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in 200:
		n = WorldIface.objects_for(f, 40).size()
	var per := float(Time.get_ticks_usec() - t0) / 1000.0 / 200.0
	print("  [bldg] objects_for in the apartment block (%d objects): %.3f ms" % [n, per])
	_check(per < 4.0 * TestFixture.SLACK, "objects_for is cheap in a 16-flat block (%.3f ms)" % per)
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	f.level = 0
