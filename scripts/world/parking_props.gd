class_name ParkingProps
extends Node3D
## The carports of the driveways (task 42, display only): a house with a garage room has an open carport (four posts, a beam frame and a see-through roof panel so the car under it still
## shows) at the head of its driveway. Built once per map (VehicleView.reset marks it dirty). Cause: a house that has a garage keeps its car under cover.
##   props.dirty = true      props.sync()      props.count()

var dirty: bool = true
var _n: int = 0


func count() -> int:
	return _n


func sync() -> void:
	if not dirty or not Workplace.map_ready():
		return
	dirty = false
	for c in get_children():
		c.queue_free()
	_n = 0
	for lot_id in Neighborhood.lot_ids():
		for pl in VehicleBays.of(str(lot_id)):
			if bool(pl.get("carport", false)):
				add_child(_carport(pl))
				_n += 1


func _mat(c: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = m
	parent.add_child(mi)


func _carport(pl: Dictionary) -> Node3D:
	var root := Node3D.new()
	var p: Vector2 = pl["pos"]
	root.name = "Carport"
	root.position = Vector3(p.x, 0.0, p.y)
	var post: Material = _mat(Color(0.36, 0.30, 0.25))
	var roof: Material = _mat(Color(0.30, 0.33, 0.36), 0.55)
	var w: float = 3.0
	var l: float = 5.0
	var h: float = 2.4
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(root, Vector3(0.14, h, 0.14), Vector3(sx * w * 0.5, h * 0.5, sz * l * 0.5), post)
	for sx2 in [-1.0, 1.0]:
		_box(root, Vector3(0.12, 0.16, l + 0.1), Vector3(sx2 * w * 0.5, h, 0.0), post)
	for sz2 in [-1.0, 1.0]:
		_box(root, Vector3(w + 0.1, 0.16, 0.12), Vector3(0.0, h, sz2 * l * 0.5), post)
	_box(root, Vector3(w + 0.3, 0.05, l + 0.3), Vector3(0.0, h + 0.1, 0.0), roof)
	return root
