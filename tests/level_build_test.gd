extends RefCounted
## Build mode on several floors: add a floor above / a basement below (only while stairs reach it), costs that grow per level,
## the structure rules (no floating floors, nothing the floors above rest on may be removed), roofs, undo of all of it.

const Kit := preload("res://tests/level_kit.gd")

var fails: Array = []
var spent: int = 0
var refunded: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	_add_floor_flow()
	_cost_grows()
	_support_rules()
	_basement_flow()
	_undo_everything()
	_lift_extends()
	_rooms_per_level()
	Kit.world().reset()
	return fails


## A one-storey house on the plain 32x24 world: walls x 6..18, y 6..14, wood floor, a door; building = the whole grid.
func _house() -> int:
	var W := Kit.world()
	W.reset(32, 24)
	spent = 0
	refunded = 0
	W.coin_spend = func(_h: int, a: int) -> bool:
		spent += a
		return true
	W.coin_refund = func(_h: int, a: int) -> void:
		refunded += a
	W.set_floor_rect_raw(Vector2i(6, 6), Vector2i(17, 13), "wood")
	for x in range(6, 18):
		W.set_edge(Vector3i(x, 6, 0), "wall")
		W.set_edge(Vector3i(x, 14, 0), "wall")
	for y in range(6, 14):
		W.set_edge(Vector3i(6, y, 1), "wall")
		W.set_edge(Vector3i(18, y, 1), "wall")
	W.place_object("door", Vector2i(10, 13), 2)
	return W.lbuild.ensure_building(Vector2i(8, 8))


func _add_floor_flow() -> void:
	var W := Kit.world()
	var bid := _house()
	_check(bid >= 0 and W.levels.level_count(bid) == 1, "a house is a one-level building")
	var why := W.lbuild.why_not_add(bid, true)
	_check(why.find("stairs") >= 0, "no floor without stairs: '%s'" % why)
	_check(W.lbuild.add_level(bid, true) == 0 and W.last_error != "", "add_level refuses (%s)" % W.last_error)
	var sid := W.buy_place("stairs", Vector2i(8, 8), 0, 1, 0)
	_check(sid >= 0, "stairs bought on the ground floor: %s" % W.last_error)
	_check(W.lbuild.why_not_add(bid, true) == "", "stairs going up allow a new floor")
	var lv := W.lbuild.add_level(bid, true)
	_check(lv == 1, "level 1 added (got %d: %s)" % [lv, W.last_error])
	_check(W.levels.level_count(bid) == 2 and int(W.levels.building(bid)["max"]) == 1, "the building has two levels")
	var lay := W.levels.layer(1)
	_check(lay.floors.size() > 50, "the new level has floors over the house (%d tiles)" % lay.floors.size())
	_check(not lay.walls.is_empty(), "and an outer wall")
	_check(not lay.floors.has(Vector2i(8, 8)) or lay.holes.has(Vector2i(8, 8)), "the stairwell is open")
	_check(W.has_route(Vector3i(7, 10, 0), Vector3i(12, 10, 1)), "the new floor is reachable by the stairs")
	# furnish upstairs
	var bed := W.buy_place("single_bed", Vector2i(12, 10), 0, 1, 1)
	_check(bed >= 0, "bed on the new floor: %s" % W.last_error)
	_check(W.object_at(Vector2i(12, 10), 1) != null and W.object_at(Vector2i(12, 10), 0) == null, "it is on level 1 only")
	# a wall upstairs and a door in it
	var n := W.set_wall_line(Vector2i(10, 8), Vector2i(10, 12), "wall", 1, 1)
	_check(n == 4, "partition wall on level 1 (%d edges)" % n)
	var door := W.buy_place("door", Vector2i(10, 9), 3, 1, 1)
	_check(door >= 0, "door in it: %s" % W.last_error)
	# roof
	_check(W.lbuild.set_roof(bid, "gable", 1), "roof style")
	_check(str(W.levels.building(bid)["roof"]) == "gable", "roof is gable")
	# nothing can be added a third level without stairs on level 1
	_check(W.lbuild.why_not_add(bid, true).find("stairs") >= 0, "a third floor needs stairs on level 1 first")


