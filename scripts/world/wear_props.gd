class_name WearProps
extends RefCounted
## Task 41a (view only): the small real-shaped props of the wear layer, built procedurally, one cached mesh per kind and one MultiMesh (one draw call) per kind:
##   litter  paper (crumpled), can, bottle, bag, newspaper      clutter  box (cardboard), dishes, clothes, towel
## Colours are muted per kind and picked by a 0..1 tone (no saturated confetti). `build(parent, placements)` makes the MultiMeshInstance3Ds;
## a placement is {kind, pos: Vector3, yaw (deg), scale (float), tone (0..1)}. Meshes are tiny (under 100 triangles).

const KINDS := ["paper", "can", "bottle", "bag", "newspaper", "box", "dishes", "clothes", "towel"]
const PALETTES := {
	"paper": ["#a8a291", "#938e80", "#b0aa96", "#868274", "#9d9784"],
	"can": ["#9a4a3e", "#6c7f8c", "#8d9190", "#5f7a5a", "#a58a4a", "#7a7d80"],
	"bottle": ["#4a6a4a", "#6a4f32", "#7f8a86", "#3e5568", "#5a6e44"],
	"bag": ["#7a7f83", "#5f7286", "#9a9486", "#3e3f42", "#857f72"],
	"newspaper": ["#aaa592", "#9a9582", "#b4af9a"],
	"box": ["#8a6f4c", "#7c6446", "#9a8159", "#6f5a40"],
	"dishes": ["#bdb7a6", "#a9a598", "#8a9595", "#b0a37f"],
	"clothes": ["#6e7a8a", "#8a6a62", "#7d8068", "#4f5258", "#a29682", "#5e6b5a"],
	"towel": ["#8b9a9e", "#a8967d", "#7c8a8f"],
}
static var _meshes: Dictionary = {}
static var _mat: StandardMaterial3D = null


static func color_of(kind: String, tone: float) -> Color:
	var pal: Array = PALETTES.get(kind, ["#aaaaaa"])
	var c := Color(str(pal[int(clampf(tone, 0.0, 0.9999) * pal.size()) % pal.size()]))
	return c.darkened(fposmod(tone * 7.3, 1.0) * 0.18)


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.albedo_color = Color.WHITE
		_mat.roughness = 0.95
		_mat.resource_name = "wear_props"
	return _mat


static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var b := _Builder.new()
	match kind:
		"paper":
			b.add(_sphere(0.07, 5, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 0.9)), Vector3(0, 0.05, 0)), Color(1, 1, 1))
			b.add(_sphere(0.04, 4, 2), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), Vector3(0.05, 0.07, 0.02)), Color(0.9, 0.9, 0.9))
		"can":
			var lie := Basis.from_euler(Vector3(0, 0, PI * 0.5))
			b.add(_cyl(0.033, 0.11, 8), Transform3D(lie, Vector3(0, 0.033, 0)), Color(1, 1, 1))
			b.add(_cyl(0.026, 0.115, 8), Transform3D(lie, Vector3(0, 0.033, 0)), Color(0.82, 0.82, 0.8))
		"bottle":
			var lie := Basis.from_euler(Vector3(0, 0, PI * 0.5))
			b.add(_cyl(0.04, 0.15, 8), Transform3D(lie, Vector3(0, 0.04, 0)), Color(1, 1, 1))
			b.add(_cyl(0.017, 0.09, 6), Transform3D(lie, Vector3(0.115, 0.04, 0)), Color(1, 1, 1))
			b.add(_cyl(0.02, 0.025, 6), Transform3D(lie, Vector3(0.17, 0.04, 0)), Color(0.35, 0.35, 0.33))
		"bag":
			b.add(_sphere(0.14, 7, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 0.8)), Vector3(0, 0.06, 0)), Color(1, 1, 1))
			b.add(_box(Vector3(0.04, 0.09, 0.02)), Transform3D(Basis.from_euler(Vector3(0.3, 0.3, 0.2)), Vector3(-0.07, 0.12, 0.03)), Color(0.9, 0.9, 0.9))
			b.add(_box(Vector3(0.04, 0.08, 0.02)), Transform3D(Basis.from_euler(Vector3(-0.2, 0.2, -0.3)), Vector3(0.06, 0.12, -0.03)), Color(0.9, 0.9, 0.9))
		"newspaper":
			b.add(_box(Vector3(0.3, 0.012, 0.22)), Transform3D(Basis.from_euler(Vector3(0, 0.1, 0)), Vector3(0, 0.008, 0)), Color(1, 1, 1))
			b.add(_box(Vector3(0.26, 0.01, 0.2)), Transform3D(Basis.from_euler(Vector3(0, -0.25, 0)), Vector3(0.03, 0.02, 0.02)), Color(0.9, 0.9, 0.88))
		"box":
			b.add(_box(Vector3(0.36, 0.22, 0.28)), Transform3D(Basis(), Vector3(0, 0.11, 0)), Color(1, 1, 1))
			b.add(_box(Vector3(0.36, 0.012, 0.15)), Transform3D(Basis.from_euler(Vector3(-0.6, 0, 0)), Vector3(0, 0.25, -0.12)), Color(0.88, 0.88, 0.86))
			b.add(_box(Vector3(0.36, 0.012, 0.15)), Transform3D(Basis.from_euler(Vector3(0.9, 0, 0)), Vector3(0, 0.24, 0.12)), Color(0.9, 0.9, 0.88))
		"dishes":
			b.add(_cyl(0.11, 0.02, 9), Transform3D(Basis(), Vector3(0, 0.01, 0)), Color(1, 1, 1))
			b.add(_cyl(0.09, 0.02, 9), Transform3D(Basis(), Vector3(0.01, 0.03, 0)), Color(0.94, 0.94, 0.92))
			b.add(_sphere(0.04, 5, 3), Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), Vector3(0.0, 0.05, 0.0)), Color(0.42, 0.32, 0.2))
			b.add(_cyl(0.04, 0.085, 7), Transform3D(Basis(), Vector3(0.15, 0.043, 0.08)), Color(0.7, 0.72, 0.72))
		"clothes":
			b.add(_box(Vector3(0.32, 0.03, 0.24)), Transform3D(Basis.from_euler(Vector3(0, 0.3, 0)), Vector3(0, 0.015, 0)), Color(1, 1, 1))
			b.add(_box(Vector3(0.24, 0.035, 0.2)), Transform3D(Basis.from_euler(Vector3(0.05, -0.6, 0.06)), Vector3(0.05, 0.045, 0.03)), Color(0.78, 0.8, 0.84))
			b.add(_cyl(0.025, 0.26, 6), Transform3D(Basis.from_euler(Vector3(0.1, 0.9, PI * 0.5)), Vector3(-0.08, 0.04, 0.12)), Color(0.9, 0.86, 0.82))
		"towel":
			b.add(_box(Vector3(0.4, 0.025, 0.25)), Transform3D(Basis.from_euler(Vector3(0, 0.2, 0)), Vector3(0, 0.013, 0)), Color(1, 1, 1))
			b.add(_box(Vector3(0.22, 0.03, 0.2)), Transform3D(Basis.from_euler(Vector3(0, -0.4, 0)), Vector3(0.05, 0.04, 0)), Color(0.88, 0.88, 0.88))
		_:
			b.add(_box(Vector3(0.15, 0.1, 0.15)), Transform3D(Basis(), Vector3(0, 0.05, 0)), Color(1, 1, 1))
	var m := b.finish()
	_meshes[kind] = m
	return m


