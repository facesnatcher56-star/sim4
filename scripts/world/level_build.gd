class_name LevelBuild
extends RefCounted
## Build mode for multi-floor buildings (`World.lbuild`): add a floor above / a basement below, paint floors and draw walls on a level,
## roof styles, the STRUCTURE RULES and their prices. Objects are placed with World.buy_place(..., level) as always.
##
## Rules (the player sees these messages):
##   - A floor on level 1 and up must be SUPPORTED: the tile below has a floor (levels above the first) and a wall edge or a pillar
##     (object tag "support") of the level below lies within SUPPORT_SPAN tiles. Nothing floats. Basements rest on the earth.
##   - A level can only be added while a staircase / ladder / lift reaches it: a stair or ladder going up placed on the top level, or a
##     lift running to the top level (basements: a stair or ladder going down on the lowest level).
##   - You cannot remove a wall, pillar or floor that a floor above rests on.
##   - Cost grows with each level: LEVEL_BASE + LEVEL_STEP per level above the first (basements dearer), + walls and floors, + roof.
## The new level starts as the footprint of the level below (floor everywhere that is roofed / walled there) with an outer wall, so the
## player can subdivide it at once. Undo reverses it all.

const SUPPORT_SPAN := 4
const LEVEL_BASE := 700
const LEVEL_STEP := 300
const BASEMENT_BASE := 900
const BASEMENT_STEP := 350
const ROOF_STYLES := ["flat", "gable", "hip", "none"]
const ROOF_PRICE := {"flat": 300, "gable": 500, "hip": 650, "none": 0}
const NEW_FLOOR := "wood"
const NEW_BASEMENT_FLOOR := "concrete"
const MSG_SUPPORT := "Floors need a wall or pillar underneath (within 4 tiles)."

var world: WorldGrid


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ buildings

## The building record at a tile; creates one for a lot region (the whole lot is the footprint) when there is none yet. -1 if the
## tile belongs to no lot (open ground).
func ensure_building(tile: Vector2i) -> int:
	var bid := world.levels.building_at(tile)
	if bid >= 0:
		return bid
	var rid := world.regions.region_at(tile)
	if rid >= 0 and world.regions.is_lot(rid):
		return world.levels.add_building(world.regions.regions[rid]["rect"], 0, 0, {"region": rid})
	if not world.regions.has_regions():
		return world.levels.add_building(Rect2i(0, 0, world.width, world.height), 0, 0, {})
	return -1


func level_price(level: int) -> int:
	if level > 0:
		return LEVEL_BASE + LEVEL_STEP * (level - 1)
	return BASEMENT_BASE + BASEMENT_STEP * (-level - 1)


# ------------------------------------------------------------------ support

## Tiles of `level` that are within SUPPORT_SPAN of one of its wall edges or pillars. `ignore` = edges treated as removed,
## `skip_obj` = object id treated as removed.
func support_cover(level: int, bid: int, ignore: Dictionary = {}, skip_obj: int = -1) -> Dictionary:
	var rc: Rect2i = world.levels.building(bid).get("rect", Rect2i())
	var src: Dictionary = {}
	var walls: Dictionary = world.levels.walls_of(level)
	for e in walls:
		if ignore.has(e) or not (str(walls[e]) in ["wall", "window", "door"]):
			continue
		src[Vector2i(e.x, e.y)] = true
		src[Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y)] = true
	for o in world.objects.values():
		if o.level == level and o.id != skip_obj and o.has_tag("support") and rc.has_point(o.tile):
			src[o.tile] = true
	var cover: Dictionary = {}
	for t in src:
		for dy in range(-SUPPORT_SPAN, SUPPORT_SPAN + 1):
			for dx in range(-SUPPORT_SPAN, SUPPORT_SPAN + 1):
				cover[Vector2i(t.x + dx, t.y + dy)] = true
	return cover


