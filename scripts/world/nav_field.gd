class_name NavField
extends RefCounted
## Distances (in steps, exactly what WorldPaths.find_path would return) from ONE tile to every tile of a rectangle: a single
## Dijkstra instead of one A* per candidate. Autonomy asks for the path length to every object of the lot from the same tile;
## WorldNav builds a field after a few such queries. Blocked tiles can be reached (as a goal) but not walked through.

var rect: Rect2i
var steps: PackedInt32Array = PackedInt32Array()      # per rect tile, -1 = unreachable


func steps_to(t: Vector2i) -> int:
	if not rect.has_point(t):
		return -1
	return steps[(t.y - rect.position.y) * rect.size.x + (t.x - rect.position.x)]


static func build(world: WorldGrid, from: Vector2i, rc: Rect2i) -> NavField:
	var nf := NavField.new()
	var win := rc.intersection(Rect2i(0, 0, world.width, world.height))
	nf.rect = win
	var ww := win.size.x
	var n := ww * win.size.y
	var ox := win.position.x
	var oy := win.position.y
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var st := PackedInt32Array()
	st.resize(n)
	st.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var dxs := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
	var dys := PackedInt32Array([0, 0, 1, -1, 1, -1, 1, -1])
	var blocked: Dictionary = world._blocked
	var walls: Dictionary = world.walls
	var has_walls := not walls.is_empty()
	var heap := PackedInt64Array()
	var si := (from.y - oy) * ww + (from.x - ox)
	g[si] = 0.0
	st[si] = 0
	WorldPaths._ipush(heap, si)
	while heap.size() > 0:
		var ci: int = WorldPaths._ipop(heap) & 0xFFFFFF
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		var cx := ci % ww + ox
		var cy := ci / ww + oy
		if ci != si and blocked.has(Vector2i(cx, cy)):
			continue                                   # a blocked tile is a goal only, never a way through
		var gc: float = g[ci]
		for k in 8:
			var nx := cx + dxs[k]
			var ny := cy + dys[k]
			if nx < ox or ny < oy or nx >= win.end.x or ny >= win.end.y:
				continue
			var ni := (ny - oy) * ww + (nx - ox)
			if closed[ni] == 1:
				continue
			var cost := 1.0
			if k < 4:
				if has_walls:
					var e: Vector3i
					match k:
						0: e = Vector3i(cx + 1, cy, 1)
						1: e = Vector3i(cx, cy, 1)
						2: e = Vector3i(cx, cy + 1, 0)
						_: e = Vector3i(cx, cy, 0)
					var wt: String = walls.get(e, "")
					if wt != "" and wt in world.BLOCKING_WALLS:
						continue
			else:
				cost = 1.4142
				if not world.paths._step_ok(Vector2i(cx, cy), Vector2i(dxs[k], dys[k]), Vector2i(nx, ny)):
					continue
			var ng := gc + cost
			if ng < g[ni] - 0.0001:
				g[ni] = ng
				st[ni] = st[ci] + 1
				WorldPaths._ipush(heap, (int(ng * 256.0) << 24) | ni)
	nf.steps = st
	return nf
