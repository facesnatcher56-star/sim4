extends RefCounted
## Save / load with several levels: buildings, sparse layers, objects (level + lift span), stairwell openings, routes, folk level, JSON round trip.

const Kit := preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	_round_trip()
	_old_world_dict()
	_sparse_memory()
	Kit.world().reset()
	return fails


func _round_trip() -> void:
	var W := Kit.world()
	var bid := Kit.tower(6, true, 1)
	W.place_object("computer", Vector2i(12, 8), 0, 3)
	W.place_object("window", Vector2i(10, 4), 0, 2)
	var f := Folk.create("Ivy")
	W.add_folk(f, Vector2i(12, 9), 3)
	var from := Vector3i(5, 6, 0)
	var to := Vector3i(12, 9, 5)
	var len_before := W.route_length(from, to)
	var lift_before := W.portals.record(Kit.lift_id())
	var d := W.save_dict(true)
	var txt := JSON.stringify(d)
	var parsed = JSON.parse_string(txt)
	_check(parsed is Dictionary and (parsed as Dictionary).has("levels"), "levels are in the save")
	W.reset()
	_check(not W.levels.any() and W.levels.layers.is_empty(), "reset forgets the building")
	W.load_dict(parsed)
	_check(W.levels.buildings.size() == 1, "one building loaded")
	var b: Dictionary = W.levels.building(bid)
	_check(not b.is_empty() and int(b["max"]) == 5 and int(b["min"]) == -1 and (b["rect"] as Rect2i) == Kit.FOOT, "building range + rect kept (%s)" % str(b))
	_check(W.levels.floor_at(Vector2i(10, 10), 4) == "wood" and W.levels.floor_at(Vector2i(10, 10), -1) == "concrete", "floors on several levels")
	_check(W.levels.wall_at(Vector3i(4, 6, 1), 3) == "wall", "walls on level 3")
	var comp = W.object_at(Vector2i(12, 8), 3)
	_check(comp != null and comp.level == 3 and comp.def_id == "computer", "the computer is on level 3")
	_check(W.levels.wall_at(Vector3i(10, 4, 0), 2) == "window", "the window on level 2 kept its edge")
	var lift = W.get_object(Kit.lift_id())
	_check(lift != null and lift.span == 5, "the lift shaft keeps its span (%d)" % (lift.span if lift != null else -1))
	_check(W.portals.record(Kit.lift_id()).get("stops", []).size() == lift_before.get("stops", []).size(), "lift stops rebuilt")
	_check(W.levels.layer(2).holes.has(Vector2i(6, 6)) or W.levels.layer(2).holes.has(Vector2i(6, 10)), "stairwell openings rebuilt")
	_check(not W.is_walkable(Vector2i(16, 8), 4), "the shaft blocks its tile on every level")
	_check(is_equal_approx(W.route_length(from, to), len_before), "same route length after loading (%f vs %f)" % [W.route_length(from, to), len_before])
	var r: Array = W.find_route(from, to)
	_check(not r.is_empty() and r[-1] == to, "route works after loading")
	var g = W.get_folk(f.id)
	_check(g != null and g.level == 3 and g.tile == Vector2i(12, 9), "the folk is still on level 3")
	# edits after loading work like before
	_check(W.place_object("sofa", Vector2i(8, 12), 0, 4) >= 0, "can still build on level 4")
	# and saving again gives the same levels
	var d2 := W.save_dict(true)
	_check(JSON.stringify(d2["levels"]) == JSON.stringify(d["levels"]) , "second save has identical levels")


func _old_world_dict() -> void:
	var W := Kit.world()
	W.reset(20, 12)
	W.place_object("fridge", Vector2i(3, 3))
	var d := W.save_dict(false)
	_check(not d.has("levels"), "a world without upper floors writes no levels block")
	W.reset()
	W.load_dict(d)
	_check(W.objects.size() == 1 and not W.levels.any(), "plain worlds still round-trip")


func _sparse_memory() -> void:
	var W := Kit.world()
	Kit.tower(20, true)
	_check(W.levels.layers.size() == 19, "19 layers for a 20-storey tower (%d)" % W.levels.layers.size())
	var tiles := 0
	for lay in W.levels.layers.values():
		tiles += (lay as LevelLayer).floors.size()
	_check(tiles == 19 * Kit.FOOT.size.x * Kit.FOOT.size.y, "layers only hold the tower footprint (%d tiles, not %d)" % [tiles, 19 * 32 * 24])
	var d := W.save_dict(false)
	var kb := JSON.stringify(d).length() / 1024
	_check(kb < 600, "a 20-storey tower stays small in the save (%d KB)" % kb)
