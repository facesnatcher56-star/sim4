extends RefCounted
## Office careers use their floor of the tower (Workplace.entry_tile(career).level): the commute still walks to the door, the worker is
## hidden INSIDE on his own floor (not the ground floor), walks home down the stairs / lift at the end of the shift. A doctor works at the
## hospital lot.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var wseed := _seed_with_tower()
	_check(wseed > 0, "a world seed that draws an office tower exists")
	if wseed <= 0:
		return fails
	var folk: Array = Kit.new_game("small", 777, wseed)
	var tower: String = Neighborhood.template_of("office")
	var floors: Dictionary = LotLoader.template(tower).get("career_floors", {})
	_check(floors.has("coder") and int(floors["coder"]) >= 1, "%s gives coders an upper floor (%s)" % [tower, str(floors)])
	_hooks()
	_coder_commute(folk[0], int(floors.get("coder", 1)))
	_hospital_doctor(folk[1])
	Kit.teardown()
	return fails


## The first world seed whose draw gives the office lot a tower.
func _seed_with_tower() -> int:
	for s in range(1, 60):
		if str(LotPicker.pick(s, "small")["office"]).begins_with("tower_"):
			return s
	return -1


func _hooks() -> void:
	var e: Dictionary = Workplace.entry_tile("coder")
	_check(e["tile"] == NeighborhoodLots.entry_tile("office") and int(e["level"]) >= 1, "entry_tile(coder) = the office door + the coder floor (%s)" % str(e))
	_check(int(Workplace.entry_tile("scientist")["level"]) > int(e["level"]), "scientists work higher up")
	_check(int(Workplace.entry_tile("barista")["level"]) == 0, "single-storey workplaces stay on the ground floor")
	var land: Vector2i = Workplace.landing_tile("office", int(e["level"]))
	_check(Kit.world().levels.is_walkable(land, int(e["level"])), "the landing of the coder floor is a walkable tile")


func _coder_commute(mira: Folk, floor_level: int) -> void:
	Careers.hire(mira, "coder", 1)
	WorldIface.coins[int(mira.household_id)] = 0
	Kit.set_time(2, 6, 30)
	var arrived := false
	for m in 3 * 60:
		Kit.run(1)
		if Kit.count_events("arrived_at_work") > 0:
			arrived = true
			break
	_check(arrived, "the coder arrived at work")
	Kit.run(3)
	_check(SysUtil.is_away(mira) and NeighborhoodLots.lot_at(mira.tile) == "office", "inside the tower")
	_check(mira.level == floor_level, "on the coder floor (level %d, expected %d)" % [mira.level, floor_level])
	_check(Kit.world().levels.is_walkable(mira.tile, mira.level), "standing on a walkable tile of that floor")
	var near_desk := false
	for o in Kit.world().all_objects():
		if o.level == mira.level and (str(o.def_id) in ["computer", "desk"]) and absi(o.tile.x - mira.tile.x) + absi(o.tile.y - mira.tile.y) <= 3:
			near_desk = true
	_check(near_desk, "next to a desk of her own floor")
	# the shift ends: she walks home from the upper floor by the stairs or the lift
	Away.recall(int(mira.id), "test")
	Kit.run(2)
	_check(Commute.trips.has(int(mira.id)) and str(Commute.trips[int(mira.id)]["state"]) == "home", "walking home")
	var plan: float = Workplace.commute_minutes(mira, NeighborhoodLots.entry_tile(Neighborhood.HOME))
	var left_floor := false
	for m in int(plan) + 60:
		Kit.run(1)
		if mira.level == 0 and NeighborhoodLots.lot_at(mira.tile) != "office":
			left_floor = true
		if NeighborhoodLots.lot_at(mira.tile) == Neighborhood.HOME:
			break
	_check(left_floor, "came down to the ground floor and out of the building")
	_check(NeighborhoodLots.lot_at(mira.tile) == Neighborhood.HOME and mira.level == 0, "home again (lot %s level %d)" % [NeighborhoodLots.lot_at(mira.tile), mira.level])


func _hospital_doctor(tobin: Folk) -> void:
	_check(Workplace.lot_for("doctor") == "hospital", "doctors work at the hospital")
	var e: Dictionary = Workplace.entry_tile("doctor")
	_check(e["tile"] == NeighborhoodLots.entry_tile("hospital") and int(e["level"]) == 0, "at the hospital door, ground floor (emergency)")
