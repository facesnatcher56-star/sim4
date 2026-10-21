extends RefCounted
## Shared helpers for the parking tests (no run(), so the runner skips it): the footprint of a car, the checks of a place, and a run of the vehicle layer that audits every parked car.

const K = preload("res://tests/vehicle_kit.gd")


## The corners and the middle of a car's footprint at `pos` facing `face`.
static func footprint(pos: Vector2, face: Vector2) -> Array:
	var f: Vector2 = face.normalized()
	var r: Vector2 = Vector2(-f.y, f.x)
	var out: Array = []
	for a in [-2.1, 0.0, 2.1]:
		for b in [-0.9, 0.0, 0.9]:
			out.append(pos + f * a + r * b)
	return out


## Over `hours` (hour of day, each `secs` vehicle seconds long) every parked car of the layer stands inside a place of its lot: footprint inside the marked area, on paved ground, never on a
## footway, crossing, junction or lane. Returns {seen, outside, fails}.
static func layer_run(sd: int, hours: Array, secs: float) -> Dictionary:
	K.game("classic", sd)
	var w = WorldIface.world()
	var pts: Array = []
	for lot_id in Neighborhood.lot_ids():
		var rc: Rect2i = NeighborhoodLots.rect_of(str(lot_id))
		pts.append(Vector2(float(rc.position.x + 16), float(rc.position.y + 12)))
	var vv: VehicleView = K.layer(pts)
	var res := {"seen": 0, "outside": 0, "fails": [], "parked_at_driveway": 0, "cars": {}}
	var clock = SimEnv.clock()
	for hour in hours:
		clock.advance_minutes(maxi((int(hour) * 60 + 1440) - (clock.total_minutes % 1440), 1))
		K.run_seconds(vv, secs, 1)
		for v in vv.sim.vehicles:
			if str(v["state"]) != "parked" or str(v["kind"]) != "car" or not v.has("lot"):
				continue
			res["seen"] += 1
			(res["cars"] as Dictionary)[int(v["id"])] = true
			var places: Array = VehicleBays.of(str(v["lot"]))
			var k: int = int(v.get("bay", -1))
			if k < 0 or k >= places.size():
				res["outside"] += 1
				(res["fails"] as Array).append("seed %d: parked car of %s has no place (bay %d of %d)" % [sd, str(v["lot"]), k, places.size()])
				continue
			var pl: Dictionary = places[k]
			if str(pl["kind"]) == "driveway":
				res["parked_at_driveway"] += 1
			var rc2: Rect2 = (pl["rect"] as Rect2).grow(0.1)
			for p in footprint(v["pos"], v["dir"]):
				var pp: Vector2 = p
				var t := Vector2i(int(floorf(pp.x)), int(floorf(pp.y)))
				var fl: String = w.get_floor(t)
				if not rc2.has_point(pp) or fl in ["sidewalk", "crosswalk", "asphalt", "lawn", "grass"] or VehicleRoads.junction_at_point(pp) != Vector2i(-1, -1):
					res["outside"] += 1
					(res["fails"] as Array).append("seed %d hour %d: parked car of %s at %s facing %s sticks out of its %s (tile %s is %s)" % [sd, int(hour), str(v["lot"]), str(v["pos"]), str(v["dir"]), str(pl["kind"]), str(t), fl])
					break
	K.free_layer(vv)
	return res
