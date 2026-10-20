extends "res://scripts/world/lot_models.gd"
## LotView layer: CHUNKED static terrain. The map is cut into 16x16 chunks (WorldRegions.CHUNK). Each chunk owns
##   * one floor ArrayMesh (vertex colours; road centre lines + crosswalk bars are baked in as flat quads),
##   * a grass-tint and a snow overlay mesh (materials shared with WeatherView, see overlay_*_mat),
##   * MultiMesh trees scattered deterministically on the map's "park" grass (big-map mode only).
## Chunk meshes are built lazily the first time a chunk is near the camera and rebuilt only when World.regions reports
## the chunk's floors changed. Chunks outside the view rectangle are hidden; chunk_is_active()/chunk_is_kept() tell the wall
## layer which chunks should have wall/door nodes. In the legacy single lot (2x2 chunks) everything is simply always visible.

const VIEW_MARGIN := 5.0            # tiles beyond the screen rectangle that still count as visible (tall things)
const KEEP_EXTRA := 26.0            # walls / trees stay built this much further out (hysteresis)
const BUILDS_PER_FRAME := 6
const MARK_Y := 0.004
const TREE_SPECIES := ["oak", "pine"]
const SNOW_FLOORS := ["grass", "lawn", "dirt", "stone", "concrete", "sand"]

var overlay_grass_mat: StandardMaterial3D
var overlay_snow_mat: StandardMaterial3D
var overlay_wet_mat: StandardMaterial3D        # darkens roads and pavements in rain (look-driven; hidden at alpha 0)
var tree_mats: Dictionary = {}          # "oak"/"pine"/"trunk" -> StandardMaterial3D (WeatherView tints the leaves by season)

var _chunks: Dictionary = {}            # Vector2i -> {root, floor, grass, snow, trees:Array}
var _chunk_dirty: Dictionary = {}       # Vector2i -> true (needs a (re)build when visible)
var _vis: Dictionary = {}               # chunks in the view rectangle (drawn)
var _keep: Dictionary = {}              # chunks that keep walls / trees alive
var _floor_mat: StandardMaterial3D
var _snow_on: bool = false
var _wet_on: bool = false
var _marks: Array = []                  # road centre lines [x0, y0, x1, y1] in tile units
var _tree_meshes: Dictionary = {}       # species -> ArrayMesh (leaves + trunk surfaces) or null
var _chunk_root: Node3D


func _init_chunk_materials() -> void:
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.vertex_color_use_as_albedo = true
	_floor_mat.roughness = 0.95
	overlay_grass_mat = _overlay(Color(1, 1, 1, 0))
	overlay_snow_mat = _overlay(Color(0.95, 0.97, 1.0, 0))
	overlay_wet_mat = _overlay(Color(0.05, 0.07, 0.1, 0))
	overlay_wet_mat.roughness = 0.2            # wet streets catch the lamps
	overlay_wet_mat.metallic_specular = 1.0
	tree_mats = {"oak": _tree_mat(Color(0.35, 0.62, 0.28)), "pine": _tree_mat(Color(0.18, 0.42, 0.26)), "trunk": _tree_mat(Color(0.38, 0.27, 0.18))}


