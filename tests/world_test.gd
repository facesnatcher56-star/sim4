extends RefCounted
## World agent tests. Convention: run() -> Array of failure strings (empty = pass).

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	W = Engine.get_main_loop().root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	_test_defs()
	_test_pathfinding()
	_test_corner_cutting()
	_test_placement()
	_test_reservation()
	_test_rooms_and_score()
	_test_build_and_undo()
	_test_radius_events()
	_test_save_load()
	_test_sim_state_is_saved()
	_test_starter_house()
	W.reset()
	return fails


func _test_defs() -> void:
	for id in ["fridge", "stove", "table", "chair", "bed", "toilet", "shower", "bathtub", "sink", "sofa", "tv",
			"bookshelf", "easel", "treadmill", "computer", "counter", "plant", "lamp", "trash_bin", "door",
			"window", "rug"]:
		var d: Dictionary = W.get_def(id)
		_check(not d.is_empty(), "def missing: " + id)
		for k in ["label", "size", "price", "tags", "slots", "state", "advertises", "decor", "interactions", "model"]:
			_check(d.has(k), "def %s lacks key %s" % [id, k])


func _test_pathfinding() -> void:
	W.reset(12, 8)
	# vertical wall at x=6 (vertices) from y=0..8 splits the lot completely
	W.add_wall(Vector2i(6, 0), Vector2i(6, 8))
	_check(W.find_path(Vector2i(1, 1), Vector2i(10, 1)).is_empty(), "path through solid wall")
	_check(W.find_path(Vector2i(1, 1), Vector2i(5, 6)).size() > 0, "same-side path missing")
	# door at tile (6,3) west edge
	W.set_edge(Vector3i(6, 3, 1), "door")
	var p: Array = W.find_path(Vector2i(1, 1), Vector2i(10, 1))
	p.push_front(Vector2i(1, 1))
	_check(p.size() > 1, "no path through door")
	var crossed := false
	for i in range(p.size() - 1):
		if p[i] == Vector2i(5, 3) and p[i + 1] == Vector2i(6, 3):
			crossed = true
	_check(crossed, "path did not cross via door tiles")
	# window blocks
	W.set_edge(Vector3i(6, 3, 1), "window")
	_check(W.find_path(Vector2i(1, 1), Vector2i(10, 1)).is_empty(), "path through window")
	# object blocks tile, forces detour but exists
	W.reset(8, 5)
	W.place_object("fridge", Vector2i(3, 2), 0)
	_check(not W.is_walkable(Vector2i(3, 2)), "fridge tile should be blocked")
	var p2: Array = W.find_path(Vector2i(0, 2), Vector2i(7, 2))
	_check(p2.size() > 0 and not (Vector2i(3, 2) in p2), "detour around object failed")
	# 4-dir pathing has no diagonal steps
	var p3: Array = W.find_path(Vector2i(0, 0), Vector2i(4, 4), false)
	p3.push_front(Vector2i(0, 0))
	var diag := false
	for i in range(p3.size() - 1):
		var d: Vector2i = p3[i + 1] - p3[i]
		if d.x != 0 and d.y != 0:
			diag = true
	_check(not diag and p3.size() == 9, "4-dir path invalid")
	# goal inside blocked furniture is reachable (slot inside)
	_check(W.find_path(Vector2i(0, 0), Vector2i(3, 2)).size() > 0, "path to blocked goal tile failed")
	# fence blocks, remove opens
	W.reset(8, 5)
	W.add_wall(Vector2i(0, 2), Vector2i(8, 2))
	_check(W.find_path(Vector2i(1, 0), Vector2i(1, 4)).is_empty(), "path across full wall")
	W.set_wall_line(Vector2i(3, 2), Vector2i(4, 2), "none")
	_check(W.find_path(Vector2i(1, 0), Vector2i(1, 4)).size() > 0, "gap not opened")


