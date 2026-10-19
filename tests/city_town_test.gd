extends RefCounted
## Task 12.5 / 12.6: street lamps, bins and litter, new amenities, holiday decoration, the ageing of pipes and cables; zoning, growth and construction over days.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := C.setup()
	C.home(w)
	K.set_time(10, 10)
	Story.generate_townies()
	CityGov.install()
	CityGov.ensure()
	CityPublic.ensure()
	var z: String = C.zone()
	# --- street lamps
	var full: int = CityPublic.total_lamps(z)
	K.expect(f, CityPublic.working_lamps(z) == full and CityPublic.lamp_equiv() == 8, "every lamp works in a new town (%d)" % full)
	var lamps_pts: float = float(CrimeRate.components()["lamps"])
	CityPublic.cfg()["lamp_break_per_day"] = 1.0
	CityPublic.on_day(SysUtil.day())
	K.expect(f, CityPublic.working_lamps(z) == 0 and CityPublic.lamp_equiv() == 0, "with every lamp broken the town is dark")
	K.expect(f, float(CrimeRate.components()["lamps"]) > lamps_pts, "dark streets count against the crime rate (%.1f vs %.1f)" % [float(CrimeRate.components()["lamps"]), lamps_pts])
	K.expect(f, K.has_note("street lamps are out") and CityPublic.quality() < 0.0, "the zone is told about it and the town does not like it")
	CityPublic.cfg()["lamp_break_per_day"] = 0.0
	CityPublic._week(CityPublic.cfg(), 1.0)
	K.expect(f, CityPublic.working_lamps(z) == 2, "crews fix two lamps a week at the standard budget")
	CityPublic._week(CityPublic.cfg(), 2.0)
	K.expect(f, CityPublic.working_lamps(z) == 6, "and more with a bigger budget")
	CityPublic._week(CityPublic.cfg(), 1.0)
	CityPublic._week(CityPublic.cfg(), 1.0)
	K.expect(f, CityPublic.working_lamps(z) == full and K.has_note("working again"), "then all are fixed and the zone is told")
	# --- bins and litter
	for d in 40:
		CityPublic._litter_day(z, CityPublic.cfg(), 1.0)
	K.expect(f, CityPublic.litter(z) > 0.5 and K.has_note("Rubbish"), "bins that are never emptied turn into litter")
	CityPublic.bin_fill[z] = 0.0
	for d2 in 30:
		CityPublic._litter_day(z, CityPublic.cfg(), 1.0)
		CityPublic.bin_fill[z] = 0.0
	K.expect(f, CityPublic.litter(z) < 0.1, "emptied bins and the litter goes away")
	# --- new amenities need a good parks budget and money
	CityGov.treasury = 0.0
	CityPublic.weeks_since_amenity = 99
	var before: int = 0
	for zz in CityPublic.amenities:
		for kk in CityPublic.amenities[zz]:
			before += int(CityPublic.amenities[zz][kk])
	CityPublic._week(CityPublic.cfg(), 1.2)
	var after: int = 0
	for zz2 in CityPublic.amenities:
		for kk2 in CityPublic.amenities[zz2]:
			after += int(CityPublic.amenities[zz2][kk2])
	K.expect(f, after == before, "no money, no new bench")
	var built_any: bool = false
	CityGov.treasury = 5000.0
	for i in 40:
		CityPublic.weeks_since_amenity = 99
		CityPublic._week(CityPublic.cfg(), 1.2)
		var n: int = 0
		for zz3 in CityPublic.amenities:
			for kk3 in CityPublic.amenities[zz3]:
				n += int(CityPublic.amenities[zz3][kk3])
		if n > before:
			built_any = true
			break
	K.expect(f, built_any and CityGov.treasury < 5000.0, "with money and a generous parks budget the town builds more benches, toilets, fountains and playgrounds")
	# --- holidays
	var hday: int = 1
	while Holidays.today(hday).is_empty() and hday < 400:
		hday += 1
	CityPublic.decor_until = -1
	CityPublic.on_day(hday)
	K.expect(f, CityPublic.decorated() or CityPublic.decor_until >= hday, "the town is decorated on a holiday")
	K.set_time(hday, 10)
	K.expect(f, CityPublic.decorated() and K.has_note("decorated"), "and the player hears about it")
	# --- ageing infrastructure
	CityPublic.age = 0.0
	var m0: float = CityBudget.maintenance_mult("utilities")
	CityBudget.set_funding("utilities", 0.5)
	for d3 in 300:
		CityPublic.on_day(100 + d3)
	K.expect(f, CityPublic.age > 0.3, "pipes and cables age when they are starved (%.2f)" % CityPublic.age)
	CityBudget.reset()
	K.expect(f, CityBudget.maintenance_mult("utilities") > m0, "and old equipment fails more often")
	var old_age: float = CityPublic.age
	CityBudget.set_funding("utilities", 1.4)
	for d4 in 100:
		CityPublic.on_day(500 + d4)
	CityBudget.reset()
	K.expect(f, CityPublic.age < old_age, "a generous utilities budget renews them")
	# --- town growth: zoning, scaffolding, workers, opening
	CityGov.treasury = 5000.0
	CityPlan.reset()
	var pop: int = StoryGrowth.population()
	Story.cfg()["max_population"] = pop
	K.expect(f, CityPlan.population_fill() >= 0.99, "the town is full")
	CityPlan.zoning = {"residential": 1.0, "commercial": 0.0, "civic": 0.0}
	var day0: int = SysUtil.day()
	CityPlan.on_day(day0 + 10)
	K.expect(f, CityPlan.projects.size() == 1 and str(CityPlan.projects[0]["state"]) == "scaffold" and CityGov.treasury < 5000.0, "a full town starts a project: scaffolding goes up and the town pays")
	K.expect(f, CityPlan.describe(CityPlan.projects[0]).find("Scaffolding") == 0, "in plain words: %s" % CityPlan.describe(CityPlan.projects[0]))
	var p0: Dictionary = CityPlan.projects[0]
	CityPlan.on_day(int(p0["scaffold_end"]))
	K.expect(f, str(p0["state"]) == "building" and int(p0["workers"]) >= 4, "then workers start building (%d)" % int(p0["workers"]))
	K.expect(f, CityPlan.describe(p0).find("workers are building") > 0, "also in words: %s" % CityPlan.describe(p0))
	CityPlan.on_day(int(p0["ready"]) - 1)
	K.expect(f, CityPlan.projects.size() == 1, "it takes days, not a moment")
	CityPlan.on_day(int(p0["ready"]))
	K.expect(f, CityPlan.projects.is_empty() and int(CityPlan.built["residential"]) == 1 and CityPlan.extra_capacity() == 4, "the flats open and the town can hold four more homes")
	K.expect(f, StoryGrowth.cfg().is_empty() == false and CityPlan.population_fill() < 1.0, "so the town is no longer full")
	# commercial and civic
	CityPlan.zoning = {"residential": 0.0, "commercial": 1.0, "civic": 0.0}
	Story.cfg()["max_population"] = pop - 5
	CityPlan.last_check = 0
	var rev0: float = CityGov.revenue(1.0)
	CityPlan.on_day(day0 + 400)
	CityPlan.on_day(int(CityPlan.projects[0]["ready"]) + 5)
	K.expect(f, int(CityPlan.built.get("commercial", 0)) == 1 and CityGov.revenue(1.0) > rev0, "shops raise the town's revenue")
	CityPlan.built["civic"] = 2
	CityGov.recompute()
	K.expect(f, CityBudget.funding("parks") > 1.05, "community centres add to the parks budget")
	CityPlan.built["civic"] = 0
	# money and limits
	CityGov.treasury = 0.0
	CityPlan.zoning = {"residential": 1.0, "commercial": 0.0, "civic": 0.0}
	CityPlan.projects.clear()
	CityPlan.last_check = 0
	Story.cfg()["max_population"] = pop - 20
	CityPlan.on_day(day0 + 600)
	K.expect(f, CityPlan.projects.is_empty(), "no money, no building")
	CityGov.treasury = 99999.0
	for k in 5:
		CityPlan.last_check = 0
		CityPlan.on_day(day0 + 700 + k * 10)
	K.expect(f, CityPlan.projects.size() <= 2, "at most two projects at a time (%d)" % CityPlan.projects.size())
	CityPlan.shift_zoning("civic")
	var zs: float = 0.0
	for kz in CityPlan.zoning:
		zs += float(CityPlan.zoning[kz])
	K.expect(f, float(CityPlan.zoning["civic"]) >= 0.049 and absf(zs - 1.0) < 0.001, "rezoning moves land from the other uses")
	# --- growth really lets more townies in
	CityPlan.built["residential"] = 5
	Story.cfg()["max_population"] = pop
	var c: Dictionary = Story.cfg()
	K.expect(f, StoryGrowth.population() < int(c["max_population"]) + CityPlan.extra_capacity(), "new housing lifts the population cap used by arrivals and births")
	# --- save and load
	var s0: String = JSON.stringify(CityState.to_dict())
	CityState.from_dict(JSON.parse_string(s0))
	K.expect(f, JSON.stringify(CityState.to_dict()) == s0, "public spaces and planning survive a JSON round trip")
	K.teardown()
	return f
