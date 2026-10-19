extends RefCounted
## WorldNav / NavGraph on the real map: every lot street gate reaches every other, roads are crossed on crosswalks only,
## walkers stay on sidewalks / crosswalks / their own lot, routes are not silly, blocked or unreachable targets fail fast, and
## a wall / fence edit changes the route (cache invalidation).

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	Kit.new_game("small")
	var W: Node = Kit.world()
	_check(W.nav.is_active(), "the portal graph is active on the big map")
	_connectivity(W)
	_sidewalk_only(W)
	_home_to_cafe(W)
	_fail_fast(W)
	_invalidation(W)
	_field(W)
	Kit.teardown()
	return fails

func _ports(W) -> Dictionary:
	return W.nav.lot_ports()

func _connectivity(W) -> void:
	var ports: Dictionary = _ports(W)
	_check(ports.size() == 19, "every lot has a street gate on the sidewalk (%d)" % ports.size())
	var ids: Array = ports.keys()
	var bad := 0
	for a in ids:
		for b in ids:
			if a != b:
				var n: float = W.path_length(Neighborhood.entry_tile(a), Neighborhood.entry_tile(b))
				if n < 0.0:
					bad += 1
					fails.append("no way from the %s door to the %s door" % [a, b])
	_check(bad == 0, "all 16 lot doors reach each other")
	# the park and the woods are reachable too
	var green: Dictionary = W.regions.by_lot("green")
	var gt: Vector2i = (green["rect"] as Rect2i).position + Vector2i(2, 2)
	_check(W.path_length(Neighborhood.entry_tile("home"), gt) > 0.0, "the green is reachable from home")
	var woods: Dictionary = W.regions.by_lot("south")
	var wt: Vector2i = (woods["rect"] as Rect2i).position + Vector2i(60, 4)
	_check(W.path_length(Neighborhood.entry_tile("home"), wt) > 0.0, "the woods are reachable from home")

## Floors under a path: only the start / end lots, sidewalk, crosswalk (and the walker's own legs in open ground).
func _sidewalk_only(W) -> void:
	var pairs := [["home", "cafe"], ["gym", "townie_c"], ["school", "townie_b"], ["market", "park"], ["library", "home"]]
	for pr in pairs:
		var a: Vector2i = Neighborhood.entry_tile(pr[0])
		var b: Vector2i = Neighborhood.entry_tile(pr[1])
		var p: Array = W.find_path(a, b)
		_check(not p.is_empty(), "%s -> %s has a path" % pr)
		_check(float(p.size()) == W.path_length(a, b), "%s -> %s: path_length == find_path size (%d vs %s)" % [pr[0], pr[1], p.size(), str(W.path_length(a, b))])
		var ra: int = W.region_at(a)
		var rb: int = W.region_at(b)
		var cross := 0
		var prev: Vector2i = a
		for t in p:
			var rid: int = W.region_at(t)
			var fl: String = W.get_floor(t)
			var ok: bool = rid == ra or rid == rb or fl == "sidewalk" or fl == "crosswalk"
			_check(ok, "%s -> %s: tile %s (%s, region %d) is off the sidewalks" % [pr[0], pr[1], str(t), fl, rid])
			_check(maxi(absi(t.x - prev.x), absi(t.y - prev.y)) == 1, "%s -> %s: step %s -> %s is not adjacent" % [pr[0], pr[1], str(prev), str(t)])
			prev = t
			if fl == "crosswalk":
				cross += 1
			_check(fl != "asphalt", "%s -> %s: walks on asphalt at %s" % [pr[0], pr[1], str(t)])
		_check(cross > 0, "%s -> %s crosses at least one road, on a crosswalk" % pr)

func _home_to_cafe(W) -> void:
	var a: Vector2i = Neighborhood.entry_tile("home")
	var b: Vector2i = Neighborhood.entry_tile("cafe")
	var n: float = W.path_length(a, b)
	var man: int = absi(a.x - b.x) + absi(a.y - b.y)
	print("  [nav] home -> cafe: %d steps, Manhattan %d (x%.2f), %.0f game minutes" % [int(n), man, n / man, n * Interaction.WALK_MIN_PER_TILE])
	_check(n > 0.0 and n <= man * 1.6, "home -> cafe route is sane (%d steps vs Manhattan %d)" % [int(n), man])
	# next-door lots are short
	var n2: float = W.path_length(Neighborhood.entry_tile("home"), Neighborhood.entry_tile("townie_a"))
	_check(n2 > 0.0 and n2 <= 90.0, "home -> townie_a is a short walk (%d)" % int(n2))

