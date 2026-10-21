extends SceneTree
## Not a unit test: the task 42 pictures, windowed (Forward+). One case per process (windowed runs may hang: the caller retries).
## godot --path . --rendering-method forward_plus --script res://tests/park42_shot.gd -- <out dir> <WxH> <look> <case> [home_template]
## cases: street_night (moving cars with beams), brake, indicate, reverse, ambulance, driveway, garage (carport), bays (lay-by), carpark, forecourt
## out file: <out dir>/park42_<case>_<W>x<H>.png. Uses Looks.set_look(look) ("grounded" is the default of the game).
var _main: Node = null
var _out := "user://"
var _look := "grounded"
var vv = null


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
	var case: String = args[3]
	var home_tpl: String = args[4] if args.size() > 4 else "classic"
	var size := Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7, "home_template": home_tpl})
	await _frames(30)
	Looks.set_look(_look)
	await _frames(10)
	var clock = root.get_node("Clock")
	clock.set_speed(1)
	var lv = _main.lot_view
	_main.hud.visible = false
	for f in SysUtil.residents():
		f.idle_until_min = 1 << 30
	vv = lv.get_node("VehicleView")
	await _case(case, size, clock, lv)
	print("done")
	OS.kill(OS.get_process_id())


func _set_time(clock, hour: float, weather: String = "sunny") -> void:
	Weather.force(weather, 0.0)
	Weather._wet = 1.0 if weather == "rain" else 0.0
	clock.total_minutes = 2 * 1440 + int(hour * 60.0)
	clock.minute_passed.emit(clock.total_minutes)


func _look_at(lv, at: Vector2, zoom: float) -> void:
	lv.select("none", -1)
	lv.set_zoom(zoom)
	lv._target = Vector3(at.x, 0, at.y)
	lv._zoom = lv._zoom_target
	lv._update_daylight()


func _save(size: Vector2i, name: String) -> void:
	await create_timer(0.3).timeout
	var img: Image = root.get_texture().get_image()
	if img.get_size() != size:
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var p := "%s/park42_%s_%dx%d.png" % [_out, name, size.x, size.y]
	img.save_png(p)
	print("saved ", p)


## Leave the layer's own parking dice out of the picture: the shot puts the cars where it wants them.
func _quiet_layer() -> void:
	vv.cfg["ambient"]["max_moving"] = 0
	vv.cfg["filler"]["per_hour_max"] = 0.0
	vv.cfg["filler"]["floor_per_hour"] = 0.0
	for lot_id in Neighborhood.lot_ids():
		vv.ambient._lots_done[str(lot_id)] = true
	vv.sim.vehicles.clear()
	vv.nodes.clear()


const GLBS := ["car_hatchback_red", "car_sedan_blue", "car_hatchback_white", "car_van_white", "car_sedan_yellow", "car_hatchback_blue"]


func _park(lot: String, n: int, skip: int = 0) -> Array:
	var out: Array = []
	var pls: Array = VehicleBays.of(lot)
	for k in pls.size():
		if out.size() >= n:
			break
		if k < skip:
			continue
		var pl: Dictionary = pls[k]
		var v: Dictionary = vv.sim.add_parked("car", GLBS[(k * 5 + lot.length()) % GLBS.size()], pl["pos"], pl["face"], {"tag": "shot"})
		v["lot"] = lot
		v["bay"] = k
		out.append(v)
	return out


func _lane_cars(lot: String, count: int, gap: float, east_bound: bool = false) -> Array:
	var fr: Dictionary = VehicleRoads.frontage(lot)
	var out: Array = []
	var z: float = float(fr["lane_z"])
	var x0: float = float(fr["gate"]) + 4.0
	for k in count:
		var pts: Array = [Vector2(x0 + 30.0 + float(k) * gap, z), Vector2(x0 - 80.0, z)]
		if east_bound:
			z = float(fr["hy"]) + 6.0 - (z - float(fr["hy"]))
			pts = [Vector2(x0 - 30.0 - float(k) * gap, float(fr["hy"]) + 4.05), Vector2(x0 + 80.0, float(fr["hy"]) + 4.05)]
		var v: Dictionary = vv.sim.add("car", GLBS[k % GLBS.size()], VehiclePath.make(pts, 1.8), {"end": "dead", "tag": "shot"})
		v["ignore_signals"] = true
		out.append(v)
	return out


