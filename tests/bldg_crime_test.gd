extends RefCounted
## Everything that asks "where" in a building with floors: crime (burglars use ground-floor doors and windows only; whereabouts and witnesses
## know the floor), autonomy (objects_near filters by floor, a flat's furniture is its household's), weather (only the top roof is outdoors).

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("medium", 777, 1, "medium_f01")
	_entry_points()
	_whereabouts(folk)
	_witnesses(folk)
	_objects_near(folk)
	_weather(folk)
	Kit.teardown()
	_apartments()
	Kit.teardown()
	return fails


func _entry_points() -> void:
	var W: Node = Kit.world()
	var expected := 0
	var upstairs := 0
	for o in W.all_objects():
		if str(o.def_id) in ["door", "window"] and Neighborhood.lot_at(o.tile) == Neighborhood.HOME:
			if o.level == 0:
				expected += 1
			else:
				upstairs += 1
	_check(upstairs > 0 and expected > 0, "the two-storey home has doors / windows on both floors (%d up, %d down)" % [upstairs, expected])
	var pts: Array = CrimePlace.entry_points(1)
	var home_pts := 0
	for t in pts:
		if Neighborhood.lot_at(t) == Neighborhood.HOME:
			home_pts += 1
	_check(home_pts == expected, "burglars only get the ground-floor doors / windows (%d of %d)" % [home_pts, expected + upstairs])


func _whereabouts(folk: Array) -> void:
	var f: Folk = folk[0]
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	f.level = 0
	var pid := int(f.id)
	_check(CrimePlace.where_now(pid) == "home:1" and CrimePlace.where_now(pid, true) == "home:1", "ground floor: plain location")
	f.level = 1
	_check(CrimePlace.where_now(pid) == "home:1", "upstairs: the same place for alibis ...")
	_check(CrimePlace.where_now(pid, true) == "home:1#1", "... and the floor when asked (%s)" % CrimePlace.where_now(pid, true))
	CrimePlace.record_now(pid)
	var minute := SysUtil.now()
	_check(CrimePlace.where_was(pid, minute) == "home:1", "the log keeps the place")
	_check(CrimePlace.where_was(pid, minute, true) == "home:1#1", "and the floor (%s)" % CrimePlace.where_was(pid, minute, true))
	_check(CrimePlace.level_of(pid) == 1, "level_of")


func _witnesses(folk: Array) -> void:
	var a: Folk = folk[0]
	var b: Folk = folk[1]
	var t := NeighborhoodLots.entry_tile(Neighborhood.HOME)
	a.tile = t
	b.tile = t + Vector2i(2, 0)
	a.level = 0
	b.level = 0
	_check(CrimePlace.can_witness(int(a.id), int(b.id)), "same floor, close: seen")
	b.level = 1
	_check(not CrimePlace.can_witness(int(a.id), int(b.id)), "another floor (a ceiling between): not seen")
	b.level = 0
	b.tile = t + Vector2i(12, 0)
	_check(not CrimePlace.can_witness(int(a.id), int(b.id)), "too far: not seen")
	a.level = 0
	b.level = 0
	a.tile = t
	b.tile = t


func _objects_near(folk: Array) -> void:
	var f: Folk = folk[0]
	var t := NeighborhoodLots.entry_tile(Neighborhood.HOME)
	var all: Array = WorldIface.objects_near(t, 40)
	var l0: Array = WorldIface.objects_near(t, 40, 0)
	var l1: Array = WorldIface.objects_near(t, 40, 1)
	var levels: Dictionary = {}
	for o in all:
		levels[o.level] = true
	_check(levels.has(0) and levels.has(1), "objects_near without a level returns every floor (%s)" % str(levels.keys()))
	var only0 := true
	for o in l0:
		only0 = only0 and o.level == 0
	var only1 := not l1.is_empty()
	for o in l1:
		only1 = only1 and o.level == 1
	_check(only0 and not l0.is_empty() and only1 and l0.size() + l1.size() == all.size(), "with a level: just that floor (%d + %d = %d)" % [l0.size(), l1.size(), all.size()])
	# a folk at home sees every floor (the bed is upstairs) ...
	f.tile = t
	f.level = 0
	var mine: Array = WorldIface.objects_for(f, 40)
	var up := false
	for o in mine:
		up = up or o.level == 1
	_check(up, "in a home the other floors are offered too (the bed is upstairs)")
	# ... but in a venue only the own floor
	var rc := NeighborhoodLots.rect_of("office")
	var door := NeighborhoodLots.entry_tile("office")
	f.tile = door
	var venue: Array = WorldIface.objects_for(f, 40)
	var floors: Dictionary = {}
	for o in venue:
		floors[o.level] = true
	_check(floors.size() <= 1, "in a venue autonomy only offers the folk's own floor (%s)" % str(floors.keys()))
	f.tile = t


