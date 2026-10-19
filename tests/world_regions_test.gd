extends RefCounted
## Regions, chunk index, build rules, rooms-at-scale and MapBuilder. Convention: run() -> Array of failure strings.

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
	_test_legacy_mode()
	_test_map_layout()
	_test_build_rules()
	_test_chunks()
	_test_rooms_at_scale()
	_test_save_roundtrip()
	_test_determinism()
	W.reset()
	return fails


func _first_tile(floor_type: String) -> Vector2i:
	for i in W.floors.size():
		if W.floors[i] == floor_type:
			return Vector2i(i % W.width, i / W.width)
	return Vector2i(-1, -1)


func _test_legacy_mode() -> void:
	W.reset(32, 24)
	_check(not W.regions.has_regions(), "legacy: regions should be empty")
	_check(W.can_build(Vector2i(3, 3)) and W.can_build(Vector2i(31, 23)), "legacy: everything buildable")
	_check(W.place_object("plant", Vector2i(5, 5), 0) != -1, "legacy: place failed (%s)" % W.last_error)
	_check(W.paint_floor(Vector2i(2, 2), "wood", 0), "legacy: paint failed")
	W.set_wall_line(Vector2i(8, 8), Vector2i(12, 8), "wall", 0)
	_check(W.room_id(Vector2i(8, 7)) != -1, "legacy: room query")
	_check(W.is_outdoor(Vector2i(0, 0)), "legacy: map border tile is outdoor")
	_check(W.chunk_of(Vector2i(17, 31)) == Vector2i(1, 1), "chunk_of")


func _test_map_layout() -> void:
	var rep: Dictionary = MapBuilder.build(W)
	_check(W.width == W.MAP_W and W.height == W.MAP_H, "map size")
	_check(int(rep["lots"]) == 16, "16 lots expected, got %s" % str(rep["lots"]))
	var lots: Array = []
	for k in ["home", "venue", "townie_home"]:
		lots.append_array(W.regions.of_kind(k))
	_check(lots.size() == 16, "lot regions %d" % lots.size())
	var map_rc := Rect2i(0, 0, W.width, W.height)
	for i in lots.size():
		var a: Rect2i = lots[i]["rect"]
		_check(map_rc.encloses(a), "%s outside the map" % lots[i]["lot"])
		for j in range(i + 1, lots.size()):
			_check(not a.intersects(lots[j]["rect"]), "%s overlaps %s" % [lots[i]["lot"], lots[j]["lot"]])
		var e: Vector2i = lots[i]["entry"]
		_check(a.has_point(e), "%s entry outside its rect" % lots[i]["lot"])
		var touches := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if W.get_floor(e + d) in ["sidewalk", "asphalt", "crosswalk"]:
				touches = true
		_check(touches, "%s entry not next to a sidewalk/road" % lots[i]["lot"])
		_check(W.region_at(a.position) == lots[i]["id"] and W.region_at(a.end - Vector2i.ONE) == lots[i]["id"], "%s region lookup" % lots[i]["lot"])
	_check(W.regions.home_id != -1 and str(W.regions.home()["owner"]) == "player", "home region")
	var hrc: Rect2i = W.regions.home()["rect"]
	_check(hrc.position.y > W.height * 4 / 10 and absi(hrc.get_center().x - W.width / 2) < 40, "home should sit centre-south, got %s" % str(hrc))
	_check(W.get_floor(Vector2i(0, 0)) == "grass", "map margin is grass")
	var counts := {}
	for t in W.floors:
		counts[t] = int(counts.get(t, 0)) + 1
	for f in ["asphalt", "sidewalk", "crosswalk", "lawn", "water", "sand", "grass"]:
		_check(int(counts.get(f, 0)) > 0, "floor type %s missing from the map" % f)
	_check(not W.is_walkable(_first_tile("water")), "water must not be walkable")
	# the whole road grid is connected for walkers: school gate -> home gate
	var home_e: Vector2i = W.regions.home()["entry"]
	var sch_e: Vector2i = W.regions.by_lot("school")["entry"]
	_check(W.has_path(sch_e, home_e), "no walk from the school gate to the home gate")


