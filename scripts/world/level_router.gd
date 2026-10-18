class_name LevelRouter
extends RefCounted
## Routes between levels (`World.router`; World.find_route / route_length / has_route). The ground (level 0, the existing WorldNav) and
## every upper / lower level of a building are joined by PORTALS (LevelPortals): a lazy A* over portal ends. Nodes are the
## walkable ends of the active portals of the one or two buildings involved plus START and GOAL; two nodes on the same level
## (and same building, or both on the ground) are joined by a tile path whose true length is only computed when the search pops that
## edge (an optimistic Chebyshev bound is used until then), so a 15-storey tower costs a handful of tile A*s, not hundreds.
##
## Position = Vector3i(x, y, level). A route lists the entries after the start up to and including the goal: ordinary tile steps,
## then for a staircase the walked stair tiles and the landing, for a lift [shaft on level a, shaft on level b, exit tile].
## Cost is in "tile units": one tile step = 1, a stair level = steps + STAIR_PEN, a lift ride = ELEV_BASE + levels + queue.
## Level 0 to level 0 is just WorldNav (nothing changes for old callers). Unreachable levels fail BEFORE any tile search
## (a breadth-first look over which levels the portals connect).

const CACHE := 4096

var world: WorldGrid
var _lens := LruCache.new(CACHE)
var _legs := LruCache.new(8192)
var _seen: int = -1
var last_stats: Dictionary = {}        # {nodes, settled, legs} of the last search (tests / tuning)
var _legs_done: int = 0
var _nodes_cache: Dictionary = {}      # building id -> portal ends (valid until the next structural change)
var _reach_cache: Dictionary = {}      # Vector2i(building, start level) -> {level: true}


func _init(w: WorldGrid) -> void:
	world = w


func reset() -> void:
	_lens.clear()
	_legs.clear()
	_nodes_cache.clear()
	_reach_cache.clear()
	_seen = -1


## Drop the cached routes and leg lengths only (the portal graph of the buildings stays): tests and benchmarks of an uncached route.
func clear_paths() -> void:
	_lens.clear()
	_legs.clear()


func _sync() -> void:
	var g: int = world.levels.gen * 1000003 + world.nav.gen
	if g != _seen:
		_seen = g
		_lens.clear()
		_legs.clear()
		_nodes_cache.clear()
		_reach_cache.clear()


# ------------------------------------------------------------------ public API

## Route cost in tile units, -1 when unreachable. Cached for the default stair effort.
func route_length(from: Vector3i, to: Vector3i, smult: float = 1.0) -> float:
	if from == to:
		return 0.0
	if from.z == 0 and to.z == 0:
		return world.nav.path_length(LPos.tile(from), LPos.tile(to))
	_sync()
	var key := _key(from, to)
	if smult == 1.0:
		var c = _lens.fetch(key)
		if c != null:
			return c
	var r := _solve(from, to, smult, false)
	var cost: float = float(r["cost"])
	if smult == 1.0:
		_lens.put(key, cost)
	return cost


func has_route(from: Vector3i, to: Vector3i) -> bool:
	return from == to or route_length(from, to) >= 0.0


## The route entries (see class comment). [] when unreachable OR from == to (use has_route to tell them apart).
func find_route(from: Vector3i, to: Vector3i, smult: float = 1.0) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if from == to:
		return out
	if from.z == 0 and to.z == 0:
		for t in world.nav.find_path(LPos.tile(from), LPos.tile(to)):
			out.append(LPos.make(t, 0))
		return out
	_sync()
	var r := _solve(from, to, smult, true)
	out.assign(r.get("path", []))
	return out


## Cost in tile units of an existing route walked by a folk with stair effort `smult`.
func cost_of(route: Array, smult: float = 1.0) -> float:
	var cost := 0.0
	for i in route.size():
		var p: Vector3i = route[i]
		var prev: Vector3i = route[i - 1] if i > 0 else p
		if i == 0 or p.z == prev.z:
			cost += 1.0
		else:
			cost += LevelPortals.STAIR_PEN * smult if world.portals.elevators.lift_at(LPos.tile(p), p.z) < 0 else LevelPortals.ELEV_BASE + float(absi(p.z - prev.z))
	return cost


