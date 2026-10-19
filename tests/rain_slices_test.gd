extends RefCounted
## Rain on plants (task 17.4): the hourly pass only counts an owed hour per lot; RainSlices waters the lots a few per minute (two-phase: outdoor tests first,
## then the writes); the daily catch-up takes what is left. Same total water as watering at once.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _plant_somewhere() -> int:
	var w = WorldIface.world()
	for y in range(2, w.height - 2):
		for x in range(2, w.width - 2):
			var t := Vector2i(x, y)
			if w.is_walkable(t) and bool(w.is_outdoor(t, 0)) and w.object_at(t) == null:
				var id: int = w.place_object("plant", t)
				if id >= 0:
					return id
	return -1

func run() -> Array:
	fails = []
	HoodKit.teardown()
	HoodKit.new_game("classic", 11, 11)
	var w = WorldIface.world()
	var pid: int = _plant_somewhere()
	var p = w.get_object(pid) if pid >= 0 else null
	_check(p != null, "a plant was placed: %s" % str(w.last_error))
	if p == null:
		HoodKit.teardown()
		return fails
	var amt: float = float(Weather.effects().get("garden", {}).get("plant_rain_water_per_hour", 0.8))
	var lot: String = NeighborhoodLots.lot_at(p.tile)
	p.state["water"] = 1.0
	Weather._rain_deferred.clear()
	Weather._rain_deferred[lot] = 2
	_check(RainSlices.active(), "owed rain makes the row active")
	_check(RainSlices.due_lots().has(lot), "the lot is due (no anchor far away)")
	RainSlices.run()
	_check(Weather._rain_deferred.is_empty(), "the watered lot's count is paid")
	_check(absf(float(p.state["water"]) - (1.0 + 2.0 * amt)) < 0.01, "two owed hours water the plant by 2 x the hourly amount (%s)" % str(p.state["water"]))
	_check(not RainSlices.active(), "idle again = zero cost")
	# spread: many owed lots are not all done in one minute
	for i in 40:
		Weather._rain_deferred["fake_%02d" % i] = 1
	RainSlices.run()
	_check(Weather._rain_deferred.size() == 40 - maxi(RainSlices.MIN_BATCH, ceili(40.0 / RainSlices.SPREAD)), "a minute pays only max(2, 40 / 12) lots (left %d)" % Weather._rain_deferred.size())
	var guard := 0
	while RainSlices.active() and guard < 100:
		RainSlices.run()
		guard += 1
	_check(guard <= 20 and not RainSlices.active(), "all owed lots are paid within the spread (%d minutes)" % guard)
	# the daily catch-up still waters what is owed (no scheduler slices in a bare call)
	p.state["water"] = 0.0
	Weather._rain_deferred[lot] = 3
	WeatherWorld.on_day(1, false)
	_check(absf(float(p.state["water"]) - minf(3.0 * amt, 10.0)) < 0.01, "the daily catch-up waters owed hours (%s)" % str(p.state["water"]))
	_check(Weather._rain_deferred.is_empty(), "catch-up clears the debt")
	HoodKit.teardown()
	return fails
