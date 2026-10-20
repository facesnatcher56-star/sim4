extends RefCounted
## Task 33c (view only): a folk you follow, or a housemate at work, is never a flat silhouette behind a wall. Cutaway drops the wall that stands
## between the camera and the selected folk (planting seeds behind the back wall is visible); a folk nobody follows keeps the silhouette.
## Ray test like pov_home_audit: after the walls settle no standing wall mesh box meets the ray from the selected folk toward the camera.

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
	MapLots.build(W, LotLoader.CLASSIC)
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	root.add_child(sv)
	var lv: Node3D = (load("res://scenes/world/lot_view.tscn") as PackedScene).instantiate()
	sv.add_child(lv)
	lv.frame_home()
	lv._apply_camera()
	lv._cam.force_update_transform()
	lv.tool = "select"
	for i in 3:
		lv._update_shells(0.3)
	lv._sync_wall_chunks(true)
	var homelot := str(W.regions.home()["lot"])
	var rect: Rect2i = lv._shells[homelot]["rect"]
	var d: Vector3 = lv._cam_dir()
	# two far outer walls of the home (one per folk), a spot just behind each, away from the camera
	var spots: Array = []
	for w in lv._walls:
		if w["kind"] != "wall" or w["free"] or not LotView.is_far_wall(w["e"], rect, d) or not lv._in_open_building(w):
			continue
		var p: Vector3 = w["pos"]
		if absf(d.z) > 0.25 and w["axis"] == 0:
			spots.append({"e": w["e"], "p": p - Vector3(0, 0, signf(d.z) * 0.9)})
		elif absf(d.x) > 0.25 and w["axis"] == 1:
			spots.append({"e": w["e"], "p": p - Vector3(signf(d.x) * 0.9, 0, 0)})
		if spots.size() >= 9:
			break
	_check(spots.size() >= 6, "found %d far walls to stand behind" % spots.size())
	if spots.size() < 6:
		return _done(W, sv, lv)
	var a = _folk(W, "Rosa", 1)
	var b = _folk(W, "Fenn", 1)
	var c = _folk(W, "Odd", 2)
	lv._sync_folk()
	var sa: Dictionary = spots[0]
	var sb: Dictionary = spots[3]
	var sc: Dictionary = spots[spots.size() - 1]
	_put(lv, a, sa["p"])
	_put(lv, b, sb["p"])
	_put(lv, c, sc["p"])
	_settle(lv)
	for f in [a, b, c]:
		_check(_hidden_by_wall(lv, f), "setup: %s starts hidden behind a wall" % str(f.name))
	_settle(lv)
	_check(_hidden_by_wall(lv, a) and _hidden_by_wall(lv, b) and _hidden_by_wall(lv, c), "nobody selected: every wall stays up (silhouette)")
	lv.select("folk", a.id)
	_settle(lv)
	_check(not _hidden_by_wall(lv, a), "ray test: nothing hides the selected folk from the camera")
	_check(_hidden_by_wall(lv, b), "a housemate who is only standing there keeps the silhouette")
	_check(_hidden_by_wall(lv, c), "another household's folk keeps the silhouette")
	# a housemate at work: cut too
	b.current = Interaction.create("go_here", b, -1, true)
	_settle(lv)
	_check(not _hidden_by_wall(lv, b), "a housemate doing something is no longer hidden")
	_check(_hidden_by_wall(lv, c), "the stranger is still behind the wall")
	b.current = null
	# deselect: the walls come back
	lv.select("none", -1)
	_settle(lv)
	_check(_hidden_by_wall(lv, a), "with nobody followed the wall stands again")
	# Walls Up is the player's choice: never overridden
	lv.select("folk", a.id)
	lv.set_wall_mode(LotView.WallMode.UP)
	lv._xray_t = 0.0
	lv._update_xray(1.0)
	_check(lv._see_walls.is_empty(), "Walls Up keeps every wall (no automatic cut)")
	return _done(W, sv, lv)


func _settle(lv) -> void:
	lv._xray_t = 0.0
	lv._update_xray(1.0)
	for i in 30:
		lv._update_walls(0.1)


func _folk(W, nm: String, hid: int):
	var f := Folk.create(nm)
	f.age_stage = "adult"
	f.household_id = hid
	W.add_folk(f, Vector2i(2, 2))
	return f


func _put(lv, f, p: Vector3) -> void:
	var fv = lv._folk_views[f.id]
	fv._last_tile = Vector2i(-999, -999)
	fv._waypoints.clear()
	fv.position = Vector3(p.x, 0.0, p.z)
	fv._ybase = 0.0
	fv.visible = true


func _hidden_by_wall(lv, f) -> bool:
	var fv = lv._folk_views[f.id]
	var toward: Vector3 = lv._cam.global_transform.basis.z
	var hp: Vector3 = fv.global_position + Vector3(0, 0.6, 0)
	for w in lv._walls:
		if float(w["scale"]) <= 0.5 or w["kind"] == "fence":
			continue
		var p: Vector3 = w["pos"]
		var half := Vector3(0.58, LotView.WALL_H * 0.5, LotView.WALL_T) if w["axis"] == 0 else Vector3(LotView.WALL_T, LotView.WALL_H * 0.5, 0.58)
		var bb := AABB(p + Vector3(0, LotView.WALL_H * 0.5 * float(w["scale"]), 0) - half * Vector3(1, float(w["scale"]), 1), half * Vector3(2, 2.0 * float(w["scale"]), 2))
		var h = bb.intersects_ray(hp, toward)
		if h != null and (h - hp).dot(toward) > 0.05:
			return true
	return false


func _done(W, sv, lv) -> Array:
	var root: Window = Engine.get_main_loop().root
	sv.remove_child(lv)
	lv.free()
	root.remove_child(sv)
	sv.free()
	W.reset()
	return fails
