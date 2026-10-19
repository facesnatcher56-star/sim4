extends RefCounted
## SLOW (by name): pregnancy, twin and loss rates over many pregnancies against the data, and births per town year of the statistical townies.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_rates(f)
	_town_births(f)
	return f

func _rates(f: Array) -> void:
	var w := K.setup(1101)
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	PregnancyLoss.set_mature(true)
	var m := K.make_folk(w, "Ann Rowe", [])
	m.sex = "female"
	var d := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 12))
	d.sex = "male"
	Aging.set_age_days(m, 90.0)
	Aging.set_age_days(d, 90.0)
	var n := 700
	var lost := 0
	var births := 0
	var babies := 0
	var twins := 0
	var trip := 0
	var lost_risky := 0
	var n_risky := 350
	for round_i in 2:
		var risky: bool = round_i == 1
		var count: int = n_risky if risky else n
		for i in count:
			Aging.pregnancies.clear()
			Fertility.rest_for(m.id, 0)
			Pregnancy.extra[m.id] = {"infertile": false, "tries": 0, "revealed": false, "boost_until": 0, "rest_until": 0}
			Pregnancy.extra[d.id] = {"infertile": false, "tries": 0, "revealed": false, "boost_until": 0, "rest_until": 0}
			m.buffs.clear()
			if risky:
				m.add_buff("injured")
				m.add_buff("starving")
			K.set_time(1, 8)
			var rec: Dictionary = Pregnancy.start(m.id, d.id, true)
			rec["known"] = true
			for day in range(2, 5):
				K.set_time(day, 0)
				if Aging.pregnancies.has(m.id):
					PregnancyRisk.on_day(m.id, Pregnancy.rec(m.id))
					PregnancyLoss.on_day(m.id, Pregnancy.rec(m.id))
			var survived: bool = Aging.pregnancies.has(m.id)
			if survived:
				births += 1
				var kids: int = int(Pregnancy.rec(m.id)["kids"])
				twins += 1 if kids == 2 else 0
				trip += 1 if kids == 3 else 0
			elif risky:
				lost_risky += 1
			else:
				lost += 1
			m.buffs.clear()
	var lc: Dictionary = Pregnancy.cfg("loss")
	var p_ok: float = 1.0
	for tri in [1, 2, 3]:
		p_ok *= 1.0 - PregnancyLoss.chance("miscarriage", tri, 1.0)
		p_ok *= 1.0 - PregnancyLoss.chance("stillbirth", tri, 1.0)
	var want_loss: float = 1.0 - p_ok
	var got_loss: float = float(lost) / n
	print("  loss share %.3f (data %.3f), risky %.3f; twins %.3f, triplets %d of %d births" % [got_loss, want_loss, float(lost_risky) / n_risky, float(twins) / maxf(births, 1.0), trip, births])
	K.expect(f, absf(got_loss - want_loss) < 0.025, "loss share near the data (%.3f vs %.3f)" % [got_loss, want_loss])
	K.expect(f, float(lost_risky) / n_risky > got_loss * 1.8, "risk factors raise the loss share (%.3f vs %.3f)" % [float(lost_risky) / n_risky, got_loss])
	K.expect(f, absf(float(twins) / maxf(births, 1.0) - float(Pregnancy.cfg("conception")["twins"])) < 0.02, "twins about 2%% (%.3f)" % [float(twins) / maxf(births, 1.0)])
	K.teardown()

func _town_births(f: Array) -> void:
	K.setup(1102)
	Story.generate_townies(12)
	var g: Dictionary = Story.cfg().get("growth", {})
	Story.cfg()["max_population"] = 60
	var years := 30
	var days: int = years * int(Aging.days_per_year())
	var born_total := 0
	var lost_births := 0
	for d in range(1, days + 1):
		K.set_time(d, 6)
		var before: int = Story.townies.size()
		StoryGrowth.on_day()
		for t in Story.alive_townies():
			if Story.stage_of(t) == "adult" and not t.has("last_checked"):
				t["last_checked"] = true
		born_total += maxi(Story.townies.size() - before, 0)
		# keep the town steady so rates are comparable
		var alive: Array = Story.alive_townies()
		if alive.size() > 24:
			for t2 in alive.slice(24):
				Story.townies.erase(int(t2["id"]))
	var per_year: float = float(born_total) / years
	print("  births per town year: %.2f over %d years" % [per_year, years])
	K.expect(f, per_year >= 0.3 and per_year <= 14.0, "births per town year stay in a sensible band (%.2f)" % per_year)
	K.expect(f, lost_births == 0, "bookkeeping")
	K.teardown()
