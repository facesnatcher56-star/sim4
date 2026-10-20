extends SceneTree
## POV audit for task 32 (windowed tool, not part of the fast tier). args: <mode> <out_dir>
##   hover : seed-101 family home, mouse over a desk, bed, sofa and fridge at the default view (shots + what the hover picked)
##   audit : a three-storey home (large_f01), every camera rotation x 3 zoom levels, the household placed on each floor in turn;
##           for every room with a folk in it, camera ray tests (folk and floor unoccluded by any wall / roof / shell mesh); 12 shots.
var _main: Node = null
var _f := 0
var _mode := ""
var _out := ""
var _jobs: Array = []        # audit steps: Callables run one per settle period
var _wait := 0
var _fails := 0
var _checks := 0
var _rooms_seen := 0
var _offscreen := 0
var _lines: Array = []


func _process(_d: float) -> bool:
	if _main == null:
		var a := OS.get_cmdline_user_args()
		_mode = a[0]
		_out = a[1]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_f += 1
	if _f == 5:
		var r := RandomNumberGenerator.new()
		r.seed = 101
		var h := HouseholdSetup.make_household("family", r)
		var opts := {"scenario": "family", "difficulty": "normal", "world_seed": 101}
		if _mode == "audit":
			opts["home_template"] = "large_f01"
		_main.start_new_game(h, str(Scenario.def("family").get("start_id", "classic")), opts)
	if _f == 60:
		root.get_node("Clock").set_speed(0)
		var lv = _main.lot_view
		lv.frame_home()
		lv._snap_camera()
		print("WALLMODE ", lv.wall_mode, " zoom ", lv._zoom)
		if _mode == "hover":
			_plan_hover()
		else:
			_plan_audit()
	if _f > 60:
		if _wait > 0:
			_wait -= 1
		elif not _jobs.is_empty():
			var j: Callable = _jobs.pop_front()
			_wait = int(j.call())
		else:
			for l in _lines:
				print(l)
			print("AUDIT_DONE checks=%d fails=%d rooms=%d offscreen=%d" % [_checks, _fails, _rooms_seen, _offscreen])
			quit(0)
	return false


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])


# ------------------------------------------------------------------ hover

func _plan_hover() -> void:
	var lv = _main.lot_view
	var W = root.get_node("World")
	for want in ["desk", "bed", "sofa", "fridge"]:
		_jobs.append(func():
			for o in W.all_objects():
				if str(o.def_id) == want and (W.regions.home()["rect"] as Rect2i).has_point(o.tile):
					var bb: AABB = lv._object_aabb(o)
					var c := bb.get_center()
					c.y = bb.position.y + minf(bb.size.y * 0.5, 0.6)
					lv._target = Vector3(c.x, 0, c.z)          # close enough to see the outline
					lv._zoom_target = 9.0
					lv._snap_camera()
					lv._cam.force_update_transform()
					var p: Dictionary = lv.pick(lv._cam.unproject_position(c))
					lv.set_process(false)             # the real mouse is elsewhere: freeze the view's own hover update and set the hover by hand
					lv._set_hover(p["kind"], p["id"], p["tile"])
					lv._update_highlights()
					var o2 = W.get_object(lv.hover_id) if lv.hover_kind == "object" else null
					print("HOVERED want=%s got=%s" % [want, str(o2.def_id) if o2 != null else lv.hover_kind])
					break
			return 4)
		_jobs.append(func():
			_shot("after_hover_" + want)
			lv.set_process(true)
			return 3)


# ------------------------------------------------------------------ audit

func _household() -> Array:
	var out: Array = []
	for f in root.get_node("World").all_folk():
		if int(f.household_id) > 0 and not f.has_meta("visitor") and not f.has_meta("away"):
			out.append(f)
	return out


## Rooms of one floor of the building: arrays of tiles, split by every wall edge (doors included).
func _rooms(bid: int, level: int) -> Array:
	var W = root.get_node("World")
	var rc: Rect2i = (W.levels.building(bid)["rect"] as Rect2i).grow(-1)      # the building rect holds a one-tile margin outside the walls
	var seen: Dictionary = {}
	var rooms: Array = []
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			if seen.has(t) or not W.levels.is_walkable(t, level):
				continue
			var room: Array = []
			var stack: Array = [t]
			seen[t] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				room.append(c)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if seen.has(n) or not rc.has_point(n) or not W.levels.is_walkable(n, level):
						continue
					var e: Vector3i = _edge(c, n)
					if W.levels.wall_at(e, level) != "":
						continue
					seen[n] = true
					stack.append(n)
			rooms.append(room)
	return rooms


