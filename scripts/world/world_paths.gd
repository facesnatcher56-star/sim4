class_name WorldPaths
extends RefCounted
## A* pathfinding over the tile grid (walls on edges, blocking objects, doors).
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

const FULL_SEARCH_TILES := 4096   # grids up to this size (the 32x24 lot) always search the whole map
const WINDOW_MARGIN := 12         # tiles around the two end points for the first, bounded search

var world: WorldGrid


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ pathfinding

func _step_ok(a: Vector2i, d: Vector2i, goal: Vector2i) -> bool:
	var b := a + d
	if not world.in_bounds(b):
		return false
	if world._blocked.has(b) and b != goal:
		return false
	if d.x == 0 or d.y == 0:
		return world.edge_open(a, b)
	# diagonal: no corner cutting
	var hx := a + Vector2i(d.x, 0)
	var hy := a + Vector2i(0, d.y)
	if not world.is_walkable(hx) or not world.is_walkable(hy):
		return false
	return world.edge_open(a, hx) and world.edge_open(hx, b) and world.edge_open(a, hy) and world.edge_open(hy, b)

## A* path of steps: EXCLUDES the start tile, INCLUDES the goal (size == number of steps).
## Empty array if unreachable OR if from == to (use has_path() to tell them apart).
## The goal tile may itself be blocked (e.g. a slot inside furniture); start tile is never checked.
## Small grids search the whole map. Big grids (> FULL_SEARCH_TILES) first search a bounded window around the two
## tiles (arrays sized to the window, not the map) and only fall back to the whole map when that finds nothing.
func find_path(from: Vector2i, to: Vector2i, diagonals: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not world.in_bounds(from) or not world.in_bounds(to):
		return out
	if from == to:
		return out
	var whole := Rect2i(0, 0, world.width, world.height)
	if world.width * world.height > FULL_SEARCH_TILES:
		return _find_big(from, to, diagonals, whole)
	return _search(from, to, diagonals, whole)


## A* restricted to `rect` (clipped to the map): never searches outside it, so an unreachable goal fails after at most
## rect-area expansions. WorldNav uses it for the legs inside a lot / a park / around a street tile.
func find_path_rect(from: Vector2i, to: Vector2i, rect: Rect2i, diagonals: bool = true) -> Array[Vector2i]:
	var win := rect.intersection(Rect2i(0, 0, world.width, world.height))
	if from == to or not win.has_point(from) or not win.has_point(to):
		var none: Array[Vector2i] = []
		return none
	return _search_big(from, to, diagonals, win)


func _find_big(from: Vector2i, to: Vector2i, diagonals: bool, whole: Rect2i) -> Array[Vector2i]:
	var dist := maxi(absi(from.x - to.x), absi(from.y - to.y))
	var m := WINDOW_MARGIN + dist / 3
	var win := Rect2i(mini(from.x, to.x) - m, mini(from.y, to.y) - m, absi(from.x - to.x) + 1 + 2 * m, absi(from.y - to.y) + 1 + 2 * m).intersection(whole)
	if win != whole:
		var out := _search_big(from, to, diagonals, win)
		if not out.is_empty():
			return out
	return _search_big(from, to, diagonals, whole)


func _search(from: Vector2i, to: Vector2i, diagonals: bool, win: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ww := win.size.x
	var ox := win.position.x
	var oy := win.position.y
	var x1 := win.end.x
	var y1 := win.end.y
	var n := ww * win.size.y
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	if diagonals:
		dirs.append_array([Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)])
	# binary heap of [f, idx] pairs
	var heap: Array = []
	var si := (from.y - oy) * ww + (from.x - ox)
	var gi := (to.y - oy) * ww + (to.x - ox)
	g[si] = 0.0
	_heap_push(heap, [_h(from, to), si])
	var found := false
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var ci: int = top[1]
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		if ci == gi:
			found = true
			break
		var cur := Vector2i(ci % ww + ox, ci / ww + oy)
		for d in dirs:
			var nb := cur + d
			if nb.x < ox or nb.y < oy or nb.x >= x1 or nb.y >= y1:
				continue
			if not _step_ok(cur, d, to):
				continue
			var ni := (nb.y - oy) * ww + (nb.x - ox)
			if closed[ni] == 1:
				continue
			var cost := 1.0 if (d.x == 0 or d.y == 0) else 1.4142
			var ng: float = g[ci] + cost
			if ng < g[ni]:
				g[ni] = ng
				came[ni] = ci
				_heap_push(heap, [ng + _h(nb, to), ni])
	if not found:
		return out
	var idx := gi
	while idx != -1:
		out.append(Vector2i(idx % ww + ox, idx / ww + oy))
		idx = came[idx]
	out.reverse()
	out.remove_at(0)
	return out

## Same A* as _search, tuned for big maps: packed integer heap (f in 1/256 steps << 24 | index), inlined orthogonal moves.
func _search_big(from: Vector2i, to: Vector2i, diagonals: bool, win: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ww := win.size.x
	var ox := win.position.x
	var oy := win.position.y
	var x1 := win.end.x
	var y1 := win.end.y
	var n := ww * win.size.y
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var ndirs := 8 if diagonals else 4
	var dxs := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
	var dys := PackedInt32Array([0, 0, 1, -1, 1, -1, 1, -1])
	var blocked: Dictionary = world._blocked
	var walls: Dictionary = world.walls
	var has_walls := not walls.is_empty()
	var heap := PackedInt64Array()
	var si := (from.y - oy) * ww + (from.x - ox)
	var gi := (to.y - oy) * ww + (to.x - ox)
	g[si] = 0.0
	_ipush(heap, _key(_h(from, to), _h(from, to), si))
	var found := false
	while heap.size() > 0:
		var ci: int = _ipop(heap) & 0xFFFFFF
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		if ci == gi:
			found = true
			break
		var cx := ci % ww + ox
		var cy := ci / ww + oy
		var gc: float = g[ci]
		for k in ndirs:
			var nx := cx + dxs[k]
			var ny := cy + dys[k]
			if nx < ox or ny < oy or nx >= x1 or ny >= y1:
				continue
			var ni := (ny - oy) * ww + (nx - ox)
			if closed[ni] == 1:
				continue
			var nb := Vector2i(nx, ny)
			if blocked.has(nb) and nb != to:
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
				if not _step_ok(Vector2i(cx, cy), Vector2i(dxs[k], dys[k]), to):
					continue
			var ng := gc + cost
			if ng < g[ni]:
				g[ni] = ng
				came[ni] = ci
				var hn := _h(nb, to)
				_ipush(heap, _key(ng + hn, hn, ni))
	if not found:
		return out
	var idx := gi
	while idx != -1:
		out.append(Vector2i(idx % ww + ox, idx / ww + oy))
		idx = came[idx]
	out.reverse()
	out.remove_at(0)
	return out


## Heap key: f (1/256 steps) | h (ties go to the node nearer the goal) | tile index.
func _key(f: float, h: float, idx: int) -> int:
	return (int(f * 256.0) << 40) | (int(h * 256.0) << 24) | idx


static func _ipush(h: PackedInt64Array, v: int) -> void:
	h.append(v)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p] <= v:
			break
		h[i] = h[p]
		i = p
	h[i] = v


static func _ipop(h: PackedInt64Array) -> int:
	var top: int = h[0]
	var last: int = h[h.size() - 1]
	h.resize(h.size() - 1)
	var n := h.size()
	if n > 0:
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= n:
				break
			var m := l
			if l + 1 < n and h[l + 1] < h[l]:
				m = l + 1
			if h[m] >= last:
				break
			h[i] = h[m]
			i = m
		h[i] = last
	return top


## Number of steps (0 when from == to), -1 if unreachable.
func path_length(from: Vector2i, to: Vector2i) -> float:
	if from == to:
		return 0.0
	var p := find_path(from, to)
	if p.is_empty():
		return -1.0
	return float(p.size())

func has_path(from: Vector2i, to: Vector2i) -> bool:
	return from == to or not find_path(from, to).is_empty()

func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(a.x - b.x)
	var dy := absf(a.y - b.y)
	return (dx + dy) + (1.4142 - 2.0) * minf(dx, dy)

func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p

func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and h[l][0] < h[m][0]:
				m = l
			if r < n and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var tmp = h[m]
			h[m] = h[i]
			h[i] = tmp
			i = m
	return top

## Reachable non-blocked neighbour of a tile closest to `from` (for approaching blocked tiles).
func nearest_reachable_neighbor(from: Vector2i, target: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_len := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = target + d
		if not world.is_walkable(nb) or not world.edge_open(target, nb):
			continue
		var l := path_length(from, nb)
		if l >= 0.0 and l < best_len:
			best_len = l
			best = nb
	return best
