class_name NavGraph
extends RefCounted
## The pedestrian ribbon of the map as a graph: sidewalks and crosswalks, built from data/map_layout.json (MapBuilder's road
## grid). Nodes = run end points (block corners, crosswalk ends); a RUN is a straight line of ribbon tiles between two nodes
## (a sidewalk stretch, a one-tile corner link or a crosswalk). Roads can only be crossed on a crosswalk run because those are
## the only runs that join two sides. Edge weight = number of tile steps, so a route's length equals its tile count.
##
##   build(layout)            nodes + runs
##   refresh_blocked(world)   mark runs blocked by walls / objects (call again after a change)
##   plan(p1, p2)             cheapest way between two ribbon tiles -> {total, direct, n1, n2} or {} when none
##   tiles(plan, p1, p2)      the tiles of that plan (excludes p1, includes p2)

const INF_I := 1 << 28
const FLOORS := ["sidewalk", "crosswalk"]

var node_tile: Array[Vector2i] = []
var node_of: Dictionary = {}              # tile -> node id
var runs: Array = []                      # {a, b: Vector2i, na, nb: int, len: int, ok: bool}
var run_of: Dictionary = {}               # interior tile of a run -> run index
var on_ribbon: Dictionary = {}            # every ribbon tile -> true
var _adj: Array = []                      # node -> Array of [other node, run index]
var _sssp: Dictionary = {}                # node -> {dist: PackedInt32Array, prev: PackedInt32Array}
var _plans := LruCache.new(1024)


func node_count() -> int:
	return node_tile.size()


func _node(t: Vector2i) -> int:
	if node_of.has(t):
		return node_of[t]
	node_tile.append(t)
	node_of[t] = node_tile.size() - 1
	on_ribbon[t] = true
	return node_tile.size() - 1


func _run(a: Vector2i, b: Vector2i) -> void:
	if a == b:
		return
	var r := {"a": a, "b": b, "na": _node(a), "nb": _node(b), "len": absi(a.x - b.x) + absi(a.y - b.y), "ok": true}
	runs.append(r)
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var t := a + step
	while t != b:
		run_of[t] = runs.size() - 1
		on_ribbon[t] = true
		t += step


func build(lay: Dictionary) -> void:
	node_tile.clear()
	node_of.clear()
	runs.clear()
	run_of.clear()
	on_ribbon.clear()
	var rw := int(lay.get("road_w", 6))
	var e := rw - 1
	var vx: Array = lay["vroads_x"]
	var hy: Array = lay["hroads_y"]
	var na := vx.size()
	var nb := hy.size()
	for a in na:
		for b in nb:
			var jx := int(vx[a])
			var jy := int(hy[b])
			var nw := Vector2i(jx, jy)
			var ne := Vector2i(jx + e, jy)
			var sw := Vector2i(jx, jy + e)
			var se := Vector2i(jx + e, jy + e)
			if b > 0:        # crosswalk over the vertical road just north of the junction, and the corner links to it
				_run(Vector2i(jx, jy - 1), Vector2i(jx + e, jy - 1))
				_run(nw, Vector2i(jx, jy - 1))
				_run(ne, Vector2i(jx + e, jy - 1))
			else:
				_run(nw, ne)
			if b < nb - 1:
				_run(Vector2i(jx, jy + rw), Vector2i(jx + e, jy + rw))
				_run(sw, Vector2i(jx, jy + rw))
				_run(se, Vector2i(jx + e, jy + rw))
			else:
				_run(sw, se)
			if a > 0:
				_run(Vector2i(jx - 1, jy), Vector2i(jx - 1, jy + e))
				_run(nw, Vector2i(jx - 1, jy))
				_run(sw, Vector2i(jx - 1, jy + e))
			else:
				_run(nw, sw)
			if a < na - 1:
				_run(Vector2i(jx + rw, jy), Vector2i(jx + rw, jy + e))
				_run(ne, Vector2i(jx + rw, jy))
				_run(se, Vector2i(jx + rw, jy + e))
			else:
				_run(ne, se)
	for b in nb:                  # sidewalk stretches between junctions
		for a in na - 1:
			var y := int(hy[b])
			_run(Vector2i(int(vx[a]) + rw, y), Vector2i(int(vx[a + 1]) - 1, y))
			_run(Vector2i(int(vx[a]) + rw, y + e), Vector2i(int(vx[a + 1]) - 1, y + e))
	for a in na:
		for b in nb - 1:
			var x := int(vx[a])
			_run(Vector2i(x, int(hy[b]) + rw), Vector2i(x, int(hy[b + 1]) - 1))
			_run(Vector2i(x + e, int(hy[b]) + rw), Vector2i(x + e, int(hy[b + 1]) - 1))
	refresh_blocked(null)


