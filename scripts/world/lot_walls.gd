extends "res://scripts/world/lot_chunks.gd"
## LotView layer: Wall meshes, cut-away animation and door leaves. Wall / door nodes live in one container per 16x16
## chunk and only exist for chunks near the camera (chunk_is_kept): a 160x120 map with hundreds of walls never builds them all.

const WALL_CHUNKS_PER_FRAME := 3

var _wall_ends: Dictionary = {}       # lattice point -> number of wall edges meeting there
var _wall_by_chunk: Dictionary = {}   # Vector2i -> Array of wall edges
var _wall_nodes: Dictionary = {}      # Vector2i -> {root: Node3D, walls: Array, doors: Array}


## World walls changed (or the world was reset): drop every wall node, regroup the edges by chunk, build the near chunks now.
func _build_walls() -> void:
	for ch in _wall_nodes.values():
		(ch["root"] as Node3D).queue_free()
	_wall_nodes.clear()
	_walls.clear()
	_doors.clear()
	_wall_ends.clear()
	_wall_by_chunk.clear()
	for e2 in World.walls:
		for v in ([Vector2i(e2.x, e2.y), Vector2i(e2.x + 1, e2.y)] if e2.z == 0 else [Vector2i(e2.x, e2.y), Vector2i(e2.x, e2.y + 1)]):
			_wall_ends[v] = int(_wall_ends.get(v, 0)) + 1
		var c := World.regions.chunk_of(Vector2i(e2.x, e2.y))
		if not _wall_by_chunk.has(c):
			_wall_by_chunk[c] = []
		(_wall_by_chunk[c] as Array).append(e2)
	_walls_dirty = false
	_cut_dirty = true
	_sync_wall_chunks(true)


## Build wall nodes for chunks that came near, free those that went far. Called every frame (cheap when nothing changed).
func _sync_wall_chunks(force: bool = false) -> void:
	var changed := false
	var budget := 9999 if force else WALL_CHUNKS_PER_FRAME
	for c in _wall_by_chunk:
		if budget <= 0:
			break
		if not _wall_nodes.has(c) and chunk_is_active(c):
			_build_wall_chunk(c)
			budget -= 1
			changed = true
	for c in _wall_nodes.keys():
		if not chunk_is_kept(c):
			(_wall_nodes[c]["root"] as Node3D).queue_free()
			_wall_nodes.erase(c)
			changed = true
	if changed:
		_walls.clear()
		_doors.clear()
		for ch in _wall_nodes.values():
			_walls.append_array(ch["walls"])
			_doors.append_array(ch["doors"])


func _build_wall_chunk(c: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "walls_%d_%d" % [c.x, c.y]
	_wall_root.add_child(root)
	var entry := {"root": root, "walls": [], "doors": []}
	for e in _wall_by_chunk[c]:
		var kind: String = World.walls[e] if World.walls.has(e) else "wall"
		var horizontal: bool = e.z == 0
		var node := Node3D.new()
		node.position = Vector3(e.x + 0.5, 0, e.y) if horizontal else Vector3(e.x, 0, e.y + 0.5)
		if not horizontal:
			node.rotation.y = PI * 0.5
		var visual := _make_wall_visual(kind)
		node.add_child(visual["root"])
		root.add_child(node)
		if visual.has("leaf") and visual["leaf"] != null:
			(entry["doors"] as Array).append({"leaf": visual["leaf"], "pos": node.position, "open": 0.0})
		var pts: Array = [Vector2i(e.x, e.y), Vector2i(e.x + 1, e.y)] if horizontal else [Vector2i(e.x, e.y), Vector2i(e.x, e.y + 1)]
		var free_standing: bool = kind != "wall" and int(_wall_ends[pts[0]]) == 1 and int(_wall_ends[pts[1]]) == 1   # gate / lone doorway: never cut down
		var init_scale := 1.0 if (wall_mode == WallMode.UP or kind == "fence" or free_standing) else CUT_RATIO
		node.scale.y = init_scale
		(entry["walls"] as Array).append({"node": node, "e": e, "kind": kind, "pos": node.position, "axis": 0 if horizontal else 1,
			"scale": init_scale, "free": free_standing})
	_wall_nodes[c] = entry


func _update_walls(delta: float) -> void:
	var d := _cam_dir()
	for w in _walls:
		var target := 1.0
		if w["kind"] == "fence" or w["free"]:
			target = 1.0
		elif wall_mode == WallMode.DOWN:
			target = CUT_RATIO
		elif wall_mode == WallMode.CUTAWAY:
			var p: Vector3 = w["pos"]
			var comp: float
			var rel: float
			if w["axis"] == 0:     # along X, faces +-Z
				comp = d.z
				rel = (p.z - _target.z) * signf(d.z)
			else:                  # along Z, faces +-X
				comp = d.x
				rel = (p.x - _target.x) * signf(d.x)
			if absf(comp) > 0.25 and rel > -0.5:
				target = CUT_RATIO
		var cur: float = w["scale"]
		if not is_equal_approx(cur, target):
			cur = move_toward(cur, target, delta * 4.0)
			w["scale"] = cur
			(w["node"] as Node3D).scale.y = maxf(cur, 0.01)


func _update_doors(delta: float) -> void:
	if _doors.is_empty():
		return
	for dd in _doors:
		var leaf: Node3D = dd["leaf"]
		if not is_instance_valid(leaf):
			continue
		var gp: Vector3 = dd["pos"]
		var near := false
		for fv in _folk_views.values():
			if fv.position.distance_to(gp) < 1.3:
				near = true
				break
		dd["open"] = move_toward(dd["open"], 1.0 if near else 0.0, delta * 4.0)
		leaf.rotation.y = -dd["open"] * deg_to_rad(95)
