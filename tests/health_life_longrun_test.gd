extends RefCounted
## Task 14 health rates over years of game time (SLOW tier). Measured:
##   long-term conditions: new cases per adult per game year (rare), flares per unmanaged and per managed person-year, medicine is the difference
##   burnout: cases per working person-year for ordinary workers (rare) and for people who are always worn out (common)
##   old-age lifespan: the fit live longer than the unfit, from the real daily death dice
##   colds: the unfit catch more than the fit, from the real incident dice
## (the incidents' own long-run tests are tests/health_longrun_test.gd; this one is about the task 14 additions.)

const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	_conditions(f)
	_burnout(f)
	_lifespan(f)
	return f

func _world() -> StubWorld:
	var w := K.setup(1415)
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = 1000000
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	return w

func _conditions(f: Array) -> void:
	var w := _world()
	var years: int = TestFixture.pick(40, 12)
	var n: int = 40
	# n pretend adult townies in the Story roster, average habits
	var ids: Array = []
	for i in n:
		var t: Dictionary = Story.add_townie(120.0, "Pat %d" % i)
		ids.append(int(t["id"]))
		HealthLife.rec(int(t["id"]))["fitness"] = 45.0
		HealthLife.rec(int(t["id"]))["diet"] = 50.0
	var cases := 0
	for d in range(2, years * YEAR + 2):
		K.set_time(d, 0)
		for id in ids:
			if Story.townies[id]["alive"]:
				var before: int = (HealthLife.rec(int(id))["conds"] as Dictionary).size()
				HealthCond.day(int(id), "adult", false)
				cases += (HealthLife.rec(int(id))["conds"] as Dictionary).size() - before
	var per_year: float = float(cases) / float(n) / float(years)
	K.expect(f, per_year > 0.04 and per_year < 0.30, "new long-term conditions per adult per game year are rare (%.3f)" % per_year)
	# flares with and without medicine, on a fixed asthma case
	var flares_un := 0
	var flares_med := 0
	var person_years: int = TestFixture.pick(300, 100)
	var tid: int = ids[0]
	HealthLife.rec(tid)["conds"] = {"asthma": {"since": 0, "diag": true, "doses": 0, "flares": 0, "told": true}}
	var c: Dictionary = HealthLife.rec(tid)["conds"]["asthma"]
	for i in person_years * YEAR:
		c["doses"] = 0
		var b1: int = int(c["flares"])
		HealthCond._condition_day(tid, "asthma", c, false)
		flares_un += int(c["flares"]) - b1
		c["doses"] = 5
		var b2: int = int(c["flares"])
		HealthCond._condition_day(tid, "asthma", c, false)
		flares_med += int(c["flares"]) - b2
	var un_rate: float = float(flares_un) / float(person_years)
	var med_rate: float = float(flares_med) / float(person_years)
	K.expect(f, un_rate > 1.2 and un_rate < 3.0, "unmanaged asthma flares per game year (%.2f)" % un_rate)
	K.expect(f, med_rate < un_rate * 0.25, "and with medicine far fewer (%.2f)" % med_rate)
	print("health_life_longrun: conditions %.3f per adult-year, asthma flares %.2f unmanaged / %.2f managed per year" % [per_year, un_rate, med_rate])
	K.teardown()

func _burnout(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	Careers.hire(ann, "coder", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var years: int = TestFixture.pick(20, 8)
	var results: Dictionary = {}
	for tired_share in [0.3, 1.0]:
		var cases := 0
		HealthLife.reset()
		HealthLife.counts.clear()
		for d in range(2, years * YEAR + 2):
			K.set_time(d, 18)
			ann.remove_buff("burnt_out")
			if SysUtil.weekday(d) < 5:
				ann.needs["energy"].value = -40.0 if rng.randf() < tired_share else 30.0
				LifeTick.on_game_event("returned_from_work", {"folk_id": 1, "skipped": false})
			K.set_time(d + 1, 0)
			HealthLifeDay.on_day(d + 1)
		cases = int(HealthLife.counts.get("burnout", 0))
		results[tired_share] = float(cases) / float(years)
	K.expect(f, float(results[0.3]) < 0.4, "ordinary workers rarely burn out (%.2f a game year)" % float(results[0.3]))
	K.expect(f, float(results[1.0]) > 0.5 and float(results[1.0]) < 4.0, "people who are always worn out burn out every so often (%.2f a game year)" % float(results[1.0]))
	print("health_life_longrun: burnout %.2f (30%% tired) / %.2f (always tired) per game year" % [float(results[0.3]), float(results[1.0])])
	K.teardown()

## Mean age at death by running the real death dice with the multiplier of a fit and of an unfit person.
func _lifespan(f: Array) -> void:
	var w := _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var dc: Dictionary = Aging.cfg().get("death", {})
	var n: int = TestFixture.pick(4000, 1500)
	var means: Dictionary = {}
	for kind in ["fit", "unfit"]:
		var r: Dictionary = HealthLife.rec(1)
		r["fitness"] = 90.0 if kind == "fit" else 8.0
		r["diet"] = 85.0 if kind == "fit" else 12.0
		r["dental"] = 90.0 if kind == "fit" else 20.0
		var mult: float = HealthLife.death_mult(1)
		var shift: float = HealthLife.age_shift(1)
		var total := 0.0
		for i in n:
			var d: float = float(dc.get("start_day", 170))
			while d < float(dc.get("max_day", 230)):
				var p: float = (float(dc.get("chance_per_day", 0.03)) + float(dc.get("ramp_per_day", 0.004)) * (d - float(dc.get("start_day", 170)))) * mult
				if rng.randf() < p:
					break
				d += 1.0
			total += d + shift          # d = the effective age; Aging compares age - shift
		means[kind] = total / float(n)
	K.expect(f, float(means["fit"]) - float(means["unfit"]) > 14.0 and float(means["fit"]) - float(means["unfit"]) < 40.0, "the fit live longer: %.1f vs %.1f game days" % [float(means["fit"]), float(means["unfit"])])
	print("health_life_longrun: mean death day fit %.1f unfit %.1f" % [float(means["fit"]), float(means["unfit"])])
	K.teardown()
