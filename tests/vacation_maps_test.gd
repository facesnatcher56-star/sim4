extends RefCounted
## Task 22: the holiday maps load into the Southwoods zones with no placement failures, every object is reachable from the arrival tile
## (the ship across five decks), two zones can be loaded together, and unloading leaves the woods exactly as they were.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	Kit.new_game("small")
	VacationContent.install()
	var w: Node = Kit.world()
	var outside_before: int = w.objects.size()
	for map_id in DestDefs.ids():
		_one(w, map_id)
	_two_zones(w)
	_check(w.objects.size() == outside_before, "after all unloads the world holds the same objects (%d vs %d)" % [w.objects.size(), outside_before])
	Kit.teardown()
	return fails

func _one(w: Node, map_id: String) -> void:
	var res: Dictionary = DestLoader.load_zone(0, map_id, "trip_0", "Test " + map_id)
	_check(bool(res["ok"]), "%s loads without placement failures: %s" % [map_id, str(res.get("failed", []))])
	var rc: Rect2i = res["rect"]
	var spawn: Vector2i = res["spawn"][0]
	_check(w.is_walkable(spawn), "%s: arrival tile %s is walkable" % [map_id, str(spawn)])
	_check(NeighborhoodLots.lot_at(spawn) == "trip_0", "%s: the zone is the lot trip_0" % map_id)
	var bad: Array = LotLoader.unreachable_objects(w, spawn, rc)
	_check(bad.is_empty(), "%s: unreachable objects: %s" % [map_id, str(bad.slice(0, 8))])
	if map_id == "ship":
		var lobby: Vector2i = rc.position + Vector2i(15, 14)
		var n_levels: int = w.levels.range_at(lobby).y - w.levels.range_at(lobby).x + 1
		_check(n_levels == 5, "the ship has five decks (%d)" % n_levels)
		var cabins: Array = DestLoader.cabin_list("ship", rc)
		_check(cabins.size() >= 10, "the ship lists its cabins (%d)" % cabins.size())
		var classes := {}
		for c in cabins:
			classes[c["class"]] = int(classes.get(c["class"], 0)) + 1
		_check(classes.has("inside") and classes.has("ocean") and classes.has("suite"), "inside, ocean and suite cabins: %s" % str(classes))
		for p in DestLoader.posts("ship", rc):
			var t3 := Vector3i(p["tile"].x, p["tile"].y, int(p["level"]))
			_check(w.has_route(Vector3i(spawn.x, spawn.y, 0), t3), "crew post %s reachable from the gangway" % str(p))
		for c2 in cabins:
			var c3 := Vector3i(c2["tile"].x, c2["tile"].y, int(c2["level"]))
			_check(w.has_route(Vector3i(spawn.x, spawn.y, 0), c3), "cabin %s reachable" % str(c2["id"]))
	var removed: int = DestLoader.unload_zone(0)
	_check(removed > 0, "%s: unload removed objects (%d)" % [map_id, removed])
	var left := 0
	for o in w.objects.values():
		if rc.has_point(o.tile):
			left += 1
	_check(left == 0, "%s: nothing left in the zone (%d)" % [map_id, left])
	_check(DestLoader.region_of_zone(0) < 0, "%s: region gone" % map_id)
	_check(w.get_floor(rc.position + Vector2i(1, 1)) == "grass" and w.is_walkable(rc.position + Vector2i(1, 1)), "%s: woods restored" % map_id)
	_check(not w.levels.any() or w.levels.building_at(rc.position + Vector2i(16, 10)) < 0, "%s: building record gone" % map_id)
	_check(NeighborhoodLots.lot_at(rc.position + Vector2i(5, 5)) == "", "%s: back to the street/woods lookup" % map_id)

func _two_zones(w: Node) -> void:
	var a: Dictionary = DestLoader.load_zone(0, "ship", "trip_0", "Ship")
	var b: Dictionary = DestLoader.load_zone(1, "city", "trip_1", "Port")
	_check(bool(a["ok"]) and bool(b["ok"]), "ship and a port load side by side")
	DestLoader.unload_zone(1)
	_check(DestLoader.region_of_zone(0) >= 0 and NeighborhoodLots.lot_at(a["spawn"][0]) == "trip_0", "unloading the port leaves the ship alone")
	DestLoader.unload_zone(0)
