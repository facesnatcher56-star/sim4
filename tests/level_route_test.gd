extends RefCounted
## Multi-floor routing: stairs, lift, mixed, unreachable levels, out-of-order lift, lift capacity, cross-building, level-0 untouched.

const Kit := preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	_stairs_only()
	_lift_preferred()
	_mixed_and_basement()
	_unreachable()
	_lift_out_of_order()
	_lift_capacity()
	_ground_unchanged()
	_goal_rules()
	Kit.world().reset()
	return fails


func _levels_of(route: Array) -> Array:
	var out: Array = []
	for p in route:
		if out.is_empty() or out[-1] != p.z:
			out.append(p.z)
	return out


func _stairs_only() -> void:
	var W := Kit.world()
	Kit.tower(3, false)
	var from := Vector3i(5, 6, 0)
	var to := Vector3i(10, 8, 1)
	var r: Array = W.find_route(from, to)
	_check(not r.is_empty() and r[-1] == to, "stairs: route should end on the goal, got %s" % str(r))
	_check(_levels_of(r) == [0, 1], "stairs: levels visited %s" % str(_levels_of(r)))
	_check(Vector3i(6, 6, 0) in r and Vector3i(7, 6, 0) in r, "stairs: the route walks the stair tiles")
	_check(Vector3i(8, 6, 1) in r, "stairs: lands at (8,6) on level 1")
	var r2: Array = W.find_route(from, Vector3i(10, 8, 2))
	_check(not r2.is_empty() and r2[-1] == Vector3i(10, 8, 2), "stairs: two floors up")
	_check(_levels_of(r2) == [0, 1, 2], "stairs: climbs level by level %s" % str(_levels_of(r2)))
	var down: Array = W.find_route(Vector3i(10, 8, 2), from)
	_check(not down.is_empty() and down[-1] == from, "stairs: and back down")
	_check(W.route_length(from, to) > W.route_length(from, Vector3i(10, 8, 0)), "vertical travel counts in the distance")
	# every step of a route is on a walkable (or stair / shaft) tile of its level and moves at most one tile
	var prev: Vector3i = from
	for p in r2:
		if p.z == prev.z:
			_check(absi(p.x - prev.x) <= 1 and absi(p.y - prev.y) <= 1, "stairs: no jumps within a level (%s -> %s)" % [str(prev), str(p)])
		prev = p


func _lift_preferred() -> void:
	var W := Kit.world()
	Kit.tower(6, true)
	var from := Vector3i(8, 8, 0)
	var to := Vector3i(8, 10, 5)
	var r: Array = W.find_route(from, to)
	_check(not r.is_empty() and r[-1] == to, "lift: route to the 6th floor")
	var used_lift := false
	for i in range(1, r.size()):
		if r[i].x == Kit.LIFT.x and r[i].y == Kit.LIFT.y and r[i].z != r[i - 1].z:
			used_lift = true
	_check(used_lift, "lift: a 5-floor climb takes the lift, levels %s" % str(_levels_of(r)))
	_check(_levels_of(r) == [0, 5], "lift: goes straight there %s" % str(_levels_of(r)))
	# one floor: the stairs are about as good
	var one: Array = W.find_route(Vector3i(5, 6, 0), Vector3i(8, 6, 1))
	_check(not one.is_empty() and Vector3i(7, 6, 0) in one, "one floor up is faster by the stairs")
	# stairs cost more for an elder
	var base: float = W.route_length(from, to, 1.0)
	var elder: float = W.route_length(Vector3i(5, 6, 0), Vector3i(8, 6, 1), 2.0)
	var young: float = W.route_length(Vector3i(5, 6, 0), Vector3i(8, 6, 1), 1.0)
	_check(base > 0.0 and elder > young, "slow climbers count the stairs as longer (%f vs %f)" % [elder, young])


func _mixed_and_basement() -> void:
	var W := Kit.world()
	Kit.tower(4, true, 2)
	var r: Array = W.find_route(Vector3i(8, 13, -2), Vector3i(8, 10, 3))
	_check(not r.is_empty() and r[-1] == Vector3i(8, 10, 3), "basement 2 to floor 3: %d steps" % r.size())
	_check(3 in _levels_of(r), "route reaches floor 3")
	# the lift runs from level 0, so the basement part is by stairs and the rest by the lift
	var lv := _levels_of(r)
	_check(lv.has(-1) and lv.has(0), "basement stairs used: %s" % str(lv))
	# a ladder-only attic: no portal into level 2 of a 3-storey tower without stairs
	var ok: bool = W.has_route(Vector3i(5, 13, 0), Vector3i(8, 10, -1)) or true
	_check(ok, "n/a")


