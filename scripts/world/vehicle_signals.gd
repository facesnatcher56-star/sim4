class_name VehicleSignals
extends RefCounted
## Street furniture of the vehicle layer: the traffic light heads at the junctions near a focus (they show what VehicleSim.signal_state decides: green, red, or a blinking
## amber when the zone has no power) and the bus shelters at the marked stops of the routes. Display only.

var view: VehicleView
var _heads: Dictionary = {}          # "i,j" -> [{mesh, axis}]
var _shelters: Dictionary = {}       # lot id -> Node3D
var _root: Node3D = null
var _mats: Dictionary = {}


func _init(v: VehicleView) -> void:
	view = v


func clear() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_heads.clear()
	_shelters.clear()


func _ensure_root() -> void:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "Street"
		view.add_child(_root)
		_heads.clear()
		_shelters.clear()


func _mat(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = {"green": Color(0.25, 0.95, 0.35), "red": Color(1.0, 0.18, 0.12), "amber": Color(1.0, 0.7, 0.1), "pole": Color(0.25, 0.27, 0.3)}[kind]
		_mats[kind] = m
	return _mats[kind]


func sync() -> void:
	_ensure_root()
	for id in VehicleRoads.junction_ids():
		var key := "%d,%d" % [id.x, id.y]
		var c: Vector2 = VehicleRoads.junction_center(id.x, id.y)
		var near: bool = view.in_range(c)
		if near and not _heads.has(key):
			_build_junction(key, c)
		elif not near and _heads.has(key) and view.beyond_drop(c):
			for h in _heads[key]:
				(h["node"] as Node).queue_free()
			_heads.erase(key)
	_sync_shelters()


func _build_junction(key: String, c: Vector2) -> void:
	var list: Array = []
	for corner in [[1, 1, 1], [-1, -1, 1], [1, -1, 0], [-1, 1, 0]]:
		var n := Node3D.new()
		n.position = Vector3(c.x + float(corner[0]) * 2.7, 0.0, c.y + float(corner[1]) * 2.7)
		var pole := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, 2.4, 0.12)
		pole.mesh = pm
		pole.position.y = 1.2
		pole.material_override = _mat("pole")
		n.add_child(pole)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.34, 0.34, 0.34)
		head.mesh = hm
		head.position.y = 2.5
		head.material_override = _mat("red")
		n.add_child(head)
		_root.add_child(n)
		list.append({"node": n, "head": head, "axis": int(corner[2])})
	_heads[key] = list


func update() -> void:
	for key in _heads:
		var p: PackedStringArray = (key as String).split(",")
		var i: int = int(p[0])
		var j: int = int(p[1])
		for h in _heads[key]:
			var st: String = view.sim.signal_state(i, j, int(h["axis"]))
			var kind: String = "red"
			if st == "green":
				kind = "green"
			elif st == "dark":
				kind = "amber" if fposmod(view.sim.vt, 1.0) < 0.5 else "pole"
			(h["head"] as MeshInstance3D).material_override = _mat(kind)


func _sync_shelters() -> void:
	var stop_lots: Dictionary = {}
	for r in TransportBus.routes():
		for l in r["stops"]:
			stop_lots[str(l)] = true
	var model: PackedScene = load("res://assets/models/outdoor/bus_stop.glb") if ResourceLoader.exists("res://assets/models/outdoor/bus_stop.glb") else null
	for lot_id in stop_lots:
		var f: Dictionary = VehicleRoads.frontage(str(lot_id))
		if f.is_empty():
			continue
		var pos := Vector2(float(f["gate"]) + float((view.cfg.get("bus_stop", {}) as Dictionary).get("x_from_gate", 6.0)), float(f["hy"]) - 1.3)
		var near: bool = view.in_range(pos)
		if near and not _shelters.has(lot_id) and model != null:
			var n: Node3D = model.instantiate()
			n.position = Vector3(pos.x, 0.0, pos.y)
			n.rotation.y = PI
			_root.add_child(n)
			_shelters[lot_id] = n
		elif not near and _shelters.has(lot_id) and view.beyond_drop(pos):
			(_shelters[lot_id] as Node).queue_free()
			_shelters.erase(lot_id)
