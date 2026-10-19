extends RefCounted
## SLOW tier (task 05): many game years of exposure. (1) With an exposure marker held on, the measured rate of every accident equals its data
## rate; with the documented exposure the per-person-year targets hold. (2) Deaths stay extremely rare compared with injuries.
## (3) Ten game years of the whole far town run through the hourly markers + dice (statistical): rates in a sane band, nothing stacks.

const K = preload("res://tests/systems_kit.gd")
const YEAR := 28
const IDS := ["drowning_scare", "kids_near_water", "choking", "electric_shock", "slip_fall", "traffic_hit", "kids_near_road", "workout_injury", "workplace_injury"]
## marker(s) that hold the exposure + the age stage to test with
const SETUP := {
	"drowning_scare": [["acc_water"], "adult"], "kids_near_water": [["acc_near_water", "acc_unsupervised"], "child"], "choking": [["acc_eating"], "adult"],
	"electric_shock": [["acc_repair_electric"], "adult"], "slip_fall": [["acc_slippery"], "adult"], "traffic_hit": [["acc_on_road"], "adult"],
	"kids_near_road": [["acc_near_road", "acc_unsupervised"], "child"], "workout_injury": [["acc_exercise"], "adult"], "workplace_injury": [["acc_job_risky"], "adult"],
}

func run() -> Array:
	var f: Array = []
	_exposed_rates(f)
	_death_budget(f)
	_town_years(f)
	return f

func _near_rel(measured: float, target: float, tol: float) -> bool:
	return absf(measured / target - 1.0) <= tol

func _world() -> StubWorld:
	var w := K.setup()
	IncidentDefs.reset()
	Incidents.reset()
	IncidentContent.install()
	Incidents.set_level("rare")
	Weather.unforce()
	return w

func _release() -> void:
	for id in Hospital.patients.keys():
		Hospital.discharge(int(id))

## Hold the marker on for a number of person-years of exposure and compare measured (triggered / exposure) with the data rate.
func _exposed_rates(f: Array) -> void:
	var targets: Dictionary = (IncidentDefs.cfg("accidents", {}) as Dictionary).get("targets", {})
	for id in IDS:
		var w := _world()
		Incidents.seed_rng(1000 + IDS.find(id))
		var stage: String = str(SETUP[id][1])
		var folk: Array = []
		for i in 10:
			var fk := K.make_folk(w, "P%d" % i, [], 1 + i, Vector2i(5 + i, 5), stage)
			fk.skills["fitness"]["level"] = 3          # neutral for every skill based multiplier
			fk.skills["handiness"]["level"] = 3
			folk.append(fk)
		var years: int = TestFixture.pick(4, 3)
		var def: Dictionary = IncidentDefs.get_def(id)
		for m0 in SETUP[id][0]:
			folk[0].add_buff(m0)
		var expect_rate: float = Incidents.effective_rate(id, folk[0])
		K.expect(f, expect_rate > 0.0, "%s: the exposure markers make the incident possible" % id)
		for h in years * YEAR * 24:
			for fk2 in folk:
				for m in SETUP[id][0]:
					if not fk2.has_buff(m):
						fk2.add_buff(m)
			K.set_time(2 + h / 24, h % 24)
			for fk4 in folk:
				if not Hospital.is_in(fk4):
					IncidentChecks._roll(id, def, IncidentSubject.of_folk(fk4))
			K.set_time(2 + h / 24, h % 24, 30)
			Incidents.on_minute()                  # warned accidents come due (nobody rescues here)
			if h % 24 == 23:
				_release()
				for i2 in folk.size():             # the rare death: a fresh person takes the place
					if w.get_folk(folk[i2].id) == null:
						folk[i2] = K.make_folk(w, "R%d_%d" % [i2, h], [], 20 + i2, Vector2i(5 + i2, 7), stage)
						folk[i2].skills["fitness"]["level"] = 3
						folk[i2].skills["handiness"]["level"] = 3
			if h % 6 == 5:
				for fk3 in folk:                   # alive, healthy, in place: the exposure sample stays the same size
					fk3.remove_buff("injured")
					fk3.remove_buff("shaken_up")
		var st: Dictionary = Incidents.stat(id)
		if int(st["triggered"]) < 8:
			f.append("%s: too few events to measure (%d)" % [id, int(st["triggered"])])
			K.teardown()
			continue
		var measured: float = Incidents.measured_rate(id)
		K.expect(f, _near_rel(measured, expect_rate, maxf(0.35, 3.0 / sqrt(float(st["triggered"])))), "%s: measured %.3f vs data %.3f per exposure-year (%d events)" % [id, measured, expect_rate, int(st["triggered"])])
		var t: Dictionary = targets[id]
		print("  [accidents] %-18s measured %.3f vs data %.3f per exposure-year (%d events, %d person-years)" % [id, measured, expect_rate, int(st["triggered"]), years * 10])
		var per_year: float = float(def["base_rate_per_year"]) * float(t["checks_per_year"]) / 672.0
		K.expect(f, _near_rel(per_year, float(t["per_person_year"]), 0.1), "%s: %.3f per person-year at the documented exposure" % [id, per_year])
		K.teardown()

