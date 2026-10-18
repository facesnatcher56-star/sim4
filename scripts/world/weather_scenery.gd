extends "res://scripts/world/weather_state.gd"
## WeatherView layer: legacy tree ring around the single lot, seasonal grass tint, snow cover. (Big map: the LotView chunks scatter the trees.)


func _build_trees() -> void:
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.roughness = 0.9
	_pine_mat = StandardMaterial3D.new()
	_pine_mat.roughness = 0.9
	_pine_mat.albedo_color = Color(0.16, 0.36, 0.22)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.25, 0.16)
	trunk_mat.roughness = 1.0
	var snow_cap_mat := StandardMaterial3D.new()
	snow_cap_mat.albedo_color = Color(0.96, 0.98, 1.0)
	snow_cap_mat.roughness = 1.0
	var cx: float = 16.0
	var cy: float = 12.0
	var w = WorldIface.world()
	var ww: float = float(w.width) if w != null else 32.0
	var wh: float = float(w.height) if w != null else 24.0
	cx = ww * 0.5
	cy = wh * 0.5
	_tree_dims = Vector2i(int(ww), int(wh))
	if w != null and w.get("regions") != null and w.regions.has_regions():
		return        # continuous map: trees are MultiMeshes per chunk (lot_chunks.gd)
	var r := RandomNumberGenerator.new()
	r.seed = 424242
	var n: int = 0
	var guard: int = 0
	while n < TREE_COUNT and guard < 2000:
		guard += 1
		var x: float = r.randf_range(-22.0, ww + 22.0)
		var z: float = r.randf_range(-20.0, wh + 20.0)
		# keep a clear margin around the lot so trees never hide the house from the iso camera
		var dx: float = maxf(maxf(-x, x - ww), 0.0)
		var dz: float = maxf(maxf(-z, z - wh), 0.0)
		if maxf(dx, dz) < 5.5:
			continue
		var pine: bool = r.randf() < 0.28
		var root := Node3D.new()
		root.position = Vector3(x, 0.0, z)
		var sc: float = r.randf_range(0.85, 1.35)
		root.scale = Vector3(sc, sc, sc)
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.11
		tm.bottom_radius = 0.17
		tm.height = 1.1
		trunk.mesh = tm
		trunk.material_override = trunk_mat
		trunk.position.y = 0.55
		root.add_child(trunk)
		var canopy := Node3D.new()
		canopy.position.y = 1.0
		root.add_child(canopy)
		var cap: MeshInstance3D = null
		if pine:
			for i in 3:
				var cm := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 1.0 - float(i) * 0.27
				cone.height = 1.1
				cm.mesh = cone
				cm.material_override = _pine_mat
				cm.position.y = 0.45 + float(i) * 0.6
				canopy.add_child(cm)
			cap = MeshInstance3D.new()
			var capm := CylinderMesh.new()
			capm.top_radius = 0.0
			capm.bottom_radius = 0.55
			capm.height = 0.6
			cap.mesh = capm
			cap.material_override = snow_cap_mat
			cap.position.y = 1.95
			canopy.add_child(cap)
		else:
			for i2 in 3:
				var sm := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 0.85 - 0.15 * float(i2)
				sp.height = sp.radius * 2.0
				sm.mesh = sp
				sm.material_override = _leaf_mat
				sm.position = Vector3(r.randf_range(-0.35, 0.35) if i2 > 0 else 0.0, 0.8 + 0.4 * float(i2), r.randf_range(-0.3, 0.3) if i2 > 0 else 0.0)
				canopy.add_child(sm)
		scenery.add_child(root)
		_trees.append({"root": root, "canopy": canopy, "pine": pine, "cap": cap, "blossom": (not pine) and r.randf() < 0.45})
		n += 1