func _fail_fast(W) -> void:
	var a: Vector2i = Neighborhood.entry_tile("home")
	# a tile boxed in by walls in the middle of the green, a pond tile, and a tile in a lot whose gate is fenced
	var green: Rect2i = W.regions.by_lot("green")["rect"]
	var box: Vector2i = green.position + Vector2i(3, 3)
	for e in [Vector3i(box.x, box.y, 0), Vector3i(box.x, box.y + 1, 0), Vector3i(box.x, box.y, 1), Vector3i(box.x + 1, box.y, 1)]:
		W.set_edge(e, "wall")
	var t0 := Time.get_ticks_usec()
	var n: float = W.path_length(a, box)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [nav] boxed-in target: %.1f ms" % ms)
	_check(n < 0.0 and ms < 20.0 * TestFixture.SLACK, "a walled-in target is unreachable and fails fast (%.1f ms, %s)" % [ms, str(n)])
	for e in [Vector3i(box.x, box.y, 0), Vector3i(box.x, box.y + 1, 0), Vector3i(box.x, box.y, 1), Vector3i(box.x + 1, box.y, 1)]:
		W.set_edge(e, "none")
	# fence the gate of the market: nobody gets in or out
	var mk: Dictionary = W.regions.by_lot("market")
	var g: Vector2i = mk["entry"]
	var inside: Vector2i = Neighborhood.entry_tile("market")
	_check(W.path_length(a, inside) > 0.0, "market reachable before the gate is fenced")
	W.set_edge(Vector3i(g.x, g.y + 1, 0), "fence")
	t0 = Time.get_ticks_usec()
	var n2: float = W.path_length(a, inside)
	var n3: float = W.path_length(inside, a)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_check(n2 < 0.0 and n3 < 0.0 and ms < 20.0 * TestFixture.SLACK, "a fenced gate closes the lot both ways, fast (%.1f ms)" % ms)
	W.set_edge(Vector3i(g.x, g.y + 1, 0), "none")
	_check(W.path_length(a, inside) > 0.0, "reachable again after the fence is removed")
	t0 = Time.get_ticks_usec()
	var pond := Vector2i(green.position.x + 14, green.position.y + 10)
	var np: float = W.path_length(a, pond)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [nav] pond tile: %s steps in %.1f ms" % [str(np), ms])
	_check(ms < 20.0 * TestFixture.SLACK, "pond target answered fast (%.1f ms)" % ms)

## Blocking a whole sidewalk stretch (or fencing a gate) must change the cached route.
func _invalidation(W) -> void:
	var a: Vector2i = Neighborhood.entry_tile("home")
	var b: Vector2i = Neighborhood.entry_tile("townie_a")
	var before: Array = W.find_path(a, b)
	var len_before: float = W.path_length(a, b)
	_check(float(before.size()) == len_before, "route and length agree before the edit")
	# put a fence edge across the sidewalk the route uses, right at its middle
	var street_tiles: Array = []
	for t in before:
		if W.get_floor(t) == "sidewalk":
			street_tiles.append(t)
	_check(street_tiles.size() > 4, "the route uses the sidewalk")
	if street_tiles.size() < 5:
		return
	var m: Vector2i = street_tiles[street_tiles.size() / 2]
	var nxt: Vector2i = before[before.find(m) + 1]
	var e: Vector3i = W.edge_between(m, nxt)
	W.set_edge(e, "fence")
	var after: Array = W.find_path(a, b)
	var len_after: float = W.path_length(a, b)
	_check(not after.is_empty() and float(after.size()) == len_after, "a route still exists after the sidewalk is cut (%d)" % after.size())
	_check(len_after > len_before and not after.has(nxt) or not (after.find(m) >= 0 and after.find(m) + 1 < after.size() and after[after.find(m) + 1] == nxt), "the route changed after the cut (%d -> %d)" % [int(len_before), int(len_after)])
	W.set_edge(e, "none")
	_check(W.path_length(a, b) == len_before, "and went back after the cut is removed (%s vs %s)" % [str(W.path_length(a, b)), str(len_before)])

## The distance field used for many in-lot questions gives exactly the A* step counts.
func _field(W) -> void:
	var from: Vector2i = Neighborhood.entry_tile("home")
	var rc: Rect2i = Neighborhood.rect_of("home")
	var nf: NavField = NavField.build(W, from, rc)
	var checked := 0
	for o in W.objects_in_lot_of(from, 40.0):
		var t: Vector2i = o.tile
		var p: Array = W.paths.find_path_rect(from, t, rc)
		_check(nf.steps_to(t) == (p.size() if not p.is_empty() else (0 if t == from else -1)), "field == A* for %s at %s (%d vs %d)" % [o.def_id, str(t), nf.steps_to(t), p.size()])
		checked += 1
	_check(checked > 10, "the home lot has objects to compare (%d)" % checked)