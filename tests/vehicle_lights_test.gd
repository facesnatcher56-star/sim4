extends RefCounted
## Task 42 (fast): the lights of the vehicles do what a driver's would. Pure state: headlights on at night, dusk, in rain and in fog, off by day and when parked; brake lights while slowing or
## waiting; the indicator on the side of the next turn; reversing lights while backing out of a driveway; the beam is a low beam of 15 to 20 m; real lights only for the nearest few.

const K = preload("res://tests/vehicle_kit.gd")

var fails: Array = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func run() -> Array:
	fails = []
	K.game("classic")
	_context()
	_state()
	_beam_mesh()
	_rigs()
	K.Kit.teardown()
	return fails


func _context() -> void:
	var clock = SimEnv.clock()
	var cases: Array = [[12, "sunny", false, "noon, sunny"], [23, "sunny", true, "night"], [3, "sunny", true, "3 am"], [12, "rain", true, "noon, rain"], [12, "fog", true, "noon, fog"], [12, "snow", true, "noon, snow"]]
	for c in cases:
		clock.total_minutes = 2 * 1440 + int(c[0]) * 60
		Weather.force(str(c[1]), 0.0)
		var ctx: Dictionary = VehicleLights.context()
		_check(bool(ctx["on"]) == bool(c[2]), "headlights %s: expected %s got %s" % [str(c[3]), str(c[2]), str(ctx["on"])])
	# dusk: somewhere between sunset and night the switch flips on
	Weather.force("sunny", 0.0)
	var was_on: bool = false
	var turned_on_at: float = -1.0
	for m in range(15 * 60, 23 * 60, 10):
		clock.total_minutes = 2 * 1440 + m
		var on: bool = bool(VehicleLights.context()["on"])
		if on and not was_on and turned_on_at < 0.0:
			turned_on_at = float(m) / 60.0
		was_on = on
	_check(turned_on_at > 15.0 and turned_on_at < 22.5, "lights come on at dusk (at %.1f h)" % turned_on_at)
	Weather.unforce()


func _car(sim: VehicleSim, pts: Array, s0: float = 0.0) -> Dictionary:
	var path: VehiclePath = VehiclePath.make(pts, 1.8)
	return sim.add("car", "car_hatchback_red", path, {"end": "dead", "s": s0})


func _state() -> void:
	var sim := VehicleSim.new()
	var night: Dictionary = {"on": true, "dark": 1.0}
	var day: Dictionary = {"on": false, "dark": 0.0}
	var straight: Array = [Vector2(100, 50), Vector2(60, 50)]
	var v: Dictionary = _car(sim, straight, 5.0)
	v["v"] = 6.0
	var st: Dictionary = VehicleLights.state(v, night, 6.0)
	_check(bool(st["head"]) and bool(st["tail"]) and not bool(st["brake"]) and int(st["ind"]) == 0 and not bool(st["rev"]), "a car driving at night shows head and tail lights only: %s" % str(st))
	st = VehicleLights.state(v, day, 6.0)
	_check(not bool(st["head"]) and not bool(st["tail"]), "no lights by day: %s" % str(st))
	st = VehicleLights.state(v, day, 8.0)
	_check(bool(st["brake"]) and bool(st["tail"]), "slowing: brake lights even by day: %s" % str(st))
	v["v"] = 0.0
	st = VehicleLights.state(v, day, 0.0)
	_check(bool(st["brake"]), "waiting at a light: brake lights stay on")
	var pk: Dictionary = sim.add_parked("car", "car_sedan_red", Vector2(80, 50), Vector2(0, -1))
	st = VehicleLights.state(pk, night, 0.0)
	_check(not bool(st["head"]) and not bool(st["tail"]) and not bool(st["brake"]) and not bool(st["rev"]), "a parked car shows nothing, even at night: %s" % str(st))
	# a right turn (heading west, then north: north is on the right) and a left turn (west, then south)
	var right: Dictionary = _car(sim, [Vector2(100, 50), Vector2(80, 50), Vector2(80, 20)], 8.0)
	right["v"] = 5.0
	st = VehicleLights.state(right, night, 5.0)
	_check(int(st["ind"]) == 1, "a right turn ahead blinks right: %s" % str(st))
	var left: Dictionary = _car(sim, [Vector2(100, 50), Vector2(80, 50), Vector2(80, 80)], 8.0)
	left["v"] = 5.0
	st = VehicleLights.state(left, night, 5.0)
	_check(int(st["ind"]) == -1, "a left turn ahead blinks left: %s" % str(st))
	var far: Dictionary = _car(sim, [Vector2(200, 50), Vector2(80, 50), Vector2(80, 20)], 5.0)
	far["v"] = 5.0
	st = VehicleLights.state(far, night, 5.0)
	_check(int(st["ind"]) == 0, "no indicator 100 m before the turn")
	# backing out of a driveway: reversing lights while the body points the way it came
	var rv: Dictionary = sim.add_parked("car", "car_sedan_red", Vector2(60, 40), Vector2(0, -1))
	sim.restart(rv, VehiclePath.make([Vector2(60, 39.2), Vector2(60, 52), Vector2(40, 52)], 1.8), [], "dead", {}, 12.0)
	rv["v"] = 2.0
	rv["s"] = 3.0
	st = VehicleLights.state(rv, day, 2.0)
	_check(bool(st["rev"]) and not bool(st["brake"]) and int(st["ind"]) == 0, "backing out shows the reversing lights: %s" % str(st))
	_check(VehicleSim.reversing(rv), "VehicleSim says it is reversing")
	var face: Vector2 = sim.face(rv, rv["path"])
	_check(face.y < -0.9, "while backing out the body still points north (%s)" % str(face))
	rv["s"] = 20.0
	rv["v"] = 5.0
	st = VehicleLights.state(rv, day, 5.0)
	_check(not bool(st["rev"]), "no reversing lights once it drives forward")
	# backing up to free a deadlock (VehicleJams): reversing lights too
	var jam: Dictionary = _car(sim, straight, 20.0)
	jam["v"] = 0.0
	jam["reverse_left"] = 2.0
	st = VehicleLights.state(jam, night, 0.0)
	_check(bool(st["rev"]) and not bool(st["brake"]), "a car backing up to free a jam shows the reversing lights: %s" % str(st))
	# an ambulance with its siren
	var amb: Dictionary = sim.add("ambulance", "ambulance", VehiclePath.make(straight, 1.8), {"end": "dead"})
	amb["lights"]["siren"] = true
	amb["v"] = 8.0
	st = VehicleLights.state(amb, day, 8.0)
	_check(bool(st["siren"]), "the siren flag reaches the flash")