func _test_corner_cutting() -> void:
	W.reset(6, 6)
	# walls forming an L corner: wall edge between (2,2)|(3,2) and edge between (2,2)|(2,3)
	W.add_wall(Vector2i(3, 2), Vector2i(3, 3))   # vertical edge west of tile (3,2)
	W.add_wall(Vector2i(2, 3), Vector2i(3, 3))   # horizontal edge north of tile (2,3)
	# diagonal (2,2)->(3,3) would cut the corner
	var p: Array = W.find_path(Vector2i(2, 2), Vector2i(3, 3))
	p.push_front(Vector2i(2, 2))
	var cut := false
	for i in range(p.size() - 1):
		if p[i] == Vector2i(2, 2) and p[i + 1] == Vector2i(3, 3):
			cut = true
	_check(not cut, "diagonal corner cutting through walls")
	_check(p.size() > 0, "path around corner should still exist")
	# diagonal blocked by an object on one side
	W.reset(6, 6)
	W.place_object("fridge", Vector2i(3, 2), 0)
	var p2: Array = W.find_path(Vector2i(2, 2), Vector2i(3, 3))
	p2.push_front(Vector2i(2, 2))
	var cut2 := false
	for i in range(p2.size() - 1):
		if p2[i] == Vector2i(2, 2) and p2[i + 1] == Vector2i(3, 3):
			cut2 = true
	_check(not cut2, "diagonal between object corner")


func _test_placement() -> void:
	W.reset(10, 8)
	var a: int = W.place_object("fridge", Vector2i(2, 2), 0)
	_check(a >= 0, "first place failed")
	_check(W.place_object("fridge", Vector2i(2, 2), 0) == -1, "overlap allowed")
	_check(not W.can_place("fridge", Vector2i(-1, 0), 0), "out of bounds allowed")
	_check(not W.can_place("fridge", Vector2i(10, 0), 0), "out of bounds (hi) allowed")
	_check(W.place_object("table", Vector2i(1, 2), 0) == -1, "2x1 overlap with fridge allowed")
	_check(W.place_object("table", Vector2i(3, 2), 0) >= 0, "adjacent table failed")
	_check(not W.can_place("table", Vector2i(9, 5), 0), "2x1 table hanging off edge")
	# rotation changes the footprint
	_check(W.can_place("bed", Vector2i(8, 3), 0), "bed 1x2 should fit")
	_check(not W.can_place("bed", Vector2i(9, 7), 0), "bed beyond bottom should fail")
	# rug is floor layer: can overlap table
	_check(W.place_object("rug", Vector2i(3, 2), 0) >= 0, "rug under table failed")
	_check(W.place_object("rug", Vector2i(3, 2), 0) == -1, "rug on rug allowed")
	_check(W.is_walkable(Vector2i(4, 3)), "rug must not block")
	# wall-mounted needs a wall
	_check(not W.can_place("door", Vector2i(5, 5), 0), "door without wall")
	W.add_wall(Vector2i(0, 5), Vector2i(10, 5))
	_check(W.can_place("door", Vector2i(5, 5), 0), "door on wall (north edge of tile 5,5)")
	var d: int = W.place_object("door", Vector2i(5, 5), 0)
	_check(d >= 0, "door place")
	_check(W.place_object("window", Vector2i(5, 5), 0) == -1, "two mounts on one edge")
	_check(W.find_path(Vector2i(5, 6), Vector2i(5, 4)).size() > 0, "door object should be passable")
	var pd: Array = W.find_path(Vector2i(2, 6), Vector2i(2, 4))
	pd.push_front(Vector2i(2, 6))
	var via_door := false
	for i in range(pd.size() - 1):
		if pd[i] == Vector2i(5, 5) and pd[i + 1] == Vector2i(5, 4):
			via_door = true
	_check(via_door, "path must cross the wall only through the door")
	# removal frees the tile
	_check(W.remove_object(a), "remove returned false")
	_check(W.is_walkable(Vector2i(2, 2)), "tile not freed")
	_check(not W.remove_object(a), "double remove true")
	_check(W.place_object("fridge", Vector2i(2, 2), 0) >= 0, "replace after removal")
	# removing the door restores plain wall
	W.remove_object(d)
	_check(W.find_path(Vector2i(5, 6), Vector2i(5, 4)).is_empty(), "wall not restored after door removal")
	# wall through footprint blocked: bed at (1,1) covers (1,1),(1,2); edge between has wall
	W.reset(6, 6)
	W.add_wall(Vector2i(1, 2), Vector2i(2, 2))
	_check(not W.can_place("bed", Vector2i(1, 1), 0), "bed across a wall allowed")