func _edge(a: Vector2i, b: Vector2i) -> Vector3i:
	if a.x != b.x:
		return Vector3i(maxi(a.x, b.x), a.y, 1)
	return Vector3i(a.x, maxi(a.y, b.y), 0)


## The tile of a room farthest from its walls (most room around it), for a folk to stand on.
func _spot(room: Array, level: int) -> Vector2i:
	var W = root.get_node("World")
	var best: Vector2i = room[0]
	var best_s := -1
	for t in room:
		var s := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if W.levels.wall_at(_edge(t, t + d), level) == "" and W.levels.is_walkable(t + d, level):
				s += 1
		if s > best_s:
			best_s = s
			best = t
	return best


func _plan_audit() -> void:
	var W = root.get_node("World")
	var lv = _main.lot_view
	var home: Dictionary = W.regions.home()
	var bid: int = W.levels.building_at((home["rect"] as Rect2i).position + Vector2i(6, 6))
	if bid < 0:
		var rc0: Rect2i = home["rect"]
		for y in range(rc0.position.y, rc0.end.y, 2):
			for x in range(rc0.position.x, rc0.end.x, 2):
				if bid < 0:
					bid = W.levels.building_at(Vector2i(x, y))
	print("AUDIT building %d range %s" % [bid, str(W.levels.range_at(W.levels.building(bid)["rect"].position + Vector2i(2, 2)))])
	var b: Dictionary = W.levels.building(bid)
	var base_zoom: float = lv._zoom
	var zooms := [base_zoom, base_zoom * 0.72, base_zoom * 0.5]
	var idx := 0
	for rot in 4:
		for zi in 3:
			var floor_shot: int = idx % (int(b["max"]) - int(b["min"]) + 1) + int(b["min"])
			idx += 1
			for level in range(int(b["min"]), int(b["max"]) + 1):
				var rooms := _rooms(bid, level)
				rooms.sort_custom(func(x, y): return x.size() > y.size())
				var folk := _household()
				var group := 0
				while group * folk.size() < rooms.size():
					var g := group
					group += 1
					var last_group: bool = group * folk.size() >= rooms.size()
					_jobs.append(func():
						return _setup(rot, zooms[zi], level, rooms, g, bid))
					_jobs.append(func():
						var shot: bool = level == floor_shot and last_group
						_check_all(bid, level, "r%d z%d floor %d group %d" % [rot, zi, level, g])
						if shot:
							_shot("home_audit_rot%d_zoom%d_floor%d" % [rot, zi, level])
						return 1)


func _setup(rot: int, zoom: float, level: int, rooms: Array, g: int, bid: int) -> int:
	var W = root.get_node("World")
	var lv = _main.lot_view
	var folk := _household()
	while lv._yaw_step != rot:
		lv.rotate_camera(1)
	lv._yaw = lv._yaw_target
	lv._zoom_target = zoom
	lv._zoom = zoom
	lv.wall_mode = lv.WallMode.CUTAWAY
	var first_pos := Vector3.ZERO
	for i in folk.size():
		var f = folk[i]
		var ri: int = g * folk.size() + i
		var t := Vector2i(2, 2)
		var lvl := level
		if ri < rooms.size():
			t = _spot(rooms[ri], level)
		else:
			t = _spot(rooms[ri % rooms.size()], level)
		f.tile = t
		f.level = lvl
		var fv = lv._folk_views[f.id]
		fv._last_tile = Vector2i(-999, -999)
		fv._waypoints.clear()
		fv.position = Vector3(t.x + 0.5, LPos.elev(lvl), t.y + 0.5)
		fv._ybase = LPos.elev(lvl)
		fv.remove_meta("level_hidden") if fv.has_meta("level_hidden") else null
		if i == 0:
			first_pos = fv.position
	lv.select("folk", folk[0].id)
	lv._target = Vector3(first_pos.x, LPos.elev(level), first_pos.z)
	return 45


