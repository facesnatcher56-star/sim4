extends RefCounted
## SLOW tier: many game years of the stub world with the default Surprises setting. The measured rate (events per subject-year that
## passed the conditions) of the seed incidents must be close to the data targets, and nothing may crash, stack or grow without bound.

const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	_daily(f)
	_hourly(f)
	_levels(f)
	return f

func _near_rel(measured: float, target: float, tol: float) -> bool:
	return absf(measured / target - 1.0) <= tol

func _elder(w: StubWorld, nm: String, hid: int) -> Folk:
	var e := K.make_folk(w, nm, [], hid, Vector2i(10 + hid, 10), "elder")
	Aging.set_age_days(e, 150.0)
	e.skills["fitness"]["level"] = 3          # no fitness multiplier either way
	return e

func _release_patients() -> void:
	for id in Hospital.patients.keys():
		Hospital.discharge(int(id))

func _daily(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	Incidents.set_level("rare")
	Weather.force("sunny")
	for h in 3:
		K.make_folk(w, "Adult%d" % h, [], h + 1, Vector2i(5 + h, 5))
	var elders: Array = []
	for i in 20:
		elders.append(_elder(w, "Elder%d" % i, 1 + i % 3))
	Story.generate_townies()
	var years: int = TestFixture.pick(120, 40)
	var deaths: int = 0
	for d in years * YEAR:
		K.set_time(2 + d, 3)
		Incidents.on_day()
		K.set_time(2 + d, 5)
		Incidents.on_minute()          # warnings that came due (2 hours later) turn into their outcome
		for i in elders.size():
			if w.get_folk(elders[i].id) == null:
				deaths += 1
				elders[i] = _elder(w, "Elder%d_%d" % [i, d], 1 + i % 3)
		_release_patients()
		K.set_time(2 + d, 23)
		Hospital.on_hour()
		while Story.alive_townies().size() < 12:
			Story.add_townie()
		if Incidents.active().size() > 40:
			f.append("pending warnings pile up (%d)" % Incidents.active().size())
			break
	var ha: Dictionary = Incidents.stat("heart_attack")
	var fm: Dictionary = Incidents.stat("found_money")
	var tm: Dictionary = Incidents.stat("townie_mishap")
	var r_ha: float = Incidents.measured_rate("heart_attack")
	K.expect(f, int(ha["triggered"]) >= 15 and _near_rel(r_ha, 0.02, 0.4), "heart_attack: %d events in %.0f elder-years = %.4f/yr (target 0.02)" % [int(ha["triggered"]), float(ha["exposure"]), r_ha])
	var r_fm: float = Incidents.measured_rate("found_money")
	K.expect(f, _near_rel(r_fm, 1.0, 0.2), "found_money: %d events in %.1f household-years = %.3f/yr (target 1.0; home + 6 townie lots)" % [int(fm["triggered"]), float(fm["exposure"]), r_fm])
	var r_tm: float = Incidents.measured_rate("townie_mishap")
	K.expect(f, int(tm["triggered"]) > 30 and _near_rel(r_tm, 0.15, 0.3), "townie_mishap: %d events = %.3f/yr (target 0.15)" % [int(tm["triggered"]), r_tm])
	K.expect(f, deaths >= 1 and deaths <= int(ha["triggered"]), "some heart attacks killed (%d) but not all of them" % deaths)
	K.expect(f, Incidents.history(1000).size() <= int(IncidentDefs.cfg("history_cap", 200)), "history stays capped")
	K.expect(f, Graves.list().size() >= deaths and Graves.list().size() < 5000, "graves recorded (%d)" % Graves.list().size())
	print("    longrun daily: %d years, heart %d/%.0fy, found %d/%.0fy, townie %d/%.0fy, elder deaths %d, graves %d" % [years, int(ha["triggered"]), float(ha["exposure"]),
		int(fm["triggered"]), float(fm["exposure"]), int(tm["triggered"]), float(tm["exposure"]), deaths, Graves.list().size()])
	Weather.unforce()
	K.teardown()

func _hourly(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	Incidents.set_level("rare")
	Weather.force("sunny")
	var folk: Array = []
	for i in 12:
		folk.append(K.make_folk(w, "Adult%d" % i, [], 1 + i % 3, Vector2i(5 + i, 5)))
	var years: int = TestFixture.pick(16, 6)
	for h in years * YEAR * 24:
		K.set_time(2 + h / 24, h % 24)
		Incidents.on_hour()
		if h % 24 == 23:
			_release_patients()
			for fk in folk:
				fk.remove_buff("injured")
	var fall: Dictionary = Incidents.stat("minor_fall")
	var r: float = Incidents.measured_rate("minor_fall")
	K.expect(f, int(fall["triggered"]) >= 40 and _near_rel(r, 0.5, 0.25), "minor_fall: %d falls in %.0f folk-years = %.3f/yr (target 0.5)" % [int(fall["triggered"]), float(fall["exposure"]), r])
	K.expect(f, Hospital.patients.size() <= folk.size() + 12, "no stacking of hospital patients")
	print("    longrun hourly: %d years, falls %d/%.0fy" % [years, int(fall["triggered"]), float(fall["exposure"])])
	Weather.unforce()
	K.teardown()

func _levels(f: Array) -> void:
	for pair in [["off", 0.0], ["normal", 3.0], ["chaotic", 10.0]]:
		var w := K.setup()
		Incidents.reset()
		Incidents.set_level(pair[0])
		K.make_folk(w, "Ada", [], 1)
		K.make_folk(w, "Bo", [], 2)
		var years: int = TestFixture.pick(40, 20)
		for d in years * YEAR:
			K.set_time(2 + d, 3)
			Incidents.on_day()
		var fm: Dictionary = Incidents.stat("found_money")
		if float(pair[1]) == 0.0:
			K.expect(f, int(fm["triggered"]) == 0, "Off: no found_money in %d years" % years)
		else:
			var r: float = Incidents.measured_rate("found_money")
			K.expect(f, _near_rel(r, float(pair[1]), 0.2), "%s: found_money %.2f/yr (target %.1f)" % [pair[0], r, float(pair[1])])
		K.teardown()
