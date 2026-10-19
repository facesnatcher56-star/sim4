extends RefCounted
## Task 12.3 long run (slow tier): average response times of the three services over every lot and every hour, against the targets in data/services.json,
## and what a starved budget does to them.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _mean(service: String, calls: int) -> float:
	var lots: Array = []
	for l in Neighborhood.lots():
		lots.append(str((l as Dictionary).get("id", "")))
	var total: float = 0.0
	for i in calls:
		CityServices.reset()                                                  # every call finds its station at full strength
		Kit.set_time(3 + (i % 5), (i * 7) % 24, (i * 13) % 60)
		total += float(CityServices.dispatch(service, str(lots[i % lots.size()]))["minutes"])
	return total / float(calls)

func run() -> Array:
	fails = []
	Kit.new_game("small")
	CityState.reset()
	UtilityEvents.dice_on = false
	Weather.force("sunny")
	var targets: Dictionary = CityServices.cfg().get("targets", {})
	var base: Dictionary = {}
	for s in ["fire", "ambulance", "police"]:
		base[s] = _mean(s, 2400)
		var t: float = float(targets[s])
		_check(base[s] > t * 0.6 and base[s] < t * 1.7, "%s: average response %.1f min, target %.0f" % [s, base[s], t])
		print("  [city] %s average response %.1f min (target %.0f)" % [s, base[s], t])
	CityBudget.set_funding("fire", 0.5)
	CityBudget.set_funding("health", 0.5)
	CityBudget.set_funding("police", 0.5)
	for s2 in ["fire", "ambulance", "police"]:
		var poor: float = _mean(s2, 2400)
		_check(poor > float(base[s2]) * 1.05, "%s: a starved budget is slower (%.1f vs %.1f min)" % [s2, poor, base[s2]])
	CityBudget.reset()
	Kit.teardown()
	return fails
