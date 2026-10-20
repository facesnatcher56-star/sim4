class_name VehicleWalkers
extends RefCounted
## Little walking figures of the vehicle layer (task 37, display only): the driver who gets out of a car that has parked and walks away up the path to the lot, and the
## person who walks down to a parked car before it leaves. Why: a car must not appear or vanish on its own; a parked car has somebody who came in it and goes with it.
## A figure is plain data {pos, to, speed, on_done}: it walks in a straight line to `to` and then is finished (it goes indoors, or gets in and `on_done` starts the car).
## They are not folk (no needs, no sim state); a headless layer keeps the data and draws nothing.
##   walkers.add(from, to, color_seed, on_done: Callable)      walkers.tick(dt)      walkers.count()      walkers.clear()

const SPEED := 1.5

var view: VehicleView
var list: Array = []
var _root: Node3D = null
var _mats: Dictionary = {}


func _init(v: VehicleView) -> void:
	view = v


func count() -> int:
	return list.size()


func clear() -> void:
	for w in list:
		if w.get("node") != null and is_instance_valid(w["node"]):
			(w["node"] as Node).queue_free()
	list.clear()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null


func add(from: Vector2, to: Vector2, color_seed: int, on_done: Callable = Callable()) -> void:
	list.append({"pos": from, "to": to, "seed": color_seed, "on_done": on_done, "node": null})


func _body(seed: int) -> Node3D:
	var col := Color.from_hsv(float(absi(seed) % 360) / 360.0, 0.45, 0.8)
	var n := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 1.1
	body.mesh = cap
	body.position.y = 0.65
	body.material_override = m
	n.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.14
	sph.height = 0.28
	head.mesh = sph
	head.position.y = 1.32
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.86, 0.7, 0.58)
	head.material_override = hm
	n.add_child(head)
	return n


func tick(dt: float) -> void:
	var keep: Array = []
	for w in list:
		var pos: Vector2 = w["pos"]
		var to: Vector2 = w["to"]
		var step: float = SPEED * dt
		var arrived: bool = pos.distance_to(to) <= step
		w["pos"] = to if arrived else pos + (to - pos).normalized() * step
		if view.draw:
			if w["node"] == null:
				if _root == null or not is_instance_valid(_root):
					_root = Node3D.new()
					_root.name = "Walkers"
					view.add_child(_root)
				w["node"] = _body(int(w["seed"]))
				_root.add_child(w["node"])
			(w["node"] as Node3D).position = Vector3((w["pos"] as Vector2).x, 0.0, (w["pos"] as Vector2).y)
		if arrived:
			if w["node"] != null and is_instance_valid(w["node"]):
				(w["node"] as Node).queue_free()
			if (w["on_done"] as Callable).is_valid():
				(w["on_done"] as Callable).call()
		else:
			keep.append(w)
	list = keep
