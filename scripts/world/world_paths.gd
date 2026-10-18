class_name WorldPaths
extends RefCounted
## A* pathfinding over the tile grid (walls on edges, blocking objects, doors).
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

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
func find_path(from: Vector2i, to: Vector2i, diagonals: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not world.in_bounds(from) or not world.in_bounds(to):
		return out
	if from == to:
		return out
	var n := world.width * world.height
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
	var si := from.y * world.width + from.x
	var gi := to.y * world.width + to.x
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
		var cur := Vector2i(ci % world.width, floori(float(ci) / world.width))
		for d in dirs:
			if not _step_ok(cur, d, to):
				continue
			var nb := cur + d
			var ni := nb.y * world.width + nb.x
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
		out.append(Vector2i(idx % world.width, floori(float(idx) / world.width)))
		idx = came[idx]
	out.reverse()
	out.remove_at(0)
	return out

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
