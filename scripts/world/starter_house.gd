extends RefCounted
## Builds the furnished starter lot (2 bedrooms, bathroom, kitchen, living room + yard).
## Layout (tiles): house x4..19, y4..15.
##  top row    y4..9 : bedroom A x4..9 | bathroom x10..13 | bedroom B x14..19
##  bottom row y10..15: kitchen x4..10 | living room x11..19


static func build(w) -> void:
	# --- floors
	w.set_floor_rect_raw(Vector2i(4, 4), Vector2i(9, 9), "carpet")
	w.set_floor_rect_raw(Vector2i(10, 4), Vector2i(13, 9), "tile")
	w.set_floor_rect_raw(Vector2i(14, 4), Vector2i(19, 9), "carpet")
	w.set_floor_rect_raw(Vector2i(4, 10), Vector2i(10, 15), "tile")
	w.set_floor_rect_raw(Vector2i(11, 10), Vector2i(19, 15), "wood")
	w.set_floor_rect_raw(Vector2i(15, 16), Vector2i(15, 20), "stone")

	# --- walls (vertex coordinates)
	w.add_wall(Vector2i(4, 4), Vector2i(20, 4))
	w.add_wall(Vector2i(4, 16), Vector2i(20, 16))
	w.add_wall(Vector2i(4, 4), Vector2i(4, 16))
	w.add_wall(Vector2i(20, 4), Vector2i(20, 16))
	w.add_wall(Vector2i(4, 10), Vector2i(20, 10))
	w.add_wall(Vector2i(10, 4), Vector2i(10, 10))
	w.add_wall(Vector2i(14, 4), Vector2i(14, 10))
	w.add_wall(Vector2i(11, 10), Vector2i(11, 16))
	# yard fence (gate at the front)
	w.set_wall_line(Vector2i(2, 2), Vector2i(30, 2), "fence", 0)
	w.set_wall_line(Vector2i(30, 2), Vector2i(30, 22), "fence", 0)
	w.set_wall_line(Vector2i(2, 22), Vector2i(30, 22), "fence", 0)
	w.set_wall_line(Vector2i(2, 2), Vector2i(2, 22), "fence", 0)
	w.set_edge(Vector3i(15, 22, 0), "door")   # gate

	# --- doors and windows (wall mounted)
	var P := func(id: String, x: int, y: int, r: int) -> void:
		var oid: int = w.place_object(id, Vector2i(x, y), r)
		if oid == -1:
			push_warning("starter_house: could not place %s at %d,%d (%s)" % [id, x, y, w.last_error])
	P.call("door", 9, 9, 2)     # bedroom A -> kitchen
	P.call("door", 11, 9, 2)    # bathroom -> living
	P.call("door", 16, 9, 2)    # bedroom B -> living
	P.call("door", 10, 12, 1)   # kitchen -> living
	P.call("door", 15, 15, 2)   # front door
	P.call("door", 7, 15, 2)    # back door
	P.call("window", 6, 4, 0)
	P.call("window", 4, 6, 3)
	P.call("window", 12, 4, 0)
	P.call("window", 16, 4, 0)
	P.call("window", 19, 6, 1)
	P.call("window", 4, 12, 3)
	P.call("window", 19, 12, 1)
	P.call("window", 18, 15, 2)
	P.call("window", 13, 15, 2)

	# --- bedroom A (two single beds)
	P.call("bed", 4, 4, 0)
	P.call("bed", 4, 7, 0)
	P.call("lamp", 7, 4, 0)
	P.call("bookshelf", 8, 4, 0)
	P.call("plant", 9, 8, 2)
	P.call("rug", 6, 6, 0)
	# --- bathroom
	P.call("toilet", 10, 4, 0)
	P.call("sink", 11, 4, 0)
	P.call("shower", 13, 4, 0)
	P.call("bathtub", 12, 7, 0)
	P.call("trash_bin", 10, 8, 2)
	# --- bedroom B / study
	P.call("bed", 14, 4, 0)
	P.call("computer", 18, 4, 0)
	P.call("easel", 14, 8, 2)
	P.call("plant", 19, 8, 2)
	P.call("rug", 16, 6, 0)
	# --- kitchen
	P.call("fridge", 4, 10, 0)
	P.call("counter", 5, 10, 0)
	P.call("stove", 6, 10, 0)
	P.call("counter", 7, 10, 0)
	P.call("sink", 8, 10, 0)
	P.call("table", 6, 13, 0)
	P.call("chair", 6, 12, 0)
	P.call("chair", 7, 12, 0)
	P.call("trash_bin", 10, 15, 2)
	P.call("plant", 4, 15, 2)
	# --- living room
	P.call("tv", 13, 10, 0)
	P.call("sofa", 13, 14, 2)
	P.call("rug", 13, 12, 0)
	P.call("bookshelf", 18, 10, 0)
	P.call("treadmill", 18, 13, 0)
	P.call("lamp", 15, 14, 2)
	P.call("plant", 19, 15, 2)
	# --- yard
	P.call("plant", 12, 18, 0)
	P.call("plant", 18, 18, 0)
	P.call("trash_bin", 21, 17, 0)

	w.starter_spawn_tiles.assign([Vector2i(6, 5), Vector2i(6, 8), Vector2i(16, 5)])
	w.starter_bedroom_tile = Vector2i(6, 5)