func _meshes_under(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree() and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes_under(c, out)


## True when a ray from `p` toward the camera meets a wall / roof / floor-slab / standing-shell mesh.
func _blocked(p: Vector3, back: Vector3, blockers: Array) -> String:
	for bl in blockers:
		var mi: MeshInstance3D = bl["mi"]
		if bl["faces"] == null:
			var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
			if bb.intersects_ray(p, back) != null:
				return str(bl["what"])
		else:
			var xf: Transform3D = mi.global_transform
			var fc: PackedVector3Array = bl["faces"]
			var i := 0
			while i + 2 < fc.size():
				if Geometry3D.ray_intersects_triangle(p, back, xf * fc[i], xf * fc[i + 1], xf * fc[i + 2]) != null:
					return str(bl["what"])
				i += 3
	return ""


var _probe := Vector3.ZERO


func _blockers(level: int) -> Array:
	var lv = _main.lot_view
	var back: Vector3 = lv._cam.global_transform.basis.z
	var out: Array = []
	var meshes: Array = []
	for wn in lv._walls:
		var node: Node3D = wn["node"]
		if is_instance_valid(node) and node.is_visible_in_tree() and float(wn["scale"]) > 0.3:
			var mine: Array = []
			_meshes_under(node, mine)
			for mi in mine:
				out.append({"mi": mi, "faces": null, "what": "ground wall %s %s scale %.2f" % [str(wn["e"]), str(wn["kind"]), float(wn["scale"])]})
	var lvv = lv.level_view
	for l in lvv.level_nodes:
		for k in ["walls", "floor"]:
			var mi2: MeshInstance3D = lvv.level_nodes[l][k]
			if mi2.mesh != null and l >= level:       # the floor slab of the level you stand on is what you stand on: not a blocker
				if k == "floor" and l == level:
					continue
				out.append({"mi": mi2, "faces": mi2.mesh.get_faces(), "what": "level %d %s" % [l, k]})
	if lvv._roof != null:
		out.append({"mi": lvv._roof, "faces": lvv._roof.mesh.get_faces(), "what": "roof"})
	for sh in lv._shells.values():
		var root3: Node3D = sh["root"]
		if root3.visible:
			for mi3 in sh["meshes"]:
				if is_instance_valid(mi3) and (mi3 as GeometryInstance3D).transparency < 0.5:
					out.append({"mi": mi3, "faces": null, "what": "shell %s fade=%.2f coarse_box_hit=%s" % [str(sh["lot"]), float(sh["fade"]), str(lv.ray_hits_box(_probe, back, sh["aabb"]))]})
	return out


func _check_all(bid: int, level: int, label: String) -> void:
	var lv = _main.lot_view
	lv._cam.force_update_transform()
	var back: Vector3 = lv._cam.global_transform.basis.z
	var blockers := _blockers(level)
	var vp := root.get_visible_rect().size
	var any_fail := false
	for f in _household():
		var fv = lv._folk_views[f.id]
		var rc: Rect2i = (root.get_node("World").levels.building(bid)["rect"] as Rect2i).grow(-1)
		if f.level != level or not rc.has_point(f.tile):
			continue
		var head: Vector3 = fv.position + Vector3(0, 1.45, 0)
		var body: Vector3 = fv.position + Vector3(0, 0.8, 0)
		var floor_p: Vector3 = fv.position + Vector3(0, 0.05, 0)
		var sp: Vector2 = lv._cam.unproject_position(body)
		if lv._cam.is_position_behind(body) or sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y:
			_offscreen += 1
			continue
		_checks += 1
		_rooms_seen += 1
		_probe = body
		blockers = _blockers(level)
		var bh := _blocked(head, back, blockers)
		var bb2 := _blocked(body, back, blockers)
		var bf := _blocked(floor_p, back, blockers)
		var vis_ok: bool = fv.visible and (bh == "" or bb2 == "") and bf == ""
		if not vis_ok:
			any_fail = true
			_fails += 1
			_lines.append("FAIL %s folk %s tile %s visible=%s head=[%s] body=[%s] floor=[%s]" % [label, f.name, str(f.tile), str(fv.visible), bh, bb2, bf])
	if not any_fail:
		_lines.append("ok   %s" % label)
