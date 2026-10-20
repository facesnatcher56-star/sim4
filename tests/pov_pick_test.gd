extends RefCounted
## Task 32 item 1: the mouse picks what is in the room, not the windows and lights above it. Headless: a furnished classic home, the
## default home view, LotView.pick over a screen grid and at the on-screen centre of beds, sofas, desks and fridges.

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
	W.reset(32, 24)
	if not LotLoader.apply(LotLoader.CLASSIC, W):
		return ["classic home does not place"]
	var lv: Node3D = (load("res://scenes/world/lot_view.tscn") as PackedScene).instantiate()
	var sv := SubViewport.new()          # the headless window is 64x64: give the view a real screen
	sv.size = Vector2i(1280, 720)
	root.add_child(sv)
	sv.add_child(lv)
	lv.frame_home()
	lv._apply_camera()
	lv._cam.force_update_transform()
	var vp := Vector2(sv.size)
	# 1. live-mode grid sweep: windows, doors and ceiling lights are never what the mouse lands on
	var total := 0
	var bad := 0
	var names: Dictionary = {}
	for y in range(40, int(vp.y) - 40, 12):
		for x in range(40, int(vp.x) - 40, 12):
			var p: Dictionary = lv.pick(Vector2(x, y))
			if p["kind"] != "object":
				continue
			total += 1
			var o = W.get_object(int(p["id"]))
			var d := str(o.def_id)
			names[d] = int(names.get(d, 0)) + 1
			if o.is_wall_mounted() or o.has_tag("ceiling"):
				bad += 1
	_check(total > 20, "the sweep lands on objects (%d)" % total)
	_check(float(bad) <= 0.05 * float(total), "windows / doors / ceiling lights are under 5%% of object hovers: %d of %d" % [bad, total])
	# 2. building tools see wall-hung things again, with the CURRENT wall height
	lv.build_mode = true
	var win = null
	for o in W.all_objects():
		if o.is_wall_mounted() and str(o.def_id) == "window":
			win = o
			break
	if win != null:
		var low: AABB = lv._object_aabb(win)
		lv.set_wall_mode(LotView.WallMode.UP)
		lv._wall_by_edge.clear()
		var high: AABB = lv._object_aabb(win)
		_check(high.size.y > low.size.y, "a cut-down wall shortens its window's pick box (%.2f vs %.2f)" % [low.size.y, high.size.y])
		lv.set_wall_mode(LotView.WallMode.CUTAWAY)
	lv.build_mode = false
	# 3. clicking furniture at its on-screen centre picks it
	var want := ["desk", "bed", "sofa", "fridge", "stove", "toilet", "dining_chair", "bookcase_tall", "tv", "computer"]
	var tried := 0
	var hit_ok := 0
	var seen: Dictionary = {}
	for o in W.all_objects():
		var d := str(o.def_id)
		if not want.has(d) or seen.has(d) or o.is_wall_mounted():
			continue
		seen[d] = true
		var bb: AABB = lv._object_aabb(o)
		var c := bb.get_center()
		c.y = bb.position.y + minf(bb.size.y * 0.5, 0.6)
		var sp: Vector2 = lv._cam.unproject_position(c)
		var p: Dictionary = lv.pick(sp)
		tried += 1
		var got = W.get_object(int(p["id"])) if p["kind"] == "object" else null
		if got != null and (got.id == o.id or str(got.def_id) == d):
			hit_ok += 1
		elif d in ["desk", "bed", "sofa", "fridge"]:
			fails.append("clicking the %s picks %s" % [d, str(got.def_id) if got != null else str(p["kind"])])
	_check(tried >= 4, "enough furniture to click (%d)" % tried)
	print("pov_pick: %d object hovers, %d scenery, clicks %d/%d, hovered: %s" % [total, bad, hit_ok, tried, str(names)])
	sv.remove_child(lv)
	lv.free()
	root.remove_child(sv)
	sv.free()
	W.reset()
	return fails
