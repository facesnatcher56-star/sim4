class_name ObjectVisualNodes
extends RefCounted
## Task 33.3 (view only): turns a look from ObjectVisualRules into nodes on one object node of LotView: surface recolours (soil, screens, lamp shades), a tint overlay
## (grime, scorch), model droop, small primitive parts (burners, crops, crumpled blanket) under "StateFx", and particles + lights under "StateFx/Near",
## which ObjectStateView switches off for objects far from the camera. Materials and meshes are shared and cached; nothing runs per frame (the flicker is a shader).

const FX := "StateFx"
const NEAR := "Near"

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}
static var _hidden_mat: StandardMaterial3D = null
static var _flick_shader: Shader = null


static func _mesh_instances(root: Node, out: Array) -> void:
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		if c.name != FX:
			_mesh_instances(c, out)


static func _name_matches(sname: String, pat: String) -> bool:
	if pat.ends_with("*"):
		return sname.begins_with(pat.trim_suffix("*"))
	return sname == pat


static func surface_name(mi: MeshInstance3D, i: int) -> String:
	var m: Material = mi.mesh.surface_get_material(i) if mi.mesh != null else null
	return str(m.resource_name) if m != null else ""


## Apply `look` (possibly {}) to the object node. Idempotent: the same look twice does nothing.
static func apply(node: Node3D, look: Dictionary) -> void:
	var sig := var_to_str(look)
	if str(node.get_meta("ovsig", "")) == sig:
		return
	node.set_meta("ovsig", sig)
	var vis: Node3D = node.get_child(0) as Node3D if node.get_child_count() > 0 else null
	if vis == null:
		return
	var meshes: Array = []
	_mesh_instances(vis, meshes)
	for mi in meshes:
		for i in (mi as MeshInstance3D).get_surface_override_material_count():
			(mi as MeshInstance3D).set_surface_override_material(i, null)
		(mi as MeshInstance3D).material_overlay = null
	vis.scale = Vector3.ONE
	vis.rotation.z = 0.0
	var old := node.get_node_or_null(FX)
	if old != null:
		node.remove_child(old)
		old.queue_free()
	node.set_meta("has_near", false)
	if look.is_empty():
		return
	vis.scale = look["scale"]
	vis.rotation.z = deg_to_rad(float(look["tilt"]))
	var surf: Dictionary = look["surfaces"]
	var hide: Array = look["hide"]
	if not surf.is_empty() or not hide.is_empty():
		for mi in meshes:
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for i in m.mesh.get_surface_count():
				var sname := surface_name(m, i)
				for h in hide:
					if _name_matches(sname, str(h)):
						m.set_surface_override_material(i, _invisible())
				for pat in surf:
					if _name_matches(sname, str(pat)):
						var sd: Dictionary = surf[pat]
						m.set_surface_override_material(i, material_for(sd["color"], float(sd["emit"]), float(sd["flicker"])))
	if look["overlay"] != null:
		var ov := _overlay(look["overlay"])
		for mi in meshes:
			(mi as MeshInstance3D).material_overlay = ov
	if (look["parts"] as Array).is_empty() and (look["fx"] as Array).is_empty():
		return
	var fx := Node3D.new()
	fx.name = FX
	node.add_child(fx)
	var near := Node3D.new()
	near.name = NEAR
	fx.add_child(near)
	var has_near := false
	var merged: MeshInstance3D = _merged_parts(look["parts"])         # task 41a: plain parts of one object become ONE mesh with vertex colours (a poor bed is 6 boxes)
	if merged != null:
		fx.add_child(merged)
	for p in (look["parts"] as Array):
		var mi := _part(p) if merged == null or not _mergeable(p) else null
		if mi != null:
			fx.add_child(mi)
		var lg: Array = p["light"]
		if lg.size() >= 2:
			var om := OmniLight3D.new()
			om.omni_range = float(lg[0])
			om.light_energy = float(lg[1])
			om.light_color = p["color"]
			om.shadow_enabled = false
			om.position = p["pos"]
			near.add_child(om)
			has_near = true
	for f in (look["fx"] as Array):
		var ps := make_particles(str(f["kind"]), f["pos"])
		if ps != null:
			near.add_child(ps)
			has_near = true
	node.set_meta("has_near", has_near)


static func _mergeable(p: Dictionary) -> bool:
	return float(p["emit"]) <= 0.0 and float(p["flicker"]) <= 0.0 and (p["light"] as Array).is_empty() and (p["color"] as Color).a >= 0.99


