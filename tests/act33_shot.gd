extends SceneTree
## Not a unit test: windowed close-ups of 12 everyday actions with their clip, hand props and particles (task 33), family seed 101 home. Objects that
## the home lacks (garden plot, fishing spot, weights) are walked to anywhere on the map. The progress ring (task 33.4) is not drawn here.
## godot --path . --resolution 1280x720 --script res://tests/act33_shot.gd -- docs/act33/shot [name+name+...]
var _prefix := "user://a33"
var _main: Node = null
var _home := Vector2i.ZERO
var _side := false                       # third argument "front": photograph from the front; the default is the side (an object in front of the folk would hide the pose)


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


## The object of that kind within 12 tiles of the home; places one in the yard when the home has none.
func _near_obj(def_id: String) -> int:
	var id := _obj(def_id)
	if id >= 0:
		var o = root.get_node("World").get_object(id)
		if absi(o.tile.x - _home.x) + absi(o.tile.y - _home.y) <= 12:
			return id
	var W = root.get_node("World")
	for rad in range(2, 14):
		for dx in range(-rad, rad + 1):
			for dy in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var t := _home + Vector2i(dx, dy)
				var nid: int = W.place_object(def_id, t, 0)
				if nid >= 0:
					return nid
	return -1


## The object of that kind nearest to the home.
func _obj(def_id: String) -> int:
	var best := -1
	var best_d := 1 << 30
	for o in root.get_node("World").objects_of_def(def_id):
		var d: int = absi(o.tile.x - _home.x) + absi(o.tile.y - _home.y)
		if d < best_d:
			best_d = d
			best = o.id
	return best


func _cmd(fid: int, iid: String, target: int) -> bool:
	var f = root.get_node("World").get_folk(fid)
	for n in ["energy", "hygiene", "bladder", "social", "hunger", "fun"]:
		if f.needs.has(n):
			f.needs[n].set_value(10.0)
	var ir := Interaction.create(iid, f, target, true)
	if ir == null:
		return false
	print("cmd ", iid, " target ", target, " ok")
	f.idle_until_min = 0
	f.enqueue(ir)
	root.get_node("SimDirector")._fill(f)
	return true


## Objects standing between the folk and a camera looking from `cam` (they would hide the pose behind an x-ray silhouette).
func _blockers(fv, cam: Vector3) -> int:
	var W = root.get_node("World")
	var t: Vector2i = W.pos_to_tile(fv.position)
	var sx := 0 if absf(cam.x) < 0.3 else (1 if cam.x > 0 else -1)
	var sz := 0 if absf(cam.z) < 0.3 else (1 if cam.z > 0 else -1)
	var n := 0
	for step in [1, 2]:
		for dd in [Vector2i(sx * step, 0), Vector2i(0, sz * step), Vector2i(sx * step, sz * step)]:
			if dd == Vector2i.ZERO:
				continue
			if step == 1 and (dd.x == 0 or dd.y == 0) and not W.edge_open(t, t + dd, 0):
				n += 2                         # a wall right there
			var o = W.object_at(t + dd)
			if o != null and not o.def_id.begins_with("floor"):
				n += 1
	return n


## Turns the camera in 90 degree steps until the folk looks toward it (the face, the hands and what they hold are what the shot is about).
func _face_camera(fv) -> void:
	if fv == null:
		return
	var lv = _main.lot_view
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, fv.facing_yaw)
	var best := 0
	var best_dot := -2.0
	for k in 4:
		var cam := Vector3(0, 0, 1).rotated(Vector3.UP, lv._yaw_target + k * PI * 0.5)
		var d := fwd.dot(cam)
		if _side:
			d = -absf(d) + 0.01 * d             # from the side: the pose in profile
		d -= 3.0 * _blockers(fv, cam)
		if d > best_dot:
			best_dot = d
			best = k
	if best > 0:
		lv.rotate_camera(best)


## Everybody else stands still (nobody dances with, or chats up, the folk being photographed).
func _park_others(fid: int) -> void:
	for o in root.get_node("World").all_folk():
		if o.id == fid:
			continue
		o.queue.clear()
		if o.current != null and str(o.current.state) != "finished":
			o.current.finish(false)
		o.current = null
		o.idle_until_min = 1 << 30


func _until_running(fid: int) -> bool:
	var f = root.get_node("World").get_folk(fid)
	for i in 240:
		if f.current != null and str(f.current.state) == "running":
			return true
		_park_others(fid)
		root.get_node("Clock").advance_minutes(1)
	return false


