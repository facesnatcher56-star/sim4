extends SceneTree
## Not a unit test: windowed screenshots of the vehicle layer (task 12b).
## godot --path . --resolution 1600x900 --script res://tests/vehicle_shot.gd -- out_prefix scenario [more scenarios]
## scenarios: ambient (parked and passing cars), bus (a timetable bus at a stop), car (a player's car trip), taxi, bike, fire (engine to a call), crash (two cars, hazards, tow), night
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(prefix: String, name: String) -> void:
	await create_timer(0.15).timeout
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved ", name)


func _look(lv, at: Vector2, zoom: float) -> void:
	lv.frame_home()
	lv._target = Vector3(at.x, 0, at.y)
	lv.set_zoom(zoom)
	lv._zoom = zoom
	lv._update_daylight()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://veh"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7})
	await _frames(20)
	var clock = root.get_node("Clock")
	var lv = _main.lot_view
	_main.hud.visible = false
	clock.set_speed(1)
	Weather.force("sunny", 0.0)
	clock.total_minutes = 12 * 60
	for f in SysUtil.residents():
		f.idle_until_min = 1 << 30
	lv.select("none", -1)
	var vv = lv.get_node("VehicleView")
	for i in range(1, args.size()):
		var sc: String = args[i]
		match sc:
			"ambient":
				var home: Dictionary = VehicleRoads.frontage("home")
				_look(lv, Vector2(float(home["gate"]), float(home["hy"]) - 2.0), 34.0)
				await create_timer(5.0).timeout
				print("focus ", vv.focus_points(), " map_ready ", Workplace.map_ready(), " active ", vv.active, " stats ", vv.stats(), " speed ", clock.speed)
				await _shot(prefix, "ambient_1")
				await create_timer(4.0).timeout
				await _shot(prefix, "ambient_2")
				print("stats ", vv.stats())
			"wide":
				_look(lv, Vector2(60, 60), 70.0)
				await create_timer(5.0).timeout
				await _shot(prefix, "wide")
				print("stats ", vv.stats())
			"car", "taxi", "bike", "crash":
				await _trip_shots(prefix, sc, lv, vv, clock)
			"fire":
				var e: Dictionary = CityServices.dispatch("fire", "home")
				var f2: Dictionary = VehicleRoads.frontage("home")
				_look(lv, Vector2(float(f2["gate"]), float(f2["hy"]) - 2.0), 26.0)
				var t1 := Time.get_ticks_msec()
				var got := 0
				while got < 4 and Time.get_ticks_msec() - t1 < 90000:
					await create_timer(2.0).timeout
					for v in vv.sim.vehicles:
						if str(v["kind"]) == "fire":
							_look(lv, v["pos"], 18.0)
							await create_timer(0.3).timeout
							got += 1
							await _shot(prefix, "fire_%d" % got)
			"east":
				CityPlan.projects.clear()
				CityPlan.built_plots = {"plot_1": "residential", "plot_4": "commercial"}
				CityPlan.projects.append({"id": 1, "zone": "east", "plot": "plot_2", "kind": "civic", "state": "scaffold", "start": 1, "scaffold_end": 5, "ready": 15, "workers": 0})
				CityPlan.projects.append({"id": 2, "zone": "east", "plot": "plot_3", "kind": "residential", "state": "building", "start": 1, "scaffold_end": SysUtil.day() - 4, "ready": SysUtil.day() + 4, "workers": 5})
				_look(lv, Vector2(212, 60), 56.0)
				await create_timer(2.0).timeout
				await _shot(prefix, "east_wide")
				_look(lv, Vector2(212, 90), 30.0)
				await create_timer(1.5).timeout
				await _shot(prefix, "east_plots")
				_look(lv, Vector2(176, 50), 30.0)
				await create_timer(1.5).timeout
				await _shot(prefix, "east_civic")
			"town":
				Story.generate_townies()
				CityGov.ensure()
				CityPlan.projects.append({"id": 1, "zone": "east", "plot": "plot_2", "kind": "civic", "state": "scaffold", "start": 1, "scaffold_end": 5, "ready": 15, "workers": 0})
				Utilities.begin("power", CityState.zone_of_household(1), 3.0, "fault")
				_main.hud.visible = true
				_main.hud.town_dialog.show_for(SysUtil.residents()[0].id)
				await create_timer(1.0).timeout
				await _shot(prefix, "town_panel")
			"night":
				clock.total_minutes = 23 * 60
				var home2: Dictionary = VehicleRoads.frontage("home")
				_look(lv, Vector2(float(home2["gate"]), float(home2["hy"]) - 2.0), 34.0)
				await create_timer(4.0).timeout
				await _shot(prefix, "night")
	quit(0)