func _case(c: String, size: Vector2i, clock, lv) -> void:
	var hour := 12.0
	var weather := "sunny"
	var fr: Dictionary = VehicleRoads.frontage("market")
	var at := Vector2(float(fr["gate"]), float(fr["hy"]))
	var zoom := 30.0
	_quiet_layer()
	match c:
		"street_night":
			hour = 21.5
			zoom = 34.0
			at = Vector2(float(fr["gate"]) - 6.0, float(fr["hy"]) + 2.0)
			_park("market", 4)
			await _frames(5)
			_lane_cars("market", 3, 17.0)
			_lane_cars("market", 2, 21.0, true)
		"brake":
			hour = 21.5
			zoom = 22.0
			at = Vector2(float(fr["gate"]) - 4.0, float(fr["hy"]) + 2.0)
			var v: Dictionary = _lane_cars("market", 1, 0.0)[0]
			var plen: float = (v["path"] as VehiclePath).length
			v["stops"] = [{"s": 60.0, "hold": true, "tag": "stop"}]
			var w2: Dictionary = _lane_cars("market", 1, 0.0)[0]
			w2["s"] = 0.0
			w2["stops"] = [{"s": 49.0, "hold": true, "tag": "stop"}]
			v["s"] = 8.0
			w2["s"] = 4.0
		"indicate":
			hour = 21.5
			zoom = 22.0
			at = Vector2(float(fr["gate"]) - 2.0, float(fr["hy"]) + 2.0)
			var gx: float = float(fr["gate"]) - 6.0
			var pts: Array = [Vector2(gx + 36.0, float(fr["lane_z"])), Vector2(gx, float(fr["lane_z"])), Vector2(gx, float(fr["hy"]) + 9.0)]
			var vi: Dictionary = vv.sim.add("car", "car_sedan_blue", VehiclePath.make(pts, 1.8), {"end": "dead", "tag": "shot", "s": 23.0})
			vi["ignore_signals"] = true
			vi["vmax"] = 1.6
		"reverse":
			hour = 20.0
			zoom = 20.0
			var hf: Dictionary = VehicleRoads.frontage(Neighborhood.HOME)
			var pls: Array = VehicleBays.of(Neighborhood.HOME)
			if not pls.is_empty():
				var p: Vector2 = pls[0]["pos"]
				at = Vector2(p.x, float(hf["hy"]) - 2.0)
				var parked: Array = _park(Neighborhood.HOME, 1)
				await _frames(10)
				vv.ambient._leave(parked[0])
		"ambulance":
			hour = 22.0
			zoom = 26.0
			at = Vector2(float(fr["gate"]) + 4.0, float(fr["hy"]) + 2.0)
			_park("market", 3)
			var pts2: Array = [Vector2(float(fr["gate"]) + 40.0, float(fr["lane_z"])), Vector2(float(fr["gate"]) - 90.0, float(fr["lane_z"]))]
			var am: Dictionary = vv.sim.add("ambulance", "ambulance", VehiclePath.make(pts2, 1.8), {"end": "dead", "tag": "shot"})
			am["ignore_signals"] = true
			am["lights"]["siren"] = true
			am["s"] = 22.0
			am["vmax"] = 3.0
		"driveway", "garage":
			hour = 12.0
			zoom = 20.0
			var lot_id: String = Neighborhood.HOME
			var best: Dictionary = {}
			for l in Neighborhood.lot_ids():
				for pl in VehicleBays.of(str(l)):
					if str(pl["kind"]) == "driveway" and best.is_empty() and ((c == "garage") == bool(pl.get("carport", false))):
						best = pl
						lot_id = str(l)
			if best.is_empty():
				print("no ", c, " place on this map")
			else:
				var p2: Vector2 = best["pos"]
				at = Vector2(p2.x, p2.y + 2.0)
				_park(lot_id, 2)
		"bays", "carpark", "forecourt":
			hour = 12.0
			zoom = 20.0
			var lot2: String = "car_park" if c == "carpark" else ("market" if c == "forecourt" else "apartments")
			var pls2: Array = VehicleBays.of(lot2)
			if c == "bays":
				for l2 in Neighborhood.lot_ids():
					for pl2 in VehicleBays.of(str(l2)):
						if str(pl2["kind"]) == "layby":
							lot2 = str(l2)
				pls2 = VehicleBays.of(lot2)
			if not pls2.is_empty():
				var fr2: Dictionary = VehicleRoads.frontage(lot2)
				at = Vector2(float(fr2["gate"]), float(fr2["hy"]) - 2.0)
				_park(lot2, 6)
	_set_time(clock, hour, weather)
	clock.set_speed(1)
	_look_at(lv, at, zoom)
	await create_timer(1.5).timeout
	var VL = load("res://scripts/world/vehicle_lights.gd")
	if c == "indicate":
		var waited := 0
		while waited < 900:
			var hit := false
			for v3 in vv.sim.vehicles:
				if str(v3["tag"]) == "shot" and int(VL.turn_ahead(v3)) != 0 and fposmod(vv.sim.vt, 0.7) < 0.3:
					hit = true
			if hit:
				break
			await process_frame
			waited += 1
		clock.set_speed(0)                          # freeze the layer on the blink
	elif c == "reverse":
		var tries := 0
		while tries < 900:
			var rv := false
			for v2 in vv.sim.vehicles:
				if VehicleSim.reversing(v2) and float(v2["s"]) > 2.0:
					rv = true
			if rv:
				break
			await process_frame
			tries += 1
		clock.set_speed(0)
	elif c == "brake":
		await create_timer(2.0).timeout
	elif c == "ambulance":
		var w3 := 0
		while fposmod(vv.sim.vt, 0.36) > 0.15 and w3 < 600:
			await process_frame
			w3 += 1
		clock.set_speed(0)
	elif c == "street_night":
		await create_timer(1.0).timeout
	await create_timer(0.6).timeout
	await _save(size, c)
