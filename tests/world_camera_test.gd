extends RefCounted
## LotView camera + chunk streaming on the 160x120 map (headless, no frames: the per-frame helpers are called by hand).
## Convention: run() -> Array of failure strings.

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	W = root.get_node_or_null("World")
	if W == null or not ResourceLoader.exists("res://scenes/world/lot_view.tscn"):
		return ["World / lot_view missing"]
	var lv: Node3D = (load("res://scenes/world/lot_view.tscn") as PackedScene).instantiate()
	root.add_child(lv)
	_test_legacy(lv)
	MapBuilder.build(W)
	_test_framing(lv)
	_test_pan_zoom(lv)
	_test_follow(lv)
	_test_chunks(lv)
	root.remove_child(lv)
	lv.free()
	W.reset()
	return fails


func _test_legacy(lv: Node3D) -> void:
	W.reset()
	lv.set_zoom(500.0)
	_check(lv._zoom_target <= 34.0 + 0.001, "single lot keeps the 34 zoom cap (%f)" % lv._zoom_target)
	_check(lv._follow_id == -1, "no follow in the single lot")


func _test_framing(lv: Node3D) -> void:
	lv.frame_home()
	var hrc: Rect2i = W.regions.home()["rect"]
	var t: Vector3 = lv._target
	_check(Rect2(hrc).has_point(Vector2(t.x, t.z)), "frame_home should centre on the home lot, got %s vs %s" % [str(t), str(hrc)])
	_check(lv._zoom_target >= 4.0 and lv._zoom_target <= LotView.ZOOM_MAX_BIG, "framing zoom %f" % lv._zoom_target)
	# the whole home rect must be on screen
	var cam: Camera3D = lv._cam
	var half_h: float = lv._zoom * 0.5
	for c in [hrc.position, hrc.end, Vector2i(hrc.position.x, hrc.end.y), Vector2i(hrc.end.x, hrc.position.y)]:
		var p := cam.unproject_position(Vector3(c.x, 0, c.y))
		_check(p.x > -50 and p.y > -50, "home corner %s off screen at %s" % [str(c), str(p)])
	_check(half_h > 0.0, "zoom")


func _test_pan_zoom(lv: Node3D) -> void:
	lv.set_zoom(500.0)
	_check(is_equal_approx(lv._zoom_target, LotView.ZOOM_MAX_BIG), "big map zoom cap should be LotView.ZOOM_MAX_BIG (whole map), got %f" % lv._zoom_target)
	lv.set_zoom(0.1)
	_check(is_equal_approx(lv._zoom_target, 4.0), "zoom floor")
	lv._pan(5000.0, 5000.0)
	_check(lv._target.x <= W.width and lv._target.z <= W.height and lv._target.x >= 0.0 and lv._target.z >= 0.0, "pan must stay inside the map: %s" % str(lv._target))
	lv._pan(-9000.0, -9000.0)
	_check(lv._target.x >= 0.0 and lv._target.z >= 0.0, "pan clamp at the origin: %s" % str(lv._target))
	var before: Vector3 = lv._target
	lv.rotate_camera(1)
	_check(lv._target == before, "rotating must keep the camera target")


func _test_follow(lv: Node3D) -> void:
	lv.frame_home()
	var stub := Node3D.new()
	stub.position = Vector3(100.5, 0, 60.5)
	lv.add_child(stub)
	lv._folk_views[777] = stub
	lv._on_selection_changed("folk", 777)
	_check(lv._follow_id == 777, "selecting a folk starts the follow")
	for i in 60:
		lv._update_follow(0.1)
	_check(lv._target.distance_to(Vector3(100.5, 0, 60.5)) < 0.5, "camera should have glided onto the folk, at %s" % str(lv._target))
	lv._pan(1.0, 0.0)
	_check(lv._follow_id == -1, "manual pan lets go of the folk")
	lv._on_selection_changed("object", 5)
	_check(lv._follow_id == -1, "only folk are followed")
	lv._folk_views.erase(777)
	stub.free()


func _test_chunks(lv: Node3D) -> void:
	lv.frame_home()
	lv._update_chunks(true)
	var hrc: Rect2i = W.regions.home()["rect"]
	_check(lv.chunk_is_active(W.chunk_of(hrc.get_center())), "home chunk must be active")
	_check(not lv.chunk_is_active(Vector2i(0, 0)) or lv._zoom > 30.0, "far corner chunk should not be drawn at the home view")
	_check(lv._chunks.has(W.chunk_of(hrc.get_center())), "home chunk mesh not built")
	var built: int = lv._chunks.size()
	_check(built < 80, "chunks are built lazily, got %d of 80" % built)
	_check(lv._vis.size() < 60, "only chunks near the view are drawn, got %d of 80" % lv._vis.size())
	# a floor edit rebuilds exactly that chunk
	var t := hrc.position + Vector2i(5, 5)
	var c: Vector2i = W.chunk_of(t)
	var m0: Mesh = (lv._chunks[c]["floor"] as MeshInstance3D).mesh
	_check(W.paint_floor(t, "wood", 0), "paint")
	lv._floors_dirty = true
	lv._update_chunks()
	_check((lv._chunks[c]["floor"] as MeshInstance3D).mesh != m0, "edited chunk floor mesh was not rebuilt")
	# walls only exist for near chunks
	W.set_wall_line(t, t + Vector2i(4, 0), "wall", 0)
	lv._build_walls()
	_check(lv._walls.size() == 4, "4 wall nodes near the camera, got %d" % lv._walls.size())
	W.regions.enforce = false
	var far: Vector2i = W.regions.by_lot("school")["rect"].position + Vector2i(4, 4)
	W.set_wall_line(far, far + Vector2i(4, 0), "wall", 0)
	W.regions.enforce = true
	lv._build_walls()
	_check(lv._walls.size() == 4, "far walls must not be instanced (%d nodes)" % lv._walls.size())
	lv._target = Vector3(far.x, 0, far.y)
	lv._update_chunks(true)
	lv._sync_wall_chunks(true)
	_check(lv._walls.size() == 4 and lv._wall_nodes.has(W.chunk_of(far)), "walls follow the camera (%d nodes)" % lv._walls.size())
	_check(not lv._wall_nodes.has(W.chunk_of(t)) or lv.chunk_is_kept(W.chunk_of(t)), "far chunk walls are freed")
