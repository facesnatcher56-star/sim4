extends RefCounted
## Perf probe: a 15-storey tower on the full 160x120 map. Route costs (budgets: cached path_length < 0.2 ms, uncached cross-level < 5 ms),
## save size, and the map without any tower is not slower for ordinary ground paths. Prints the numbers.

const Kit := preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	var W := Kit.world()
	Neighborhood.start_game("classic")
	var park: Dictionary = W.regions.by_lot("park")
	var base: Vector2i = (park["rect"] as Rect2i).position
	var foot := Rect2i(base.x + 8, base.y + 4, 16, 12)
	W.regions.enforce = false          # a loader placing a building anywhere on the map
	var bid := Kit.add_tower(W, foot, 15, true)
	W.regions.enforce = true
	_check(W.levels.level_count(bid) == 15, "15 floors")
	var far := Vector3i(3, 3, 0)
	var top := Vector3i(foot.position.x + 8, foot.position.y + 8, 14)
	W.route_length(far, top)          # warm-up: builds the street graph once
	W.nav.touch_tile(Vector2i(0, 0))
	var tn := Time.get_ticks_usec()
	W.path_length(Vector2i(3, 3), Vector2i(foot.end.x - 3, foot.position.y + 5))
	print("  [levels] (the cold ground leg alone: %.2f ms)" % (float(Time.get_ticks_usec() - tn) / 1000.0))
	var tb := Time.get_ticks_usec()
	W.router.reset()
	W.portals.nodes_of(bid)
	W.router._reach(bid, 0)
	print("  [levels] (portal ends + reach for the tower: %.2f ms)" % (float(Time.get_ticks_usec() - tb) / 1000.0))
	var tl := Time.get_ticks_usec()
	for i in 200:
		LevelPaths.path_len(W, 14, Vector2i(foot.position.x + 2, foot.position.y + 6), Vector2i(foot.end.x - 3, foot.position.y + 5), foot)
	print("  [levels] (one tile A* on a 16x12 floor: %.3f ms)" % (float(Time.get_ticks_usec() - tl) / 1000.0 / 200.0))
	# uncached cross-level routes (router + nav caches dropped before each)
	var results: Dictionary = {}
	for mode in ["warm nav", "cold nav"]:
		var worst := 0.0
		var total := 0.0
		var n := 0
		for tx in range(6):
			for lvl in [3, 7, 10, 14]:
				W.router.clear_paths()
				if mode == "cold nav":
					W.nav.touch_tile(Vector2i(0, 0))        # drops the nav caches too (the street graph stays built)
				var to := Vector3i(foot.position.x + 5 + tx, foot.position.y + 8, lvl)
				var t0 := Time.get_ticks_usec()
				var c: float = W.route_length(far, to)
				var ms := float(Time.get_ticks_usec() - t0) / 1000.0
				total += ms
				worst = maxf(worst, ms)
				n += 1
				_check(c > 0.0, "reachable floor %d" % lvl)
		results[mode] = worst
		results[mode + " avg"] = total / n
		print("  [levels] uncached map -> floors 3..14 of a 15-storey tower, router caches dropped, %s: avg %.2f ms, worst %.2f ms (%d routes)" % [mode, total / n, worst, n])
	print("  [levels] search stats for floor 14: %s" % str(W.router.last_stats))
	_check(float(results["warm nav avg"]) < 3.0 and float(results["warm nav"]) < 8.0, "uncached cross-level route is a few ms at most with a warm street graph (avg %.2f, worst %.2f: the first one also builds the tower's portal graph)" % [float(results["warm nav avg"]), float(results["warm nav"])])
	_check(float(results["cold nav"]) < 12.0, "even with every street cache cold (%.2f)" % float(results["cold nav"]))
	# stairs-only (lift out of order): a long chain of floors
	for o in W.objects_of_def("elevator"):
		W.set_object_state(o.id, "out_of_order", true)
	W.router.clear_paths()
	var t1 := Time.get_ticks_usec()
	var c2: float = W.route_length(Vector3i(foot.position.x + 4, foot.position.y + 8, 0), top)
	var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
	print("  [levels] stairs only, ground -> floor 14: %.2f ms, cost %.0f" % [ms2, c2])
	_check(c2 > 0.0 and ms2 < 25.0, "a 14-flight climb is planned in %.2f ms" % ms2)
	for o in W.objects_of_def("elevator"):
		W.set_object_state(o.id, "out_of_order", false)
	# route entries (the real walk) once
	W.router.clear_paths()
	var t2 := Time.get_ticks_usec()
	var r: Array = W.find_route(far, top)
	var ms3 := float(Time.get_ticks_usec() - t2) / 1000.0
	print("  [levels] find_route map -> floor 14 (%d entries): %.2f ms" % [r.size(), ms3])
	_check(not r.is_empty() and r[-1] == top, "route reaches the top")
	# cached length
	W.route_length(far, top)
	var t3 := Time.get_ticks_usec()
	for i in 2000:
		W.route_length(far, top)
	var per := float(Time.get_ticks_usec() - t3) / 1000.0 / 2000.0
	print("  [levels] cached route_length: %.4f ms per call" % per)
	_check(per < 0.2, "cached path_length under 0.2 ms (%.4f)" % per)
	var t4 := Time.get_ticks_usec()
	for i in 2000:
		WorldIface.path_length(Vector2i(3, 3), Vector2i(foot.position.x + 8, foot.position.y + 8), 0, 14)
	var per2 := float(Time.get_ticks_usec() - t4) / 1000.0 / 2000.0
	print("  [levels] WorldIface.path_length (autonomy) cached: %.4f ms per call" % per2)
	_check(per2 < 0.2, "autonomy distance cached under 0.2 ms (%.4f)" % per2)
	# ground paths unchanged by the tower
	W.nav.touch_tile(Vector2i(0, 0))
	var t5 := Time.get_ticks_usec()
	var gp := W.path_length(Vector2i(3, 3), Vector2i(150, 100))
	var ms5 := float(Time.get_ticks_usec() - t5) / 1000.0
	_check(gp > 0.0, "ground path across the map still works")
	print("  [levels] ground path across the map with the tower present: %.2f ms (%d steps)" % [ms5, int(gp)])
	var layers_tiles := 0
	for lay in W.levels.layers.values():
		layers_tiles += (lay as LevelLayer).floors.size()
	var kb := JSON.stringify(W.save_dict(false)["levels"]).length() / 1024
	print("  [levels] tower memory: %d floor tiles in %d layers, levels block in the save %d KB" % [layers_tiles, W.levels.layers.size(), kb])
	W.reset()
	return fails
