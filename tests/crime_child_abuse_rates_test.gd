extends RefCounted
## SLOW tier: child abuse incidence over many family-years (statistical townie version). It must stay very rare overall, never happen to low-risk
## families, happen more in high-risk families, and only ever where the risk factors were really present.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := C.town(4)
	JusticePlayer.auto = "ignore"
	var years: int = TestFixture.pick(16, 4)
	var groups: Dictionary = {"typical": [], "low": [], "high": []}
	var sizes: Dictionary = {"typical": 50, "low": 20, "high": 20}
	for g in groups:
		for i in int(sizes[g]):
			var traits: Array = []
			var coins: int = SysUtil.rng.randi_range(100, 800)
			match g:
				"low":
					traits = ["easygoing", "optimist"]
					coins = 3000
				"high":
					traits = ["hot_headed", "vengeful"]
					coins = 0
			var parent: Dictionary = Story.add_townie(112.0, "", traits, "" if g == "high" or i % 3 == 2 else "cook")
			parent["coins"] = coins
			var kid: Dictionary = Story.add_townie(25.6, "", [], "")
			Family.parents[int(kid["id"])] = [int(parent["id"])]
			if g == "low":
				for j in 3:
					var fr: Dictionary = Story.add_townie(112.0)
					RelationshipService.add_both(int(parent["id"]), int(fr["id"]), "friendship", 60.0)
			elif g == "typical" and i % 3 != 0:
				var fr2: Dictionary = Story.add_townie(112.0)
				RelationshipService.add_both(int(parent["id"]), int(fr2["id"]), "friendship", 50.0)
			(groups[g] as Array).append([int(parent["id"]), int(kid["id"])])
	var max_raw: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	for d in years * 28:
		K.set_time(3 + d, 12)
		if d % 5 == 0:
			for pr in groups["high"]:
				RelationshipRomance.add_tension(int(pr[0]), int(pr[1]), 70.0)
				RelationshipRomance.add_tension(int(pr[1]), int(pr[0]), 70.0)
		CrimeChildAbuse.on_day()
		ChildServices.on_day()
		if d % 7 == 0:
			for g2 in groups:
				for pr2 in groups[g2]:
					var raw: float = float(CrimeChildAbuse.assess(int(pr2[0]), int(pr2[1]))["raw"])
					max_raw[int(pr2[1])] = maxf(float(max_raw.get(int(pr2[1]), 0.0)), raw)
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var inc: Dictionary = {}
	var needs_risk: bool = true
	for g3 in groups:
		var n: int = 0
		for pr3 in groups[g3]:
			var kid_rec: Dictionary = JusticeState.abuse["kids"].get(int(pr3[1]), {})
			n += int(kid_rec.get("incidents", 0))
			if int(kid_rec.get("incidents", 0)) > 0 and float(max_raw.get(int(pr3[1]), 0.0)) <= float(JusticeState.sect("child_abuse")["min_raw"]):
				needs_risk = false
		inc[g3] = float(n) / (float(years) * float((groups[g3] as Array).size()))
	var all: float = (float(inc["typical"]) * 50.0 + float(inc["low"]) * 20.0 + float(inc["high"]) * 20.0) / 90.0
	print("[child_abuse_rates] %d years in %.0f s: incidents per family-year: typical %.4f, low-risk %.4f, high-risk %.4f; warnings %d, reports %d, placements %d" % [
		years, secs, float(inc["typical"]), float(inc["low"]), float(inc["high"]), JusticeState.counter("abuse_warnings"), JusticeState.counter("abuse_reports"), JusticeState.counter("abuse_placements")])
	K.expect(f, float(inc["typical"]) <= 0.02, "typical families: very rare (%.4f per family-year)" % float(inc["typical"]))
	K.expect(f, float(inc["low"]) == 0.0, "low-risk families: never")
	K.expect(f, float(inc["high"]) > float(inc["typical"]) and float(inc["high"]) < 0.6, "high-risk families: more often, still far from every year (%.3f)" % float(inc["high"]))
	K.expect(f, needs_risk, "every incident happened in a family whose risk had been above the threshold")
	K.expect(f, all < 0.15, "overall incidence stays low (%.4f)" % all)
	JusticePlayer.auto = ""
	K.teardown()
	return f
