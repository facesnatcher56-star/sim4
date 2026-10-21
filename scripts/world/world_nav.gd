class_name WorldNav
extends RefCounted
## Hierarchical pathfinding of the big map (`World.nav`; World.find_path / path_length / has_path go through it).
##   - both tiles in the same lot (or the same park): tile A* restricted to that rectangle (wall-edge aware, never leaves it)
##   - otherwise: tile A* from the start to the lot's street gate (a tile outside every lot: nearest sidewalk), a route over the
##     sidewalk / crosswalk graph (NavGraph: roads are crossed on crosswalks only), tile A* from the destination's gate in.
## Every tile of a lot is entered / left through its gate (region.entry, in the lot's south fence line, next to the sidewalk).
## Worlds without regions or smaller than WorldPaths.FULL_SEARCH_TILES (classic lot, small tests) use the plain tile A*.
## Unreachable targets fail fast: a blocked gate / blocked sidewalk run is found without searching the map.
## Caches (small LRUs, dropped on any wall / object change): street leg per tile, path_length per tile pair, routes per
## ribbon tile pair (inside NavGraph).

const RAY := 40                       # tiles searched in each direction for the nearest sidewalk from open ground
const LEG_PAD := 12
const FIELD_AFTER := 3                # in-lot path_length questions from one tile before a distance field is built

static var enabled: bool = true          # false = plain windowed tile A* everywhere (benchmarks / debugging)

var world: WorldGrid
var graph: NavGraph = null
var gen: int = 0                      # bumped on every change (tests / debugging)
var _state: int = 0                   # 0 not built, 1 active, 2 off (map does not match the layout)
var _ribbon_dirty: bool = false
var _legs := LruCache.new(1024)
var _lens := LruCache.new(4096)
var _fields := LruCache.new(8)         # tile -> NavField (one Dijkstra answers every path_length from that tile)
var _asked: Dictionary = {}            # tile -> path_length queries inside its lot since the last change


func _init(w: WorldGrid) -> void:
	world = w


## World.reset() / loading a world: forget the graph and every cache.
func reset() -> void:
	_state = 0
	graph = null
	_ribbon_dirty = false
	_legs.clear()
	_lens.clear()
	_fields.clear()
	_asked.clear()
	gen += 1


## A blocking object / wall edge appeared or went away at `t`.
func touch_tile(t: Vector2i) -> void:
	gen += 1
	_legs.clear()
	_lens.clear()
	_fields.clear()
	_asked.clear()
	if graph != null and graph.on_ribbon.has(t):
		_ribbon_dirty = true


func touch_edge(e: Vector3i) -> void:
	touch_tile(Vector2i(e.x, e.y))
	touch_tile(Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y))


func is_active() -> bool:
	if not enabled:
		return false
	if _state == 0:
		if world.width * world.height <= WorldPaths.FULL_SEARCH_TILES or not world.regions.has_regions():
			return false
		var g := NavGraph.new()
		g.build(MapBuilder.layout())
		if not g.floors_match(world):
			_state = 2
			return false
		graph = g
		g.refresh_blocked(world)
		_state = 1
	if _state != 1:
		return false
	if _ribbon_dirty:
		_ribbon_dirty = false
		graph.refresh_blocked(world)
	return true


# ------------------------------------------------------------------ public API

