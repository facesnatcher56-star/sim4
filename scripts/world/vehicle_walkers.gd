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


## The same adult model and rig as FolkView, a stable look from the seed (never primitives). A missing model is an error, not a drawn stand-in.
func _body(seed: int) -> Node3D:
	var n := Node3D.new()
	var path: String = FolkView.variant_path("adult")
	var ps = load(path) if path != "" else null
	if not (ps is PackedScene):
		push_error("VehicleWalkers: no folk model to draw a walker with (%s)" % path)
		return n
	var rig: Node = (ps as PackedScene).instantiate()
	n.add_child(rig)
	var g := RandomNumberGenerator.new()
	g.seed = absi(seed) * 2654435761 + 17
	var ap: Dictionary = Genetics.random_appearance(g)
	var shirt_d := Color.from_hsv(float(absi(seed) % 360) / 360.0, 0.55, 0.85)
	FolkRigStyle.apply(rig, ap, "adult", shirt_d)
	var anim: AnimationPlayer = _find_anim(rig)
	if anim != null:
		FolkView.prepare_player(anim)
		var clip: String = str(FolkView.anim_map().get("walk_clip", "Walk"))
		if anim.has_animation(clip):
			anim.play(clip)
	return n


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


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
			var nd := w["node"] as Node3D
			nd.position = Vector3((w["pos"] as Vector2).x, 0.0, (w["pos"] as Vector2).y)
			if pos.distance_to(to) > 0.01:
				nd.rotation.y = atan2(-(to.x - pos.x), -(to.y - pos.y))
		if arrived:
			if w["node"] != null and is_instance_valid(w["node"]):
				(w["node"] as Node).queue_free()
			if (w["on_done"] as Callable).is_valid():
				(w["on_done"] as Callable).call()
		else:
			keep.append(w)
	list = keep
