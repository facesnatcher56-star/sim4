class_name WearYard
extends RefCounted
## Task 41a (view only): a neglected yard that does not read as a crop. Grass in CLUSTERS of mixed height (short tufts, medium clumps, a few tall stands), wide curved
## blades with a dark root and a light tip, broad-leaf weeds with the odd dandelion, brown / straw / dead clumps, and a DEAD PATCH (a brown decal with dry stalks and bare soil).
## Colours are muted greens, olives, straw and brown. One MultiMesh per mesh type (about eight draw calls for a whole yard). Own RandomNumberGenerator.
##   build(parent, area [x0, z0, x1, z1] world metres, opts {clumps, seed, dead_patches, skip: Array of Rect2 world rects kept free}) -> Node3D

const PALETTES := {
	"green": ["#6f7a42", "#5f6e3a", "#7a8148", "#68743f"],
	"olive": ["#8a8a4a", "#7d7a40", "#908c52"],
	"straw": ["#a89a5a", "#b3a468", "#9c8c50"],
	"brown": ["#7a6038", "#6b5230", "#85693e"],
	"dead": ["#6d5a38", "#5b4a2e", "#7a6642"],
}
static var _meshes: Dictionary = {}
static var _mat: StandardMaterial3D = null


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.roughness = 1.0
		_mat.resource_name = "wear_yard"
	return _mat


## A clump of `n` curved blades: height h (+- 30 %), spread r, lean. Vertex colours: dark at the root, light at the tip.
static func clump_mesh(key: String, n: int, h: float, r: float, width: float, lean: float) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var ang := rng.randf() * TAU
		var d := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-d.z, 0, d.x)
		var base := d * rng.randf_range(0.0, r)
		var bh := h * rng.randf_range(0.65, 1.2)
		var bw := width * rng.randf_range(0.8, 1.3)
		var bend := lean * rng.randf_range(0.4, 1.4)
		var o := v.size()
		for k in 3:                                          # three rings: root, mid, tip
			var t := float(k) / 2.0
			var out := d * (bend * t * t * bh)               # leans outward, curved
			var wk := bw * (1.0 - t * 0.85)
			var p := base + out + Vector3(0, bh * t, 0)
			v.append(p - side * wk)
			v.append(p + side * wk)
			var shade := lerpf(0.55, 1.0, t)
			col.append(Color(shade, shade, shade))
			col.append(Color(shade, shade, shade))
			nm.append(Vector3.UP)
			nm.append(Vector3.UP)
		for k in 2:
			var a := o + k * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material())
	_meshes[key] = m
	return m


## A broad-leaf weed: a flat rosette of 6 leaves, optionally with a small flower bud on a stem.
static func weed_mesh(flower: bool) -> ArrayMesh:
	var key := "weed_f" if flower else "weed"
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for i in 6:
		var ang := float(i) / 6.0 * TAU
		var d := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-d.z, 0, d.x)
		var o := v.size()
		v.append(Vector3(0, 0.03, 0) - side * 0.02)
		v.append(Vector3(0, 0.03, 0) + side * 0.02)
		v.append(d * 0.12 + Vector3(0, 0.09, 0) - side * 0.07)
		v.append(d * 0.12 + Vector3(0, 0.09, 0) + side * 0.07)
		v.append(d * 0.24 + Vector3(0, 0.07, 0))
		for k in 5:
			nm.append(Vector3.UP)
			col.append(Color(0.7, 0.7, 0.7) if k < 2 else (Color(1, 1, 1) if k < 4 else Color(0.95, 0.95, 0.9)))
		idx.append_array([o, o + 1, o + 2, o + 1, o + 3, o + 2, o + 2, o + 3, o + 4])
	if flower:
		var o2 := v.size()
		for k in 4:
			var a := float(k) / 4.0 * TAU
			v.append(Vector3(cos(a) * 0.03, 0.27, sin(a) * 0.03))
			nm.append(Vector3.UP)
			col.append(Color(1.0, 0.92, 0.35))
		v.append(Vector3(0, 0.31, 0))
		nm.append(Vector3.UP)
		col.append(Color(1.0, 0.95, 0.5))
		for k in 4:
			idx.append_array([o2 + k, o2 + (k + 1) % 4, o2 + 4])
		var s0 := v.size()                                   # stem
		v.append(Vector3(-0.006, 0.03, 0))
		v.append(Vector3(0.006, 0.03, 0))
		v.append(Vector3(0.0, 0.27, 0.0))
		for k in 3:
			nm.append(Vector3.UP)
			col.append(Color(0.45, 0.55, 0.3))
		idx.append_array([s0, s0 + 1, s0 + 2])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material())
	_meshes[key] = m
	return m


static func _pick(rng: RandomNumberGenerator, pal: String) -> Color:
	var arr: Array = PALETTES[pal]
	var c := Color(str(arr[rng.randi() % arr.size()]))
	return c.lightened(rng.randf_range(-0.08, 0.1))


static func _in(area: Array, p: Vector2) -> bool:
	return p.x >= float(area[0]) and p.x <= float(area[2]) and p.y >= float(area[1]) and p.y <= float(area[3])