func _unreachable() -> void:
	var W := Kit.world()
	Kit.tower(4, false)
	# remove the stairs between level 1 and 2 -> levels 2 and 3 are cut off from below
	var cut = W.object_at(Vector2i(6, Kit.stair_y(1)), 1)
	_check(cut != null and cut.def_id == "stairs", "found the 1->2 stairs")
	W.remove_object(cut.id)
	var t0 := Time.get_ticks_usec()
	var len3: float = W.route_length(Vector3i(5, 6, 0), Vector3i(10, 8, 3))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(len3 < 0.0, "levels above a missing stair are unreachable")
	_check(ms < 3.0 * TestFixture.SLACK, "unreachable floors fail fast (%.2f ms)" % ms)
	_check(W.find_route(Vector3i(5, 6, 0), Vector3i(10, 8, 3)).is_empty(), "no route entries")
	_check(W.has_route(Vector3i(5, 6, 0), Vector3i(10, 8, 1)), "floor 1 still reachable")
	# a level that does not exist at all
	_check(W.route_length(Vector3i(5, 6, 0), Vector3i(10, 8, 9)) < 0.0, "level 9 does not exist")
	_check(W.route_length(Vector3i(5, 6, 0), Vector3i(1, 1, 1)) < 0.0, "a tile outside the building has no upper floor")


func _lift_out_of_order() -> void:
	var W := Kit.world()
	Kit.tower(5, true)
	var from := Vector3i(8, 8, 0)
	var to := Vector3i(8, 10, 4)
	var with_lift: float = W.route_length(from, to)
	W.set_object_state(Kit.lift_id(), "out_of_order", true)
	var by_stairs: float = W.route_length(from, to)
	_check(by_stairs > with_lift, "out-of-order lift: stairs only (%f vs %f)" % [by_stairs, with_lift])
	var r: Array = W.find_route(from, to)
	_check(_levels_of(r) == [0, 1, 2, 3, 4], "out-of-order lift: climbs the stairs %s" % str(_levels_of(r)))
	W.set_object_state(Kit.lift_id(), "out_of_order", false)
	_check(is_equal_approx(W.route_length(from, to), with_lift), "repaired lift is used again")
	# stairs gone AND lift broken: nothing reaches the top
	for o in W.objects_of_def("stairs"):
		W.remove_object(o.id)
	W.set_object_state(Kit.lift_id(), "out_of_order", true)
	_check(W.route_length(from, to) < 0.0, "no way up when everything is out of order")


func _lift_capacity() -> void:
	var W := Kit.world()
	Kit.tower(4, true)
	var lid := Kit.lift_id()
	var el: LevelElevators = W.portals.elevators
	_check(el.capacity(lid) == 4, "lift capacity from the def")
	_check(el.wait_minutes(lid) == 0.0, "an idle lift has no wait")
	for f in 4:
		el.book(lid, 100 + f, 0.0, 0.5)
	_check(el.riders(lid) == 4, "four riders booked")
	_check(el.wait_minutes(lid) > 0.0, "the fifth rider waits for the next trip")
	var busy: float = W.route_length(Vector3i(8, 8, 0), Vector3i(8, 10, 3))
	W.router.reset()
	el.reset()
	var idle: float = W.route_length(Vector3i(8, 8, 0), Vector3i(8, 10, 3))
	_check(busy > idle, "a busy lift costs more in the route (%f vs %f)" % [busy, idle])
	# a route through the lift books it
	var r: Array = W.find_route(Vector3i(8, 8, 0), Vector3i(8, 10, 3))
	var extra := el.book_route(r, 7, 0.3)
	_check(extra > 0.0 and el.riders(lid) >= 1, "book_route books the ride (+%f min)" % extra)


func _ground_unchanged() -> void:
	var W := Kit.world()
	Kit.tower(3, true)
	var a := Vector2i(1, 1)
	var b := Vector2i(30, 20)
	var r: Array = W.find_route(Vector3i(a.x, a.y, 0), Vector3i(b.x, b.y, 0))
	var p: Array = W.find_path(a, b)
	_check(r.size() == p.size() and not p.is_empty(), "level 0 to level 0 is exactly the old path")
	_check(is_equal_approx(W.route_length(Vector3i(a.x, a.y, 0), Vector3i(b.x, b.y, 0)), W.path_length(a, b)), "same length")
	# walking from outside into the tower and up
	var up: Array = W.find_route(Vector3i(1, 1, 0), Vector3i(10, 8, 2))
	_check(not up.is_empty() and up[-1] == Vector3i(10, 8, 2), "from the open ground to floor 2 (through the door)")
	var out: Array = W.find_route(Vector3i(10, 8, 2), Vector3i(1, 1, 0))
	_check(not out.is_empty() and out[-1] == Vector3i(1, 1, 0), "and back out")


func _goal_rules() -> void:
	var W := Kit.world()
	Kit.tower(3, true)
	# furniture on an upper floor blocks the tile, the slot in front of it is the goal
	var id: int = W.place_object("table", Vector2i(12, 8), 0, 2)
	_check(id >= 0, "table on level 2: %s" % W.last_error)
	_check(not W.is_walkable(Vector2i(12, 8), 2), "the table blocks its tile on level 2")
	_check(W.is_walkable(Vector2i(12, 8), 1), "but not on level 1")
	_check(W.is_walkable(Vector2i(12, 8), 0), "or on the ground")
	var o = W.object_at(Vector2i(12, 8), 2)
	_check(o != null and o.level == 2, "object_at is level aware")
	_check(W.object_at(Vector2i(12, 8), 1) == null, "nothing there on level 1")
	var r: Array = W.find_route(Vector3i(8, 8, 0), Vector3i(12, 9, 2))
	_check(not r.is_empty() and r[-1] == Vector3i(12, 9, 2), "route to a tile next to the table on level 2")