func _update_ground(pos: float) -> void:
	var tint: Color = _season_col("grass_tint", pos, Color("#9be36a"))
	var alpha: float = _season_num("grass_alpha", pos, 0.2)
	var wet: float = float(p["wet"])
	var snowc: float = float(p["snowcover"])
	# wet ground darkens and turns bluish; snow covers everything
	var g: Color = tint.lerp(Color(0.12, 0.16, 0.2), wet * 0.5)
	var ga: float = clampf(alpha + wet * 0.25, 0.0, 1.0)
	g = g.lerp(Color(0.95, 0.97, 1.0), snowc)
	ga = lerpf(ga, 0.96, snowc)
	_grass_mat.albedo_color = Color(g.r, g.g, g.b, ga)
	var sc := Color(0.95, 0.97, 1.0, clampf(snowc * 0.95, 0.0, 0.95))
	if lot.has_method("set_overlay_snow_visible"):
		lot.call("set_overlay_snow_visible", snowc > 0.02)
	_snow_mat.albedo_color = sc
	var ground = lot.get("_ground_mi")
	if ground != null and ground is MeshInstance3D and (ground as MeshInstance3D).material_override is StandardMaterial3D:
		var gc: Color = _season_col("ground", pos, Color("#6fb050"))
		gc = gc.lerp(Color(0.1, 0.14, 0.12), wet * 0.3)
		gc = gc.lerp(Color(0.92, 0.95, 0.98), snowc)
		((ground as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = gc


func _update_trees(pos: float) -> void:
	var w = WorldIface.world()
	if w != null and Vector2i(int(w.width), int(w.height)) != _tree_dims:
		for t in _trees:
			(t["root"] as Node3D).queue_free()      # lot size changed (travel / new game): re-ring the scenery
		_trees.clear()
		_build_trees()
	var leaf: Color = _season_col("leaf", pos, Color("#3f9a3a"))
	var leaf_amt: float = _season_num("leaf_alpha", pos, 1.0)
	var snowc: float = float(p["snowcover"])
	var spring_f: float = clampf(1.0 - absf(pos - 0.5) * 3.0, 0.0, 1.0)     # blossoms peak mid spring
	var bl := Color(str(Seasons.info("spring").get("blossom", "#f6b8d0")))
	_leaf_mat.albedo_color = leaf.lerp(Color(0.95, 0.97, 1.0), snowc * 0.4)
	_pine_mat.albedo_color = Color(0.16, 0.36, 0.22).lerp(Color(0.85, 0.9, 0.95), snowc * 0.55)
	if lot.has_method("set_tree_colors"):      # chunked MultiMesh trees (big map) follow the same seasons
		lot.call("set_tree_colors", _leaf_mat.albedo_color.lerp(Color(0.5, 0.75, 0.4), 0.15), _pine_mat.albedo_color.lerp(Color(0.2, 0.5, 0.3), 0.2))
	for t in _trees:
		var canopy: Node3D = t["canopy"]
		if bool(t["pine"]):
			canopy.visible = true
			var cap = t["cap"]
			if cap != null:
				(cap as Node3D).visible = snowc > 0.1
		else:
			var s: float = clampf(leaf_amt, 0.0, 1.0)
			canopy.visible = s > 0.06
			canopy.scale = Vector3.ONE * lerpf(0.55, 1.0, s)
	# blossoms: tint a share of deciduous canopies pink in spring
	for t2 in _trees:
		if bool(t2["blossom"]) and spring_f > 0.01:
			for c2 in (t2["canopy"] as Node3D).get_children():
				if c2 is MeshInstance3D:
					(c2 as MeshInstance3D).material_override = _blossom_mat(bl.lerp(leaf, 1.0 - spring_f))
		elif not bool(t2["pine"]) and bool(t2["blossom"]):
			for c3 in (t2["canopy"] as Node3D).get_children():
				if c3 is MeshInstance3D and (c3 as MeshInstance3D).material_override != _leaf_mat:
					(c3 as MeshInstance3D).material_override = _leaf_mat

var _blossom: StandardMaterial3D = null

func _blossom_mat(c: Color) -> StandardMaterial3D:
	if _blossom == null:
		_blossom = StandardMaterial3D.new()
		_blossom.roughness = 0.9
	_blossom.albedo_color = c
	return _blossom
