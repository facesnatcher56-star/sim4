class_name WorldRoomsLevels
extends RefCounted
## Rooms of ONE upper / lower level of a building (same result shape as WorldRooms._build_part, so every room query works per level).
## Flood fill over the level's floor tiles between its wall edges. A room is OUTDOOR when it is open to the outside: it touches the
## building rectangle, a fence, or a tile with no floor (void), or it is on the top level of a building with no roof.
## Stairwell openings (holes) are open air inside the building and do not count as void.

const DX := [1, -1, 0, 0]
const DY := [0, 0, 1, -1]
const EX := [1, 0, 0, 0]
const EY := [0, 0, 1, 0]
const EZ := [1, 1, 0, 0]


static func build(world: WorldGrid, level: int, bid: int, base: int) -> Dictionary:
	var rooms: Array = []
	var room_of: Dictionary = {}
	var b: Dictionary = world.levels.building(bid)
	var lay: LevelLayer = world.levels.layer(level, false)
	if b.is_empty() or lay == null:
		return {"rooms": rooms, "room_of": room_of}
	var rc: Rect2i = b["rect"]
	var open_sky: bool = level == int(b["max"]) and str(b["roof"]) == "none"
	var walls: Dictionary = lay.walls
	for start in lay.floors:
		if room_of.has(start) or not rc.has_point(start) or lay.holes.has(start):
			continue
		var idx := rooms.size()
		var tiles: Array[Vector2i] = []
		var outdoor := open_sky
		var stack: Array[Vector2i] = [start]
		room_of[start] = idx
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			tiles.append(c)
			for k in 4:
				var nb := Vector2i(c.x + DX[k], c.y + DY[k])
				var wt: String = walls.get(Vector3i(c.x + EX[k], c.y + EY[k], EZ[k]), "")
				if wt != "":
					if wt == "fence":
						outdoor = true
					continue
				if not rc.has_point(nb):
					outdoor = true
					continue
				if not lay.floors.has(nb):
					if not lay.holes.has(nb):
						outdoor = true       # open edge of the floor: air
					continue
				if lay.holes.has(nb) or room_of.has(nb):
					continue
				room_of[nb] = idx
				stack.append(nb)
		rooms.append({"id": base + idx, "tiles": tiles, "outdoor": outdoor})
	_score(world, rooms, room_of, rc, level, lay)
	return {"rooms": rooms, "room_of": room_of}


static func _score(world: WorldGrid, rooms: Array, room_of: Dictionary, rc: Rect2i, level: int, lay: LevelLayer) -> void:
	var decor_of: Dictionary = {}
	for r in rooms:
		var fl := 0.0
		var ms := 0.0
		for t in r["tiles"]:
			var ft: String = lay.floors.get(t, "")
			if not decor_of.has(ft):
				decor_of[ft] = float((world.FLOOR_DEFS.get(ft, {}) as Dictionary).get("decor", 0.0))
			fl += decor_of[ft]
			ms += float(world.mess.get(t, 0.0)) if level == 0 else 0.0
		r["decor"] = 0.0
		r["objects"] = []
		r["mess"] = ms
		r["floor_decor"] = fl / maxf(1.0, float(r["tiles"].size()))
	var oids: Dictionary = {}
	for c in world.regions.chunks_in_rect(rc):
		for id in world.regions.chunk_objects(c):
			oids[id] = true
	for id in oids:
		var o = world.objects.get(id, null)
		if o == null or o.level != level or not rc.has_point(o.tile):
			continue
		var idx: int = room_of.get(o.tile, -1)
		if idx == -1:
			continue
		var cv: Vector2 = o.env_contribution()
		var r: Dictionary = rooms[idx]
		r["decor"] += cv.x
		r["mess"] += cv.y
		r["objects"].append(o.id)
	for r in rooms:
		r["score"] = float(r["decor"]) + float(r["floor_decor"]) * 3.0 - float(r["mess"])
		r["cleanliness"] = 1.0 / (1.0 + float(r["mess"]) / 4.0)


## Line of sight between two tiles of one level: nothing blocks it except a solid wall edge crossed on the way (windows, doors and
## fences are see-through). Different levels never see each other except through a stairwell hole (adjacent levels, hole tile).
static func can_see(world: WorldGrid, a: Vector3i, b: Vector3i) -> bool:
	if a.z != b.z:
		if absi(a.z - b.z) != 1:
			return false
		var up := a if a.z > b.z else b
		var lay_up := world.levels.layer(up.z, false)
		var t := Vector2i(up.x, up.y)
		return lay_up != null and lay_up.holes.has(t) or world.levels.ground_holes.has(t) and up.z == 0
	var walls: Dictionary = world.levels.walls_of(a.z)
	if walls.is_empty():
		return true
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	var cx := x0
	var cy := y0
	while cx != b.x or cy != b.y:
		var e2 := 2 * err
		var nx := cx
		var ny := cy
		if e2 > -dy:
			err -= dy
			nx += sx
		if e2 < dx:
			err += dx
			ny += sy
		# crossing from (cx,cy) to (nx,ny): check the edge(s) crossed
		if nx != cx:
			if _blocks(walls, Vector3i(maxi(cx, nx), cy, 1)):
				return false
		if ny != cy:
			if _blocks(walls, Vector3i(nx, maxi(cy, ny), 0)):
				return false
		cx = nx
		cy = ny
	return true


static func _blocks(walls: Dictionary, e: Vector3i) -> bool:
	return str(walls.get(e, "")) == "wall"
