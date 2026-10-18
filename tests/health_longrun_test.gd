extends RefCounted
## SLOW tier: many game years of households living together with the default Surprises setting. Measured per household-year:
## colds about 2-4, flu about 0.5, deaths from illness under 0.02 (and none from needs, exposure or injury while everyone is looked after).

const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	_illness(f)
	return f

func _release_patients() -> void:
	for id in Hospital.patients.keys():
		Hospital.discharge(int(id))

func _illness(f: Array) -> void:
	var w := K.setup()
	SysContent.install_all()
	Incidents.reset()
	Weather.force("sunny")
	var hh_n: int = 8
	var members: Array = []
	for h in hh_n:
		var hid: int = h + 1
		WorldIface.coins[hid] = 1000000
		var base := Vector2i(5 + (h % 4) * 40, 5 + (h / 4) * 40)
		members.append(K.make_folk(w, "A%d" % h, [], hid, base))
		members.append(K.make_folk(w, "B%d" % h, [], hid, base + Vector2i(2, 0)))
		if h % 3 == 0:
			var e := K.make_folk(w, "E%d" % h, [], hid, base + Vector2i(4, 0), "elder")
			Aging.set_age_days(e, 150.0)
			members.append(e)
		else:
			members.append(K.make_folk(w, "C%d" % h, [], hid, base + Vector2i(4, 0), "child"))
	var years: int = TestFixture.pick(14, 5)
	var deaths: Dictionary = {}
	var d0: int = 2
	for d in years * YEAR:
		for hr in 24:
			K.set_time(d0 + d, hr)
			for fk in w.all_folk():
				fk.tick_buffs(60.0)
				for n in ["hunger", "energy", "hygiene"]:
					fk.needs[n].set_value(60.0)       # everybody is looked after: needs deaths must not happen
			Incidents.on_hour()
			if hr % 6 == 0:
				Incidents.on_minute()
			_release_patients()
		K.set_time(d0 + d, 23, 59)
		Incidents.on_minute()
		Incidents.on_day()
		for e2 in K.events:
			if e2[0] == "died":
				deaths[str(e2[1].get("cause", ""))] = int(deaths.get(str(e2[1].get("cause", "")), 0)) + 1
		K.events.clear()
		for i in members.size():                      # keep the households whole
			var m = members[i]
			if w.get_folk(m.id) == null:
				var nm := K.make_folk(w, "R%d_%d" % [i, d], [], m.household_id, m.tile, m.age_stage)
				if m.age_stage == "elder":
					Aging.set_age_days(nm, 150.0)
				members[i] = nm
	var hh_years: float = float(hh_n * years)
	var cold: int = int(Incidents.stat("catch_cold")["triggered"])
	var flu: int = int(Incidents.stat("catch_flu")["triggered"])
	var illness_deaths: int = int(deaths.get("illness", 0))
	var cold_r: float = float(cold) / hh_years
	var flu_r: float = float(flu) / hh_years
	var death_r: float = float(illness_deaths) / hh_years
	K.expect(f, cold_r >= 2.0 and cold_r <= 4.0, "colds per household-year %.2f (target 2 to 4)" % cold_r)
	K.expect(f, flu_r >= 0.3 and flu_r <= 0.8, "flu per household-year %.2f (target about 0.5)" % flu_r)
	K.expect(f, death_r < 0.02, "illness deaths per household-year %.4f (target < 0.02), %d deaths" % [death_r, illness_deaths])
	var others: int = 0
	for c in ["starvation", "exhaustion", "hypothermia", "heatstroke"]:
		others += int(deaths.get(c, 0))
	K.expect(f, others == 0, "no needs / exposure deaths when everyone is looked after (%d)" % others)
	print("    longrun health: %d years x %d households: cold %.2f, flu %.2f, illness deaths %.4f (%d), worsened %d, exposed marks %d" % [years, hh_n, cold_r, flu_r, death_r,
		illness_deaths, int(Incidents.stat("illness_worsens")["triggered"]), int(Health.counters.get("exposed", 0))])
	K.teardown()