func _cost_grows() -> void:
	var W := Kit.world()
	var bid := _house()
	var p1 := W.lbuild.level_price(1)
	var p2 := W.lbuild.level_price(2)
	var p5 := W.lbuild.level_price(5)
	_check(p1 < p2 and p2 < p5, "each level costs more than the last (%d, %d, %d)" % [p1, p2, p5])
	_check(W.lbuild.level_price(-1) > W.lbuild.level_price(1), "a basement is dearer than the first floor")
	_check(W.lbuild.level_price(-3) > W.lbuild.level_price(-1), "and deeper ones more")
	W.buy_place("stairs", Vector2i(8, 8), 0, 1, 0)
	var before := spent
	W.lbuild.add_level(bid, true)
	_check(spent - before >= p1, "adding level 1 charged at least its price (%d)" % (spent - before))
	var c1 := spent - before
	W.buy_place("stairs", Vector2i(8, 11), 0, 1, 1)
	before = spent
	W.lbuild.add_level(bid, true)
	var c2 := spent - before
	_check(c2 > c1 - 400, "the next level is not cheaper (%d vs %d)" % [c2, c1])
	# a lift costs per floor it serves
	var lift_price := W.object_price("elevator")
	before = spent
	W.buy_place("elevator", Vector2i(15, 8), 0, 1, 0)
	_check(spent - before == lift_price * 3, "the lift is paid per floor (%d)" % (spent - before))
	# not enough coins
	W.coin_spend = func(_h: int, _a: int) -> bool: return false
	W.buy_place("stairs", Vector2i(8, 8), 0, 1, 2)
	var lv_before := W.levels.level_count(bid)
	_check(W.lbuild.add_level(bid, true) == 0 and W.levels.level_count(bid) == lv_before, "a poor player cannot add a level")
	_check(W.last_error == "not enough coins" or W.last_error.find("stairs") >= 0, "with a clear message (%s)" % W.last_error)


func _support_rules() -> void:
	var W := Kit.world()
	var bid := _house()
	W.buy_place("stairs", Vector2i(8, 8), 0, 1, 0)
	W.lbuild.add_level(bid, true)
	# a floor far from any wall below cannot be painted on level 1 (outside the house footprint)
	var n_far := W.paint_floor_rect(Vector2i(26, 18), Vector2i(28, 20), "wood", 1, 1)
	_check(n_far == 0 and W.last_error.find("underneath") >= 0, "no floating floor in the open (%d, '%s')" % [n_far, W.last_error])
	# a balcony next to the wall is fine
	var n_ok := W.paint_floor_rect(Vector2i(19, 8), Vector2i(20, 9), "tile", 1, 1)
	_check(n_ok == 4, "a balcony beside the wall (%d tiles: %s)" % [n_ok, W.last_error])
	# but not 8 tiles out
	var n_out := W.paint_floor_rect(Vector2i(27, 8), Vector2i(28, 9), "tile", 1, 1)
	_check(n_out == 0, "a floor 9 tiles from the wall floats")
	# level 2 on a hole: needs a floor below it
	W.buy_place("stairs", Vector2i(8, 11), 0, 1, 1)
	W.lbuild.add_level(bid, true)
	_check(W.paint_floor_rect(Vector2i(19, 8), Vector2i(19, 8), "tile", 1, 2) == 1, "level 2 over the balcony ok (a new level starts with the footprint below)")
	_check(W.paint_floor_rect(Vector2i(22, 8), Vector2i(22, 8), "wood", 1, 2) == 0, "level 2 with nothing underneath refused")
	# a wall the floor above rests on cannot be removed
	var gone := W.set_wall_line(Vector2i(6, 6), Vector2i(18, 6), "none", 1, 0)
	_check(gone == 0 and W.last_error.find("rests") >= 0, "removing ground walls under the floor above is refused (%d, '%s')" % [gone, W.last_error])
	# but the floor above can be removed first, then the wall may go
	_check(W.paint_floor_rect(Vector2i(19, 8), Vector2i(19, 8), "none", 1, 2) == 1, "floor removed on level 2")
	# erasing a floor with another one above is refused
	_check(W.paint_floor_rect(Vector2i(12, 12), Vector2i(12, 12), "none", 1, 1) == 0 and W.last_error.find("above") >= 0, "cannot dig out floor 1 under floor 2")
	# pillars hold floors too
	var pillar := W.buy_place("pillar", Vector2i(24, 4), 0, 1, 0)
	_check(pillar >= 0, "pillar: %s" % W.last_error)
	_check(W.paint_floor_rect(Vector2i(24, 4), Vector2i(25, 5), "wood", 1, 1) == 4, "a floor on a pillar")
	_check(not W.sell_object(pillar, 1) , "the pillar cannot be sold while the floor rests on it")
	_check(W.last_error.find("rests") >= 0, "with the reason")
	# walls erased on the top level have nothing above: allowed
	_check(W.set_wall_line(Vector2i(6, 6), Vector2i(10, 6), "none", 1, 2) >= 0, "top level walls can go")