func _weather(folk: Array) -> void:
	var f: Folk = folk[0]
	var inside: Vector2i = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	var rc := NeighborhoodLots.rect_of(Neighborhood.HOME)
	var yard := Vector2i(rc.position.x + 1, rc.position.y + 1)
	_check(Weather.is_outdoor(yard, 0), "the yard is outdoors")
	var bid: int = Kit.world().levels.building_at(inside)
	_check(bid >= 0, "the home is a building")
	var room_tile := inside
	_check(not Weather.is_outdoor(room_tile, 1), "the first floor under the roof is not rained on")
	f.tile = room_tile
	f.level = 1
	Weather.outdoors_fn = Callable()
	_check(not WeatherFolk.is_outside(f), "a folk upstairs is not outside")
	_check(Weather.walk_speed_mult_at(room_tile, 1) == 1.0, "no snow slowdown indoors upstairs")
	f.level = 0
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)


func _apartments() -> void:
	var seed_with_flats := 1
	var folk: Array = Kit.new_game("small", 777, seed_with_flats)
	var units: Array = ApartmentUnits.units_of("apartments")
	_check(units.size() >= 8, "the apartment block has flats (%d)" % units.size())
	var W: Node = Kit.world()
	for u in units:
		var d = ApartmentUnits.door_of(u)
		_check(d != null, "flat %s has an entrance door" % str(u["id"]))
		if d == null:
			return
	_check(ApartmentUnits.free_units("apartments").size() == units.size(), "all flats are free to begin with")
	var u0: Dictionary = units[0]
	var u1: Dictionary = units[1]
	_check(ApartmentUnits.assign(u0, 1) and ApartmentUnits.assign(u1, 2), "two households move in")
	_check(ApartmentUnits.owner_of(u0) == 1 and ApartmentUnits.owner_of(u1) == 2, "the owners are recorded")
	_check(bool(ApartmentUnits.door_of(u0).state.get("locked", false)), "their doors are locked")
	_check(ApartmentUnits.free_units("apartments").size() == units.size() - 2, "two flats fewer to let")
	_check(ApartmentUnits.units_of_household(2).size() == 1, "units_of_household")
	# autonomy: a household uses its own flat and the shared corridor, never the neighbour's
	var mira: Folk = folk[0]
	mira.household_id = 1
	var in0 := Vector2i(-1, -1)
	for o in W.all_objects():
		if o.level == u0["level"] and (u0["rect"] as Rect2i).has_point(o.tile) and not o.is_wall_mounted():
			in0 = o.tile
			break
	_check(in0.x >= 0, "furniture in the first flat")
	mira.tile = in0
	mira.level = int(u0["level"])
	var seen_own := false
	var seen_other := false
	for o in WorldIface.objects_for(mira, 40):
		if o.level == u0["level"] and (u0["rect"] as Rect2i).has_point(o.tile):
			seen_own = true
		if o.level == u1["level"] and (u1["rect"] as Rect2i).has_point(o.tile):
			seen_other = true
	_check(seen_own and not seen_other, "household 1 uses its own flat (%s) and not the neighbour's (%s)" % [str(seen_own), str(seen_other)])
	var intruder := Folk.create("Ivo")
	intruder.household_id = 2
	W.add_folk(intruder, in0, int(u0["level"]))
	var sees_u0 := false
	for o in WorldIface.objects_for(intruder, 40):
		if o.level == u0["level"] and (u0["rect"] as Rect2i).has_point(o.tile):
			sees_u0 = true
	_check(not sees_u0, "another household standing in a flat is not offered its furniture")
	ApartmentUnits.release(u0)
	_check(ApartmentUnits.owner_of(u0) == 0 and not bool(ApartmentUnits.door_of(u0).state.get("locked", false)), "moving out frees the flat and unlocks the door")
