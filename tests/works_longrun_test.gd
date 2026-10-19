extends RefCounted
## Task 31, slow: how often industrial strikes and closures happen over years, how a recession changes it, and promotion cadence of every industrial career.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_rates(f)
	_cadence(f)
	return f

func _staff(w) -> void:
	Story.generate_townies(12)
	var adults: Array = []
	for tid in Story.townies:
		if Story.stage_of(Story.townies[tid]) == "adult":
			adults.append(tid)
	var ids: Array = Works.career_ids()
	for i in adults.size():
		Story.townies[adults[i]]["career"] = ids[i % ids.size()]

func _years(f: Array, days: int, prosperity: float, label: String) -> Dictionary:
	var w := K.setup(31)
	_staff(w)
	WorksEvents.reset()
	MarketEconomy.enabled = prosperity != 0.0
	MarketEconomy.prosperity = prosperity
	var t0: Dictionary = {}
	var restaff := 0
	for d in range(2, days + 2):
		K.set_time(d, 6)
		WorksEvents.on_day(d)
		if d % 30 == 0:
			_staff(w)          # closed firms hire again (the town's own job dice do this in the real game)
			restaff += 1
	var out := {"strike": int(WorksEvents.counts.get("strike", 0)), "closure": int(WorksEvents.counts.get("closure", 0))}
	print("  [works] %s: %d days, %d strikes, %d closures" % [label, days, out["strike"], out["closure"]])
	MarketEconomy.enabled = false
	MarketEconomy.prosperity = 0.0
	K.teardown()
	return out

func _rates(f: Array) -> void:
	var calm: Dictionary = _years(f, 1680, 0.0, "calm town (60 game years of 28 days)")
	var slump: Dictionary = _years(f, 1680, -0.6, "deep recession")
	var per_year_calm: float = float(calm["strike"]) / 60.0
	K.expect(f, per_year_calm > 0.3 and per_year_calm < 8.0, "a calm town sees an industrial strike every month or two across five trades (%.1f)" % per_year_calm)
	K.expect(f, float(calm["closure"]) / 60.0 < 3.0, "closures are rare in a calm town (%.2f a year)" % (float(calm["closure"]) / 60.0))
	K.expect(f, int(slump["closure"]) > int(calm["closure"]) * 2 and int(slump["strike"]) > int(calm["strike"]), "a recession brings more closures and strikes (%d/%d vs %d/%d)" % [slump["closure"], slump["strike"], calm["closure"], calm["strike"]])

func _cadence(f: Array) -> void:
	for cid in Works.career_ids():
		var w := K.setup(2000 + str(cid).length())
		var cd: Dictionary = Careers.career_def(cid)
		var a = K.make_folk(w, "Pro")
		for s in ["handiness", "fitness", "logic", "charisma"]:
			a.add_skill_xp(s, Folk.xp_for_level(10) + 1)
		var fid := int(a.id)
		Careers.hire(a, cid, 1)
		var shifts := 0
		var last := 1
		var per: Array = []
		var day := 1
		var guard := 0
		while Careers.level_of(fid) < 5 and guard < 120:
			guard += 1
			day += 1
			K.set_time(day, 12)
			var t0: Dictionary = (cd["tasks"] as Array)[0]
			for n in int(t0["count"]):
				CareerProgress.on_interaction(fid, str((t0["interactions"] as Array)[0]), true)
			CareerShifts.on_returned(a, {"reason": "work", "completed": true, "worked_min": 480.0, "data": {}})
			shifts += 1
			if Careers.level_of(fid) != last:
				per.append(shifts)
				shifts = 0
				last = Careers.level_of(fid)
		K.expect(f, Careers.level_of(fid) >= 4, "%s reaches level 4 (stuck at %d)" % [cid, Careers.level_of(fid)])
		for n2 in per:
			K.expect(f, int(n2) >= 3 and int(n2) <= 14, "%s promotion cadence %s shifts per level is out of 3..14" % [cid, str(per)])
		K.teardown()
