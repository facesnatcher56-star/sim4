extends RefCounted
## Folk walking across floors: Interaction.start plans the multi-floor route once, tick() carries the folk (tile + level) along it,
## elders / injured folk take longer on stairs, autonomy distance counts vertical travel, folk save their level.

const Kit := preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	_go_here_by_stairs()
	_use_object_upstairs()
	_stairs_slower_for_elders()
	_autonomy_distance()
	_folk_level_saved()
	_stale_level_resets()
	Kit.world().reset()
	return fails


func _walk(ir: Interaction, minutes_cap: float = 120.0) -> Array:
	## ticks until the folk arrives; returns the (tile, level) pairs seen
	var seen: Array = []
	var t := 0.0
	while ir.state == "walking" and t < minutes_cap:
		ir.tick(0.25)
		t += 0.25
		var f: Folk = ir.actor
		seen.append(Vector3i(f.tile.x, f.tile.y, f.level))
	return seen


func _go_here_by_stairs() -> void:
	var W := Kit.world()
	Kit.tower(3, false)
	var f := Folk.create("Ana")
	W.add_folk(f, Vector2i(5, 6), 0)
	var ir := Interaction.create_goto(f, Vector2i(12, 8), true, 2)
	_check(ir != null and ir.start(), "go_here to floor 2 starts")
	_check(not ir.path3.is_empty() and ir.path3[-1] == Vector3i(12, 8, 2), "the planned route ends on floor 2")
	_check(ir.state == "walking" and ir.travel_total > 0.0, "it is a walk")
	var seen := _walk(ir)
	var levels: Array = []
	for p in seen:
		if levels.is_empty() or levels[-1] != p.z:
			levels.append(p.z)
	_check(levels == [0, 1, 2] or levels == [1, 2] or levels == [0, 1, 2], "the folk passes floor 1 on the way: %s" % str(levels))
	_check(ir.state == "running" or ir.state == "finished", "arrived (%s)" % ir.state)
	_check(f.tile == Vector2i(12, 8) and f.level == 2, "standing at (12,8) on level 2, got %s level %d" % [str(f.tile), f.level])
	# route one floor: a shorter walk takes less time
	var f2 := Folk.create("Bo")
	W.add_folk(f2, Vector2i(5, 6), 0)
	var ir2 := Interaction.create_goto(f2, Vector2i(12, 8), true, 1)
	ir2.start()
	_check(ir2.travel_total < ir.travel_total, "one floor up is quicker than two (%f vs %f)" % [ir2.travel_total, ir.travel_total])
	_check(W.folk.has(f.id), "folk registered")


func _use_object_upstairs() -> void:
	var W := Kit.world()
	Kit.tower(3, true)
	var cid: int = W.place_object("computer", Vector2i(12, 8), 0, 2)
	_check(cid >= 0, "computer on floor 2: %s" % W.last_error)
	var f := Folk.create("Cy")
	W.add_folk(f, Vector2i(8, 12), 0)
	var ir := Interaction.create("research_online", f, cid, true)
	_check(ir != null, "interaction exists")
	if ir == null:
		return
	_check(ir.start(), "start() finds a route to a computer on another floor")
	_check(ir.path3.size() > 0 and ir.path3[-1].z == 2, "the route ends upstairs")
	var seen := _walk(ir)
	_check(not seen.is_empty(), "the folk walked")
	_check(f.level == 2 and f.tile == W.slot_tile(cid, 0), "at the computer's seat on floor 2 (got %s level %d)" % [str(f.tile), f.level])
	_check(ir.slot_idx >= 0, "slot reserved")
	ir.cancel("player")
	_check(f.level == 2, "staying upstairs after the interaction")
	# and the way back down to the ground
	var back := Interaction.create_goto(f, Vector2i(8, 12), true, 0)
	_check(back.start() and back.path3[-1] == Vector3i(8, 12, 0), "the way back down")
	_walk(back)
	_check(f.level == 0, "back on the ground")


func _stairs_slower_for_elders() -> void:
	var W := Kit.world()
	Kit.tower(3, false)
	var adult := Folk.create("Dee")
	var elder := Folk.create("Eli")
	elder.age_stage = "elder"
	W.add_folk(adult, Vector2i(5, 6), 0)
	W.add_folk(elder, Vector2i(5, 6), 0)
	var a := Interaction.create_goto(adult, Vector2i(10, 8), true, 2)
	var e := Interaction.create_goto(elder, Vector2i(10, 8), true, 2)
	a.start()
	e.start()
	_check(e.travel_total > a.travel_total * 1.2, "an elder needs longer on the stairs (%f vs %f)" % [e.travel_total, a.travel_total])
	# the same distance on one floor is NOT slower for an adult vs elder by that factor (stairs are the difference)
	var flat_a := Interaction.create_goto(adult, Vector2i(10, 8), true, 0)
	adult.current = null
	flat_a.start()
	var flat_e := Interaction.create_goto(elder, Vector2i(10, 8), true, 0)
	elder.current = null
	flat_e.start()
	_check(is_equal_approx(flat_a.travel_total, flat_e.travel_total), "on the flat both walk alike")


func _autonomy_distance() -> void:
	var W := Kit.world()
	Kit.tower(4, false)
	var f := Folk.create("Fay")
	W.add_folk(f, Vector2i(5, 6), 0)
	var near := WorldIface.path_length(Vector2i(5, 6), Vector2i(12, 8), 0, 0)
	var up1 := WorldIface.path_length(Vector2i(5, 6), Vector2i(12, 8), 0, 1)
	var up3 := WorldIface.path_length(Vector2i(5, 6), Vector2i(12, 8), 0, 3)
	_check(near > 0 and up1 > near and up3 > up1, "distance grows with floors: %d < %d < %d" % [near, up1, up3])
	_check(WorldIface.path_length(Vector2i(12, 8), Vector2i(12, 8), 0, 1) > 0, "same x,y but another floor is not distance 0")
	_check(WorldIface.path_length(Vector2i(5, 6), Vector2i(12, 8), 0, 9) < 0, "a floor that does not exist is unreachable")


func _folk_level_saved() -> void:
	var f := Folk.create("Gus")
	f.tile = Vector2i(9, 9)
	f.level = -2
	var g := Folk.from_dict(f.to_dict())
	_check(g.level == -2 and g.tile == Vector2i(9, 9), "Folk.to_dict / from_dict keep the level")
	var old := f.to_dict()
	old.erase("level")
	_check(Folk.from_dict(old).level == 0, "a dict without a level means the ground")


func _stale_level_resets() -> void:
	var W := Kit.world()
	Kit.tower(2, false)
	var f := Folk.create("Hal")
	W.add_folk(f, Vector2i(30, 20), 3)          # level 3 does not exist there (teleported / stale)
	var ir := Interaction.create_goto(f, Vector2i(29, 20), true, 0)
	_check(ir.start(), "a stale level does not break a walk")
	_check(f.level == 0, "the folk is put back on the ground")