func _test_build_rules() -> void:
	MapBuilder.build(W)
	var home: Dictionary = W.regions.home()
	var hrc: Rect2i = home["rect"]
	var inside := hrc.position + Vector2i(8, 8)
	var cafe_rc: Rect2i = W.regions.by_lot("cafe")["rect"]
	var outside := cafe_rc.position + Vector2i(8, 8)
	_check(W.can_build(inside), "home tile must be buildable")
	_check(not W.can_build(outside), "cafe tile must not be buildable")
	_check(not W.can_build(Vector2i(0, 0)) and not W.can_build(Vector2i(-3, 4)), "open ground / out of bounds not buildable")
	_check(not W.can_place("plant", outside, 0) and W.last_error == "You can only build on your own lot.", "can_place outside: %s" % W.last_error)
	_check(W.place_object("plant", outside, 0) == -1, "place outside should fail")
	_check(W.buy_place("plant", outside, 0, 0) == -1, "buy_place outside should fail")
	var id: int = W.place_object("plant", inside, 0)
	_check(id != -1, "place inside home failed: %s" % W.last_error)
	_check(W.set_wall_line(outside, outside + Vector2i(4, 0), "wall", 0) == 0 and W.last_error == "You can only build on your own lot.", "wall outside")
	_check(W.set_wall_line(inside + Vector2i(2, 2), inside + Vector2i(6, 2), "wall", 0) == 4, "wall inside home")
	_check(not W.paint_floor(outside, "wood", 0) and W.last_error == "You can only build on your own lot.", "paint outside")
	_check(W.paint_floor(inside + Vector2i(3, 0), "wood", 0), "paint inside")
	# a rect straddling the lot border paints only the home part
	var painted: int = W.paint_floor_rect(hrc.position - Vector2i(2, 0), hrc.position + Vector2i(1, 0), "wood", 0)
	_check(painted == 2, "rect straddling the border painted %d" % painted)
	# loaders can switch the rule off
	W.regions.enforce = false
	_check(W.place_object("plant", outside, 0) != -1, "enforce=false should allow the loader")
	W.regions.enforce = true
	_check(not W.sell_object_at(outside), "sell outside should fail")
	_check(W.sell_object(id, 0), "sell inside")


func _test_chunks() -> void:
	MapBuilder.build(W)
	var hrc: Rect2i = W.regions.home()["rect"]
	var t := hrc.position + Vector2i(5, 5)
	var id: int = W.place_object("plant", t, 0)
	var c: Vector2i = W.chunk_of(t)
	_check(c == Vector2i(t.x / 16, t.y / 16), "chunk_of")
	_check(id in W.regions.chunk_objects(c), "object not in its chunk")
	W.remove_object(id)
	_check(not (id in W.regions.chunk_objects(c)), "object still in chunk after remove")
	var id2: int = W.place_object("plant", t, 0)
	var d: Dictionary = W.save_dict()
	W.load_dict(JSON.parse_string(JSON.stringify(d)))
	_check(id2 in W.regions.chunk_objects(c), "chunk index after load")
	W.regions.take_dirty_floor_chunks()
	W.paint_floor(t + Vector2i(1, 0), "wood", 0)
	var dirty: Array = W.regions.take_dirty_floor_chunks()
	_check(dirty.size() == 1 and dirty[0] == W.chunk_of(t + Vector2i(1, 0)), "dirty floor chunk set %s" % str(dirty))
	_check(W.regions.chunk_count() == Vector2i((W.MAP_W + 15) / 16, (W.MAP_H + 15) / 16), "chunk count %s" % str(W.regions.chunk_count()))