func _beam_mesh() -> void:
	var m: ArrayMesh = VehicleLights.mesh_for(1.8, 4.2, "car_hatchback_red")
	var bb: AABB = m.get_aabb()
	_check(m.get_surface_count() == 1, "one surface for every lamp (%d)" % m.get_surface_count())
	var reach: float = -bb.position.z - 2.1
	_check(reach >= 15.0 and reach <= 20.0, "the low beam reaches 15 to 20 m (%.1f)" % reach)
	_check(bb.size.y < 1.0, "the lamp mesh is flat (%.2f)" % bb.size.y)
	_check(VehicleLights.mesh_for(1.8, 4.2, "car_hatchback_blue") == m, "one mesh is shared by cars of one size")


## Real lights only for the nearest few.
func _rigs() -> void:
	var holder := Node3D.new()
	K.Kit.root().add_child(holder)
	var sim := VehicleSim.new()
	var nodes := VehicleNodes.new()
	for k in 30:
		var v: Dictionary = sim.add("car", "car_hatchback_red", VehiclePath.make([Vector2(150.0 - float(k) * 4.0, 40), Vector2(10, 40)], 1.8), {"end": "dead", "s": 2.0})
		v["v"] = 5.0
	for k2 in 5:
		var e: Dictionary = sim.add("ambulance", "ambulance", VehiclePath.make([Vector2(30.0 + float(k2) * 6.0, 44), Vector2(10, 44)], 1.8), {"end": "dead", "s": 1.0})
		e["lights"]["siren"] = true
		e["v"] = 7.0
	Weather.force("sunny", 0.0)
	SimEnv.clock().total_minutes = 2 * 1440 + 23 * 60
	nodes.cam_ground = Vector2(60, 40)
	nodes.sync(holder, sim.vehicles, 1.0, 0.18)
	nodes.sync(holder, sim.vehicles, 1.1, 0.18)
	var n: Dictionary = nodes.rigs.count()
	var cap: int = int((VehicleLightRigs.cfg()).get("real_n", 6))
	var capo: int = int((VehicleLightRigs.cfg()).get("emergency_n", 3))
	print("  [lights] 35 vehicles at night: %d spot lights (cap %d), %d flashing lights (cap %d)" % [int(n["spots"]), cap, int(n["omnis"]), capo])
	_check(int(n["spots"]) >= 1 and int(n["spots"]) <= cap, "real headlights only for the nearest %d (%d)" % [cap, int(n["spots"])])
	_check(int(n["omnis"]) >= 1 and int(n["omnis"]) <= capo, "real blue and red lights only for the nearest %d (%d)" % [capo, int(n["omnis"])])
	nodes.clear()
	holder.get_parent().remove_child(holder)
	holder.free()
	Weather.unforce()
