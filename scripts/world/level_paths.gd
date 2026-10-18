class_name LevelPaths
extends RefCounted
## Tile A* inside ONE upper / lower level (level != 0) of a building: floors are sparse (a tile without a floor is void), walls sit on
## edges exactly like the ground (BLOCKING_WALLS stop you, doors do not), blocking objects / stairwells are in `blocked`.
## Search is confined to the building rectangle, so an unreachable goal fails after at most rect-area expansions.
## Same conventions as WorldPaths: the path EXCLUDES the start, INCLUDES the goal, a blocked goal (slot inside furniture) is allowed,
## the length of a path is its number of steps (a diagonal counts 1).

const DXS := [1, -1, 0, 0, 1, 1, -1, -1]
const DYS := [0, 0, 1, -1, 1, -1, 1, -1]


static func find_path(world: WorldGrid, level: int, from: Vector2i, to: Vector2i, rect: Rect2i, diagonals: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lay: LevelLayer = world.levels.layer(level, false)
	if lay == null or from == to or not rect.has_point(from) or not rect.has_point(to) or not lay.floors.has(to):
		return out
	var ww := rect.size.x
	var ox := rect.position.x
	var oy := rect.position.y
	var n := ww * rect.size.y
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var floors: Dictionary = lay.floors
	var blocked: Dictionary = lay.blocked
	var walls: Dictionary = lay.walls
	var ndirs := 8 if diagonals else 4
	var heap := PackedInt64Array()
	var si := (from.y - oy) * ww + (from.x - ox)
	var gi := (to.y - oy) * ww + (to.x - ox)
	g[si] = 0.0
	WorldPaths._ipush(heap, _key(_h(from, to), si))
	var found := false
	while heap.size() > 0:
		var ci: int = WorldPaths._ipop(heap) & 0xFFFFFF
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		if ci == gi:
			found = true
			break
		var cx := ci % ww + ox
		var cy := ci / ww + oy
		var cur := Vector2i(cx, cy)
		var gc: float = g[ci]
		for k in ndirs:
			var nx: int = cx + DXS[k]
			var ny: int = cy + DYS[k]
			if nx < ox or ny < oy or nx >= rect.end.x or ny >= rect.end.y:
				continue
			var ni := (ny - oy) * ww + (nx - ox)
			if closed[ni] == 1:
				continue
			var nb := Vector2i(nx, ny)
			if not floors.has(nb) or (blocked.has(nb) and nb != to):
				continue
			var cost := 1.0
			if k < 4:
				if _wall_between(walls, cur, nb):
					continue
			else:
				cost = 1.4142
				var hx := Vector2i(nx, cy)
				var hy := Vector2i(cx, ny)
				if not floors.has(hx) or not floors.has(hy) or blocked.has(hx) or blocked.has(hy):
					continue
				if _wall_between(walls, cur, hx) or _wall_between(walls, hx, nb) or _wall_between(walls, cur, hy) or _wall_between(walls, hy, nb):
					continue
			var ng := gc + cost
			if ng < g[ni]:
				g[ni] = ng
				came[ni] = ci
				WorldPaths._ipush(heap, _key(ng + _h(nb, to), ni))
	if not found:
		return out
	var idx := gi
	while idx != -1:
		out.append(Vector2i(idx % ww + ox, idx / ww + oy))
		idx = came[idx]
	out.reverse()
	out.remove_at(0)
	return out


static func _wall_between(walls: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if walls.is_empty():
		return false
	var e: Vector3i
	if a.x == b.x:
		e = Vector3i(a.x, maxi(a.y, b.y), 0)
	else:
		e = Vector3i(maxi(a.x, b.x), a.y, 1)
	var t: String = walls.get(e, "")
	return t != "" and (t == "wall" or t == "window" or t == "fence")


static func _key(f: float, idx: int) -> int:
	return (int(f * 256.0) << 24) | idx


static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(a.x - b.x)
	var dy := absf(a.y - b.y)
	return (dx + dy) + (1.4142 - 2.0) * minf(dx, dy)


## Steps (-1 unreachable, 0 same tile).
static func path_len(world: WorldGrid, level: int, from: Vector2i, to: Vector2i, rect: Rect2i) -> float:
	if from == to:
		return 0.0
	var p := find_path(world, level, from, to, rect)
	return -1.0 if p.is_empty() else float(p.size())
