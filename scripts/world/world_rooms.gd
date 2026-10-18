class_name WorldRooms
extends RefCounted
## Room detection (flood fill between walls) with decor / cleanliness scores.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

var world: WorldGrid
var dirty: bool = true
var _room_of: Dictionary = {}             # tile -> room index
var _rooms: Array = []                    # {id, tiles:Array[Vector2i], outdoor:bool}


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ rooms

func _rebuild_rooms() -> void:
	_rooms.clear()
	_room_of.clear()
	for y in world.height:
		for x in world.width:
			var start := Vector2i(x, y)
			if _room_of.has(start):
				continue
			var idx := _rooms.size()
			var tiles: Array[Vector2i] = []
			var outdoor := false
			var stack: Array[Vector2i] = [start]
			_room_of[start] = idx
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				tiles.append(c)
				if c.x == 0 or c.y == 0 or c.x == world.width - 1 or c.y == world.height - 1:
					outdoor = true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = c + d
					if not world.in_bounds(nb):
						continue
					var wt: String = world.walls.get(world.edge_between(c, nb), "")
					if wt != "":
						if wt == "fence":
							outdoor = true   # fenced-only areas are still outdoors
						continue   # any wall type incl. door separates rooms
					if _room_of.has(nb):
						continue
					_room_of[nb] = idx
					stack.append(nb)
			_rooms.append({"id": idx, "tiles": tiles, "outdoor": outdoor})
	dirty = false
	# compute scores
	for r in _rooms:
		r["decor"] = 0.0
		r["mess"] = 0.0
		r["objects"] = []
		var fl := 0.0
		for t in r["tiles"]:
			fl += float((world.FLOOR_DEFS.get(world.get_floor(t), {}) as Dictionary).get("decor", 0.0))
			r["mess"] += float(world.mess.get(t, 0.0))
		r["floor_decor"] = fl / maxf(1.0, float(r["tiles"].size()))
	for o in world.objects.values():
		var rid := -1
		if o.is_wall_mounted():
			# belongs to the room on the side it was placed from
			rid = _room_of.get(o.tile, -1)
		else:
			rid = _room_of.get(o.tile, -1)
		if rid == -1:
			continue
		var c: Vector2 = o.env_contribution()
		_rooms[rid]["decor"] += c.x
		_rooms[rid]["mess"] += c.y
		_rooms[rid]["objects"].append(o.id)
	for r in _rooms:
		r["score"] = float(r["decor"]) + float(r["floor_decor"]) * 3.0 - float(r["mess"])
		r["cleanliness"] = 1.0 / (1.0 + float(r["mess"]) / 4.0)

func _ensure_rooms() -> void:
	if dirty:
		_rebuild_rooms()

func room_id(tile: Vector2i) -> int:
	_ensure_rooms()
	return _room_of.get(tile, -1)

func room_tiles(tile: Vector2i) -> Array[Vector2i]:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	if rid == -1:
		return []
	return _rooms[rid]["tiles"]

func is_outdoor(tile: Vector2i) -> bool:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	return rid != -1 and _rooms[rid]["outdoor"]

func room_count() -> int:
	_ensure_rooms()
	return _rooms.size()

func room_info(tile: Vector2i) -> Dictionary:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	if rid == -1:
		return {}
	var r: Dictionary = _rooms[rid]
	return {"id": rid, "size": r["tiles"].size(), "outdoor": r["outdoor"], "decor": r["decor"],
		"mess": r["mess"], "floor_decor": r["floor_decor"], "score": r["score"],
		"cleanliness": r["cleanliness"], "objects": (r["objects"] as Array).duplicate()}

## Environment score of the room containing `tile`: sum(decor) + floor bonus - mess. ~ -10..+20.
func room_score(tile: Vector2i) -> float:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	return 0.0 if rid == -1 else float(_rooms[rid]["score"])

## 0..1 (1 = spotless)
func room_cleanliness(tile: Vector2i) -> float:
	_ensure_rooms()
	var rid: int = _room_of.get(tile, -1)
	return 1.0 if rid == -1 else float(_rooms[rid]["cleanliness"])