func _test_reservation() -> void:
	W.reset(8, 6)
	var s: int = W.place_object("sofa", Vector2i(2, 2), 0)
	_check(W.find_path(Vector2i(0, 0), Vector2i(0, 0)).is_empty() and W.has_path(Vector2i(0, 0), Vector2i(0, 0)), "same-tile path")
	_check(W.find_path(Vector2i(0, 0), Vector2i(3, 0)).size() == 3, "path length excludes start")
	_check(W.reserve(s, 0, 1), "reserve free slot")
	_check(not W.reserve(s, 0, 2), "reserve conflict allowed")
	_check(W.reserve(s, 0, 1), "re-reserve by same folk")
	_check(W.reserve(s, 1, 2), "second seat")
	_check(W.free_slot(s) == -1, "no free slot expected")
	W.release(s, 0, 2)   # wrong owner: no effect
	_check(not W.is_slot_free(s, 0), "release by wrong folk freed slot")
	W.release(s, 0, 1)
	_check(W.is_slot_free(s, 0), "slot not released")
	_check(not W.reserve(s, 5, 1), "bad slot index accepted")
	W.release_all(2)
	_check(W.is_slot_free(s, 1), "release_all failed")
	_check(not W.reserve(9999, 0, 1), "reserve on missing object")
	# slot tile rotation: fridge slot offset [0,1]
	var f: int = W.place_object("fridge", Vector2i(4, 4), 1)
	_check(W.slot_tile(f, 0) == Vector2i(3, 4), "rotated slot tile: %s" % str(W.slot_tile(f, 0)))


func _enclose(x0: int, y0: int, x1: int, y1: int) -> void:
	# tiles x0..x1, y0..y1 inclusive
	W.add_wall(Vector2i(x0, y0), Vector2i(x1 + 1, y0))
	W.add_wall(Vector2i(x0, y1 + 1), Vector2i(x1 + 1, y1 + 1))
	W.add_wall(Vector2i(x0, y0), Vector2i(x0, y1 + 1))
	W.add_wall(Vector2i(x1 + 1, y0), Vector2i(x1 + 1, y1 + 1))


