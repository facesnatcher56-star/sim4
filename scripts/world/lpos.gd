class_name LPos
extends RefCounted
## Level-aware position helper. A position on a level is a Vector3i(x, y, level): x / y are the usual tile coordinates,
## z is the LEVEL (0 = ground, negative = basements, no upper limit). A plain Vector2i tile always means level 0.
## Routes (World.find_route) are Arrays of Vector3i. Folk / WorldObject keep `tile: Vector2i` and `level: int` side by side.

const H := 3.0                    # metres from one floor surface to the next (slab 0.2 + walls 2.6 + gap)
const SLAB := 0.2


static func make(tile: Vector2i, level: int = 0) -> Vector3i:
	return Vector3i(tile.x, tile.y, level)


static func tile(p: Vector3i) -> Vector2i:
	return Vector2i(p.x, p.y)


static func level(p: Vector3i) -> int:
	return p.z


## World height (metres) of the floor surface of a level.
static func elev(level: int) -> float:
	return float(level) * H


## Level whose floor is nearest to a world height.
static func level_at_y(y: float) -> int:
	return roundi(y / H)


## Short label for buttons: G (ground), 1, 2, 3 ... above, B1, B2 ... below.
static func level_label(level: int) -> String:
	if level == 0:
		return "G"
	return str(level) if level > 0 else "B%d" % -level


## Words for tooltips and the build panel: "Ground floor", "3rd floor", "Basement 2".
static func level_name(level: int) -> String:
	if level == 0:
		return "Ground floor"
	if level < 0:
		return "Basement %d" % -level
	var suffix := "th"
	if level % 100 < 11 or level % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(level % 10, "th")
	return "%d%s floor" % [level, suffix]


## Tiles of a route as plain Vector2i (levels dropped).
static func tiles_of(route: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in route:
		out.append(Vector2i(p.x, p.y))
	return out
