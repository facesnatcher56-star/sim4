class_name LevelProps
extends RefCounted
## Procedural visuals for the structural objects: stairs (steps), stairs down (a railed opening), ladders, lifts, pillars.
## Everything is built from boxes so no model file is needed. Local frame of every node: origin = floor surface of the object's level,
## in world x / z (the node is positioned at the object's footprint centre by the caller via `centre`).

const H := LPos.H


static func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


## Node for object `o` (a WorldObject whose def has a portal block, or tag support). Null for anything else.
static func make(o) -> Node3D:
	var pd: Dictionary = o.def.get("portal", {})
	var root := Node3D.new()
	var kind := str(pd.get("kind", ""))
	var col := Color(str(o.def.get("color", "#a98b64")))
	match kind:
		"stairs":
			_stairs(root, o, int(pd.get("dz", 1)), col, bool(pd.get("exterior", false)))
		"ladder":
			_ladder(root, int(pd.get("dz", 1)), col)
		"elevator":
			_lift(root)
			var fd: Vector2 = o.front_dir()
			root.rotation.y = atan2(fd.x, fd.y)
		_:
			if o.has_tag("support"):
				_box(root, Vector3(0.34, 2.6, 0.34), Vector3(0, 1.3, 0), Color(0.72, 0.72, 0.74))
			else:
				return null
	return root


## Position (x, z) of the node: centre of the footprint.
static func centre(o) -> Vector2:
	return o.center2d()


## Yaw so the node's local +X points along the stair direction.
static func stair_yaw(o) -> float:
	var d := WorldObject.rotate_vec(Vector2(1, 0), o.rot)
	return atan2(-d.y, d.x)


static func _stairs(root: Node3D, o, dz: int, col: Color, exterior: bool) -> void:
	var n := 8
	var rise := H / float(n)
	root.rotation.y = stair_yaw(o)
	if dz > 0:
		for i in n:
			var h := rise * float(i + 1)
			var x := -1.0 + (float(i) + 0.5) * (2.0 / float(n))
			_box(root, Vector3(2.0 / float(n), h, 0.9), Vector3(x, h * 0.5, 0), col.lightened(0.05 * float(i % 2)))
		for sgn in [-1.0, 1.0]:
			_box(root, Vector3(2.0, 0.05, 0.05), Vector3(0, H * 0.5 + 0.7, 0.47 * sgn), Color(0.35, 0.3, 0.25))
	else:
		_box(root, Vector3(2.0, 0.04, 0.9), Vector3(0, 0.02, 0), Color(0.16, 0.14, 0.13))
		for i in 5:
			_box(root, Vector3(0.05, 0.06, 0.86), Vector3(-0.8 + 0.4 * float(i), 0.06, 0), col)
		for sgn in [-1.0, 1.0]:
			_box(root, Vector3(2.0, 0.9, 0.04), Vector3(0, 0.45, 0.47 * sgn), Color(0.45, 0.38, 0.3, 1.0))
	if exterior:
		_box(root, Vector3(2.05, 0.05, 1.0), Vector3(0, 0.02, 0), Color(0.3, 0.33, 0.37))


static func _ladder(root: Node3D, dz: int, col: Color) -> void:
	var h := H if dz > 0 else 0.4
	for sgn in [-1.0, 1.0]:
		_box(root, Vector3(0.05, h, 0.05), Vector3(0.18 * sgn, h * 0.5, 0), col)
	var steps := int(h / 0.3)
	for i in steps:
		_box(root, Vector3(0.36, 0.04, 0.04), Vector3(0, 0.2 + 0.3 * float(i), 0), col.darkened(0.15))


static func _lift(root: Node3D) -> void:
	var metal := Color(0.74, 0.78, 0.82)
	_box(root, Vector3(0.96, 2.6, 0.96), Vector3(0, 1.3, 0), metal)
	_box(root, Vector3(0.6, 2.1, 0.04), Vector3(0, 1.05, 0.49), Color(0.3, 0.34, 0.4))      # doors on the front (+z of the local frame)
	_box(root, Vector3(0.12, 0.12, 0.04), Vector3(0.45, 1.3, 0.5), Color(0.9, 0.8, 0.2))
