extends RefCounted
## Pathfinding budgets on the big map (WorldNav): cross-lot path_length, full find_path, in-lot lookups, unreachable targets.
## Timings are generous multiples of the measured values (the machine may be busy); the printed numbers are the real ones.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _avg_ms(n: int, f: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call(i)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)

func run() -> Array:
	fails = []
	Kit.new_game("small")
	var W: Node = Kit.world()
	var lots: Array = ["school", "library", "office", "gym", "cafe", "market", "park", "townie_c", "home", "townie_a", "townie_b"]
	var doors: Array = []
	for l in lots:
		doors.append(Neighborhood.entry_tile(l))
	# every ordered pair of doors, cold (cache cleared before each batch) and warm
	var pairs: Array = []
	for i in doors.size():
		for j in doors.size():
			if i != j:
				pairs.append([doors[i], doors[j]])
	W.nav.reset()
	var cold: float = _avg_ms(pairs.size(), func(k): W.path_length(pairs[k][0], pairs[k][1]))
	var warm: float = _avg_ms(pairs.size(), func(k): W.path_length(pairs[k][0], pairs[k][1]))
	# cross-lot lengths with the street legs already cached (same start tiles, new pairs of ribbon tiles): a different
	# destination in a lot we have left before
	var home: Vector2i = Neighborhood.entry_tile("home")
	var cafe_tiles: Array = []
	var crc: Rect2i = Neighborhood.rect_of("cafe")
	for dx in range(2, 12):
		cafe_tiles.append(crc.position + Vector2i(dx, 14))
	W.path_length(home, cafe_tiles[0])
	var mixed: float = _avg_ms(cafe_tiles.size(), func(k): W.path_length(home, cafe_tiles[k]))
	var full: float = _avg_ms(20, func(k): W.find_path(doors[k % doors.size()], doors[(k + 5) % doors.size()]))
	W.nav.reset()
	var full_cold: float = _avg_ms(1, func(_k): W.find_path(home, Neighborhood.entry_tile("cafe")))
	# in-lot lengths: what autonomy asks for (folk tile -> object use tiles of its own lot)
	var hrc: Rect2i = Neighborhood.rect_of("home")
	var objs: Array = W.objects_in_lot_of(home, 40.0)
	var inlot: float = _avg_ms(maxi(objs.size(), 1), func(k): W.path_length(home, objs[k % objs.size()].tile))
	# unreachable
	var green: Rect2i = W.regions.by_lot("green")["rect"]
	var pond := green.position + Vector2i(14, 10)
	var unreach: float = _avg_ms(5, func(_k): W.path_length(home, pond))
	print("  [perf] path_length door->door cold %.3f ms, warm %.4f ms, new dest in a known lot %.3f ms; find_path %.3f ms (cold first %.2f ms); in-lot (%d objs) %.3f ms; unreachable %.3f ms" % [cold, warm, mixed, full, full_cold, objs.size(), inlot, unreach])
	_check(cold < 2.0 * TestFixture.SLACK, "cold cross-lot path_length stays small (%.3f ms)" % cold)
	_check(warm < 0.2 * TestFixture.SLACK, "cached path_length < 0.2 ms (%.4f ms)" % warm)
	_check(mixed < 1.0 * TestFixture.SLACK, "path_length to a new tile of a known lot < 1 ms (%.3f ms)" % mixed)
	_check(full < 5.0 * TestFixture.SLACK and full_cold < 40.0 * TestFixture.SLACK, "full find_path < 5 ms (%.3f ms, cold %.2f ms)" % [full, full_cold])
	_check(inlot < 2.0 * TestFixture.SLACK, "in-lot path_length is cheap (%.3f ms)" % inlot)
	_check(unreach < 5.0 * TestFixture.SLACK, "unreachable targets fail fast (%.3f ms)" % unreach)
	if not TestFixture.fast:
		_tick_cost()          # before / after comparison (slow tier only: ~2.5 s)
	Kit.teardown()
	return fails

## Game-minute cost with 3 player folk out in three venues + the crowds (~40 NPCs): with the portal graph + autonomy budget
## (after) against plain windowed A* and no budget (before). Printed only; the test just guards against a blow-up.
func _tick_cost() -> void:
	var rows: Array = []
	for mode in ["before", "after"]:
		WorldNav.enabled = mode == "after"
		Autonomy.max_scored = 120 if mode == "after" else 1000000
		var folk: Array = Kit.new_game("small")
		Kit.set_time(2, 12)
		var spots := ["cafe", "market", "gym"]
		for i in 3:
			Neighborhood.travel([folk[i].id], spots[i], {"instant": true, "free": true, "quiet": true})
		Kit.run(12)
		var npcs: int = Crowd.npc_ids().size()
		var cands: int = Autonomy.gather(folk[0]).size()
		var c0 := Time.get_ticks_usec()
		for k in 6:
			Autonomy.choose(folk[k % 3])
		var choose_ms := float(Time.get_ticks_usec() - c0) / 1000.0 / 6.0
		var t0 := Time.get_ticks_usec()
		Kit.run(20)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
		rows.append("%s: %.2f ms/game-minute, Autonomy.choose %.1f ms (%d NPCs, %d candidates for one folk)" % [mode, ms, choose_ms, npcs, cands])
		_check(ms < 60.0 * TestFixture.SLACK, "%s: a game minute stays cheap (%.2f ms)" % [mode, ms])
	WorldNav.enabled = true
	Autonomy.max_scored = 120
	print("  [tick] ", " | ".join(rows))