# ------------------------------------------------------------------ search

static func _key(a: Vector3i, b: Vector3i) -> int:
	return (a.x & 0xFF) | ((a.y & 0xFF) << 8) | (((a.z + 512) & 0x3FF) << 16) | ((b.x & 0xFF) << 26) | ((b.y & 0xFF) << 34) | (((b.z + 512) & 0x3FF) << 42)


func _leg_len(a: Vector3i, b: Vector3i, rect: Rect2i) -> float:
	if a == b:
		return 0.0
	var k := (_key(a, b) << 1) | 1 if a.z != 0 else _key(a, b) << 1
	var c = _legs.fetch(k)
	if c != null:
		return c
	_legs_done += 1
	var n: float
	if a.z == 0:
		n = world.nav.path_length(LPos.tile(a), LPos.tile(b))
	else:
		n = LevelPaths.path_len(world, a.z, LPos.tile(a), LPos.tile(b), rect)
	_legs.put(k, n)
	return n


func _leg_path(a: Vector3i, b: Vector3i, rect: Rect2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if a == b:
		return out
	if a.z == 0:
		for t in world.nav.find_path(LPos.tile(a), LPos.tile(b)):
			out.append(LPos.make(t, 0))
	else:
		for t in LevelPaths.find_path(world, a.z, LPos.tile(a), LPos.tile(b), rect):
			out.append(LPos.make(t, a.z))
	return out


static func _cheb(a: Vector3i, b: Vector3i) -> float:
	return float(maxi(absi(a.x - b.x), absi(a.y - b.y)))


## Levels of the building reachable from `start` through its active portals.
func _reach(bid: int, start: int) -> Dictionary:
	var ck := Vector2i(bid, start)
	if _reach_cache.has(ck):
		return _reach_cache[ck]
	var seen: Dictionary = {start: true}
	var recs: Array = world.portals.of_building(bid)
	var changed := true
	while changed:
		changed = false
		for rec in recs:
			var lv: Array = []
			if str(rec["kind"]) == "elevator":
				for s in rec["stops"]:
					lv.append(s.z)
			else:
				for s in rec["stairs"]:
					lv.append(s.z)
			var hit := false
			for l in lv:
				if seen.has(l):
					hit = true
			if hit:
				for l in lv:
					if not seen.has(l):
						seen[l] = true
						changed = true
	_reach_cache[ck] = seen
	return seen


func _building_ok(bid: int, level: int) -> bool:
	return bid >= 0 and world.levels.has_level(bid, level)


func _rect_of(bid: int) -> Rect2i:
	return (world.levels.building(bid).get("rect", Rect2i()) as Rect2i)


func _solve(from: Vector3i, to: Vector3i, smult: float, want_path: bool) -> Dictionary:
	var fail := {"cost": -1.0, "path": []}
	var lv: WorldLevels = world.levels
	var bf := -1
	var bt := -1
	if from.z != 0:
		bf = lv.building_at(LPos.tile(from))
		if not _building_ok(bf, from.z):
			return fail
	if to.z != 0:
		bt = lv.building_at(LPos.tile(to))
		if not _building_ok(bt, to.z):
			return fail
	# which buildings' portals matter, and is there any chance at all (levels connected)?
	var bids: Array = []
	if from.z == 0 and to.z != 0:
		var bg := lv.building_at(LPos.tile(from))
		if bg == bt:
			if not _reach(bt, 0).has(to.z):
				return fail
		elif not _reach(bt, 0).has(to.z):
			return fail
		bids = [bt]
	elif from.z != 0 and to.z == 0:
		if not _reach(bf, from.z).has(0):
			return fail
		bids = [bf]
	else:
		if bf == bt:
			if not _reach(bf, from.z).has(to.z):
				return fail
			bids = [bf]
		else:
			if not _reach(bf, from.z).has(0) or not _reach(bt, 0).has(to.z):
				return fail
			bids = [bf, bt]
	# nodes: 0 = START, 1 = GOAL, then portal ends
	var pos: Array[Vector3i] = [from, to]
	var nbid: Array[int] = [bf, bt]
	var nrec: Array = [null, null]
	var idx_of: Dictionary = {}
	for b in bids:
		if not _nodes_cache.has(int(b)):
			_nodes_cache[int(b)] = world.portals.nodes_of(int(b))
		for nd in _nodes_cache[int(b)]:
			var p: Vector3i = nd["pos"]
			if idx_of.has(p):
				continue
			idx_of[p] = pos.size()
			pos.append(p)
			nbid.append(int(b))
			nrec.append(nd["rec"])
	var n := pos.size()
	var groups: Dictionary = {}                 # (level, building) -> node indices
	for i in n:
		var gk: int = pos[i].z * 4096 + (0 if pos[i].z == 0 else nbid[i] + 1)
		if not groups.has(gk):
			groups[gk] = []
		(groups[gk] as Array).append(i)
	var hv: Dictionary = {}                      # building -> {level: vertical lower bound to the goal side}
	if to.z != 0 or from.z != 0:
		for b in bids:
			hv[int(b)] = _vertical(int(b), to.z if int(b) == bt else 0, smult)
	var g := PackedFloat64Array()
	g.resize(n)
	g.fill(INF)
	var closed := PackedByteArray()
	closed.resize(n)
	var par := PackedInt32Array()
	par.resize(n)
	par.fill(-1)
	var via := PackedInt32Array()               # 0 leg, 1 portal
	via.resize(n)
	var heap: Array = []
	var seq := 0
	g[0] = 0.0
	_push(heap, [_hn(from, nbid[0], hv, to), seq, 0, 0.0, -1, 0, true])
	var found := false
	var settled := 0
	_legs_done = 0
	while not heap.is_empty():
		var e: Array = _pop(heap)
		var ni: int = e[2]
		var exact: bool = e[6]
		if closed[ni] == 1:
			continue
		if not exact:
			# optimistic leg: replace with the true length (or drop it)
			var pi: int = e[4]
			var leg := _leg_len(pos[pi], pos[ni], _rect_of(nbid[pi] if pos[pi].z != 0 else nbid[ni]))
			if leg < 0.0:
				continue
			var ng: float = g[pi] + leg
			if ng < g[ni]:
				g[ni] = ng
				seq += 1
				_push(heap, [ng + _hn(pos[ni], nbid[ni], hv, to), seq, ni, ng, pi, 0, true])
			continue
		if float(e[3]) > g[ni] + 0.0001:
			continue
		closed[ni] = 1
		settled += 1
		par[ni] = e[4]
		via[ni] = e[5]
		if ni == 1:
			found = true
			break
		var gc: float = g[ni]
		# portal moves
		var rec = nrec[ni]
		if rec != null:
			for other in _portal_targets(rec, pos[ni]):
				var oi: int = idx_of.get(other, -1)
				if oi < 0 or closed[oi] == 1:
					continue
				var tr := world.portals.traverse(rec, pos[ni], other, smult)
				var ng2: float = gc + float(tr["cost"])
				if ng2 < g[oi]:
					g[oi] = ng2
					seq += 1
					_push(heap, [ng2 + _hn(other, nbid[oi], hv, to), seq, oi, ng2, ni, 1, true])
		# same-level moves (optimistic until popped)
		var gk2: int = pos[ni].z * 4096 + (0 if pos[ni].z == 0 else nbid[ni] + 1)
		for mi in (groups.get(gk2, []) as Array):
			if mi == ni or closed[mi] == 1:
				continue
			if mi == 0:
				continue
			var lb: float = _cheb(pos[ni], pos[mi])
			seq += 1
			_push(heap, [gc + lb + _hn(pos[mi], nbid[mi], hv, to), seq, mi, 0.0, ni, 0, false])
		# goal on the same level of this building but in a different group key (ground goal reached from any ground node)
	last_stats = {"nodes": n, "settled": settled, "legs": _legs_done}
	if not found:
		return fail
	var cost: float = g[1]
	if not want_path:
		return {"cost": cost}
	# rebuild the chain
	var chain: Array[int] = []
	var cur := 1
	while cur != -1:
		chain.push_front(cur)
		cur = par[cur]
	var path: Array[Vector3i] = []
	for k in range(1, chain.size()):
		var a: int = chain[k - 1]
		var b: int = chain[k]
		if via[b] == 1:
			var tr2 := world.portals.traverse(nrec[a], pos[a], pos[b], smult)
			path.append_array(tr2["steps"])
		else:
			path.append_array(_leg_path(pos[a], pos[b], _rect_of(nbid[a] if pos[a].z != 0 else nbid[b])))
	return {"cost": cost, "path": path}


## Other ends reachable by taking the portal from `p`.
func _portal_targets(rec: Dictionary, p: Vector3i) -> Array:
	var out: Array = []
	var ends: Array = rec["stops"] if str(rec["kind"]) == "elevator" else rec["stairs"]
	for q in ends:
		if q != p:
			out.append(q)
	return out


func _hn(a: Vector3i, bid: int, hv: Dictionary, goal: Vector3i) -> float:
	if hv.has(bid):
		return _cheb(a, goal) + float((hv[bid] as Dictionary).get(a.z, absi(a.z - goal.z)))
	return _cheb(a, goal) + float(absi(a.z - goal.z))


func _h(a: Vector3i, goal: Vector3i) -> float:
	return _cheb(a, goal) + float(absi(a.z - goal.z))


## Cheapest portal cost between levels of a building and `target` (ignoring horizontal walking): the vertical part of the heuristic,
## so the search heads for the lift / the right stairs instead of trying every flight.
func _vertical(bid: int, target: int, smult: float) -> Dictionary:
	var vkey := Vector3i(bid, target, 0)
	if smult == 1.0 and _reach_cache.has(vkey):
		return _reach_cache[vkey]
	var adj: Dictionary = {}
	for rec in world.portals.of_building(bid):
		var ends: Array = rec["stops"] if str(rec["kind"]) == "elevator" else rec["stairs"]
		for a in ends:
			for b in ends:
				if a.z != b.z:
					var c: float = float(world.portals.traverse(rec, a, b, smult)["cost"]) - float((rec["run"] as Array).size()) - 2.0 * float(str(rec["kind"]) == "elevator")
					if not adj.has(a.z):
						adj[a.z] = []
					(adj[a.z] as Array).append([b.z, maxf(c, 1.0)])
	var dist: Dictionary = {target: 0.0}
	var todo: Array = [target]
	while not todo.is_empty():
		var best := 0
		for i in todo.size():
			if float(dist[todo[i]]) < float(dist[todo[best]]):
				best = i
		var cur: int = todo[best]
		todo.remove_at(best)
		for e in adj.get(cur, []):
			var nd: float = float(dist[cur]) + float(e[1])
			if nd < float(dist.get(e[0], INF)):
				dist[e[0]] = nd
				todo.append(e[0])
	if smult == 1.0:
		_reach_cache[vkey] = dist
	return dist


static func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		var a: Array = h[p]
		if a[0] < item[0] or (a[0] == item[0] and a[1] <= item[1]):
			break
		h[i] = a
		i = p
	h[i] = item


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	var n := h.size()
	if n > 0:
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= n:
				break
			var m := l
			if l + 1 < n:
				var a: Array = h[l + 1]
				var b: Array = h[l]
				if a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]):
					m = l + 1
			var c: Array = h[m]
			if c[0] > last[0] or (c[0] == last[0] and c[1] >= last[1]):
				break
			h[i] = c
			i = m
		h[i] = last
	return top
