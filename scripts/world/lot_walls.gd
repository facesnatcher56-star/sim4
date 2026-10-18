extends "res://scripts/world/lot_models.gd"
## LotView layer: Wall meshes, cut-away animation and door leaves.


func _build_walls() -> void:
	for w in _walls:
		w["node"].queue_free()
	_walls.clear()
	_doors.clear()
	var ends: Dictionary = {}      # lattice point -> number of wall edges meeting there
	for e2 in World.walls:
		for v in ([Vector2i(e2.x, e2.y), Vector2i(e2.x + 1, e2.y)] if e2.z == 0 else [Vector2i(e2.x, e2.y), Vector2i(e2.x, e2.y + 1)]):
			ends[v] = int(ends.get(v, 0)) + 1
	for e in World.walls:
		var kind: String = World.walls[e]
		var horizontal: bool = e.z == 0
		var node := Node3D.new()
		node.position = Vector3(e.x + 0.5, 0, e.y) if horizontal else Vector3(e.x, 0, e.y + 0.5)
		if not horizontal:
			node.rotation.y = PI * 0.5
		var visual := _make_wall_visual(kind)
		node.add_child(visual["root"])
		_wall_root.add_child(node)
		if visual.has("leaf") and visual["leaf"] != null:
			_doors.append({"leaf": visual["leaf"], "pos": node.position, "open": 0.0})
		var pts: Array = [Vector2i(e.x, e.y), Vector2i(e.x + 1, e.y)] if horizontal else [Vector2i(e.x, e.y), Vector2i(e.x, e.y + 1)]
		var free_standing: bool = kind != "wall" and int(ends[pts[0]]) == 1 and int(ends[pts[1]]) == 1   # gate / lone doorway: never cut down
		var init_scale := 1.0 if (wall_mode == WallMode.UP or kind == "fence" or free_standing) else CUT_RATIO
		node.scale.y = init_scale
		_walls.append({"node": node, "e": e, "kind": kind, "pos": node.position, "axis": 0 if horizontal else 1,
			"scale": init_scale, "free": free_standing})
	_walls_dirty = false
	_cut_dirty = true


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