func _test_rooms_and_score() -> void:
	W.reset(14, 10)
	_enclose(2, 2, 5, 5)
	_enclose(6, 2, 9, 5)   # adjacent room sharing x=6 wall
	_check(W.room_id(Vector2i(3, 3)) != W.room_id(Vector2i(7, 3)), "rooms not separated")
	_check(W.room_id(Vector2i(3, 3)) == W.room_id(Vector2i(5, 5)), "room tiles split")
	_check(W.room_tiles(Vector2i(3, 3)).size() == 16, "room size %d" % W.room_tiles(Vector2i(3, 3)).size())
	_check(W.is_outdoor(Vector2i(0, 0)), "yard should be outdoor")
	_check(not W.is_outdoor(Vector2i(3, 3)), "room flagged outdoor")
	# door merges nothing (doors separate rooms but connect paths)
	W.place_object("door", Vector2i(6, 3), 3)
	_check(W.room_id(Vector2i(5, 3)) != W.room_id(Vector2i(6, 3)), "door should still separate rooms")
	_check(W.find_path(Vector2i(3, 3), Vector2i(8, 3)).size() > 0, "rooms not connected via door")
	# env score
	var base: float = W.room_score(Vector2i(3, 3))
	var plant: int = W.place_object("plant", Vector2i(2, 2), 0)
	var with_plant: float = W.room_score(Vector2i(3, 3))
	_check(with_plant > base, "plant should raise score (%f vs %f)" % [with_plant, base])
	var sofa: int = W.place_object("sofa", Vector2i(3, 4), 0)
	var with_sofa: float = W.room_score(Vector2i(3, 3))
	_check(with_sofa > with_plant, "sofa should raise score")
	# dried plant is worth less
	W.set_object_state(plant, "water", 0.0)
	_check(W.room_score(Vector2i(3, 3)) < with_sofa, "dry plant should lower score")
	W.set_object_state(plant, "water", 10.0)
	_check(is_equal_approx(W.room_score(Vector2i(3, 3)), with_sofa + 0.0) or W.room_score(Vector2i(3, 3)) >= with_sofa,
		"watered plant score")
	# mess and dirt lower the score; other room unaffected
	var before: float = W.room_score(Vector2i(3, 3))
	var other: float = W.room_score(Vector2i(8, 3))
	W.add_mess(Vector2i(4, 4), 3.0)
	_check(W.room_score(Vector2i(3, 3)) < before, "mess should lower score")
	_check(is_equal_approx(W.room_score(Vector2i(8, 3)), other), "mess leaked into other room")
	W.add_mess(Vector2i(4, 4), -3.0)
	_check(is_equal_approx(W.room_score(Vector2i(3, 3)), before), "mess clean should restore score")
	var toilet: int = W.place_object("toilet", Vector2i(5, 2), 0)
	var t0: float = W.room_score(Vector2i(3, 3))
	W.set_object_state(toilet, "dirtiness", 10.0)
	_check(W.room_score(Vector2i(3, 3)) < t0, "dirty toilet should lower score")
	var cl: float = W.room_cleanliness(Vector2i(3, 3))
	_check(cl > 0.0 and cl < 1.0, "cleanliness range")
	W.set_object_state(toilet, "dirtiness", 0.0)
	W.set_object_state(toilet, "broken", true)
	_check(W.room_score(Vector2i(3, 3)) < t0, "broken lowers score")
	# floor type contributes
	var s_floor: float = W.room_score(Vector2i(3, 3))
	W.paint_floor_rect(Vector2i(2, 2), Vector2i(5, 5), "carpet")
	_check(W.room_score(Vector2i(3, 3)) > s_floor, "carpet should raise score vs grass")
	var info: Dictionary = W.room_info(Vector2i(3, 3))
	_check(info.has("score") and info.has("decor") and info.has("mess"), "room_info keys")
	_check(sofa >= 0, "sofa placed")


func _test_build_and_undo() -> void:
	W.reset(10, 8)
	var wallet := [1000]
	W.coin_spend = func(_h: int, amt: int) -> bool:
		if wallet[0] < amt:
			return false
		wallet[0] -= amt
		return true
	W.coin_refund = func(_h: int, amt: int) -> void:
		wallet[0] += amt
	var id: int = W.buy_place("fridge", Vector2i(1, 1), 0, 0)
	_check(id >= 0, "buy_place fridge")
	_check(wallet[0] == 400, "fridge charged: %d" % wallet[0])
	_check(W.buy_place("bed", Vector2i(5, 1), 0, 0) == -1, "bed (500) bought with 400 coins")
	wallet[0] = 100
	_check(W.buy_place("sofa", Vector2i(5, 5), 0, 0) == -1, "bought sofa without enough coins")
	_check(wallet[0] == 100, "failed purchase must not charge")
	_check(W.undo_last(), "undo buy")
	_check(W.get_object(id) == null, "fridge still exists after undo")
	_check(wallet[0] == 700, "undo refunds: %d" % wallet[0])
	# walls + undo
	wallet[0] = 1000
	var n: int = W.set_wall_line(Vector2i(0, 4), Vector2i(10, 4), "wall", 0)
	_check(n == 10, "wall edges %d" % n)
	_check(wallet[0] == 1000 - 10 * W.WALL_PRICE, "wall cost")
	_check(W.find_path(Vector2i(1, 1), Vector2i(1, 6)).is_empty(), "wall line blocks")
	_check(W.undo_last(), "undo wall")
	_check(W.find_path(Vector2i(1, 1), Vector2i(1, 6)).size() > 0, "undo wall opened path")
	_check(wallet[0] == 1000, "wall refund")
	# door replacing a wall then undo restores wall
	W.set_wall_line(Vector2i(0, 4), Vector2i(10, 4), "wall", 0)
	var dobj: int = W.place_object("door", Vector2i(3, 4), 0)
	_check(dobj >= 0, "door placed in line")
	W.set_wall_line(Vector2i(0, 4), Vector2i(10, 4), "none", 0)   # erases incl. door object
	_check(W.get_object(dobj) == null, "door object should vanish with its wall")
	W.undo_last()
	_check(W.get_object(dobj) != null, "undo restores door object")
	# floor paint + undo
	wallet[0] = 1000
	var painted: int = W.paint_floor_rect(Vector2i(0, 0), Vector2i(2, 1), "wood")
	_check(painted == 6 and W.get_floor(Vector2i(1, 1)) == "wood", "paint floor")
	_check(wallet[0] == 1000 - 6 * W.FLOOR_PRICE, "floor cost")
	W.undo_last()
	_check(W.get_floor(Vector2i(1, 1)) == "grass", "undo floor")
	# sell
	var tv: int = W.buy_place("tv", Vector2i(6, 6), 0, 0)
	wallet[0] = 0
	_check(W.sell_object(tv, 0), "sell")
	_check(wallet[0] == 250, "sell refund 50%%: %d" % wallet[0])
	_check(W.undo_last() and W.get_object(tv) != null, "undo sell restores same id")
	# undo limit
	W.clear_undo()
	for i in 60:
		W.paint_floor(Vector2i(i % 10, 7), "tile" if i % 2 == 0 else "wood", 0)
	_check(W.undo_count() <= W.UNDO_LIMIT, "undo stack bounded: %d" % W.undo_count())
	W.coin_spend = Callable()
	W.coin_refund = Callable()


