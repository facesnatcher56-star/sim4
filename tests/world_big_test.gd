extends RefCounted
## 160x120 world: reset / path / build budgets. Convention: run() -> Array of failure strings.

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


func run() -> Array:
	fails = []
	W = Engine.get_main_loop().root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	_test_reset()
	_test_paths()
	_test_map_build()
	W.reset()
	return fails


func _test_reset() -> void:
	var t0 := Time.get_ticks_usec()
	W.reset(W.MAP_W, W.MAP_H)
	var ms := _ms(t0)
	print("  [big] reset %dx%d: %.2f ms" % [W.MAP_W, W.MAP_H, ms])
	_check(W.width == 160 and W.height == 120 and W.floors.size() == 19200, "size")
	_check(ms < 60.0, "reset took %.1f ms" % ms)
	_check(W.get_floor(Vector2i(159, 119)) == "grass" and W.get_floor(Vector2i(160, 0)) == "", "floors")


func _test_paths() -> void:
	W.reset(W.MAP_W, W.MAP_H)
	var t0 := Time.get_ticks_usec()
	var p: Array[Vector2i] = W.find_path(Vector2i(0, 0), Vector2i(159, 119))
	var ms := _ms(t0)
	print("  [big] open path corner to corner: %d steps, %.1f ms" % [p.size(), ms])
	_check(p.size() == 159 and p[p.size() - 1] == Vector2i(159, 119), "corner path size %d" % p.size())
	_check(ms < 80.0, "corner path %.1f ms" % ms)
	# windowed result still avoids walls: a long wall with a gap far from both ends
	W.add_wall(Vector2i(80, 0), Vector2i(80, 110))
	t0 = Time.get_ticks_usec()
	var q: Array[Vector2i] = W.find_path(Vector2i(10, 60), Vector2i(150, 60))
	ms = _ms(t0)
	print("  [big] detour around a 110-tile wall: %d steps, %.1f ms" % [q.size(), ms])
	_check(not q.is_empty() and q[q.size() - 1] == Vector2i(150, 60), "detour path missing")
	var prev := Vector2i(10, 60)
	var through := false
	for s in q:
		_check(W.edge_open(prev, s) if (prev.x == s.x or prev.y == s.y) else true, "path crosses a wall at %s" % str(s))
		if s.y >= 110 and s.x >= 79 and s.x <= 81:
			through = true
		prev = s
	_check(through, "detour should pass the gap below y=110")
	_check(ms < 500.0, "detour path %.1f ms" % ms)
	# unreachable: boxed-in goal
	W.reset(W.MAP_W, W.MAP_H)
	W.add_wall(Vector2i(100, 50), Vector2i(104, 50))
	W.add_wall(Vector2i(100, 54), Vector2i(104, 54))
	W.add_wall(Vector2i(100, 50), Vector2i(100, 54))
	W.add_wall(Vector2i(104, 50), Vector2i(104, 54))
	t0 = Time.get_ticks_usec()
	var r: Array[Vector2i] = W.find_path(Vector2i(10, 10), Vector2i(102, 52))
	ms = _ms(t0)
	print("  [big] unreachable goal: %.1f ms" % ms)
	_check(r.is_empty(), "boxed-in goal should be unreachable")
	_check(ms < 1500.0, "unreachable search %.1f ms" % ms)
	_check(W.path_length(Vector2i(5, 5), Vector2i(60, 5)) == 55.0, "path_length")


func _test_map_build() -> void:
	var t0 := Time.get_ticks_usec()
	var rep: Dictionary = MapBuilder.build(W)
	var ms := _ms(t0)
	print("  [big] MapBuilder.build: %.1f ms (%d regions)" % [ms, int(rep["regions"])])
	_check(ms < 400.0, "MapBuilder.build took %.1f ms" % ms)
	t0 = Time.get_ticks_usec()
	var p: Array[Vector2i] = W.find_path(W.regions.by_lot("school")["entry"] + Vector2i(0, 1), W.regions.by_lot("townie_b")["entry"] + Vector2i(0, 1))
	ms = _ms(t0)
	print("  [big] school gate -> townie_b gate: %d steps, %.1f ms" % [p.size(), ms])
	_check(not p.is_empty() and ms < 100.0, "street path %d steps %.1f ms" % [p.size(), ms])
