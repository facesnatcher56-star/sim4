extends RefCounted
## Task 12.5 / 12.6 long run (slow tier): twelve game years of the town's daily upkeep at the standard budget and at a starved one: lamps, litter, ageing, and how fast
## a full town builds new housing.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

const YEARS := 12

func _years(parks: float, util: float, f: Array, label: String) -> Dictionary:
	CityPublic.reset()
	CityPlan.reset()
	CityGov.treasury = 0.0
	CityBudget.set_funding("parks", parks)
	CityBudget.set_funding("utilities", util)
	var lamp_sum: float = 0.0
	var litter_sum: float = 0.0
	var days: int = YEARS * 28
	for d in days:
		K.set_time(10 + d, 10)
		Story.cfg()["max_population"] = StoryGrowth.population() - CityPlan.extra_capacity()          # the town is always full: the planners always want to build
		if d % 7 == 0:
			CityGov.budget_week(false)
		CityGov.on_day(SysUtil.day())
		lamp_sum += CityPublic.lamp_share()
		var l: float = 0.0
		for z in CityState.zone_ids():
			l += CityPublic.litter(str(z))
		litter_sum += l / 4.0
	return {"lamps": lamp_sum / float(days), "litter": litter_sum / float(days), "age": CityPublic.age, "built": CityPlan.built.duplicate(), "treasury": CityGov.treasury}

func run() -> Array:
	var f: Array = []
	C.setup()
	Story.generate_townies()
	CityGov.install()
	CityGov.ensure()
	Story.cfg()["max_population"] = StoryGrowth.population()          # the town is always full: the planners always want to build
	var good: Dictionary = _years(1.0, 1.0, f, "standard")
	var poor: Dictionary = _years(0.5, 0.5, f, "starved")
	print("  [city] standard budget over %d years: lamps %.2f, litter %.2f, age %.2f, built %s, savings %.0f" % [YEARS, good["lamps"], good["litter"], good["age"], str(good["built"]), good["treasury"]])
	print("  [city] starved budget: lamps %.2f, litter %.2f, age %.2f, built %s" % [poor["lamps"], poor["litter"], poor["age"], str(poor["built"])])
	K.expect(f, float(good["lamps"]) > 0.6, "at the standard budget most lamps work (%.2f)" % float(good["lamps"]))
	K.expect(f, float(poor["lamps"]) < float(good["lamps"]) - 0.1, "a starved parks budget leaves more of them dark (%.2f)" % float(poor["lamps"]))
	K.expect(f, float(good["litter"]) < 0.3 and float(poor["litter"]) > float(good["litter"]) + 0.1, "and more litter (%.2f vs %.2f)" % [float(poor["litter"]), float(good["litter"])])
	K.expect(f, float(good["age"]) < 0.3 and float(poor["age"]) > 0.4, "pipes and cables age slowly when funded and fast when starved (%.2f vs %.2f)" % [float(good["age"]), float(poor["age"])])
	var total: int = 0
	for k in good["built"]:
		total += int(good["built"][k])
	K.expect(f, total >= 2 and total <= 12 * 2, "a full town gets a few new projects over %d years, not none and not a boom (%d)" % [YEARS, total])
	CityBudget.reset()
	K.teardown()
	return f
