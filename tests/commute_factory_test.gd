extends RefCounted
## A factory worker on the real map (Ironbridge Works in the east column, about 150 tiles from the home plot) reaches the gate on
## time on day 1 and day 3 (hired the evening before), and one hired at 07:00 on day 1 (game start, shift already begun) is not
## marked late or missing: the first shift is tomorrow's.

const Kit = preload("res://tests/hood_kit.gd")

func run() -> Array:
	var fails: Array = []
	for ws in [1, 2, 3]:
		_on_time(fails, ws)
	_hired_after_start(fails)
	return fails

func _setup() -> Folk:
	var folk: Array = Kit.new_game("classic", 777, 1)
	StoryPacing.enabled = false
	for i in range(1, folk.size()):
		Careers.retired[int(folk[i].id)] = {"career": "", "level": 1, "pension": 0}
	return folk[0]

func _on_time(fails: Array, ws: int) -> void:
	var folk: Array = Kit.new_game("classic", 777, ws)
	StoryPacing.enabled = false
	for i in range(1, folk.size()):
		Careers.retired[int(folk[i].id)] = {"career": "", "level": 1, "pension": 0}
	var ken: Folk = folk[0]
	Kit.set_time(1, 4)
	Careers.hire(ken, "factory_worker", 1)
	var door: Vector2i = NeighborhoodLots.entry_tile("works")
	print("  world %d: home %s -> works door %s, %d tiles, walk %.0f min, lead %.2f h" % [ws, ken.tile, door, WorldIface.path_length(ken.tile, door), Workplace.commute_minutes(ken, door), Commute.lead_hours(ken)])
	for day in [1, 3]:
		Kit.events.clear()
		Kit.set_time(day, 4)
		ken.tile = NeighborhoodLots.entry_tile("home")
		Careers.jobs[int(ken.id)]["attempt_day"] = -1
		Commute.trips.erase(int(ken.id))
		var arrived: int = -1
		var started: int = -1
		for m in 6 * 60:
			Kit.run(1)
			if started < 0 and Kit.count_events("left_for_work") > 0:
				started = SimEnv.now_min() % 1440
			if Kit.count_events("arrived_at_work") > 0:
				arrived = SimEnv.now_min() % 1440
				break
			if Kit.count_events("missed_shift") > 0:
				break
		if not (arrived >= 0 and arrived <= 7 * 60 + 5):
			fails.append("world %d day %d: arrived at minute %d (left %d), needs <= %d" % [ws, day, arrived, started, 7 * 60 + 5])
		Away.active.erase(int(ken.id))
		Away.pending.erase(int(ken.id))
	Kit.teardown()

func _hired_after_start(fails: Array) -> void:
	var ken: Folk = _setup()
	Kit.set_time(1, 7)
	Careers.hire(ken, "factory_worker", 1)
	Kit.run(4 * 60)
	if Kit.count_events("missed_shift") > 0 or Kit.count_events("late_for_work") > 0 or Kit.count_events("left_for_work") > 0:
		fails.append("hired at 07:00 on day 1: no commute, late or missed shift today (left %d, late %d, missed %d)" % [Kit.count_events("left_for_work"), Kit.count_events("late_for_work"), Kit.count_events("missed_shift")])
	if not Kit.has_note("starts at the factory worker tomorrow"):
		fails.append("the new hire is told the first shift is tomorrow")
	Kit.events.clear()
	Kit.set_time(2, 4)
	Kit.run_until(func(): return Kit.count_events("arrived_at_work") > 0 or Kit.count_events("missed_shift") > 0, 6 * 60)
	if Kit.count_events("arrived_at_work") == 0 or SimEnv.now_min() % 1440 > 7 * 60 + 5:
		fails.append("day 2: arrived on time (minute %d)" % (SimEnv.now_min() % 1440))
	Kit.teardown()
