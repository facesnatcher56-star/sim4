extends RefCounted
## Shared helpers for vehicle_* tests (no run(), so the runner skips it): a real-map game, a headless VehicleView (no meshes), vehicle seconds driven by hand.

const Kit = preload("res://tests/hood_kit.gd")

static var _acc: float = 0.0


static func game(start: String = "small") -> Array:
	var folk: Array = Kit.new_game(start)
	StoryPacing.enabled = false
	CityState.reset()
	UtilityEvents.dice_on = false
	VehicleBays.forget()
	return folk


## A headless layer (draw = false) focused on `points` (world x, z). Added under the root so its signals work.
static func layer(points: Array) -> VehicleView:
	var vv := VehicleView.new()
	vv.draw = false
	vv.forced_focus = points
	Kit.root().add_child(vv)
	return vv


## Real seconds of play at a game speed: the layer is driven frame by frame and the game clock follows (1 game minute per second at speed 1), like the game does.
static func run_seconds(vv: VehicleView, seconds: float, speed: int = 1, dt: float = 0.05) -> void:
	var n: int = int(seconds / dt)
	for _i in n:
		_acc += dt * float(Clock.MIN_PER_SEC[clampi(speed, 0, 3)])
		var whole: int = int(_acc)
		if whole > 0:
			_acc -= float(whole)
			SimEnv.clock().advance_minutes(whole)
		vv.advance(dt, speed)


static func free_layer(vv: VehicleView) -> void:
	if vv != null and is_instance_valid(vv):
		vv.get_parent().remove_child(vv)
		vv.free()


## The vehicle visual audit (the vehicle half of tests/visual_audit.gd): runs the layer over the real town while the sim plays, and counts
##   folk_in_vehicle   a folk standing inside the body of a MOVING vehicle (riders hidden in a vehicle do not count; a person who walks into a standing car is not the car's fault)
##   off_road          a moving vehicle that is not on road, sidewalk (bikes) or inside a lot
##   overlaps          two vehicle bodies cutting into each other
## Returns {folk_in_vehicle, off_road, overlaps, samples, max_vehicles, ghosted}.
static func audit(seconds: float, speed: int = 1) -> Dictionary:
	var w = WorldIface.world()
	var vv: VehicleView = layer([Vector2(40.0, 40.0), Vector2(115.0, 40.0), Vector2(40.0, 100.0), Vector2(115.0, 100.0)])
	vv.sync()
	var res := {"folk_in_vehicle": 0, "off_road": 0, "overlaps": 0, "samples": 0, "max_vehicles": 0, "ghosted": 0, "detail": []}
	var steps: int = int(seconds / 0.05)
	for step in steps:
		run_seconds(vv, 0.05, speed, 0.05)
		if step % 10 != 0:
			continue
		res["samples"] += 1
		var vs: Array = vv.sim.vehicles
		res["max_vehicles"] = maxi(int(res["max_vehicles"]), vs.size())
		for i in vs.size():
			var v: Dictionary = vs[i]
			if bool(v.get("hidden", false)):
				continue
			if str(v["state"]) != "parked":
				var p: Vector2 = v["pos"]
				var t := Vector2i(int(floorf(p.x)), int(floorf(p.y)))
				var f: String = w.get_floor(t)
				if t.x >= 2 and t.y >= 2 and t.x < int(w.width) - 2 and t.y < int(w.height) - 2 and f != "asphalt" and f != "crosswalk" and f != "sidewalk" and NeighborhoodLots.lot_at(t) == "":
					res["off_road"] += 1
			for j in range(i + 1, vs.size()):
				if VehicleSim.overlaps(v, vs[j]):
					res["overlaps"] += 1
					if (res["detail"] as Array).size() < 6:
						(res["detail"] as Array).append("overlap %s/%s %s/%s at %s %s v %.1f %.1f" % [str(v["kind"]), str(v["tag"]), str(vs[j]["kind"]), str(vs[j]["tag"]), str(v["pos"]), str(vs[j]["pos"]), float(v["v"]), float(vs[j]["v"])])
		for f2 in w.all_folk():
			if vv.trips.is_riding(int(f2.id)):
				continue
			var fp := Vector2(float(f2.tile.x) + 0.5, float(f2.tile.y) + 0.5)
			for v2 in vs:
				if bool(v2.get("hidden", false)) or float((v2["pos"] as Vector2).distance_to(fp)) > 5.0:
					continue
				if float(v2["v"]) < 0.1:
					continue                                  # a standing vehicle with somebody inside its footprint: the person walked into it (vehicles never vanish for that any more); only a vehicle that DRIVES over a person counts
				var d: Vector2 = fp - (v2["pos"] as Vector2)
				var h: Vector2 = v2["dir"]
				if absf(d.dot(h)) < float(v2["len"]) * 0.5 - 0.2 and absf(d.dot(VehicleRoads.right_of(h))) < float(v2["wid"]) * 0.5 - 0.1:
					res["folk_in_vehicle"] += 1
					if (res["detail"] as Array).size() < 4:
						(res["detail"] as Array).append("%s %s at %s state %s v %.1f" % [f2.name, str(v2["kind"]), str(v2["pos"]), str(v2["state"]), float(v2["v"])])
	res["ghosted"] = vv.sim.ghosted
	for g in vv.sim.ghost_log:
		if (res["detail"] as Array).size() < 8:
			(res["detail"] as Array).append("ghost " + str(g))
	free_layer(vv)
	return res