func _test_radius_events() -> void:
	W.reset(12, 8)
	var near: int = W.place_object("lamp", Vector2i(3, 3), 0)
	var far: int = W.place_object("lamp", Vector2i(10, 7), 0)
	var res: Array = W.objects_in_radius(Vector2i(3, 4), 2.0)
	_check(res.size() == 1 and res[0].id == near, "objects_in_radius near")
	_check(W.objects_in_radius(Vector2i(3, 4), 20.0).size() == 2, "radius all")
	_check(far >= 0, "far lamp")
	# events (only if the Events autoload exists)
	var ev: Node = Engine.get_main_loop().root.get_node_or_null("Events")
	if ev != null and ev.has_signal("object_placed"):
		var got := []
		var cb := func(i: int) -> void: got.append(i)
		ev.object_placed.connect(cb)
		var nid: int = W.place_object("plant", Vector2i(6, 2), 0)
		_check(got == [nid], "object_placed not emitted")
		var got2 := []
		var cb2 := func(i: int, s: String) -> void: got2.append([i, s])
		ev.object_state_changed.connect(cb2)
		W.set_object_state(nid, "water", 3.0)
		_check(got2.size() == 1 and got2[0] == [nid, "water"], "object_state_changed not emitted")
		var got3 := []
		var cb3 := func(i: int) -> void: got3.append(i)
		ev.object_removed.connect(cb3)
		W.remove_object(nid)
		_check(got3 == [nid], "object_removed not emitted")
		ev.object_placed.disconnect(cb)
		ev.object_state_changed.disconnect(cb2)
		ev.object_removed.disconnect(cb3)


func _test_save_load() -> void:
	W.reset(16, 12)
	_enclose(2, 2, 7, 7)
	W.place_object("door", Vector2i(4, 8), 0)
	var tv: int = W.place_object("tv", Vector2i(3, 3), 0)
	W.place_object("sofa", Vector2i(3, 6), 2)
	W.set_object_state(tv, "on", true)
	var pl: int = W.place_object("plant", Vector2i(6, 3), 0)
	W.set_object_state(pl, "water", 2.5)
	W.paint_floor_rect(Vector2i(2, 2), Vector2i(4, 4), "wood")
	W.add_mess(Vector2i(5, 5), 2.0)
	W.set_wall_line(Vector2i(10, 0), Vector2i(10, 5), "fence", 0)
	var d1: Dictionary = W.save_dict()
	var js := JSON.stringify(d1)
	var parsed: Variant = JSON.parse_string(js)
	_check(parsed is Dictionary, "save_dict not JSON-safe")
	W.reset(5, 5)
	W.load_dict(parsed)
	var d2: Dictionary = W.save_dict()
	_check(JSON.stringify(d2) == js, "save/load roundtrip differs")
	_check(W.width == 16 and W.height == 12, "size restored")
	var o = W.get_object(tv)
	_check(o != null and o.state.get("on") == true, "tv state restored")
	_check(is_equal_approx(float(W.get_object(pl).state["water"]), 2.5), "plant water restored")
	_check(W.get_floor(Vector2i(3, 3)) == "wood", "floor restored")
	_check(W.find_path(Vector2i(5, 5), Vector2i(12, 8)).is_empty() == false, "path outside room after load (via door south)")
	_check(not W.is_walkable(Vector2i(3, 3)), "blocking restored")
	# new ids continue after load
	var nid: int = W.place_object("lamp", Vector2i(12, 9), 0)
	_check(nid > pl and nid > tv, "id counter restored")


