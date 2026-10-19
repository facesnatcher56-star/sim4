extends RefCounted
## Item 4 of 12c: a building shell that covers the folk the camera follows (or the spot it looks at) fades and comes back; shells that cover nothing stay solid.
## View only: nothing here touches the sim.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	var W = root.get_node_or_null("World")
	if W == null or not ResourceLoader.exists("res://scenes/world/lot_view.tscn"):
		return ["World / lot_view missing"]
	var lv: Node3D = (load("res://scenes/world/lot_view.tscn") as PackedScene).instantiate()
	root.add_child(lv)
	MapBuilder.build(W)
	lv.frame_home()
	lv._apply_camera()
	lv._cam.force_update_transform()
	var back: Vector3 = lv._cam.global_transform.basis.z
	var box := AABB(Vector3(50, 0, 50), Vector3(10, 11, 8))
	_check(LotView.ray_hits_box(Vector3(55, 0.5, 54), back, box), "a point inside the box is covered")
	_check(LotView.ray_hits_box(Vector3(55, 0.5, 54) - back * 20.0, back, box), "a point behind the box (away from the camera) is covered")
	_check(not LotView.ray_hits_box(Vector3(55, 0.5, 54) + back * 40.0, back, box), "a point between the box and the camera is not covered")
	_check(not LotView.ray_hits_box(Vector3(20, 0.5, 20), back, box), "a point far to the side is not covered")
	# two stub shells: one over the camera focus (from the camera's side), one far away
	var mi_a := MeshInstance3D.new()
	var mi_b := MeshInstance3D.new()
	lv.add_child(mi_a)
	lv.add_child(mi_b)
	var focus := Vector3(55, 0, 54)
	lv._target = focus
	lv._shells["a"] = {"root": mi_a, "rect": Rect2i(50, 50, 10, 8), "open": false, "lot": "a", "home": false, "aabb": box, "meshes": [mi_a], "fade": 0.0}
	lv._shells["b"] = {"root": mi_b, "rect": Rect2i(10, 10, 10, 8), "open": false, "lot": "b", "home": false, "aabb": AABB(Vector3(10, 0, 10), Vector3(10, 11, 8)), "meshes": [mi_b], "fade": 0.0}
	for i in 30:
		lv._update_shell_fade(0.1)
	_check(mi_a.transparency > 0.5, "the shell that covers the followed spot fades (%.2f)" % mi_a.transparency)
	_check(mi_b.transparency == 0.0, "a shell that covers nothing stays solid")
	lv._target = Vector3(30, 0, 30)
	for i in 30:
		lv._update_shell_fade(0.1)
	_check(mi_a.transparency == 0.0, "and it comes back when the camera moves on (%.2f)" % mi_a.transparency)
	# an open shell is not drawn at all: no fade work
	lv._target = focus
	lv._shells["a"]["open"] = true
	lv._update_shell_fade(0.1)
	_check(mi_a.transparency == 0.0, "an open shell is left alone")
	root.remove_child(lv)
	lv.free()
	W.reset()
	return fails
