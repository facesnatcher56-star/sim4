extends RefCounted
## Fire in a building with floors (task 10 part B): a growing fire climbs through the stairwell faster than it spreads sideways, smoke rises
## into the room above, the lift is switched off while the building burns (and back on afterwards), folk upstairs escape by the stairs
## (never the lift), and a fire on one floor is not a fire on the others.

const Kit = preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _tick(n: int) -> void:
	var clock = Engine.get_main_loop().root.get_node("Clock")
	for i in n:
		clock.advance_minutes(1)
		Fire.on_minute()


func _setup(floors: int = 3) -> WorldGrid:
	TestFixture.reset()
	WorldIface.stub = null
	IncidentDefs.reset()
	IncidentContent.install()
	Fire.reset()
	Kit.tower(floors, true)
	var W := Kit.world()
	return W


func run() -> Array:
	fails = []
	_levels_are_separate()
	_climbs_fast()
	_smoke_and_lift()
	_escape_by_stairs()
	_fire_escape()
	Kit.world().reset()
	return fails


## A fire carries its floor; the same tile on another floor is not burning.
func _levels_are_separate() -> void:
	var W := _setup()
	var up: int = W.place_object("sofa", Vector2i(10, 8), 0, 1)
	_check(up >= 0, "sofa on level 1: %s" % W.last_error)
	_check(Fire.ignite(W.get_object(up), "candle"), "ignite the upstairs sofa")
	var f: Dictionary = Fire.active()[0]
	_check(int(f["level"]) == 1, "the fire is on level 1")
	_check(not Fire.fire_at(Vector2i(10, 8), 1).is_empty() and Fire.fire_at(Vector2i(10, 8), 0).is_empty() and Fire.fire_at(Vector2i(10, 8)).is_empty(), "fire_at is per floor")
	_check(Fire.is_burning(W.get_object(up)), "is_burning(object) knows the floor")
	var sofa0: int = W.place_object("sofa", Vector2i(10, 8), 0, 0)
	_check(sofa0 >= 0 and not Fire.is_burning(W.get_object(sofa0)), "the sofa right below is not burning")
	Fire.reset()
	W.reset()


## Fire at the foot of the stairs, stage 2: within a few spread ticks it is on the floor above, far more often than not.
func _climbs_fast() -> void:
	var climbed := 0
	var trials := 12
	for i in trials:
		var W := _setup()
		Fire.rng.seed = 40 + i
		var sofa: int = W.place_object("sofa", Vector2i(8, 6), 0, 0)             # beside the stairwell of level 0 -> 1 (stairs at x 6, 7)
		W.place_object("sofa", Vector2i(8, 6), 0, 1)                            # furniture upstairs above it
		W.place_object("armchair", Vector2i(7, 7), 0, 1)
		Fire.ignite(W.get_object(sofa), "cooking", {"stage": 2})
		_tick(15)
		for fr in Fire.active():
			if int(fr.get("level", 0)) == 1:
				climbed += 1
				break
	_check(climbed >= 8, "a stage-2 fire next to the stairwell reaches the floor above in %d/%d runs within 15 minutes" % [climbed, trials])
	# the same fire on the TOP floor has nowhere to climb
	var W2 := _setup(2)
	Fire.rng.seed = 3
	var top: int = W2.place_object("sofa", Vector2i(10, 8), 0, 1)
	Fire.ignite(W2.get_object(top), "cooking", {"stage": 3})
	_tick(20)
	var above := false
	for fr in Fire.active():
		above = above or int(fr.get("level", 0)) > 1
	_check(not above, "nothing burns above the top floor")
	Fire.reset()
	W2.reset()


func _smoke_and_lift() -> void:
	var W := _setup()
	Fire.rng.seed = 11
	var lift = W.objects_of_def("elevator")[0]
	_check(not bool(lift.state.get("out_of_order", false)), "the lift works")
	_check(W.has_route(Vector3i(11, 12, 0), Vector3i(11, 8, 2)), "a route up exists")
	var sofa: int = W.place_object("sofa", Vector2i(9, 8), 0, 0)
	W.place_object("sofa", Vector2i(9, 8), 0, 1)
	Fire.ignite(W.get_object(sofa), "cooking", {"stage": 3})
	_check(bool(lift.state.get("out_of_order", false)), "the lift is switched off while the building burns")
	var route: Array = W.find_route(Vector3i(11, 12, 0), Vector3i(11, 8, 2))
	var by_lift := false
	for i in range(1, route.size()):
		if route[i].x == route[i - 1].x and route[i].y == route[i - 1].y and route[i].z != route[i - 1].z:
			by_lift = true
	_check(not by_lift, "routes go by the stairs, not the lift (%d steps)" % route.size())
	_tick(10)
	var b: Dictionary = Fire.blazes.get("home", {})
	var smoke_below: float = FireSmoke.at(b, Vector2i(9, 8), 0) if not b.is_empty() else 0.0
	var smoke_above: float = FireSmoke.at(b, Vector2i(9, 8), 1) if not b.is_empty() else 0.0
	_check(smoke_below > 0.0, "the burning room fills with smoke (%.2f)" % smoke_below)
	_check(smoke_above > 0.0, "smoke rises into the room above (%.2f)" % smoke_above)
	_check(FireSmoke.at(b, Vector2i(9, 8), 2) <= smoke_above + 0.01, "and thins out higher up")
	Fire.extinguish_lot("home", "test")
	_tick(3)
	_check(not bool(lift.state.get("out_of_order", false)), "the lift is back once the fire is out")
	_check(not Fire.blazes.has("home"), "the blaze is over")
	Fire.reset()
	W.reset()


