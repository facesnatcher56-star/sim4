extends RefCounted
## Task 31 on the real map: the Ironbridge Works lot exists, every industrial career has stations and a way in, and a factory worker really
## commutes to the lot, works on it (visible work) and walks home.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	StoryPacing.enabled = false
	var mira: Folk = folk[0]
	for i in range(1, folk.size()):
		Careers.retired[int(folk[i].id)] = {"career": "", "level": 1, "pension": 0}
	CityState.reset()
	UtilityEvents.dice_on = false
	var W: Node = Kit.world()
	_check(Neighborhood.lots().size() == 16 and not Neighborhood.lot("works").is_empty(), "16 lots, one of them the works")
	var rg: Dictionary = W.regions.by_lot("works")
	_check(not rg.is_empty() and str(rg["venue_type"]) == "works", "the works is a venue region")
	var rc: Rect2i = rg["rect"]
	_check(Rect2i(0, 0, W.width, W.height).encloses(rc), "the works lot is inside the map")
	var door: Vector2i = NeighborhoodLots.entry_tile("works")
	_check(W.is_walkable(door) and W.path_length(NeighborhoodLots.entry_tile("home"), door) > 0.0, "the works door is walkable and reachable from home")
	for cid in Works.career_ids():
		_check(Workplace.lot_for(str(cid)) == "works", "%s works at the works lot" % cid)
		var st: Array = VisibleWork.stations("works", str(cid))
		_check(not st.is_empty(), "%s has stations on the lot (%d)" % [cid, st.size()])
		for o in st:
			_check(NeighborhoodLots.lot_at(o.tile) == "works" and W.is_walkable(WorldIface.use_tile(o, 0)), "%s station %s has a standing tile" % [cid, o.def_id])
	var bad: Array = LotLoader.unreachable_objects(W, door)
	_check(bad.is_empty(), "every object of the works is reachable: %s" % str(bad))
	# a real commute
	Careers.hire(mira, "factory_worker", 1)
	WorldIface.coins[int(mira.household_id)] = 500
	Kit.set_time(2, 5, 30)
	var arrived := -1
	for m in 4 * 60:
		Kit.run(1)
		if Kit.count_events("arrived_at_work") > 0:
			arrived = SimEnv.now_min() % 1440
			break
	_check(arrived >= 0 and arrived <= 7 * 60 + 10, "arrived at the works for the 07:00 shift (minute %d)" % arrived)
	Kit.run(20)
	_check(NeighborhoodLots.lot_at(mira.tile) == "works", "the worker is on the works lot during the shift")
	Kit.run(8 * 60)
	_check(Kit.count_events("returned_from_work") >= 1, "the shift ended and they walked home")
	Kit.teardown()
	return fails