## The sim writes object state through WorldIface; the World saves exactly that (state is the single source of truth).
func _test_sim_state_is_saved() -> void:
	W.reset()
	var id: int = W.place_object("fridge", Vector2i(4, 4), 0)
	var o = W.get_object(id)
	WorldIface.state_set(o, "stock", 3.0)
	WorldIface.state_add(o, "stock", 1.0)
	_check(float(o.state["stock"]) == 4.0 and float(WorldIface.state_get(o, "stock", -1.0)) == 4.0, "state_set / state_add write the object's state")
	var d: Dictionary = W.save_dict(false)
	var saved := -1.0
	for od in d["objects"]:
		if int(od["id"]) == id:
			saved = float(od["state"]["stock"])
	_check(saved == 4.0, "save_dict stores the state the sim wrote (%f)" % saved)
	WorldIface.state_set(o, "stock", 999.0)
	_check(float(o.state["stock"]) <= float(W.get_def("fridge")["state"]["stock"]["max"]), "state_set clamps to the definition's max")
	W.reset()


func _test_starter_house() -> void:
	W.load_starter_house()
	_check(W.all_objects().size() > 30, "starter house too empty")
	_check(W.starter_spawn_tiles.size() == 3, "3 spawn tiles")
	var bed: Vector2i = W.starter_bedroom_tile
	_check(W.is_walkable(bed), "bedroom tile blocked")
	for t in W.starter_spawn_tiles:
		_check(W.is_walkable(t), "spawn blocked %s" % str(t))
		_check(W.has_path(bed, t), "spawn unreachable %s" % str(t))
	var counts := {}
	var bad := []
	for o in W.all_objects():
		counts[o.def_id] = int(counts.get(o.def_id, 0)) + 1
		if o.is_wall_mounted() or o.slot_count() == 0:
			continue
		for i in o.slot_count():
			var st: Vector2i = o.slot_tile(i)
			if not W.in_bounds(st) or not W.has_path(bed, st):
				bad.append("%s#%d slot %d at %s" % [o.def_id, o.id, i, str(st)])
	_check(bad.is_empty(), "unreachable slots: " + str(bad))
	for need in ["fridge", "stove", "bed", "toilet", "shower", "bathtub", "sink", "sofa", "tv", "bookshelf",
			"easel", "treadmill", "computer", "table", "chair", "plant", "door", "window"]:
		_check(counts.has(need), "starter house lacks " + need)
	_check(int(counts.get("bed", 0)) >= 3, "need a bed per folk")
	# rooms: bedroom, bathroom, kitchen, living, bedroom B + yard
	var ids := {}
	for t in [Vector2i(6, 5), Vector2i(11, 5), Vector2i(16, 5), Vector2i(6, 12), Vector2i(14, 12), Vector2i(10, 18)]:
		ids[W.room_id(t)] = true
	_check(ids.size() == 6, "expected 6 distinct rooms/areas, got %d" % ids.size())
	_check(W.is_outdoor(Vector2i(10, 18)) and not W.is_outdoor(Vector2i(6, 5)), "yard/indoor flags")
	_check(W.room_score(Vector2i(14, 12)) > 0.0, "living room score positive")
	# yard to front door
	_check(W.has_path(Vector2i(15, 21), Vector2i(15, 12)), "front door route")
	# save roundtrip of whole house
	var js := JSON.stringify(W.save_dict())
	W.load_dict(JSON.parse_string(js))
	_check(JSON.stringify(W.save_dict()) == js, "starter house roundtrip")