## Start a trip of the first folk, then follow its vehicle with the camera and shoot at the wanted moments.
func _trip_shots(prefix: String, kind: String, lv, vv, clock) -> void:
	var me = SysUtil.residents()[0]
	var hid: int = int(me.household_id)
	WorldIface.coins[hid] = 9000
	var dest_lot := "office"
	var opts: Dictionary = {"own_only": true, "from_lot": "home", "to_lot": dest_lot}
	if kind == "car" or kind == "crash":
		var b: Dictionary = TransportCars.buy(hid, "hatch")
		TransportCars.refuel(hid, int(b["car"]))
	elif kind == "bike":
		Transport.bikes[str(hid)] = 1
	elif kind == "taxi":
		var now: int = SysUtil.now()
		var dest: Vector2i = NeighborhoodLots.entry_tile(dest_lot)
		Transport.active[str(me.id)] = {"mode": "taxi", "minutes": 20.0, "cost": 20, "n": 100, "wait": 5.0, "to_lot": dest_lot, "total_minutes": 20.0, "start_min": now, "arrive_min": now + 20,
			"dest_x": dest.x, "dest_y": dest.y, "folk": int(me.id)}
	me.tile = NeighborhoodLots.entry_tile("home")
	if kind != "taxi":
		TransportTrip.start(me, NeighborhoodLots.entry_tile(dest_lot), opts)
		if kind == "crash":
			(Transport.active[str(me.id)] as Dictionary)["crash"] = "serious"
	var fr: Dictionary = VehicleRoads.frontage("home")
	_look(lv, Vector2(float(fr["gate"]) - 3.0, float(fr["hy"]) - 2.0), 22.0)
	await create_timer(1.2).timeout
	await _shot(prefix, kind + "_1_kerb")
	var shots := 1
	var t0 := Time.get_ticks_msec()
	if kind == "crash":
		var seen := 0
		var last := -99999
		while seen < 6 and Time.get_ticks_msec() - t0 < 150000:
			await create_timer(1.0).timeout
			var focus := Vector2.ZERO
			for v in vv.sim.vehicles:
				if bool((v["lights"] as Dictionary).get("hazard", false)) or str(v["kind"]) == "tow":
					focus = v["pos"]
			if focus != Vector2.ZERO and Time.get_ticks_msec() - last > 5000:
				last = Time.get_ticks_msec()
				seen += 1
				_look(lv, focus, 16.0)
				await create_timer(0.4).timeout
				await _shot(prefix, "crash_scene_%d" % seen)
		print("crash stats ", vv.stats())
		return
	while shots < 8 and Time.get_ticks_msec() - t0 < 70000:
		await create_timer(2.5).timeout
		var tgt := Vector2.ZERO
		for v in vv.sim.vehicles:
			if str(v["tag"]) == "trip" or str(v["kind"]) == "tow":
				tgt = v["pos"]
		if tgt != Vector2.ZERO:
			_look(lv, tgt, 20.0)
			await create_timer(0.5).timeout
		shots += 1
		await _shot(prefix, "%s_%d" % [kind, shots])
	print("trip stats ", vv.stats())