static func _box(s: Vector3) -> PrimitiveMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func _cyl(r: float, h: float, seg: int) -> PrimitiveMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func _sphere(r: float, seg: int, rings: int) -> PrimitiveMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


## Merges primitives into one mesh with a vertex colour per part (the instance colour then multiplies it).
class _Builder extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func add(pm: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var a: Array = pm.get_mesh_arrays()
		var base := v.size()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		for i in vs.size():
			v.append(xf * vs[i])
			n.append((xf.basis * ns[i]).normalized())
			c.append(col)
		for i in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + i)

	func finish() -> ArrayMesh:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, WearProps.material())
		return m


## Litter pieces scattered over `area` [x0, z0, x1, z1] (world metres): crumpled paper, cans, bottles, bags, newspaper, in loose clusters (rubbish gathers), no confetti.
static func litter(area: Array, count: int, seed: int, y: float = 0.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var kinds := ["paper", "paper", "paper", "can", "can", "bottle", "bag", "newspaper"]
	var out: Array = []
	var last := Vector2(float(area[0]), float(area[1]))
	for i in count:
		var p := Vector2(rng.randf_range(float(area[0]), float(area[2])), rng.randf_range(float(area[1]), float(area[3])))
		if i > 0 and rng.randf() < 0.45:
			p = last + Vector2(rng.randfn(0.0, 0.35), rng.randfn(0.0, 0.25))
			p = Vector2(clampf(p.x, float(area[0]), float(area[2])), clampf(p.y, float(area[1]), float(area[3])))
		last = p
		out.append({"kind": kinds[rng.randi() % kinds.size()], "pos": Vector3(p.x, y, p.y), "yaw": rng.randf() * 360.0, "scale": rng.randf_range(0.8, 1.25), "tone": rng.randf()})
	return out


## One MultiMeshInstance3D per kind under a new Node3D `name` (added to `parent`); empty placements give an empty node.
static func build(parent: Node3D, placements: Array, node_name: String, range_end: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var by_kind: Dictionary = {}
	for p in placements:
		var k := str(p["kind"])
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(p)
	for k in by_kind:
		var list: Array = by_kind[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh(k)
		mm.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			var s := float(p.get("scale", 1.0))
			var b := Basis.from_euler(Vector3(0, deg_to_rad(float(p.get("yaw", 0.0))), 0)).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(b, p["pos"]))
			mm.set_instance_color(i, color_of(k, float(p.get("tone", 0.5))))
		var mi := MultiMeshInstance3D.new()
		mi.name = k
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			mi.visibility_range_end = range_end
		root.add_child(mi)
	return root