func _escape_by_stairs() -> void:
	var W := _setup()
	var f := Folk.create("Ines")
	f.household_id = 1
	W.add_folk(f, Vector2i(11, 8), 2)
	var exit := Vector2i(11, 20)
	var route: Array = FireLevels.escape_route(f, exit)
	_check(not route.is_empty() and route[route.size() - 1].z == 0, "a way out of the 3rd floor to the street")
	var lifts_used := 0
	for i in range(1, route.size()):
		if route[i].x == route[i - 1].x and route[i].y == route[i - 1].y and route[i].z != route[i - 1].z:
			lifts_used += 1
	var lift = W.objects_of_def("elevator")[0]
	W.set_object_state(lift.id, "out_of_order", true)
	var route2: Array = FireLevels.escape_route(f, exit)
	_check(not route2.is_empty(), "still a way out with the lift off (stairs): %d steps" % route2.size())
	_check(route2.size() >= route.size() - 1 or lifts_used == 0, "the stairs take at least as long as the lift")
	# somebody rescued from an upper floor ends up in the street, on the ground floor
	var b := {"lot": "home", "exit": [exit.x, exit.y], "rescued": []}
	var dr := {"state": "x", "aware": false, "expo": 0.0}
	FireFolk.carry_out(b, f, dr)
	_check(f.level == 0 and f.tile == exit, "carried out: on the ground floor at the exit (level %d, %s)" % [f.level, str(f.tile)])
	# a jump from the 3rd floor hurts
	f.level = 2
	f.tile = Vector2i(11, 8)
	FireLevels.land(f, true)
	_check(f.level == 0 and (f.has_buff("injured") or Hospital.is_in(f)), "a jump from a high window hurts")
	Fire.reset()
	W.reset()


## A building with NO stairs and no lift reaching the street from the 2nd floor, only an outside fire escape (ring tile west of the wall):
## the escape route of a folk upstairs goes down it.
func _fire_escape() -> void:
	TestFixture.reset()
	WorldIface.stub = null
	IncidentDefs.reset()
	IncidentContent.install()
	Fire.reset()
	var bid: int = Kit.tower(2, false, 0, false)
	var W := Kit.world()
	W.levels.buildings[bid]["rect"] = Kit.FOOT.grow(1)          # like LotLevels.prepare: the building includes the 1-tile ring around its walls
	W.levels.touch()
	# a balcony tile on level 1 outside the west wall (x 3) with a door to the room, and the escape stairs from the ground up to it
	W.levels.set_floor_rect_raw(Vector2i(3, 9), Vector2i(3, 9), "stone", 1)
	_check(W.place_object("door", Vector2i(4, 9), 3, 1) >= 0, "door to the balcony: %s" % W.last_error)
	var fe: int = W.place_object("fire_escape", Vector2i(3, 7), 1, 0)
	_check(fe >= 0, "fire escape on the outside of the wall: %s" % W.last_error)
	var f := Folk.create("Fio")
	f.household_id = 1
	W.add_folk(f, Vector2i(6, 9), 1)
	_check(W.has_route(Vector3i(6, 9, 1), Vector3i(3, 5, 0)), "a route down by the fire escape alone")
	var route: Array = FireLevels.escape_route(f, Vector2i(11, 20))
	var via := false
	for p in route:
		via = via or (p.x == 3 and p.z == 1)
	_check(not route.is_empty() and route[route.size() - 1].z == 0 and via, "the folk upstairs flees over the balcony and the fire escape (%d steps)" % route.size())
	W.set_object_state(fe, "out_of_order", true)
	_check(FireLevels.escape_route(f, Vector2i(11, 20)).is_empty(), "with the escape broken there is no way out (trapped)")
	Fire.reset()
	W.reset()