func _test_rooms_at_scale() -> void:
	MapBuilder.build(W)
	var hrc: Rect2i = W.regions.home()["rect"]
	var o := hrc.position + Vector2i(6, 6)
	_check(W.is_outdoor(Vector2i(2, 2)) and W.is_outdoor(Vector2i(80, 4)), "roads / open ground are outdoor")
	_check(W.room_id(Vector2i(2, 2)) == 0 and W.room_id(Vector2i(100, 130)) == 0, "street is one room (id 0)")
	_check(W.is_outdoor(o), "an empty lot is outdoor (touches the lot border)")
	# a closed 6x5 room inside the home lot
	W.set_wall_line(o, o + Vector2i(6, 0), "wall", 0)
	W.set_wall_line(o + Vector2i(0, 5), o + Vector2i(6, 5), "wall", 0)
	W.set_wall_line(o, o + Vector2i(0, 5), "wall", 0)
	W.set_wall_line(o + Vector2i(6, 0), o + Vector2i(6, 5), "wall", 0)
	var inner := o + Vector2i(2, 2)
	_check(not W.is_outdoor(inner), "walled room should be indoor")
	_check(W.room_tiles(inner).size() == 30, "room size %d" % W.room_tiles(inner).size())
	_check(W.room_id(inner) != W.room_id(o - Vector2i(1, 1)), "room differs from the yard")
	_check(W.room_id(inner) != 0, "indoor room is not the street")
	# speed: wall edit + room query
	var worst := 0.0
	var total := 0.0
	for i in 6:
		var t0 := Time.get_ticks_usec()
		W.set_edge(Vector3i(o.x + 3, o.y + 2, 1), "wall" if i % 2 == 0 else "none")
		var rid: int = W.room_id(inner)
		var el := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, el)
		total += el
		_check(rid != -1, "room query")
	print("  [rooms] wall edit + room query at %dx%d: avg %.2f ms, worst %.2f ms" % [W.width, W.height, total / 6.0, worst])
	_check(total / 6.0 < 5.0 * TestFixture.SLACK and worst < 10.0 * TestFixture.SLACK, "room query after a wall edit: avg %.2f worst %.2f ms (budget 5)" % [total / 6.0, worst])
	# other lots are untouched by an edit in the home lot (their partition stays cached)
	var venue_t: Vector2i = W.regions.by_lot("cafe")["rect"].position + Vector2i(4, 4)
	var r0: int = W.room_id(venue_t)
	W.set_edge(Vector3i(o.x + 3, o.y + 2, 1), "wall")
	_check(W.room_id(venue_t) == r0, "venue room id changed after a home edit")
	_check(W.room_count() > 1, "room_count")


func _test_save_roundtrip() -> void:
	MapBuilder.build(W)
	var d: Dictionary = W.save_dict()
	_check(d.has("floors_rle") and not d.has("floors"), "big map saves floors run-length encoded")
	var txt := JSON.stringify(d)
	_check(txt.length() < 400000, "save too big: %d chars" % txt.length())
	var t0 := Time.get_ticks_usec()
	W.load_dict(JSON.parse_string(txt))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [save] json %d chars, load_dict %.1f ms" % [txt.length(), ms])
	_check(ms < 150.0 * TestFixture.SLACK, "load_dict took %.1f ms" % ms)
	_check(W.regions.regions.size() == d["regions"]["regions"].size(), "regions lost on load")
	_check(W.regions.home_id != -1 and W.can_build(W.regions.home()["rect"].position), "home region after load")
	_check(not W.is_walkable(_first_tile("water")), "water blocks after load")
	var d2: Dictionary = W.save_dict()
	_check(JSON.stringify(d2["floors_rle"]) == JSON.stringify(d["floors_rle"]), "floors changed over save/load")
	_check(JSON.stringify(d2["regions"]) == JSON.stringify(d["regions"]), "regions changed over save/load")
	var road: Dictionary = W.regions.region_of(Vector2i(4, 40))
	_check(str(road.get("axis", "")) == "v" and (road.get("lines", []) as Array).size() == 4, "road markings lost: %s" % str(road.get("lines")))


func _test_determinism() -> void:
	MapBuilder.build(W)
	var a := JSON.stringify(W.save_dict())
	MapBuilder.build(W)
	var b := JSON.stringify(W.save_dict())
	_check(a == b, "MapBuilder.build is not deterministic")