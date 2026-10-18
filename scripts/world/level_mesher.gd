class_name LevelMesher
extends RefCounted
## Meshes for ONE upper / lower level of a building: floor slab, walls (merged, vertex colours), glass, roof. One call per level
## builds a handful of arrays, so a 15-storey tower is a few draw calls, not hundreds of nodes. Display only.
## y = LPos.elev(level) is the floor SURFACE; the slab hangs 0.2 below it.

const WALL_H := 2.6
const WALL_T := 0.16
const CUT_H := 0.42                      # wall height of the cut-away / "walls down" mode
const WALL_COL := Color(0.9, 0.87, 0.8)
const DOOR_COL := Color(0.62, 0.45, 0.28)


class Acc:
	extends RefCounted
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		var n := (b - a).cross(d - a).normalized()
		for v in [a, b, c, a, c, d]:
			verts.append(v)
			norms.append(n)
			cols.append(col)

	## Axis-aligned box from min corner and size (all six faces).
	func box(p: Vector3, s: Vector3, col: Color) -> void:
		var x0 := p.x
		var y0 := p.y
		var z0 := p.z
		var x1 := p.x + s.x
		var y1 := p.y + s.y
		var z1 := p.z + s.z
		quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), col)          # top
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), col.darkened(0.25))   # bottom
		quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0), col.darkened(0.08))   # north
		quad(Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y0, z1), col.darkened(0.08))   # south
		quad(Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0), col.darkened(0.14))   # west
		quad(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), col.darkened(0.14))   # east

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return mesh