## Every ribbon tile is a sidewalk / crosswalk floor? (A map that does not match the layout turns the graph off.)
func floors_match(world) -> bool:
	for t in on_ribbon:
		if not (world.get_floor(t) in FLOORS):
			return false
	return true


## Recompute which runs are open (no blocking object / wall edge along them) and reset every cached route.
func refresh_blocked(world) -> void:
	for r in runs:
		var ok := true
		if world != null:
			var a: Vector2i = r["a"]
			var step := Vector2i(signi(r["b"].x - a.x), signi(r["b"].y - a.y))
			var t := a
			ok = not world._blocked.has(t)
			while ok and t != r["b"]:
				var u := t + step
				if world._blocked.has(u) or not world.edge_open(t, u):
					ok = false
				t = u
		r["ok"] = ok
	_adj.clear()
	for i in node_tile.size():
		_adj.append([])
	for i in runs.size():
		var r2: Dictionary = runs[i]
		if r2["ok"]:
			(_adj[r2["na"]] as Array).append([r2["nb"], i])
			(_adj[r2["nb"]] as Array).append([r2["na"], i])
	_sssp.clear()
	_plans.clear()


func _sp(src: int) -> Dictionary:
	if _sssp.has(src):
		return _sssp[src]
	var n := node_tile.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(INF_I)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var heap := PackedInt64Array()
	dist[src] = 0
	WorldPaths._ipush(heap, src)
	while heap.size() > 0:
		var top: int = WorldPaths._ipop(heap)
		var u: int = top & 0xFFFF
		var du: int = top >> 16
		if du > dist[u]:
			continue
		for edge in _adj[u]:
			var v: int = edge[0]
			var nd: int = du + int(runs[edge[1]]["len"])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				WorldPaths._ipush(heap, (nd << 16) | v)
	var res := {"dist": dist, "prev": prev}
	_sssp[src] = res
	return res


## [node, cost] pairs through which a ribbon tile joins the graph (empty: not on the ribbon / its run is blocked).
func _anchors(p: Vector2i) -> Array:
	if node_of.has(p):
		return [[node_of[p], 0]]
	var ri: int = run_of.get(p, -1)
	if ri < 0 or not runs[ri]["ok"]:
		return []
	var r: Dictionary = runs[ri]
	var a: Vector2i = r["a"]
	var b: Vector2i = r["b"]
	return [[r["na"], absi(p.x - a.x) + absi(p.y - a.y)], [r["nb"], absi(p.x - b.x) + absi(p.y - b.y)]]


func plan(p1: Vector2i, p2: Vector2i) -> Dictionary:
	if p1 == p2:
		return {"total": 0, "direct": true}
	var key := Vector4i(p1.x, p1.y, p2.x, p2.y)
	var c = _plans.fetch(key)
	if c != null:
		return c
	var res := _plan(p1, p2)
	_plans.put(key, res)
	return res


func _plan(p1: Vector2i, p2: Vector2i) -> Dictionary:
	var r1: int = run_of.get(p1, -1)
	if r1 >= 0 and r1 == run_of.get(p2, -2):
		if runs[r1]["ok"]:
			return {"total": absi(p1.x - p2.x) + absi(p1.y - p2.y), "direct": true}
		return {}
	var a1 := _anchors(p1)
	var a2 := _anchors(p2)
	var best := INF_I
	var res: Dictionary = {}
	for x in a1:
		var d: PackedInt32Array = _sp(x[0])["dist"]
		for y in a2:
			var tot: int = int(x[1]) + d[y[0]] + int(y[1])
			if d[y[0]] < INF_I and tot < best:
				best = tot
				res = {"total": tot, "direct": false, "n1": x[0], "n2": y[0]}
	return res


## Straight axis-aligned line, excludes a, includes b.
static func line(a: Vector2i, b: Vector2i, out: Array[Vector2i]) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var t := a
	while t != b:
		t += step
		out.append(t)


func tiles(pl: Dictionary, p1: Vector2i, p2: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if pl.is_empty() or p1 == p2:
		return out
	if bool(pl["direct"]):
		line(p1, p2, out)
		return out
	var n1: int = pl["n1"]
	var n2: int = pl["n2"]
	line(p1, node_tile[n1], out)
	var chain: Array[int] = []
	var prev: PackedInt32Array = _sp(n1)["prev"]
	var u := n2
	while u != n1 and u != -1:
		chain.append(u)
		u = prev[u]
	chain.reverse()
	var cur := n1
	for v in chain:
		line(node_tile[cur], node_tile[v], out)
		cur = v
	line(node_tile[n2], p2, out)
	return out
