extends SceneTree
## Not a unit test: the task 41 look-test scene, windowed (Forward+, decals need it). One street scene on the real map: the home lot is the run-down house
## (furnished, then made poor), a tidy neighbour house east of it, the south street with lamps, cars, cracks and a pothole.
## godot --path . --rendering-method forward_plus --script res://tests/art41a_shot.gd -- <out dir> <WxH> <look> <case>[+<case>...]
## cases: day dusk night rain close (close = night close-up on the yard). out file: art41_<case>_<W>x<H>[_<look>].png
## Uses Looks.set_look(look) ("grounded" or "reference"); the dressing comes from data/district_dressing.json.
var _main: Node = null
var _out := "user://"
var _look := "grounded"


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var res := args[1].split("x")
	_look = args[2]
	var cases := args[3].split("+")
	var size := Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W = root.get_node("World")
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7, "home_state": "furnished"})
	await _frames(30)
	Looks.set_look(_look)          # after the startup settings apply (they would reset it)
	await _frames(10)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	var lv = _main.lot_view
	_main.hud.visible = true
	_main.hud.tips.visible = false
	var dress := load("res://scripts/world/district_dressing.gd") as GDScript
	dress.apply(lv, "home", ["tidy_house"])
	_place_folk(W, lv)
	for lot in ["police", "courthouse", "market"]:        # tall shells south of the street would hide it: keep them low for this scene
		if lv._shells.has(lot):
			(lv._shells[lot]["root"] as Node3D).scale.y = 0.4
	if "interior_before" in cases:
		await _case("interior_before", size, clock, lv)
	_poor_home(W)
	lv.get_node("WearView").skip = ["home"]         # the home's yard / tags / litter are hand-placed in the dressing groups below
	(load("res://scripts/world/wear_layer.gd") as GDScript).call("set_lot_override", "home", 0.9, 0.85)        # the player's household is broke: poor variants, mess clutter, game-applied wear dressing, grimy walls
	dress.apply(lv, "home", ["rough_street", "rundown_house", "tidy_house", "rundown_interior"])
	await _frames(20)
	for c in cases:
		if c != "interior_before":
			await _case(c, size, clock, lv)
	print("done")
	OS.kill(OS.get_process_id())


## Furnished home made poor: grimy objects, broken things, lino in the kitchen, mess on the floor, cheap clutter.
func _poor_home(W) -> void:
	var rm := []
	for o in W.all_objects():
		if not Rect2i(45, 67, 32, 24).has_point(o.tile):
			continue
		if o.def_id in ["pendant_light", "rug", "mirror"] or (o.def_id == "bookcase_tall" and (o.tile.x + o.tile.y) % 2 == 0):
			rm.append(o.id)
			continue
		if o.state.has("dirtiness"):
			o.state["dirtiness"] = 5.0 + float((o.tile.x * 7 + o.tile.y * 3) % 5)
			root.get_node("Events").object_state_changed.emit(o.id, "dirtiness")
		if o.def_id in ["tv", "stereo", "stove", "sink", "coffee_maker"] and o.state.has("broken"):
			o.state["broken"] = o.def_id == "tv" or o.def_id == "stereo"
			root.get_node("Events").object_state_changed.emit(o.id, "broken")
		if o.state.has("made"):
			o.state["made"] = false
			root.get_node("Events").object_state_changed.emit(o.id, "made")
		if o.def_id == "fridge":
			o.state["spoiled"] = 3.0
			root.get_node("Events").object_state_changed.emit(o.id, "spoiled")
	for id in rm:
		W.remove_object(id)
	for y in range(78, 83):
		for x in range(58, 65):
			if W.get_floor(Vector2i(x, y)) == "wood":
				W.set_floor_raw(Vector2i(x, y), "tile")
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 46:
		W.add_mess(Vector2i(rng.randi_range(50, 64), rng.randi_range(72, 82)), rng.randf_range(2.0, 7.0))


func _place_folk(W, lv) -> void:
	var spots := [Vector2i(53, 79), Vector2i(60, 81), Vector2i(66, 91)]
	var i := 0
	for f in W.all_folk():
		f.queue.clear()
		f.idle_until_min = 1 << 30
		if i < spots.size():
			f.tile = spots[i]
			var fv = lv.get_folk_view(f.id)
			if fv != null:
				fv.position = W.tile_to_pos(spots[i])
		i += 1


func _case(c: String, size: Vector2i, clock, lv) -> void:
	var sunset: float = Seasons.sunset(Seasons.year_pos(-1, 12.0))
	var hour := 12.0
	var weather := "sunny"
	var zoom := 22.0
	var target := Vector3(60, 0, 84)
	match c:
		"day": hour = 12.0
		"dusk":
			hour = sunset - 0.2
		"night": hour = 23.0
		"rain":
			hour = 23.0
			weather = "rain"
		"far":
			hour = 12.0
			zoom = 9.0
			target = Vector3(56, 0, 74)
		"win":
			hour = 12.0
			zoom = 5.0
			target = Vector3(56, 1.0, 72)
		"interior_before", "interior_after":
			hour = 13.0
			zoom = 11.0
			target = Vector3(58, 0, 76)
		"bedroom":
			hour = 13.0
			zoom = 5.0
			for o in root.get_node("World").all_objects():
				if o.def_id in ["bed", "single_bed"] and Rect2i(45, 67, 32, 24).has_point(o.tile):
					target = Vector3(o.tile.x + 1.0, 0, o.tile.y + 1.0)
					break
		"litter":
			hour = 15.0
			zoom = 6.5
			target = Vector3(66, 0, 90)
		"graffiti":
			hour = 15.0
			zoom = 7.0
			target = Vector3(52, 0, 88.5)
		"yard":
			hour = 14.0
			zoom = 8.5
			target = Vector3(51, 0, 86.5)
		"exterior":
			hour = 15.0
			zoom = 12.0
			target = Vector3(60, 0, 86)
		"street":
			hour = 16.0
			zoom = 16.0
			target = Vector3(62, 0, 88)
		"district":
			hour = 15.0
			zoom = 14.0
			target = Vector3(137, 0, 79)
		"close":
			hour = sunset - 0.25
			zoom = 10.0
			target = Vector3(61, 0, 86.5)
	Weather.force(weather, 0.0)
	Weather._wet = 1.0 if weather == "rain" else 0.0      # the weather model dries / wets slowly; a jump in time needs the state set
	clock.total_minutes = int(hour * 60.0)
	clock.minute_passed.emit(clock.total_minutes)       # the HUD clock and weather widget follow
	lv.select("none", -1)
	lv.set_zoom(zoom)
	lv._target = target
	lv._zoom = lv._zoom_target
	lv._update_daylight()
	await create_timer(4.0).timeout
	var img: Image = root.get_texture().get_image()
	if img.get_size() != size:
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var p := "%s/art41a_%s_%dx%d%s.png" % [_out, c, size.x, size.y, "" if _look == "grounded" else "_" + _look]
	img.save_png(p)
	print("saved ", p, " hour ", hour, " sunset ", sunset)
