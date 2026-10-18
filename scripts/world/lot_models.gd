extends "res://scripts/world/lot_camera.gd"
## LotView layer: Model loading and visuals for objects / walls / doors (glb with coloured-box fallbacks).


func _load_model(path: String) -> PackedScene:
	if _model_cache.has(path):
		return _model_cache[path]
	var ps: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		var r = load(path)
		if r is PackedScene:
			ps = r
	_model_cache[path] = ps
	return ps


func _box_mesh_instance(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	return mi


func _make_wall_visual(kind: String) -> Dictionary:
	var root := Node3D.new()
	var leaf: Node3D = null
	var wall_col := Color(0.9, 0.87, 0.8)
	var def_id := kind
	if kind == "fence":
		root.add_child(_box_mesh_instance(Vector3(1.0, 0.9, 0.06), Vector3(0, 0.45, 0), Color(0.55, 0.38, 0.22)))
		root.set_meta("fence", true)
		return {"root": root, "leaf": null}
	var model_path := "res://assets/models/%s.glb" % ("wall" if kind == "wall" else def_id)
	var ps := _load_model(model_path)
	if ps:
		var inst := ps.instantiate()
		root.add_child(inst)
		if kind == "door":
			leaf = inst.get_node_or_null("leaf")
		return {"root": root, "leaf": leaf}
	# fallbacks
	match kind:
		"wall":
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, 0), wall_col))
		"window":
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, 0.9, WALL_T), Vector3(0, 0.45, 0), wall_col))
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, WALL_H - 1.9, WALL_T), Vector3(0, 1.9 + (WALL_H - 1.9) * 0.5, 0), wall_col))
			var glass := _box_mesh_instance(Vector3(1.0, 1.0, 0.03), Vector3(0, 1.4, 0), Color(0.6, 0.8, 0.95, 0.5))
			(glass.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			root.add_child(glass)
		"door":
			root.add_child(_box_mesh_instance(Vector3(1.0 + WALL_T, WALL_H - 2.0, WALL_T), Vector3(0, 2.0 + (WALL_H - 2.0) * 0.5, 0), wall_col))
			root.add_child(_box_mesh_instance(Vector3(0.08, 2.0, WALL_T), Vector3(-0.46, 1.0, 0), Color(0.55, 0.4, 0.25)))
			root.add_child(_box_mesh_instance(Vector3(0.08, 2.0, WALL_T), Vector3(0.46, 1.0, 0), Color(0.55, 0.4, 0.25)))
			leaf = Node3D.new()
			leaf.position = Vector3(-0.42, 0, 0)
			leaf.add_child(_box_mesh_instance(Vector3(0.84, 1.95, 0.05), Vector3(0.42, 0.975, 0), Color(0.62, 0.45, 0.28)))
			root.add_child(leaf)
	return {"root": root, "leaf": leaf}


# ------------------------------------------------------------------ objects

func _yaw_for_rot(rot: int) -> float:
	var f := WorldObject.rotate_vec(Vector2(0, 1), rot)
	return atan2(-f.x, -f.y)


## Visual (model or fallback) for a definition, origin at footprint centre, unrotated (front = model -Z).
func make_def_visual(def_id: String) -> Node3D:
	var d: Dictionary = World.get_def(def_id)
	var root := Node3D.new()
	var ps := _load_model(str(d.get("model", "")))
	if ps:
		root.add_child(ps.instantiate())
		if show_labels:
			root.add_child(_label(str(d.get("label", def_id)), float(d.get("height", 1.0)) + 0.3))
		return root
	var sz: Array = d.get("size", [1, 1])
	var h: float = float(d.get("height", 1.0))
	var col := Color(str(d.get("color", "#aaaaaa")))
	var w := float(sz[0]) * 0.92
	var dp := float(sz[1]) * 0.92
	root.add_child(_box_mesh_instance(Vector3(w, h, dp), Vector3(0, h * 0.5, 0), col))
	# front marker (model front = -Z)
	root.add_child(_box_mesh_instance(Vector3(w * 0.5, h * 0.25, 0.04), Vector3(0, h * 0.7, -dp * 0.5 - 0.01), col.darkened(0.45)))
	root.add_child(_label(str(d.get("label", def_id)), h + 0.25))
	return root


func _label(text: String, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.006
	l.position = Vector3(0, y, 0)
	l.no_depth_test = true
	l.name = "Label"
	return l