func find_path(from: Vector2i, to: Vector2i, diagonals: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to or not world.in_bounds(from) or not world.in_bounds(to):
		return out
	if not is_active():
		return world.paths.find_path(from, to, diagonals)
	var rc := _shared_rect(from, to)
	if rc.size.x > 0:
		return world.paths.find_path_rect(from, to, rc, diagonals)
	var ea = _exit(from)
	var eb = _exit(to)
	if ea == null or eb == null:
		return out
	var p1: Vector2i = from if ea.is_empty() else ea.back()
	var p2: Vector2i = to if eb.is_empty() else eb.back()
	var pl := graph.plan(p1, p2)
	if pl.is_empty():
		return out
	out.append_array(ea)
	out.append_array(graph.tiles(pl, p1, p2))
	for i in range(eb.size() - 2, -1, -1):          # the way in = the exit leg of the destination, reversed
		out.append(eb[i])
	if not eb.is_empty():
		out.append(to)
	return out


## Number of steps (0 when from == to), -1 if unreachable. Cross-region lengths are leg + graph distance + leg, no tile list.
func path_length(from: Vector2i, to: Vector2i) -> float:
	if from == to:
		return 0.0
	if not world.in_bounds(from) or not world.in_bounds(to):
		return -1.0
	if not is_active():
		return world.paths.path_length(from, to)
	var key := Vector4i(from.x, from.y, to.x, to.y)
	var c = _lens.fetch(key)
	if c != null:
		return c
	var n := _length(from, to)
	_lens.put(key, n)
	return n


func has_path(from: Vector2i, to: Vector2i) -> bool:
	return from == to or path_length(from, to) >= 0.0


# ------------------------------------------------------------------ helpers

func _length(from: Vector2i, to: Vector2i) -> float:
	var rc := _shared_rect(from, to)
	if rc.size.x > 0:
		var nf: NavField = _fields.fetch(from)
		if nf == null:
			var asked: int = int(_asked.get(from, 0)) + 1
			_asked[from] = asked
			if asked > FIELD_AFTER:                  # the 4th question from the same tile: answer them all with one Dijkstra
				nf = NavField.build(world, from, rc)
				_fields.put(from, nf)
		if nf != null:
			return float(nf.steps_to(to))
		var p := world.paths.find_path_rect(from, to, rc)
		return -1.0 if p.is_empty() else float(p.size())
	var ea = _exit(from)
	var eb = _exit(to)
	if ea == null or eb == null:
		return -1.0
	var p1: Vector2i = from if ea.is_empty() else ea.back()
	var p2: Vector2i = to if eb.is_empty() else eb.back()
	var pl := graph.plan(p1, p2)
	if pl.is_empty():
		return -1.0
	return float(ea.size() + int(pl["total"]) + eb.size())


## Rectangle both tiles must stay in (their lot / park), Rect2i() when they are not in the same one.
func _shared_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var rid: int = world.regions.region_at(a)
	if rid == WorldRegions.NONE or rid != world.regions.region_at(b):
		return Rect2i()
	var r: Dictionary = world.regions.regions[rid]
	if world.regions.is_lot(rid) or str(r["kind"]) == "park":
		return r["rect"]
	return Rect2i()


## Steps from `t` to the sidewalk (cached): through the lot's gate for a tile in a lot, straight to the nearest sidewalk for open
## ground / road / park. [] = already on the ribbon, null = no way out.
func _exit(t: Vector2i):
	var k := t.y * world.width + t.x
	var c = _legs.fetch(k)
	if c != null:
		return null if c is bool else c
	var leg = _make_exit(t)
	_legs.put(k, false if leg == null else leg)
	return leg


func _make_exit(t: Vector2i):
	if graph.on_ribbon.has(t):
		var none: Array[Vector2i] = []
		return none
	var rid: int = world.regions.region_at(t)
	if rid != WorldRegions.NONE and world.regions.is_lot(rid):
		var r: Dictionary = world.regions.regions[rid]
		var g: Vector2i = r["entry"]
		var rc: Rect2i = r["rect"]
		var s := g + Vector2i(0, 1)
		var direct: Array[Vector2i] = _direct_leg(t)          # no fence on this side: step straight onto the sidewalk (no invisible walls)
		if rc.has_point(g) and graph.on_ribbon.has(s):
			var leg: Array[Vector2i] = []
			if not (world._blocked.has(s) or not world.edge_open(g, s)):
				if t != g:
					leg = world.paths.find_path_rect(t, g, rc)
				if t == g or not leg.is_empty():
					leg.append(s)
				else:
					leg = []
			if not leg.is_empty() and (direct.is_empty() or leg.size() <= direct.size()):
				return leg
			if not direct.is_empty():
				return direct
			return null
		if not direct.is_empty():
			return direct
	var p := _nearest_ribbon(t)
	if p.x < 0:
		return null
	var win := Rect2i(mini(t.x, p.x) - LEG_PAD, mini(t.y, p.y) - LEG_PAD, absi(t.x - p.x) + 1 + 2 * LEG_PAD, absi(t.y - p.y) + 1 + 2 * LEG_PAD)
	var leg2 := world.paths.find_path_rect(t, p, win)
	return null if leg2.is_empty() else leg2


## The shortest walk from a tile of a lot straight out to the nearest ribbon tile in each of the four directions (walls, fences and objects are respected by the
## windowed A*): [] when every side is walled in. So a lot's yard is open to the street wherever nothing is built.
func _direct_leg(t: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for k in range(1, 30):
			var p: Vector2i = t + d * k
			if not world.in_bounds(p):
				break
			if graph.on_ribbon.has(p):
				if not best.is_empty() and k >= best.size():
					break
				var win := Rect2i(mini(t.x, p.x) - 3, mini(t.y, p.y) - 3, absi(t.x - p.x) + 7, absi(t.y - p.y) + 7)
				var leg: Array[Vector2i] = world.paths.find_path_rect(t, p, win)
				if not leg.is_empty() and (best.is_empty() or leg.size() < best.size()):
					best = leg
				break
	return best


func _nearest_ribbon(t: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := RAY + 1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for k in range(1, mini(best_d, RAY + 1)):
			var p: Vector2i = t + d * k
			if not world.in_bounds(p):
				break
			if graph.on_ribbon.has(p):
				best = p
				best_d = k
				break
	return best


# ------------------------------------------------------------------ debugging / tests

## {lot id: {gate, street}} of every lot with a street gate on the ribbon.
func lot_ports() -> Dictionary:
	var out: Dictionary = {}
	if not is_active():
		return out
	for r in world.regions.regions.values():
		if world.regions.is_lot(int(r["id"])):
			var g: Vector2i = r["entry"]
			if graph.on_ribbon.has(g + Vector2i(0, 1)):
				out[str(r["lot"])] = {"gate": g, "street": g + Vector2i(0, 1)}
	return out