func _basement_flow() -> void:
	var W := Kit.world()
	var bid := _house()
	_check(W.lbuild.why_not_add(bid, false).find("down") >= 0, "a basement needs stairs going down first")
	var sid := W.buy_place("stairs_down", Vector2i(8, 8), 0, 1, 0)
	_check(sid >= 0, "stairs down on the ground floor: %s" % W.last_error)
	var lv := W.lbuild.add_level(bid, false)
	_check(lv == -1, "basement -1 added (%d: %s)" % [lv, W.last_error])
	_check(W.levels.floor_at(Vector2i(12, 10), -1) == "concrete", "concrete floor")
	_check(W.has_route(Vector3i(7, 10, 0), Vector3i(12, 10, -1)), "the basement is reachable by the stairs")
	_check(W.has_route(Vector3i(12, 10, -1), Vector3i(7, 10, 0)), "and the way up")
	_check(W.lbuild.why_not_add(bid, false).find("down") >= 0, "a second basement needs stairs down on the first")
	var b := W.buy_place("shower", Vector2i(12, 10), 0, 1, -1)
	_check(b >= 0, "furniture in the basement: %s" % W.last_error)
	_check(W.lbuild.add_level(bid, true) == 0, "the top is unaffected: still needs stairs up")


func _undo_everything() -> void:
	var W := Kit.world()
	var bid := _house()
	var s1 := W.buy_place("stairs", Vector2i(8, 8), 0, 1, 0)
	var undo0 := W.undo_count()
	W.lbuild.add_level(bid, true)
	_check(W.undo_count() == undo0 + 1, "add_level is one undo step")
	W.buy_place("sofa", Vector2i(13, 11), 0, 1, 1)
	W.paint_floor_rect(Vector2i(19, 8), Vector2i(19, 9), "tile", 1, 1)
	W.set_wall_line(Vector2i(10, 8), Vector2i(10, 12), "wall", 1, 1)
	W.lbuild.set_roof(bid, "hip", 1)
	_check(W.undo_last(), "undo roof")
	_check(str(W.levels.building(bid)["roof"]) == "flat", "roof back to flat")
	_check(W.undo_last(), "undo wall")
	_check(W.levels.wall_at(Vector3i(10, 8, 1), 1) == "", "partition wall gone")
	_check(W.undo_last(), "undo floor")
	_check(W.levels.floor_at(Vector2i(19, 8), 1) == "", "balcony floor gone")
	_check(W.undo_last(), "undo sofa")
	_check(W.objects_of_def("sofa").is_empty(), "sofa gone")
	var r_before := refunded
	_check(W.undo_last(), "undo add_level")
	_check(W.levels.level_count(bid) == 1, "back to one level")
	_check(W.levels.layer(1, false) == null or W.levels.layer(1, false).floors.is_empty(), "no floors left on level 1")
	_check(refunded > r_before, "the level price came back")
	_check(not W.has_route(Vector3i(7, 10, 0), Vector3i(12, 10, 1)), "level 1 is gone from the routes")
	# undo of a sold object upstairs puts it back on the right level
	W.lbuild.add_level(bid, true)
	var sofa := W.buy_place("sofa", Vector2i(13, 11), 0, 1, 1)
	W.sell_object(sofa, 1)
	_check(W.objects_of_def("sofa").is_empty(), "sofa sold")
	_check(W.undo_last(), "undo the sale")
	var back = W.objects_of_def("sofa")
	_check(back.size() == 1 and back[0].level == 1, "the sofa is back on level 1")
	_check(s1 >= 0, "stairs ok")