## May there be a floor at (tile, level)? Level <= 0 always; above: floor below + a support nearby.
func supported(tile: Vector2i, level: int, cover: Dictionary = {}) -> bool:
	if level <= 0:
		return true
	var below := level - 1
	if below != 0 and world.levels.floor_at(tile, below) == "":
		return false
	if cover.is_empty():
		var bid := world.levels.building_at(tile)
		cover = support_cover(below, bid)
	return cover.has(tile)


## Would removing these wall edges (level `level`) leave a floor above floating? "" = fine, else the message.
func removal_blocked(edges: Array, level: int, skip_obj: int = -1) -> String:
	if not world.levels.any():
		return ""
	var bid := world.levels.building_at(Vector2i(edges[0].x, edges[0].y)) if not edges.is_empty() else -1
	if bid < 0 or not world.levels.has_level(bid, level + 1):
		return ""
	var up := world.levels.layer(level + 1, false)
	if up == null or up.floors.is_empty():
		return ""
	var ignore: Dictionary = {}
	for e in edges:
		ignore[e] = true
	var cover := support_cover(level, bid, ignore, skip_obj)
	for t in up.floors:
		if not cover.has(t):
			return "The floor above rests on this."
	return ""


func can_remove_object(o) -> String:
	if not o.has_tag("support"):
		return ""
	return _support_obj_blocked(o)


func _support_obj_blocked(o) -> String:
	var bid := world.levels.building_at(o.tile)
	if bid < 0 or not world.levels.has_level(bid, o.level + 1):
		return ""
	var up := world.levels.layer(o.level + 1, false)
	if up == null:
		return ""
	var cover := support_cover(o.level, bid, {}, o.id)
	for t in up.floors:
		if not cover.has(t):
			return "The floor above rests on this."
	return ""


# ------------------------------------------------------------------ adding levels

func _top_reaches(bid: int, above: bool) -> bool:
	var b: Dictionary = world.levels.building(bid)
	var edge: int = int(b["max"]) if above else int(b["min"])
	for rec in world.portals.portals.values():
		if world.levels.building_at(rec["tile"]) != bid:
			continue
		var k := str(rec["kind"])
		if k == "elevator":
			if above and int(rec["top"]) >= edge and int(rec["base"]) <= edge:
				return true
		elif int(rec["base"]) == edge and ((above and int(rec["dz"]) > 0) or (not above and int(rec["dz"]) < 0)):
			return true
	return false


## "" when a level can be added now, else why not.
func why_not_add(bid: int, above: bool) -> String:
	var b: Dictionary = world.levels.building(bid)
	if b.is_empty():
		return "You can only build floors on a building lot."
	if world.levels.level_count(bid) >= WorldLevels.MAX_LEVELS:
		return "That is as tall as buildings go."
	if not _top_reaches(bid, above):
		return "Place stairs, a ladder or a lift going %s on the %s floor first." % ["up" if above else "down", "top" if above else "lowest"]
	return ""