static func material(glass: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glass:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
	return m


static func floor_color(world: WorldGrid, type: String, t: Vector2i) -> Color:
	var fd: Dictionary = world.FLOOR_DEFS.get(type, {})
	var col := Color(str(fd.get("color", "#b8864e")))
	if col.v > 0.72:
		col.v = 0.72 + (col.v - 0.72) * 0.3
	if (t.x + t.y) % 2 == 1:
		col = col.darkened(0.035)
	return col


## Floor slab of a level: top face per tile (not over stairwell openings), underside, and a skirt where the slab ends.
static func floors(world: WorldGrid, level: int) -> ArrayMesh:
	var lay: LevelLayer = world.levels.layer(level, false)
	var a := Acc.new()
	if lay == null:
		return a.commit()
	var y := LPos.elev(level)
	var th := LPos.SLAB
	for t in lay.floors:
		if lay.holes.has(t):
			continue
		var col := floor_color(world, str(lay.floors[t]), t)
		var x0 := float(t.x)
		var z0 := float(t.y)
		a.quad(Vector3(x0, y, z0), Vector3(x0, y, z0 + 1), Vector3(x0 + 1, y, z0 + 1), Vector3(x0 + 1, y, z0), col)
		a.quad(Vector3(x0, y - th, z0), Vector3(x0 + 1, y - th, z0), Vector3(x0 + 1, y - th, z0 + 1), Vector3(x0, y - th, z0 + 1), Color(0.55, 0.53, 0.5))
		var edge := Color(0.62, 0.6, 0.57)
		if not lay.floors.has(Vector2i(t.x, t.y - 1)):
			a.quad(Vector3(x0, y - th, z0), Vector3(x0, y, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y - th, z0), edge)
		if not lay.floors.has(Vector2i(t.x, t.y + 1)):
			a.quad(Vector3(x0 + 1, y - th, z0 + 1), Vector3(x0 + 1, y, z0 + 1), Vector3(x0, y, z0 + 1), Vector3(x0, y - th, z0 + 1), edge)
		if not lay.floors.has(Vector2i(t.x - 1, t.y)):
			a.quad(Vector3(x0, y - th, z0 + 1), Vector3(x0, y, z0 + 1), Vector3(x0, y, z0), Vector3(x0, y - th, z0), edge)
		if not lay.floors.has(Vector2i(t.x + 1, t.y)):
			a.quad(Vector3(x0 + 1, y - th, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y, z0 + 1), Vector3(x0 + 1, y - th, z0 + 1), edge)
	return a.commit()


## Walls of a level. `low(e)` -> true when that edge is drawn cut down (near the camera). Returns [solid mesh, glass mesh].
static func walls(world: WorldGrid, level: int, low: Callable) -> Array:
	var lay: LevelLayer = world.levels.layer(level, false)
	var solid := Acc.new()
	var glass := Acc.new()
	if lay == null:
		return [solid.commit(), glass.commit()]
	var y := LPos.elev(level)
	for e in lay.walls:
		var kind: String = lay.walls[e]
		var horizontal: bool = e.z == 0
		var cut: bool = kind != "fence" and low.is_valid() and bool(low.call(e))
		var h := CUT_H if cut else WALL_H
		if kind == "fence":
			h = 0.9
		var cx: float = e.x + 0.5 if horizontal else float(e.x)
		var cz: float = float(e.y) if horizontal else e.y + 0.5
		var sx: float = 1.0 + WALL_T if horizontal else WALL_T
		var sz: float = WALL_T if horizontal else 1.0 + WALL_T
		var col := WALL_COL if kind != "fence" else Color(0.55, 0.38, 0.22)
		match kind:
			"window":
				solid.box(Vector3(cx - sx * 0.5, y, cz - sz * 0.5), Vector3(sx, minf(0.9, h), sz), col)
				if not cut:
					solid.box(Vector3(cx - sx * 0.5, y + 1.9, cz - sz * 0.5), Vector3(sx, WALL_H - 1.9, sz), col)
					var gs := Vector3(sx - 0.02 if horizontal else 0.03, 1.0, 0.03 if horizontal else sz - 0.02)
					glass.box(Vector3(cx - gs.x * 0.5, y + 0.9, cz - gs.z * 0.5), gs, Color(0.6, 0.8, 0.95, 0.45))
			"door":
				if not cut:
					solid.box(Vector3(cx - sx * 0.5, y + 2.0, cz - sz * 0.5), Vector3(sx, WALL_H - 2.0, sz), col)
				var pw := 0.08
				var pxs := Vector3(pw if horizontal else sx, 2.0 if not cut else CUT_H, sz if horizontal else pw)
				if horizontal:
					solid.box(Vector3(cx - 0.46 - pw * 0.5, y, cz - sz * 0.5), pxs, DOOR_COL)
					solid.box(Vector3(cx + 0.46 - pw * 0.5, y, cz - sz * 0.5), pxs, DOOR_COL)
				else:
					solid.box(Vector3(cx - sx * 0.5, y, cz - 0.46 - pw * 0.5), pxs, DOOR_COL)
					solid.box(Vector3(cx - sx * 0.5, y, cz + 0.46 - pw * 0.5), pxs, DOOR_COL)
			_:
				solid.box(Vector3(cx - sx * 0.5, y, cz - sz * 0.5), Vector3(sx, h, sz), col)
	return [solid.commit(), glass.commit()]


## Roof over the top floor: flat slab, gable (ridge along x) or hip (pyramid per tile row bounding box).
static func roof(world: WorldGrid, bid: int, style: String) -> ArrayMesh:
	var a := Acc.new()
	var b: Dictionary = world.levels.building(bid)
	if b.is_empty() or style == "none":
		return a.commit()
	var top: int = int(b["max"])
	var lay: LevelLayer = world.levels.layer(top, false) if top != 0 else null
	var tiles: Array = []
	if lay != null:
		tiles = lay.floors.keys()
	else:
		for y in range((b["rect"] as Rect2i).position.y, (b["rect"] as Rect2i).end.y):
			for x in range((b["rect"] as Rect2i).position.x, (b["rect"] as Rect2i).end.x):
				if not world.rooms.is_outdoor(Vector2i(x, y), 0):
					tiles.append(Vector2i(x, y))
	if tiles.is_empty():
		return a.commit()
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for t in tiles:
		lo = lo.min(Vector2(t))
		hi = hi.max(Vector2(t) + Vector2.ONE)
	var y0 := LPos.elev(top) + WALL_H + 0.02
	var col := Color(0.55, 0.28, 0.22)
	var ov := 0.25
	var x0 := lo.x - ov
	var x1 := hi.x + ov
	var z0 := lo.y - ov
	var z1 := hi.y + ov
	match style:
		"gable":
			var ridge := y0 + (z1 - z0) * 0.28
			var zm := (z0 + z1) * 0.5
			a.quad(Vector3(x0, y0, z0), Vector3(x0, ridge, zm), Vector3(x1, ridge, zm), Vector3(x1, y0, z0), col)
			a.quad(Vector3(x1, y0, z1), Vector3(x1, ridge, zm), Vector3(x0, ridge, zm), Vector3(x0, y0, z1), col.darkened(0.12))
			var gcol := Color(0.85, 0.82, 0.76)
			for xx in [x0 + ov, x1 - ov]:
				a.quad(Vector3(xx, y0, z0 + ov), Vector3(xx, y0, z1 - ov), Vector3(xx, ridge - 0.02, zm), Vector3(xx, y0, z0 + ov), gcol)
		"hip":
			var peak := y0 + minf(x1 - x0, z1 - z0) * 0.3
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			var pk := Vector3(cx, peak, cz)
			a.quad(Vector3(x0, y0, z0), pk, pk, Vector3(x1, y0, z0), col)
			a.quad(Vector3(x1, y0, z1), pk, pk, Vector3(x0, y0, z1), col.darkened(0.12))
			a.quad(Vector3(x0, y0, z1), pk, pk, Vector3(x0, y0, z0), col.darkened(0.06))
			a.quad(Vector3(x1, y0, z0), pk, pk, Vector3(x1, y0, z1), col.darkened(0.06))
		_:
			a.box(Vector3(x0, y0, z0), Vector3(x1 - x0, 0.25, z1 - z0), Color(0.45, 0.45, 0.48))
	return a.commit()
