class_name WorldEdit
extends RefCounted
## Wall and floor editing.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

var world: WorldGrid


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ walls / floors

## Wall segment along a vertex line (vertex coords 0..width / 0..height). Axis-aligned only.
func add_wall(a: Vector2i, b: Vector2i) -> void:
	_apply_wall_line(a, b, "wall", null)

func _line_edges(a: Vector2i, b: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if a.y == b.y:
		for x in range(mini(a.x, b.x), maxi(a.x, b.x)):
			out.append(Vector3i(x, a.y, 0))
	elif a.x == b.x:
		for y in range(mini(a.y, b.y), maxi(a.y, b.y)):
			out.append(Vector3i(a.x, y, 1))
	return out

## Set one edge. type "" or "none" erases. Handles wall-mounted objects. Returns true if changed.
func set_edge(e: Vector3i, type: String) -> bool:
	if not world.edge_valid(e):
		return false
	if type == "none":
		type = ""
	var old: String = world.walls.get(e, "")
	if old == type:
		return false
	if world.mounts.has(e):
		world.remove_object(world.mounts[e])
	if type == "":
		world.walls.erase(e)
	else:
		world.walls[e] = type
	world.rooms.mark_dirty_edge(e)
	world.nav.touch_edge(e)
	world._emit("walls_changed")
	return true

func _apply_wall_line(a: Vector2i, b: Vector2i, type: String, rec: Variant) -> int:
	var count := 0
	for e in _line_edges(a, b):
		var old: String = world.walls.get(e, "")
		var new_t := "" if type == "none" else type
		if old == new_t:
			continue
		var obj_data: Dictionary = {}
		if world.mounts.has(e):
			obj_data = world.objects[world.mounts[e]].to_dict()
		if set_edge(e, type):
			count += 1
			if rec != null:
				(rec as Array).append({"e": e, "old": old, "new": new_t, "obj": obj_data})
	return count

## Build tool: draw (or erase with "none") a wall line. Charges coins when an economy exists.
## Returns number of edges changed (0 if nothing/can't afford).
func set_wall_line(a: Vector2i, b: Vector2i, type: String = "wall", household_id: int = -1) -> int:
	var hid := world.current_household_id if household_id < 0 else household_id
	if type != "none" and not (type in world.WALL_TYPES):
		world.last_error = "bad wall type"
		return 0
	# count edges that would change for pricing
	var would := 0
	for e in _line_edges(a, b):
		if world.walls.get(e, "") != ("" if type == "none" else type):
			if not world.regions.can_build_edge(e):
				world.regions.deny()
				return 0
			would += 1
	if would == 0:
		return 0
	var cost := 0 if type == "none" else would * world.WALL_PRICE
	if cost > 0 and not world._spend(hid, cost):
		world.last_error = "not enough coins"
		return 0
	var rec: Array = []
	var n := _apply_wall_line(a, b, type, rec)
	world._push_undo({"t": "walls", "changes": rec, "cost": cost, "hid": hid})
	return n

func paint_floor(t: Vector2i, type: String, household_id: int = -1) -> bool:
	return paint_floor_rect(t, t, type, household_id) > 0

func paint_floor_rect(a: Vector2i, b: Vector2i, type: String, household_id: int = -1) -> int:
	if not world.FLOOR_DEFS.has(type):
		world.last_error = "bad floor type"
		return 0
	var hid := world.current_household_id if household_id < 0 else household_id
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var changes: Array = []
	var denied := false
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var t := Vector2i(x, y)
			if world.in_bounds(t) and world.get_floor(t) != type:
				if not world.regions.can_build(t):
					denied = true
					continue
				changes.append({"t": t, "old": world.get_floor(t)})
	if changes.is_empty():
		if denied:
			world.regions.deny()
		return 0
	var cost: int = changes.size() * world.FLOOR_PRICE
	if not world._spend(hid, cost):
		world.last_error = "not enough coins"
		return 0
	for c in changes:
		world.floors[c["t"].y * world.width + c["t"].x] = type
		world.regions.mark_floor_dirty(c["t"])
	world.rooms.mark_dirty_rect(lo, hi)
	world._emit("floors_changed")
	world._push_undo({"t": "floor", "changes": changes, "new": type, "cost": cost, "hid": hid})
	return changes.size()

## Raw floor set (no coins/undo) used by loaders and the starter house.
func set_floor_raw(t: Vector2i, type: String) -> void:
	if world.in_bounds(t):
		world.floors[t.y * world.width + t.x] = type
		if bool((world.FLOOR_DEFS.get(type, {}) as Dictionary).get("blocks", false)):
			world._blocked[t] = true            # water: not walkable
		world.regions.mark_floor_dirty(t)
		world.rooms.mark_dirty(t)

func set_floor_rect_raw(a: Vector2i, b: Vector2i, type: String) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			set_floor_raw(Vector2i(x, y), type)
	world._emit("floors_changed")
