extends RefCounted
## Task 32 item 2 (logic): the player always sees into their own home. Cutaway cuts every camera-facing wall of an open building (the
## walls between rooms too) and keeps only the far outer walls as a backdrop; the home shell is always open, a neighbour's shell opens only
## with a folk inside; Walls Up never survives a floor change / frame_home; upper floors cut the same way.

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
	# the far-wall rule on its own: camera at +x +z, a building at (10, 10, 8, 6)
	var rc := Rect2i(10, 10, 8, 6)
	var d := Vector3(0.7, 0, 0.7)
	_check(LotView.is_far_wall(Vector3i(12, 10, 0), rc, d), "far outer wall along x stays up")
	_check(not LotView.is_far_wall(Vector3i(12, 16, 0), rc, d), "near outer wall along x is cut")
	_check(not LotView.is_far_wall(Vector3i(12, 13, 0), rc, d), "an interior wall along x is cut")
	_check(LotView.is_far_wall(Vector3i(10, 12, 1), rc, d), "far outer wall along z stays up")
	_check(not LotView.is_far_wall(Vector3i(18, 12, 1), rc, d), "near outer wall along z is cut")
	_check(LotView.is_far_wall(Vector3i(18, 12, 1), rc, Vector3(-0.7, 0, 0.7)), "turned round, the other side is the far wall")
	# the real map with the home
	MapLots.build(W, LotLoader.CLASSIC)
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	root.add_child(sv)
	var lv: Node3D = (load("res://scenes/world/lot_view.tscn") as PackedScene).instantiate()
	sv.add_child(lv)
	lv.frame_home()
	lv._apply_camera()
	var home: Dictionary = W.regions.home()
	var homelot := str(home["lot"])
	_check(lv._shells.has(homelot), "the home has a shell")
	lv.tool = "select"
	for i in 3:
		lv._update_shells(0.3)
	_check(bool(lv._shells[homelot]["open"]), "the home shell is open with nobody standing near it")
	var other_open := 0
	for sh in lv._shells.values():
		if not bool(sh["home"]) and bool(sh["open"]):
			other_open += 1
	_check(other_open == 0, "other buildings stay closed shells with nobody inside (%d open)" % other_open)
	# walls of the home settle: far outer walls up, the rest cut
	lv._sync_wall_chunks(true)
	for i in 30:
		lv._update_walls(0.1)
	var rect: Rect2i = lv._shells[homelot]["rect"]
	var d2: Vector3 = lv._cam_dir()
	var up := 0
	var cut := 0
	var wrong := 0
	for w in lv._walls:
		if not lv._in_open_building(w) or w["kind"] == "fence" or w["free"]:
			continue
		var far: bool = LotView.is_far_wall(w["e"], rect, d2)
		if far and absf(float(w["scale"]) - 1.0) < 0.01:
			up += 1
		elif not far and absf(float(w["scale"]) - LotView.CUT_RATIO) < 0.01:
			cut += 1
		else:
			wrong += 1
	_check(up > 4 and cut > 4 and wrong == 0, "home walls: %d far up, %d cut, %d wrong" % [up, cut, wrong])
	# Walls Up is never where the game leaves you
	lv.set_wall_mode(LotView.WallMode.UP)
	lv.frame_home()
	_check(lv.wall_mode == LotView.WallMode.CUTAWAY, "frame_home (load / travel home) returns to Cutaway")
	lv.set_wall_mode(LotView.WallMode.UP)
	lv.level_view.view_changed.emit()
	_check(lv.wall_mode == LotView.WallMode.CUTAWAY, "a floor change returns to Cutaway")
	lv.set_wall_mode(LotView.WallMode.DOWN)
	lv.return_to_cutaway()
	_check(lv.wall_mode == LotView.WallMode.CUTAWAY, "Walls Down returns to Cutaway too")
	sv.remove_child(lv)
	lv.free()
	root.remove_child(sv)
	sv.free()
	W.reset()
	return fails