## Add a floor above (above = true) or a basement below. Returns the new level number, or 0 when it failed (World.last_error says why).
func add_level(bid: int, above: bool, household_id: int = -1) -> int:
	var why := why_not_add(bid, above)
	if why != "":
		world.last_error = why
		return 0
	var b: Dictionary = world.levels.building(bid)
	var rc: Rect2i = b["rect"]
	var cur: int = int(b["max"]) if above else int(b["min"])
	var new_level: int = cur + 1 if above else cur - 1
	if not world.regions.can_build(rc.position + rc.size / 2) and not world.regions.can_build(rc.position):
		world.regions.deny()
		return 0
	var hid := world.current_household_id if household_id < 0 else household_id
	# footprint = floors of the level below that are roofed / walled (ground level: indoor rooms)
	var tiles: Array[Vector2i] = _footprint(bid, cur)
	if tiles.is_empty():
		world.last_error = "Build walls and a floor on this level first."
		return 0
	var land := _landing_tiles(bid, new_level)
	for t in land:
		if not tiles.has(t) and rc.has_point(t):
			tiles.append(t)
	var set_t: Dictionary = {}
	for t in tiles:
		set_t[t] = true
	var edges: Array[Vector3i] = _outline(set_t)
	var cost: int = level_price(new_level) + tiles.size() * world.FLOOR_PRICE + edges.size() * world.WALL_PRICE
	if not world._spend(hid, cost):
		world.last_error = "not enough coins"
		return 0
	var ftype := NEW_FLOOR if above else NEW_BASEMENT_FLOOR
	var lay := world.levels.layer(new_level)
	for t in tiles:
		lay.floors[t] = ftype
	for e in edges:
		lay.walls[e] = "wall"
	lay.touch()
	var old_lo: int = int(b["min"])
	var old_hi: int = int(b["max"])
	if above:
		world.levels.set_range(bid, old_lo, new_level)
		_extend_lifts(bid, new_level)
	else:
		world.levels.set_range(bid, new_level, old_hi)
	world.rooms.invalidate_all()
	world._emit("walls_changed")
	world._emit("floors_changed")
	world._push_undo({"t": "lv_add", "bid": bid, "level": new_level, "above": above, "cost": cost, "hid": hid, "lo": old_lo, "hi": old_hi})
	return new_level