## `area` and `opts.skip` rects are in world metres. opts: clumps (cluster count) or centres [Vector2], seed, dead_patches (count) or dead_centres [Vector2], weeds (count) or weed_points [Vector2].
## With explicit centres, `area` only clips the members (pass a rect that covers the lot).
static func build(parent: Node3D, area: Array, opts: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 5))
	var root := Node3D.new()
	root.name = "Yard"
	parent.add_child(root)
	var skip: Array = opts.get("skip", [])
	var by_mesh: Dictionary = {}                       # key -> {mesh, list: [[Transform3D, Color]]}
	var w := float(area[2]) - float(area[0])
	var d := float(area[3]) - float(area[1])
	var dead: Array = []                               # [centre Vector2, radius]
	if opts.has("dead_centres"):
		for dc in (opts["dead_centres"] as Array):
			dead.append([dc as Vector2, rng.randf_range(1.2, 1.9)])
	else:
		for i in int(opts.get("dead_patches", 1)):
			dead.append([Vector2(rng.randf_range(float(area[0]) + w * 0.2, float(area[2]) - w * 0.2), rng.randf_range(float(area[1]) + d * 0.2, float(area[3]) - d * 0.2)), rng.randf_range(1.3, 2.0)])
	var centres: Array = opts.get("centres", [])
	var clumps: int = centres.size() if opts.has("centres") else int(opts.get("clumps", 18))
	for ci in clumps:
		var c := (centres[ci] as Vector2) if opts.has("centres") else Vector2(rng.randf_range(float(area[0]), float(area[2])), rng.randf_range(float(area[1]), float(area[3])))
		var tall := rng.randf() < 0.22
		var pal := "green"
		var roll := rng.randf()
		if roll > 0.82:
			pal = "brown"
		elif roll > 0.6:
			pal = "straw"
		elif roll > 0.35:
			pal = "olive"
		var members := rng.randi_range(3, 8)
		for m in members:
			var p := c + Vector2(rng.randfn(0.0, 0.55), rng.randfn(0.0, 0.55))
			if not _in(area, p) or _skipped(skip, p):
				continue
			var kind := "short"
			var r := rng.randf()
			if tall and r < 0.55:
				kind = "tall"
			elif r < 0.5:
				kind = "mid"
			var p_dead := _near_dead(dead, p)
			var cc := _pick(rng, "dead" if p_dead and rng.randf() < 0.7 else pal)
			var sc := Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.7, 1.35) * (0.5 if p_dead else 1.0), rng.randf_range(0.7, 1.4))
			_add(by_mesh, kind, p, rng.randf() * TAU, sc, cc)
	var wpts: Array = opts.get("weed_points", [])
	var nweeds: int = wpts.size() if opts.has("weed_points") else int(opts.get("weeds", 20))
	for i in nweeds:
		var p := (wpts[i] as Vector2) if opts.has("weed_points") else Vector2(rng.randf_range(float(area[0]), float(area[2])), rng.randf_range(float(area[1]), float(area[3])))
		if _skipped(skip, p):
			continue
		var fl := rng.randf() < 0.3
		var cc2 := Color(0.42, 0.5, 0.26).lightened(rng.randf_range(-0.1, 0.14))
		_add(by_mesh, "weed_f" if fl else "weed", p, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.55, 1.2), cc2)
	for dp in dead:                                     # dry stalks standing in the dead patch
		for i in 7:
			var p: Vector2 = (dp[0] as Vector2) + Vector2(rng.randfn(0.0, float(dp[1]) * 0.45), rng.randfn(0.0, float(dp[1]) * 0.45))
			if _in(area, p) and not _skipped(skip, p):
				_add(by_mesh, "short", p, rng.randf() * TAU, Vector3(1, rng.randf_range(0.5, 0.9), 1), _pick(rng, "dead"))
	for key in by_mesh:
		var list: Array = by_mesh[key]["list"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = by_mesh[key]["mesh"]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.name = str(key)
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	for dp in dead:                                     # brown dead patch + bare soil on the ground (a Forward+ decal)
		_patch_decal(root, dp[0], float(dp[1]) * 2.0, "dead_grass", Color(1, 1, 1, 0.95))
		_patch_decal(root, dp[0] + Vector2(0.3, -0.2), float(dp[1]) * 0.9, "dirt_patch", Color(1, 1, 1, 0.85))
	return root


static func _near_dead(dead: Array, p: Vector2) -> bool:
	for dp in dead:
		if p.distance_to(dp[0]) < float(dp[1]):
			return true
	return false


static func _skipped(skip: Array, p: Vector2) -> bool:
	for r in skip:
		if _in(r, p):
			return true
	return false


static func _add(by_mesh: Dictionary, kind: String, p: Vector2, yaw: float, sc: Vector3, c: Color) -> void:
	if not by_mesh.has(kind):
		var m: ArrayMesh
		match kind:
			"tall": m = clump_mesh("tall", 9, 0.85, 0.12, 0.05, 0.45)
			"mid": m = clump_mesh("mid", 8, 0.42, 0.1, 0.045, 0.5)
			"weed": m = weed_mesh(false)
			"weed_f": m = weed_mesh(true)
			_: m = clump_mesh("short", 7, 0.18, 0.09, 0.04, 0.55)
		by_mesh[kind] = {"mesh": m, "list": []}
	var b := Basis.from_euler(Vector3(0, yaw, 0)).scaled(sc)
	(by_mesh[kind]["list"] as Array).append([Transform3D(b, Vector3(p.x, 0.0, p.y)), c])


static func _patch_decal(root: Node3D, c: Vector2, size: float, tex: String, mod: Color) -> void:
	var dc := Decal.new()
	dc.texture_albedo = DressingTex.tex(tex)
	dc.size = Vector3(size, 1.0, size)
	dc.position = Vector3(c.x, 0.4, c.y)
	dc.modulate = mod
	dc.upper_fade = 0.1
	dc.lower_fade = 0.1
	root.add_child(dc)