## One mesh for all plain (not glowing, no light, opaque) parts when there are more than three; null otherwise. Cached by the parts' content.
static func _merged_parts(parts: Array) -> MeshInstance3D:
	var plain: Array = parts.filter(func(p): return _mergeable(p))
	if plain.size() <= 3:
		return null
	var key := "merged%s" % var_to_str(plain).hash()
	var mesh: ArrayMesh = _meshes.get(key)
	if mesh == null:
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var c := PackedColorArray()
		var idx := PackedInt32Array()
		for p in plain:
			var pm: PrimitiveMesh = _shape_mesh(str(p["shape"]), p["size"]) as PrimitiveMesh
			var a: Array = pm.get_mesh_arrays()
			var xf := Transform3D(Basis.from_euler((p["rot"] as Vector3) * (PI / 180.0)), p["pos"])
			var base := v.size()
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in vs.size():
				v.append(xf * vs[i])
				n.append((xf.basis * ns[i]).normalized())
				c.append(p["color"])
			for i in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
				idx.append(base + i)
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, WearProps.material())
		_meshes[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Particles and lights of an object are only live while it is near the camera.
static func set_near(node: Node3D, on: bool) -> void:
	var near := node.get_node_or_null("%s/%s" % [FX, NEAR])
	if near == null:
		return
	near.visible = on
	for c in near.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = on


# ------------------------------------------------------------------ materials / meshes

## A surface that is not drawn (the model's neat blanket, its painted-in crops): fully transparent.
static func _invisible() -> StandardMaterial3D:
	if _hidden_mat == null:
		_hidden_mat = StandardMaterial3D.new()
		_hidden_mat.albedo_color = Color(1, 1, 1, 0)
		_hidden_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hidden_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _hidden_mat


static func _overlay(c: Color) -> StandardMaterial3D:
	var key := "ov%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	_mats[key] = m
	return m


static func _flicker_shader() -> Shader:
	if _flick_shader == null:
		_flick_shader = Shader.new()
		_flick_shader.code = "shader_type spatial;\nuniform vec4 col : source_color = vec4(1.0);\nuniform float emit = 1.0;\nuniform float flick = 0.0;\n" \
			+ "void fragment() {\n\tfloat f = 1.0 - flick * (0.5 + 0.5 * sin(TIME * 23.0) * sin(TIME * 6.1 + 1.3));\n" \
			+ "\tvec3 tint = mix(col.rgb, col.bgr, flick * 0.5 * (0.5 + 0.5 * sin(TIME * 2.3)));\n\tALBEDO = tint * 0.25;\n\tEMISSION = tint * emit * f;\n}\n"
	return _flick_shader


## Shared material: plain colour, glowing colour, or glowing flickering colour (TV). Flicker is off with Reduce motion / No flashing effects.
static func material_for(c: Color, emit: float, flicker: float) -> Material:
	var fl := flicker if (flicker > 0.0 and not GameSettings.reduce_motion() and GameSettings.flashing_allowed()) else 0.0
	var key := "m%s_%.2f_%.2f" % [c.to_html(), emit, fl]
	if _mats.has(key):
		return _mats[key]
	var mat: Material
	if fl > 0.0:
		var sm := ShaderMaterial.new()
		sm.shader = _flicker_shader()
		sm.set_shader_parameter("col", c)
		sm.set_shader_parameter("emit", emit)
		sm.set_shader_parameter("flick", fl)
		mat = sm
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		if c.a < 0.99:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat = m
	_mats[key] = mat
	return mat


static func _shape_mesh(shape: String, size: Vector3) -> Mesh:
	var key := "%s%s" % [shape, str(size)]
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match shape:
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x
			s.height = size.x * 2.0
			s.radial_segments = 8
			s.rings = 4
			mesh = s
		"cyl", "cone":
			var c := CylinderMesh.new()
			c.bottom_radius = size.x
			c.top_radius = 0.0 if shape == "cone" else size.x
			c.height = size.y
			c.radial_segments = 10
			c.rings = 1
			mesh = c
		_:
			var b := BoxMesh.new()
			b.size = size
			mesh = b
	_meshes[key] = mesh
	return mesh


static func _part(p: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _shape_mesh(str(p["shape"]), p["size"])
	mi.material_override = material_for(p["color"], float(p["emit"]), float(p["flicker"]))
	mi.position = p["pos"]
	mi.rotation_degrees = p["rot"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ particles

static func make_particles(kind: String, pos: Vector3) -> CPUParticles3D:
	var d := ObjectVisualRules.fx_kind(kind)
	if d.is_empty() or GameSettings.effects_quality() == 0:
		return null
	if bool(d.get("flashy", false)) and (GameSettings.reduce_motion() or not GameSettings.flashing_allowed()):
		return null
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = int(d.get("amount", 8))
	p.lifetime = float(d.get("lifetime", 1.0))
	p.explosiveness = float(d.get("explosiveness", 0.0))
	p.direction = ObjectVisualRules._vec(d.get("dir", [0, 1, 0]), Vector3.UP)
	p.spread = float(d.get("spread", 30.0))
	p.initial_velocity_min = float(d.get("v_min", 0.2))
	p.initial_velocity_max = float(d.get("v_max", 0.5))
	p.gravity = ObjectVisualRules._vec(d.get("gravity", [0, 0, 0]))
	p.scale_amount_min = float(d.get("size_min", 0.04))
	p.scale_amount_max = float(d.get("size_max", 0.08))
	var col := Color(str(d.get("color", "#ffffff")))
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = mat
	p.color = col
	if bool(d.get("fade", true)):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p