## Tiles that get a floor on the new level: floors of the level below (ground: indoor tiles), not stairwell openings.
func _footprint(bid: int, below: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rc: Rect2i = world.levels.building(bid)["rect"]
	if below == 0:
		for y in range(rc.position.y, rc.end.y):
			for x in range(rc.position.x, rc.end.x):
				var t := Vector2i(x, y)
				if not world.rooms.is_outdoor(t, 0) and not world.levels.ground_holes.has(t):
					out.append(t)
	else:
		var lay := world.levels.layer(below, false)
		if lay != null:
			for t in lay.floors:
				if not lay.holes.has(t):
					out.append(t)
	return out


## Landing tiles of the stairs / ladders that end on `level` (they must be walkable there).
func _landing_tiles(bid: int, level: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for rec in world.portals.portals.values():
		if world.levels.building_at(rec["tile"]) != bid or str(rec["kind"]) == "elevator":
			continue
		var ends: Array = rec["stairs"]
		if ends[1].z == level:
			out.append(LPos.tile(ends[1]))
		if ends[0].z == level:
			out.append(LPos.tile(ends[0]))
	return out


## Edges around a tile set (the outer wall of a new level).
func _outline(set_t: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for t in set_t:
		if not set_t.has(Vector2i(t.x, t.y - 1)):
			out.append(Vector3i(t.x, t.y, 0))
		if not set_t.has(Vector2i(t.x, t.y + 1)):
			out.append(Vector3i(t.x, t.y + 1, 0))
		if not set_t.has(Vector2i(t.x - 1, t.y)):
			out.append(Vector3i(t.x, t.y, 1))
		if not set_t.has(Vector2i(t.x + 1, t.y)):
			out.append(Vector3i(t.x + 1, t.y, 1))
	return out


## Lifts that ran to the old top now run to the new one.
func _extend_lifts(bid: int, new_top: int) -> void:
	for rec in world.portals.portals.values().duplicate():
		if str(rec["kind"]) != "elevator" or world.levels.building_at(rec["tile"]) != bid or int(rec["top"]) != new_top - 1:
			continue
		var o = world.objects.get(int(rec["id"]), null)
		if o == null:
			continue
		var lay := world.levels.layer(new_top)
		if not lay.floors.has(o.tile) or lay.occ.has(o.tile):
			continue
		world.portals.on_removed(o)
		o.span += 1
		world.portals.on_created(o)


## Remove the top / bottom level again (undo of add_level; also a player "remove floor" when it is empty).
func remove_level(bid: int, level: int, lo: int, hi: int) -> void:
	world.levels.layers.erase(level)
	world.levels.set_range(bid, lo, hi)
	for o in world.objects.values().duplicate():
		if o.level == level:
			world.remove_object(o.id)
		elif o.span > 0 and o.level + o.span >= level and o.level < level:
			world.portals.on_removed(o)
			o.span = level - 1 - o.level
			world.portals.on_created(o)
	world.rooms.invalidate_all()
	world.levels.touch()
	world._emit("walls_changed")
	world._emit("floors_changed")


func set_roof(bid: int, style: String, household_id: int = -1) -> bool:
	var b: Dictionary = world.levels.building(bid)
	if b.is_empty() or not (style in ROOF_STYLES):
		world.last_error = "bad roof"
		return false
	if str(b["roof"]) == style:
		return true
	var hid := world.current_household_id if household_id < 0 else household_id
	var cost: int = int(ROOF_PRICE[style])
	if not world._spend(hid, cost):
		world.last_error = "not enough coins"
		return false
	var old := str(b["roof"])
	b["roof"] = style
	world.levels.touch()
	world.rooms.invalidate_all()
	world._emit("floors_changed")
	world._push_undo({"t": "lv_roof", "bid": bid, "old": old, "cost": cost, "hid": hid})
	return true


# ------------------------------------------------------------------ painting / walls on a level

func _tile_ok(t: Vector2i, level: int) -> bool:
	var bid := world.levels.building_at(t)
	return bid >= 0 and world.levels.has_level(bid, level) and world.regions.can_build(t)


func paint_floor_rect(a: Vector2i, b: Vector2i, type: String, household_id: int, level: int) -> int:
	var erase := type == "none"
	if not erase and not world.FLOOR_DEFS.has(type):
		world.last_error = "bad floor type"
		return 0
	var hid := world.current_household_id if household_id < 0 else household_id
	var lay := world.levels.layer(level)
	var changes: Array = []
	var covers: Dictionary = {}
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			var t := Vector2i(x, y)
			if not _tile_ok(t, level):
				continue
			var old: String = lay.floors.get(t, "")
			if (erase and old == "") or old == type or lay.holes.has(t):
				continue
			if erase:
				var up := world.levels.layer(level + 1, false)
				if up != null and up.floors.has(t) and world.levels.has_level(world.levels.building_at(t), level + 1):
					world.last_error = "There is a floor above."
					return 0
			elif level > 0:
				var bid := world.levels.building_at(t)
				if not covers.has(bid):
					covers[bid] = support_cover(level - 1, bid)
				if not supported(t, level, covers[bid]):
					world.last_error = MSG_SUPPORT
					return 0
			changes.append({"t": t, "old": old})
	if changes.is_empty():
		return 0
	var cost: int = 0 if erase else changes.size() * world.FLOOR_PRICE
	if not world._spend(hid, cost):
		world.last_error = "not enough coins"
		return 0
	for c in changes:
		if erase:
			lay.floors.erase(c["t"])
		else:
			lay.floors[c["t"]] = type
		world.rooms.mark_dirty(c["t"], level)
	lay.touch()
	world.levels.touch()
	world._emit("floors_changed")
	world._push_undo({"t": "lv_floor", "level": level, "changes": changes, "cost": cost, "hid": hid})
	return changes.size()


func set_wall_line(a: Vector2i, b: Vector2i, type: String, household_id: int, level: int) -> int:
	if type != "none" and not (type in world.WALL_TYPES):
		world.last_error = "bad wall type"
		return 0
	var hid := world.current_household_id if household_id < 0 else household_id
	var new_t := "" if type == "none" else type
	var todo: Array[Vector3i] = []
	for e in world._line_edges(a, b):
		if world.levels.wall_at(e, level) == new_t:
			continue
		if not world.edge_valid(e) or not (_tile_ok(Vector2i(e.x, e.y), level) or _tile_ok(Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y), level)):
			continue
		todo.append(e)
	if todo.is_empty():
		return 0
	if new_t == "":
		var why := removal_blocked(todo, level)
		if why != "":
			world.last_error = why
			return 0
	var cost: int = 0 if new_t == "" else todo.size() * world.WALL_PRICE
	if not world._spend(hid, cost):
		world.last_error = "not enough coins"
		return 0
	var rec: Array = []
	for e in todo:
		var old: String = world.levels.wall_at(e, level)
		var obj_data: Dictionary = {}
		var mid: int = world.levels.mounts_of(level).get(e, -1)
		if mid >= 0:
			obj_data = world.objects[mid].to_dict()
		if world.levels.set_edge(e, type, level):
			rec.append({"e": e, "old": old, "obj": obj_data})
	world._push_undo({"t": "lv_walls", "level": level, "changes": rec, "cost": cost, "hid": hid})
	return rec.size()


# ------------------------------------------------------------------ portals

## Extra placement rules of stairs / ladders / lifts (called by WorldObjects.can_place).
func portal_fits(d: Dictionary, tile: Vector2i, rot: int, level: int) -> bool:
	var pd: Dictionary = d.get("portal", {})
	var bid := ensure_building(tile)
	if bid < 0:
		world.last_error = "Stairs and lifts go inside a building lot."
		return false
	var b: Dictionary = world.levels.building(bid)
	var kind := str(pd.get("kind", "stairs"))
	if level < int(b["min"]) or level > int(b["max"]):
		world.last_error = "there is no floor here"
		return false
	var dz := int(pd.get("dz", 1))
	if kind == "elevator":
		for m in range(level + 1, int(b["max"]) + 1):
			var lay := world.levels.layer(m, false)
			if lay == null or not lay.floors.has(tile) or lay.occ.has(tile) or lay.holes.has(tile):
				world.last_error = "The lift shaft needs floor and free space on every floor above."
				return false
		return true
	if dz > 0:
		var fp := WorldObject.footprint_of(d, tile, rot)
		var upper := world.levels.layer(level + 1, false)
		for t in fp:
			if upper != null and upper.occ.has(t):
				world.last_error = "Something is in the way upstairs."
				return false
	return true


# ------------------------------------------------------------------ undo

func undo(op: Dictionary) -> bool:
	match str(op["t"]):
		"lv_add":
			remove_level(int(op["bid"]), int(op["level"]), int(op["lo"]), int(op["hi"]))
			world.build._refund(int(op["hid"]), int(op["cost"]))
		"lv_roof":
			world.levels.building(int(op["bid"]))["roof"] = str(op["old"])
			world.levels.touch()
			world.rooms.invalidate_all()
			world._emit("floors_changed")
			world.build._refund(int(op["hid"]), int(op["cost"]))
		"lv_floor":
			var lay := world.levels.layer(int(op["level"]))
			for c in op["changes"]:
				if str(c["old"]) == "":
					lay.floors.erase(c["t"])
				else:
					lay.floors[c["t"]] = str(c["old"])
				world.rooms.mark_dirty(c["t"], int(op["level"]))
			lay.touch()
			world.levels.touch()
			world._emit("floors_changed")
			world.build._refund(int(op["hid"]), int(op["cost"]))
		"lv_walls":
			var level := int(op["level"])
			var changes: Array = op["changes"]
			for i in range(changes.size() - 1, -1, -1):
				var c: Dictionary = changes[i]
				world.levels.set_edge(c["e"], str(c["old"]), level)
				var od: Dictionary = c["obj"]
				if not od.is_empty():
					var t2: Array = od["tile"]
					var nid := world._create_object(str(od["def_id"]), Vector2i(t2[0], t2[1]), int(od["rot"]), int(od["id"]), level)
					if nid != -1:
						world.objects[nid].state = (od["state"] as Dictionary).duplicate(true)
			world.build._refund(int(op["hid"]), int(op["cost"]))
		_:
			return false
	return true