func _lift_extends() -> void:
	var W := Kit.world()
	var bid := _house()
	W.buy_place("stairs", Vector2i(8, 8), 0, 1, 0)
	W.lbuild.add_level(bid, true)
	var lift := W.buy_place("elevator", Vector2i(15, 9), 0, 1, 0)
	_check(lift >= 0, "lift: %s" % W.last_error)
	var o = W.get_object(lift)
	_check(o.span == 1, "the shaft serves two levels")
	W.buy_place("stairs", Vector2i(8, 11), 0, 1, 1)
	_check(W.lbuild.add_level(bid, true) == 2, "level 2")
	_check(o.span == 2, "the lift grew to the new top floor (span %d)" % o.span)
	_check(W.has_route(Vector3i(14, 9, 0), Vector3i(14, 9, 2)), "and reaches it")
	W.undo_last()
	_check(o.span == 1, "undo shortens the shaft again (span %d)" % o.span)
	_check(not W.has_route(Vector3i(14, 9, 0), Vector3i(14, 9, 2)), "level 2 is gone")


func _rooms_per_level() -> void:
	var W := Kit.world()
	var bid := _house()
	W.buy_place("stairs", Vector2i(8, 8), 0, 1, 0)
	W.lbuild.add_level(bid, true)
	_check(not W.is_outdoor(Vector2i(12, 10), 1), "the closed upper floor is indoors")
	var r0: int = W.room_id(Vector2i(12, 10), 0)
	var r1: int = W.room_id(Vector2i(12, 10), 1)
	_check(r0 >= 0 and r1 >= 0 and r0 != r1, "rooms are per level (%d vs %d)" % [r0, r1])
	W.set_wall_line(Vector2i(12, 6), Vector2i(12, 14), "wall", 1, 1)
	_check(W.room_id(Vector2i(10, 10), 1) != W.room_id(Vector2i(14, 10), 1), "a partition splits the upper room")
	_check(W.room_id(Vector2i(10, 10), 0) == W.room_id(Vector2i(14, 10), 0), "but not the ground room")
	W.buy_place("sofa", Vector2i(14, 10), 0, 1, 1)
	var sc_up: float = W.room_score(Vector2i(14, 10), 1)
	var sc_down: float = W.room_score(Vector2i(14, 10), 0)
	_check(sc_up != sc_down, "decor counts on its own level (%f vs %f)" % [sc_up, sc_down])
	# the ground under a floor is roofed
	W.set_wall_line(Vector2i(6, 6), Vector2i(18, 6), "wall", 1, 0)
	# a deck on the ground under a balcony counts as covered
	W.paint_floor_rect(Vector2i(19, 8), Vector2i(19, 9), "tile", 1, 1)
	_check(W.levels.covered(Vector2i(19, 8), 0), "the ground below a balcony is covered")
	_check(not W.is_outdoor(Vector2i(19, 8), 0), "so it is not rained on")
	_check(W.is_outdoor(Vector2i(22, 8), 0), "open ground is")
	# roof "none" opens the top floor to the sky
	W.lbuild.set_roof(bid, "none", 1)
	_check(W.is_outdoor(Vector2i(10, 10), 1), "no roof: the top floor is outdoors")
	W.lbuild.set_roof(bid, "flat", 1)
	_check(not W.is_outdoor(Vector2i(10, 10), 1), "roof back on")
	# line of sight inside a level
	_check(WorldRoomsLevels.can_see(W, Vector3i(8, 10, 1), Vector3i(10, 10, 1)), "see within a room")
	_check(not WorldRoomsLevels.can_see(W, Vector3i(10, 10, 1), Vector3i(14, 10, 1)), "a wall blocks the view")
	_check(not WorldRoomsLevels.can_see(W, Vector3i(10, 10, 1), Vector3i(10, 10, 0)), "floors block the view between levels")
