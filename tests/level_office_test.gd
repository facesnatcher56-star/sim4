extends RefCounted
## The demo building: the office venue template is a 3-storey building with a basement (lift, stairs, pillars). End to end on the
## plain lot AND on the real map: placement report, reachability of every object on every floor, a Folk walking from the ground
## floor to the 3rd floor by the stairs and by the lift, rooms per floor, save / load.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	_template_on_plain_lot()
	_walk_up_both_ways()
	_save_load()
	_on_the_map()
	(Engine.get_main_loop().root.get_node("World") as WorldGrid).reset()
	return fails


func _w() -> WorldGrid:
	return Engine.get_main_loop().root.get_node("World") as WorldGrid


func _template_on_plain_lot() -> void:
	var W := _w()
	_check(LotLoader.apply("office"), "office template places: %s" % str(LotLoader.report.get("failed", [])))
	_check((LotLoader.report["failed"] as Array).is_empty(), "nothing failed to place: %s" % str(LotLoader.report["failed"]))
	_check(W.levels.buildings.size() == 1, "the office is a registered building")
	var b: Dictionary = W.levels.building(W.levels.building_at(Vector2i(15, 8)))
	_check(not b.is_empty() and int(b["min"]) == -1 and int(b["max"]) == 2, "levels -1 .. 2 (three storeys and a basement): %s" % str(b))
	for lv in [-1, 1, 2]:
		_check((W.levels.layer(lv).floors as Dictionary).size() > 250, "level %d has its floor" % lv)
	var counts := {}
	for o in W.all_objects():
		counts[o.level] = int(counts.get(o.level, 0)) + 1
	_check(counts.has(0) and counts.has(1) and counts.has(2) and counts.has(-1), "objects on every level: %s" % str(counts))
	var bad := LotLoader.unreachable_objects(W, Vector2i(15, 19))
	_check(bad.is_empty(), "every object on every floor can be reached from the door: %s" % str(bad))
	var lifts := W.objects_of_def("elevator")
	_check(lifts.size() == 1 and lifts[0].span == 2, "one lift serving three floors")
	# rooms per floor: the core room is separated from the open floor by the partition wall
	_check(W.room_id(Vector2i(7, 8), 1) != W.room_id(Vector2i(15, 8), 1), "level 1: core and office are separate rooms")
	_check(not W.is_outdoor(Vector2i(15, 8), 2), "the top floor is indoors under its roof")
	_check(W.room_info(Vector2i(14, 8), 1).get("objects", []).size() > 0, "room info counts the objects of its own level")


func _levels(route: Array) -> Array:
	var out: Array = []
	for p in route:
		if out.is_empty() or out[-1] != p.z:
			out.append(p.z)
	return out


func _walk_up_both_ways() -> void:
	var W := _w()
	LotLoader.apply("office")
	var door := Vector2i(15, 19)
	var f := Folk.create("Cleo")
	W.add_folk(f, door, 0)
	# to a computer on the 3rd floor (level 2)
	var top = null
	for o in W.objects_of_def("computer"):
		if o.level == 2:
			top = o
			break
	_check(top != null, "a computer on the 3rd floor")
	if top == null:
		return
	var by_lift := Interaction.create("research_online", f, top.id, true)
	_check(by_lift.start(), "start(): walk to the 3rd floor")
	var lv := _levels(by_lift.path3)
	_check(lv == [0, 2], "by the lift: ground -> 3rd floor in one ride (%s)" % str(lv))
	while by_lift.state == "walking":
		by_lift.tick(0.5)
	_check(f.level == 2 and f.tile == W.slot_tile(top.id, 0), "arrived at the desk on the 3rd floor")
	by_lift.cancel("player")
	# lift out of order: the stairs
	W.set_object_state(W.objects_of_def("elevator")[0].id, "out_of_order", true)
	var g := Folk.create("Dion")
	W.add_folk(g, door, 0)
	var by_stairs := Interaction.create("research_online", g, top.id, true)
	_check(by_stairs.start(), "start(): walk to the 3rd floor by the stairs")
	_check(_levels(by_stairs.path3) == [0, 1, 2], "the stairs: %s" % str(_levels(by_stairs.path3)))
	var seen_levels := {}
	while by_stairs.state == "walking":
		by_stairs.tick(0.5)
		seen_levels[g.level] = true
	_check(seen_levels.has(1) and g.level == 2, "passed the 2nd floor and arrived (%s, level %d)" % [str(seen_levels), g.level])
	_check(by_stairs.travel_total > by_lift.travel_total, "the stairs take longer than the lift")
	# the basement
	var arch = null
	for o in W.objects_of_def("bookshelf"):
		if o.level == -1:
			arch = o
	var h := Folk.create("Edda")
	W.add_folk(h, door, 0)
	var down := Interaction.create_goto(h, W.slot_tile(arch.id, 0), true, -1)
	_check(down.start() and _levels(down.path3).has(-1), "the archive in the basement is reachable: %s" % str(_levels(down.path3)))


func _save_load() -> void:
	var W := _w()
	LotLoader.apply("office")
	var d := W.save_dict(true)
	var parsed = JSON.parse_string(JSON.stringify(d))
	W.reset()
	W.load_dict(parsed)
	_check(W.levels.buildings.size() == 1 and W.objects.size() == (d["objects"] as Array).size(), "office survives save / load")
	_check(W.has_route(Vector3i(15, 19, 0), Vector3i(12, 7, 2)), "routes work after loading")
	var lifts := W.objects_of_def("elevator")
	_check(lifts.size() == 1 and lifts[0].span == 2, "the lift still serves three floors")


func _on_the_map() -> void:
	var W := _w()
	Neighborhood.start_game("classic")
	var r: Dictionary = W.regions.by_lot("office")
	_check(not r.is_empty() and str(r["template"]) == "office", "the office lot is on the map")
	var bid: int = W.levels.building_of_region(int(r["id"]))
	_check(bid >= 0, "its building is linked to the lot region")
	var rc: Rect2i = r["rect"]
	var street := Vector2i(rc.position.x + 15, rc.end.y)             # just south of the lot, on the sidewalk side
	var inside := Vector3i(rc.position.x + 12, rc.position.y + 7, 2)
	var len_up: float = W.route_length(Vector3i(5, 5, 0), inside)
	_check(len_up > 0.0, "from the far side of the map to the 3rd floor of the office (%f)" % len_up)
	var route: Array = W.find_route(Vector3i(5, 5, 0), inside)
	_check(not route.is_empty() and route[-1] == inside, "map route ends on the 3rd floor")
	var levels := _levels(route)
	_check(levels == [0, 2] or levels == [0, 1, 2], "it goes through the building: %s" % str(levels))
	_check(W.route_length(Vector3i(5, 5, 0), Vector3i(inside.x, inside.y, 0)) < len_up, "going upstairs adds to the distance")
	_check(street.x >= 0, "n/a")
