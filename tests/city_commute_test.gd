extends RefCounted
## Task 12.2 on the real map: a worker with a car drives to the office (shorter lead, fuel used, the car is parked at the office, and comes home with it);
## a worker without any vehicle takes the bus when it beats walking; the player's own lot trip uses the player's bike.

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
	Careers.hire(mira, "coder", 1)
	var hid: int = int(mira.household_id)
	WorldIface.coins[hid] = 6000
	CityState.reset()
	UtilityEvents.dice_on = false
	Kit.set_time(2, 6, 30)
	var door: Vector2i = NeighborhoodLots.entry_tile("office")
	var walk: float = Workplace.commute_minutes(mira, door)
	var lead_walk: float = Commute.lead_hours(mira) * 60.0
	# the bus network connects the home lot with the office (a change at the market)
	var bp: Dictionary = TransportBus.plan("market", "office")
	_check(bool(bp["ok"]), "the bus loop links the market and the office")
	var plan0: Dictionary = TransportTrip.plan(mira, door, {"commute": true})
	print("  [city] home -> office: walk %.0f min, best on foot/bus/taxi: %s %.0f min" % [walk, plan0["mode"], float(plan0["minutes"])])
	# a car at home
	var b: Dictionary = TransportCars.buy(hid, "hatch")
	var car: Dictionary = Transport.car(int(b["car"]))
	TransportCars.refuel(hid, int(car["id"]))
	var fuel0: float = float(car["fuel"])
	var lead_car: float = Commute.lead_hours(mira) * 60.0
	_check(str(TransportTrip.plan(mira, door, {"commute": true})["mode"]) == "car", "with a car at home the commute is by car (%s)" % str(TransportTrip.plan(mira, door, {"commute": true})["mode"]))
	_check(lead_car < lead_walk - 5.0, "the car shortens the lead time (%.0f vs %.0f min)" % [lead_car, lead_walk])
	var arrived_at := -1
	for m in 3 * 60:
		Kit.run(1)
		if Kit.count_events("arrived_at_work") > 0:
			arrived_at = SimEnv.now_min() % 1440
			break
	_check(arrived_at >= 0 and arrived_at <= 9 * 60 + 5, "arrived on time by car (minute %d)" % arrived_at)
	_check(int(Transport.stats.get("trips_car", 0)) == 1 and float(car["fuel"]) < fuel0, "one car trip, fuel used")
	Kit.run(3)
	_check(str(car["at"]) == "office" and str(car["spot"]) == "lot", "the car is parked at the office (%s / %s)" % [car["at"], car["spot"]])
	# the way home, by the same car (the shift is not played out: the walk home is started by hand)
	Commute._start_home(mira, Commute.trips[int(mira.id)])
	_check(Transport.active.has(str(mira.id)) and str(Transport.active[str(mira.id)]["mode"]) == "car", "the car brings them home")
	# the player's own lot trip with a bike (own vehicles only)
	Transport.active.clear()
	Transport.cars.clear()
	Transport.bikes[str(hid)] = 1
	mira.tile = NeighborhoodLots.entry_tile("home")
	var ride: Dictionary = TransportTrip.start(mira, door, {"own_only": true, "from_lot": "home", "to_lot": "office"})
	_check(str(ride["mode"]) == "bike", "a household with a bike rides it to a far lot")
	Kit.teardown()
	return fails