func _shot(name: String, fid: int, zoom: float) -> void:
	var lv = _main.lot_view
	lv.set_zoom(zoom)
	var fv = lv.get_folk_view(fid)
	if fv != null:
		lv.focus_tile(root.get_node("World").pos_to_tile(fv.position))
	await _secs(1.5)
	if fv != null:
		lv.focus_tile(root.get_node("World").pos_to_tile(fv.position))
	await _secs(0.8)
	Input.warp_mouse(Vector2(2, 2))
	await _secs(0.3)
	var p := "%s_%s.png" % [_prefix, name]
	var img: Image = root.get_texture().get_image()
	img.resize(1280, int(1280.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(p)
	root.get_node("Clock").speed = 0
	var f = root.get_node("World").get_folk(fid)
	print("saved %s: %s %s pose %s clip %s props %s fx %s" % [p, f.name, str(f.current.def_id) if f.current != null else "-", str(fv.pose), str(fv.clip), str(fv._props.keys()), str(fv._fx.keys())])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_side = not (args.size() > 2 and args[2] == "front")
	var only: Array = (args[1] as String).split("+") if args.size() > 1 else []
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var r := RandomNumberGenerator.new()
	r.seed = 101
	_main.start_new_game(HouseholdSetup.make_household("family", r), str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	await _frames(20)
	var W = root.get_node("World")
	_main.hud.visible = false
	var hh: Array = []
	var baby := -1
	var adult := -1
	for f in W.all_folk():
		if int(f.household_id) == 1:
			hh.append(f.id)
			if str(f.age_stage) in ["baby", "toddler"] and baby < 0:
				baby = f.id
			if str(f.age_stage) == "adult" and adult < 0:
				adult = f.id
	_home = W.get_folk(adult).tile
	root.get_node("Clock").speed = 0           # the clock only moves when this script advances it: the action keeps running while the camera waits
	if baby < 0:
		var bf := Folk.create("Bibi", [])
		bf.age_stage = "baby"
		bf.household_id = 1
		W.add_folk(bf, _home + Vector2i(1, 1))
		baby = bf.id
		hh.append(baby)
	for fid in hh:
		W.get_folk(fid).idle_until_min = 1 << 30
	print("household %s baby %d adult %d" % [str(hh), baby, adult])
	# name, interaction, target object def (or "baby"), zoom
	var scenes := [
		["watering", "water_plant", "plant", 1.9],
		["cooking", "cook_meal", "stove", 1.9],
		["cleaning", "clean_object", "stove", 1.9, "dirty"],
		["repairing", "repair_object", "fridge", 1.9, "broken"],
		["phone", "check_phone", "", 1.9],
		["phone_call", "call_friend", "", 1.9],
		["eating", "eat_meal", "table", 1.9, "meal"],
		["gardening", "plant_seeds", "garden_plot", 1.9],
		["fishing", "fish_pond", "fishing_spot", 2.8],
		["painting", "paint_canvas", "easel", 1.9],
		["workout", "lift_weights", "dumbbell_rack", 1.9],
		["homework", "do_homework", "desk", 1.9],
		["feeding_baby", "feed_baby", "baby", 1.9],
		["showering", "take_shower", "shower", 1.9],
		["brushing_teeth", "brush_teeth", "sink", 1.9],
		["karaoke", "karaoke", "stereo", 1.9],
		["washing_up", "wash_dishes", "sink", 1.9, "dirty"],
	]
	for sc in scenes:
		if not only.is_empty() and not (sc[0] in only):
			continue
		for fid in hh:
			var ff = W.get_folk(fid)
			ff.queue.clear()
			if ff.current != null:
				ff.current.finish(false)
			ff.current = null
			ff.idle_until_min = 1 << 30
		for o in W.all_folk():
			var ov0 = _main.lot_view.get_folk_view(o.id)
			if ov0 != null:
				ov0.visible = true
		await _secs(0.4)
		var tgt := -1
		if sc[2] == "baby":
			tgt = baby
		elif sc[2] == "":
			tgt = -1
		else:
			tgt = _near_obj(sc[2])
		var prep: String = sc[4] if sc.size() > 4 else ""
		if tgt >= 0 and prep == "dirty":
			W.set_object_state(tgt, "dirtiness", 9.0)
		elif tgt >= 0 and prep == "broken":
			W.set_object_state(tgt, "broken", true)
		elif prep == "meal":
			W.get_folk(adult).add_buff("meal_ready")
		if (sc[2] != "" and tgt < 0) or not _cmd(adult, sc[1], tgt):
			print("could not start ", sc[0], " target ", sc[2])
			continue
		_park_others(adult)
		if not _until_running(adult):
			print("never ran ", sc[0])
			continue
		var f0 = W.get_folk(adult)
		f0.current.def["duration_min"] = 900.0       # the action keeps going while the camera looks at it (this script runs in its own process)
		_main.lot_view.set_zoom(sc[3])
		_main.lot_view.focus_tile(f0.tile)
		await _secs(1.5)
		var fv0 = _main.lot_view.get_folk_view(adult)
		if fv0 != null:                    # the clock is stopped: skip the view's walk to the object
			fv0._waypoints.clear()
			fv0._moving = false
			fv0.position = fv0._wp(f0.tile, f0.level)
			fv0._ybase = fv0.position.y
		root.get_node("Clock").speed = 1            # the clips play at game speed
		await _secs(1.0)
		for o in W.all_folk():                         # nobody else in the picture
			var ov = _main.lot_view.get_folk_view(o.id)
			if ov != null and o.id != adult:
				ov.visible = false
		_face_camera(fv0)
		await _secs(3.2)
		await _shot(sc[0], adult, sc[3])
	quit(0)