func _overlay(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.albedo_color = c
	return m


func _tree_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


# ------------------------------------------------------------------ lifecycle

## World was reset / loaded: drop every chunk, remember the road markings, mark all chunks dirty (built lazily).
func _rebuild_chunks_all() -> void:
	if _floor_root == null:
		return
	if _floor_mat == null:
		_init_chunk_materials()
	for ch in _chunks.values():
		(ch["root"] as Node3D).queue_free()
	_chunks.clear()
	_chunk_dirty.clear()
	_vis.clear()
	_keep.clear()
	World.regions.mark_all_floors_dirty()
	_floors_dirty = true
	_marks.clear()
	for r in World.regions.regions.values():
		for l in (r.get("lines", []) as Array):
			_marks.append(l)
	if _ground_mi:
		_ground_mi.queue_free()
	_ground_mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(World.width * 3.0 + 100.0, World.height * 3.0 + 100.0)
	_ground_mi.mesh = pm
	_ground_mi.position = Vector3(World.width * 0.5, -0.03, World.height * 0.5)
	_ground_mi.material_override = _mat(Looks.grade("grass", Color(0.36, 0.5, 0.3)))
	_ground_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_root.add_child(_ground_mi)
	_pull_dirty_chunks()
	_update_chunks()


func _pull_dirty_chunks() -> void:
	_floors_dirty = false
	for c in World.regions.take_dirty_floor_chunks():
		_chunk_dirty[c] = true


## Per frame: pull dirty chunks, recompute which chunks are near the camera, hide the rest, build a few missing ones.
func _update_chunks(force: bool = false) -> void:
	if _floors_dirty:
		_pull_dirty_chunks()
	var vis := {}
	var keep := {}
	var cc := World.regions.chunk_count()
	var aspect := 1.78
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size.y > 0.0:
		aspect = vp.get_visible_rect().size.x / vp.get_visible_rect().size.y
	var fwd := -_cam_dir()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var hw := _zoom * aspect * 0.5
	var hd := _zoom * 0.5 / sin(PITCH)
	var r := 11.4 + VIEW_MARGIN
	for cy in cc.y:
		for cx in cc.x:
			var d := Vector3(cx * 16.0 + 8.0 - _target.x, 0, cy * 16.0 + 8.0 - _target.z)
			var sx := absf(d.dot(right))
			var sy := absf(d.dot(fwd))
			var c := Vector2i(cx, cy)
			if sx <= hw + r and sy <= hd + r:
				vis[c] = true
			if sx <= hw + r + KEEP_EXTRA and sy <= hd + r + KEEP_EXTRA:
				keep[c] = true
	if vis != _vis:
		for c in _chunks:
			(_chunks[c]["root"] as Node3D).visible = vis.has(c)
		_vis = vis
	_keep = keep
	var budget := 9999 if force else BUILDS_PER_FRAME
	for c in _vis:
		if budget <= 0:
			break
		if _chunk_dirty.has(c) or not _chunks.has(c):
			_build_chunk(c)
			_chunk_dirty.erase(c)
			budget -= 1


func _on_framed() -> void:
	if _floor_root != null:
		_update_chunks(true)


func chunk_is_active(c: Vector2i) -> bool:
	return _vis.has(c)


func chunk_is_kept(c: Vector2i) -> bool:
	return _keep.has(c)


## Weather: the snow overlay is only drawn while there is snow cover.
func set_overlay_snow_visible(on: bool) -> void:
	if on == _snow_on:
		return
	_snow_on = on
	for ch in _chunks.values():
		(ch["snow"] as MeshInstance3D).visible = on


## Weather + look: a dark film over roads and pavements while it rains (alpha 0 hides it; the reference look never shows it).
func set_wet_overlay(alpha: float, c: Color) -> void:
	overlay_wet_mat.albedo_color = Color(c.r, c.g, c.b, clampf(alpha, 0.0, 0.9))
	var on := alpha > 0.01
	if on == _wet_on:
		return
	_wet_on = on
	for ch in _chunks.values():
		(ch["wet"] as MeshInstance3D).visible = on


# ------------------------------------------------------------------ chunk mesh

func _build_chunk(c: Vector2i) -> void:
	var rc := World.regions.chunk_rect(c)
	if rc.size.x <= 0 or rc.size.y <= 0:
		return
	var ch: Dictionary = _chunks.get(c, {})
	if ch.is_empty():
		ch = _new_chunk(c)
		_chunks[c] = ch
	var fa := _MeshArrays.new()
	var ga := _MeshArrays.new()
	var sa := _MeshArrays.new()
	var wa := _MeshArrays.new()
	var floors := World.floors
	var w := World.width
	var holes: Dictionary = World.levels.ground_holes
	var big := World.regions.has_regions()
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			var ft: String = floors[y * w + x]
			if not holes.is_empty() and holes.has(t):
				continue                                     # an opening (stairs down to the basement): no floor here
			var col := _floor_color(ft, t)
			fa.quad(x, y, x + 1, y + 1, 0.0, col)
			if ft == "crosswalk":
				_crosswalk_bars(fa, x, y)
			if ft == "grass" or ft == "lawn":
				ga.quad(x, y, x + 1, y + 1, 0.006, Color.WHITE)
			if ft == "asphalt" or ft == "crosswalk" or ft == "sidewalk":
				wa.quad(x, y, x + 1, y + 1, 0.007, Color.WHITE)
			if ft in SNOW_FLOORS:
				sa.quad(x, y, x + 1, y + 1, 0.009, Color.WHITE)
	for m in _marks:
		_add_mark(fa, m, rc)
	(ch["floor"] as MeshInstance3D).mesh = fa.commit()
	(ch["grass"] as MeshInstance3D).mesh = ga.commit()
	(ch["snow"] as MeshInstance3D).mesh = sa.commit()
	(ch["snow"] as MeshInstance3D).visible = _snow_on
	(ch["wet"] as MeshInstance3D).mesh = wa.commit()
	(ch["wet"] as MeshInstance3D).visible = _wet_on
	_build_trees_for_chunk(ch, rc, big)
	(ch["root"] as Node3D).visible = _vis.has(c) or _vis.is_empty()


func _new_chunk(c: Vector2i) -> Dictionary:
	var root := Node3D.new()
	root.name = "chunk_%d_%d" % [c.x, c.y]
	_floor_root.add_child(root)
	var out := {"root": root, "trees": []}
	for k in ["floor", "grass", "snow", "wet"]:
		var mi := MeshInstance3D.new()
		mi.name = k
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _floor_mat if k == "floor" else (overlay_grass_mat if k == "grass" else (overlay_wet_mat if k == "wet" else overlay_snow_mat))
		root.add_child(mi)
		out[k] = mi
	return out


func _floor_color(ft: String, t: Vector2i) -> Color:
	var fd: Dictionary = World.FLOOR_DEFS.get(ft, {})
	var col := Looks.floor_color(ft, Color(str(fd.get("color", "#6aa84f"))), t)
	if fd.get("srgb", false):
		col = col.srgb_to_linear()        # vertex colours are read as linear: road / sidewalk / water keep their exact look
	elif col.v > 0.72:
		col.v = 0.72 + (col.v - 0.72) * 0.3    # pale floors blow out under the noon sun
	if (t.x + t.y) % 2 == 1 and ft != "asphalt" and ft != "crosswalk" and ft != "water":
		col = col.darkened(0.035)
	if not World.mess.is_empty():
		var m: float = World.mess.get(t, 0.0)
		if m > 0.0:
			col = col.lerp(Color(0.35, 0.28, 0.2), clampf(m / 10.0, 0.0, 0.6))
	return col


## Zebra bars: bars run along the road, spaced along the walking direction (towards a neighbouring sidewalk / crosswalk).
func _crosswalk_bars(fa, x: int, y: int) -> void:
	var white := Color(0.78, 0.78, 0.74)
	var walk_x := _is_walk(x - 1, y) or _is_walk(x + 1, y)
	if walk_x:
		fa.quad(x + 0.2, y + 0.08, x + 0.7, y + 0.92, MARK_Y, white)
	else:
		fa.quad(x + 0.08, y + 0.2, x + 0.92, y + 0.7, MARK_Y, white)


func _is_walk(x: int, y: int) -> bool:
	var f := World.get_floor(Vector2i(x, y))
	return f == "crosswalk" or f == "sidewalk"


## Double yellow centre line segment clipped to the chunk.
func _add_mark(fa, m: Array, rc: Rect2i) -> void:
	var x0 := float(m[0])
	var y0 := float(m[1])
	var x1 := float(m[2])
	var y1 := float(m[3])
	var yellow := Color(0.82, 0.68, 0.16)
	if is_equal_approx(x0, x1):
		if x0 < rc.position.x - 0.3 or x0 > rc.end.x + 0.3:
			return
		var a := clampf(maxf(y0, 0.0), rc.position.y, rc.end.y)
		var b := clampf(y1, rc.position.y, rc.end.y)
		if b > a:
			for off in [-0.13, 0.13]:
				fa.quad(x0 + off - 0.045, a, x0 + off + 0.045, b, MARK_Y, yellow)
	else:
		if y0 < rc.position.y - 0.3 or y0 > rc.end.y + 0.3:
			return
		var a2 := clampf(x0, rc.position.x, rc.end.x)
		var b2 := clampf(x1, rc.position.x, rc.end.x)
		if b2 > a2:
			for off in [-0.13, 0.13]:
				fa.quad(a2, y0 + off - 0.045, b2, y0 + off + 0.045, MARK_Y, yellow)


# ------------------------------------------------------------------ trees (MultiMesh per chunk)

## Deterministic 0..1 hash of a tile.
func _hash01(x: int, y: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ ((MapBuilder.tree_seed() + salt) * 83492791)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


func _build_trees_for_chunk(ch: Dictionary, rc: Rect2i, big: bool) -> void:
	for n in ch["trees"]:
		(n as Node).queue_free()
	ch["trees"] = []
	if not big:
		return
	var density := MapBuilder.tree_density()
	var by_species := {"oak": [], "pine": []}
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			if _hash01(x, y, 1) >= density:
				continue
			if World.get_floor(Vector2i(x, y)) != "grass" or World.regions.kind_at(Vector2i(x, y)) != "park":
				continue
			if _near_pavement(x, y):
				continue
			var species: String = "pine" if _hash01(x, y, 2) < 0.35 else "oak"
			var s := 0.85 + _hash01(x, y, 3) * 0.7
			var basis := Basis(Vector3.UP, _hash01(x, y, 4) * TAU).scaled(Vector3(s, s, s))
			(by_species[species] as Array).append(Transform3D(basis, Vector3(x + 0.2 + _hash01(x, y, 5) * 0.6, 0.0, y + 0.2 + _hash01(x, y, 6) * 0.6)))
	for sp in TREE_SPECIES:
		var list: Array = by_species[sp]
		var mesh := _tree_mesh(sp)
		if list.is_empty() or mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "trees_" + sp
		mmi.multimesh = mm
		(ch["root"] as Node3D).add_child(mmi)
		(ch["trees"] as Array).append(mmi)


## No trees on the pavement edge (4-neighbours) or within 2 tiles of the pond.
func _near_pavement(x: int, y: int) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var f := World.get_floor(Vector2i(x + dx, y + dy))
			if f == "water" or f == "sand":
				return true
			if absi(dx) + absi(dy) <= 1 and (f == "sidewalk" or f == "asphalt" or f == "crosswalk" or f == "lawn"):
				return true
	return false


## Two-surface tree mesh (leaves + trunk) from the outdoor kit, cached; null when the model is missing.
func _tree_mesh(species: String) -> ArrayMesh:
	if _tree_meshes.has(species):
		return _tree_meshes[species]
	var am: ArrayMesh = null
	var ps := _load_model("res://assets/models/outdoor/tree_%s_s.glb" % species)
	if ps != null:
		var inst := ps.instantiate()
		var leaves := inst.find_child("leaves", true, false) as MeshInstance3D
		var trunk := inst.find_child("trunk", true, false) as MeshInstance3D
		if leaves != null and trunk != null:
			am = ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.mesh.surface_get_arrays(0))
			am.surface_set_material(0, tree_mats[species])
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk.mesh.surface_get_arrays(0))
			am.surface_set_material(1, tree_mats["trunk"])
		inst.free()
	_tree_meshes[species] = am
	return am


## WeatherView: seasonal leaf colours for the scattered trees.
func set_tree_colors(leaf: Color, pine: Color) -> void:
	if tree_mats.is_empty():
		return
	(tree_mats["oak"] as StandardMaterial3D).albedo_color = leaf
	(tree_mats["pine"] as StandardMaterial3D).albedo_color = pine


# ------------------------------------------------------------------ flat quad batches

class _MeshArrays:
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func quad(x0: float, z0: float, x1: float, z1: float, y: float, c: Color) -> void:
		var i := pos.size()
		pos.append(Vector3(x0, y, z0))
		pos.append(Vector3(x1, y, z0))
		pos.append(Vector3(x1, y, z1))
		pos.append(Vector3(x0, y, z1))
		col.append(c)
		col.append(c)
		col.append(c)
		col.append(c)
		idx.append(i)
		idx.append(i + 1)
		idx.append(i + 2)
		idx.append(i)
		idx.append(i + 2)
		idx.append(i + 3)

	func commit() -> ArrayMesh:
		if pos.is_empty():
			return null
		var normals := PackedVector3Array()
		normals.resize(pos.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am