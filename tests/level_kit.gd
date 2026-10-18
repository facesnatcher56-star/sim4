extends RefCounted
## Shared helpers for the multi-floor tests (no run(), so the runner skips it). Builds towers on the real World autoload.
##
## tower(): footprint Rect2i(4, 4, 16, 12). Level L has wood floors over the footprint and a perimeter wall. Stairs L -> L+1 alternate
## between two rows (y 6 on even levels, y 10 on odd levels): stairs at (6, y) rot 0 => walk on at (5, y) on level L, off at (8, y) on
## level L+1. A lift at (16, 8) (front tile (16, 9)) runs from level 0 to the top. Level 0 has a door in the south wall at (11, 15).

const FOOT := Rect2i(4, 4, 16, 12)
const LIFT := Vector2i(16, 8)

static func world() -> WorldGrid:
	return Engine.get_main_loop().root.get_node("World") as WorldGrid


static func stair_y(level: int) -> int:
	return 6 if posmod(level, 2) == 0 else 10


## Ring of wall edges around FOOT on `level`.
static func ring(W: WorldGrid, level: int) -> void:
	var r := FOOT
	for x in range(r.position.x, r.end.x):
		W.levels.set_edge(Vector3i(x, r.position.y, 0), "wall", level)
		W.levels.set_edge(Vector3i(x, r.end.y, 0), "wall", level)
	for y in range(r.position.y, r.end.y):
		W.levels.set_edge(Vector3i(r.position.x, y, 1), "wall", level)
		W.levels.set_edge(Vector3i(r.end.x, y, 1), "wall", level)


## A fresh 32x24 world with a tower of `floors` storeys (levels 0 .. floors-1), basements levels -1 .. -basements.
## Returns the building id.
static func tower(floors: int, with_lift: bool = true, basements: int = 0, with_stairs: bool = true) -> int:
	var W := world()
	W.reset(32, 24)
	var bid: int = W.levels.add_building(FOOT, -basements, floors - 1, {"roof": "flat"})
	for lv in range(-basements, floors):
		if lv != 0:
			W.levels.set_floor_rect_raw(FOOT.position, FOOT.end - Vector2i.ONE, "wood" if lv > 0 else "concrete", lv)
		ring(W, lv)
	W.set_floor_rect_raw(FOOT.position, FOOT.end - Vector2i.ONE, "wood")
	W.place_object("door", Vector2i(11, 15), 2)
	if with_stairs:
		for lv in range(0, floors - 1):
			var id: int = W.place_object("stairs", Vector2i(6, stair_y(lv)), 0, lv)
			assert(id >= 0, "stairs at level %d: %s" % [lv, W.last_error])
		for lv in range(-1, -basements - 1, -1):          # stairs down from lv+1 to lv (placed on the upper level)
			var id2: int = W.place_object("stairs_down", Vector2i(6, 13), 0, lv + 1)
			assert(id2 >= 0, "stairs_down at level %d: %s" % [lv + 1, W.last_error])
	if with_lift:
		var lift: int = W.place_object("elevator", LIFT, 0, 0)
		assert(lift >= 0, "lift: %s" % W.last_error)
	return bid


static func lift_id() -> int:
	var W := world()
	for o in W.objects_of_def("elevator"):
		return o.id
	return -1


## A tower of `floors` storeys on the CURRENT world (no reset) with the given footprint (at least 12 x 10 tiles): perimeter walls on every
## level, wood floors, stairs alternating between two rows near the west wall, a lift near the east wall, a ground door in the south wall.
## Returns the building id.
static func add_tower(W: WorldGrid, foot: Rect2i, floors: int, with_lift: bool = true) -> int:
	var bid: int = W.levels.add_building(foot, 0, floors - 1, {"roof": "flat"})
	for lv in range(0, floors):
		if lv != 0:
			W.levels.set_floor_rect_raw(foot.position, foot.end - Vector2i.ONE, "wood", lv)
		for x in range(foot.position.x, foot.end.x):
			W.levels.set_edge(Vector3i(x, foot.position.y, 0), "wall", lv)
			W.levels.set_edge(Vector3i(x, foot.end.y, 0), "wall", lv)
		for y in range(foot.position.y, foot.end.y):
			W.levels.set_edge(Vector3i(foot.position.x, y, 1), "wall", lv)
			W.levels.set_edge(Vector3i(foot.end.x, y, 1), "wall", lv)
	W.set_floor_rect_raw(foot.position, foot.end - Vector2i.ONE, "wood")
	W.place_object("door", Vector2i(foot.position.x + foot.size.x / 2, foot.end.y - 1), 2)
	for lv in range(0, floors - 1):
		var y: int = foot.position.y + (2 if posmod(lv, 2) == 0 else 6)
		var id: int = W.place_object("stairs", Vector2i(foot.position.x + 2, y), 0, lv)
		assert(id >= 0, "tower stairs level %d: %s" % [lv, W.last_error])
	if with_lift:
		var lid: int = W.place_object("elevator", Vector2i(foot.end.x - 3, foot.position.y + 4), 0, 0)
		assert(lid >= 0, "tower lift: %s" % W.last_error)
	return bid