## Weighted death chance per accident over all conditions (alone / not alone), times the yearly rates: a household may never see one.
func _death_budget(f: Array) -> void:
	var w := _world()
	var targets: Dictionary = (IncidentDefs.cfg("accidents", {}) as Dictionary).get("targets", {})
	var deaths_per_person_year: float = 0.0
	var injuries_per_person_year: float = 0.0
	var a := K.make_folk(w, "Ada", [], 1)
	for id in targets:
		var outs: Array = IncidentDefs.get_def(id)["outcomes"]
		var lethal: float = 0.0
		var hurt: float = 0.0
		var tot: float = 0.0
		# typical company: alone a quarter of the time
		for alone in [true, false]:
			var share: float = 0.25 if alone else 0.75
			if alone:
				a.add_buff("acc_alone")
				a.add_buff("acc_unsupervised")
			else:
				a.remove_buff("acc_alone")
				a.remove_buff("acc_unsupervised")
			a.add_buff("acc_slippery")
			var subj = IncidentSubject.of_folk(a)
			var w_sum: float = 0.0
			var w_dead: float = 0.0
			var w_hurt: float = 0.0
			for o in outs:
				if not IncidentCond.check(o.get("when", []), subj):
					continue
				var wt: float = float(o["weight"])
				w_sum += wt
				var args: Dictionary = o["effects"][0].get("args", {})
				if str(args.get("kill", "")) != "":
					w_dead += wt
				elif int(args.get("severity", 0)) > 0:
					w_hurt += wt
			lethal += share * w_dead / w_sum
			hurt += share * w_hurt / w_sum
			tot += share
		var py: float = float(targets[id]["per_person_year"])
		deaths_per_person_year += py * lethal / tot
		injuries_per_person_year += py * hurt / tot
		a.remove_buff("acc_slippery")
	var per_household: float = deaths_per_person_year * 3.0
	K.expect(f, per_household > 0.0 and per_household < 0.005, "accident deaths per household-year: %.5f (a household of three over 8 years: %.1f percent)" % [per_household, per_household * 8.0 * 100.0])
	K.expect(f, injuries_per_person_year > deaths_per_person_year * 15.0, "injuries (%.3f) far outnumber deaths (%.5f) per person-year" % [injuries_per_person_year, deaths_per_person_year])
	print("  [accidents] deaths/household-year %.5f, injuries/person-year %.3f" % [per_household, injuries_per_person_year])
	K.teardown()

## The whole far town for several game years through the hourly markers + statistical dice.
func _town_years(f: Array) -> void:
	var w := _world()
	K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	Incidents.seed_rng(77)
	var ids: Array = Story.townies.keys()
	var n: int = ids.size()
	var years: int = TestFixture.pick(7, 3)
	var t0: int = Time.get_ticks_msec()
	var deaths: int = 0
	var hospital_deaths: int = 0
	var buffs_max: int = 0
	var weather_ids := ["sunny", "rain", "snow", "sunny"]
	for d in years * YEAR:
		K.set_time(2 + d, 0)
		var wx: String = weather_ids[(d / 3) % 4]
		Weather.force(wx, 0.6 if wx == "snow" else 0.0)
		Weather._wet = 0.7 if wx == "rain" else 0.0
		for h in 24:
			K.set_time(2 + d, h)
			AccidentMarks.on_hour(h)
			Hospital.on_hour()
			for id3 in IDS:
				var def3: Dictionary = IncidentDefs.get_def(id3)
				for s3 in IncidentChecks.townie_subjects(true):
					IncidentChecks._roll(id3, def3, s3)
		for tid in ids:
			var t: Dictionary = Story.townies[tid]
			if not bool(t["alive"]):
				if str(t.get("cause", "")).begins_with("accident_"):
					deaths += 1
				else:
					hospital_deaths += 1
				t["alive"] = true                  # keep the sample size: count the death, bring the record back
			buffs_max = maxi(buffs_max, (t.get("buffs", []) as Array).size())
		_release()
		for tid2 in ids:
			Story.townies[tid2]["in_hospital"] = false
	Weather.unforce()
	Weather._wet = 0.0
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var totals: Dictionary = {}
	var sum: int = 0
	for id in IDS:
		var c: int = int(Incidents.stat(id)["statistical"])
		totals[id] = c
		sum += c
	var per_townie_year: float = float(sum) / float(n * years)
	print("  [accidents] %d townies, %d years: %s, accident deaths %d (+%d in hospital stays), %.1fs" % [n, years, str(totals), deaths, hospital_deaths, secs])
	K.expect(f, sum > 0 and per_townie_year > 0.05 and per_townie_year < 3.0, "accidents per townie-year in a sane band: %.2f" % per_townie_year)
	K.expect(f, float(deaths) / float(n * years) < 0.01, "accident deaths per townie-year stay tiny (%d deaths)" % deaths)
	for id2 in ["choking", "slip_fall", "traffic_hit"]:
		K.expect(f, int(totals[id2]) > 0, "%s happens to somebody in %d years of town life" % [id2, years])
	K.expect(f, buffs_max < 30, "marker buffs never pile up on a townie record (max %d)" % buffs_max)
	K.expect(f, Hospital.patients.size() <= n, "no stuck patients")
	K.teardown()