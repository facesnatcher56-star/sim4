extends RefCounted
## SLOW tier. Deaths and crimes per town-year under each personality against the storyteller switched off ("today"), with the real hourly and daily incident
## dice on the stub town: 2 seeds x 84 days per personality. Classic must stay within +-20% of today, Calm must not be above it, Chaotic stays inside a capped
## higher band. Deaths are rare in 84 days, so they are only compared when the baseline has at least 10; the death-related rates are exactly the incidents'
## own rates times the capped hard multiplier (storyteller_core_test checks the cap).

const K = preload("res://tests/systems_kit.gd")
const L = preload("res://tests/storyteller_longrun_test.gd")
const SEEDS := [11, 22]
const DAYS := 84

func run() -> Array:
	var f: Array = []
	var lr = L.new()
	var days: int = 28 if TestFixture.fast else DAYS
	var res: Dictionary = {}
	for p in ["off", "calm", "classic", "chaotic"]:
		var rows: Array = []
		for s in SEEDS:
			rows.append(lr._measure(p, int(s), days, true))
		res[p] = lr._sum(rows, days)
		print("  %-8s crimes %d deaths %d notable %d" % [p, int(res[p]["crimes"]), int(res[p]["deaths"]), int(res[p]["notable"])])
	var base_d: float = maxf(float(res["off"]["deaths"]), 1.0)
	var base_c: float = maxf(float(res["off"]["crimes"]), 1.0)
	K.expect(f, absf(float(res["classic"]["crimes"]) / base_c - 1.0) <= 0.2, "Classic crimes within 20%% of today (%.2fx)" % (float(res["classic"]["crimes"]) / base_c))
	K.expect(f, absf(float(res["classic"]["deaths"]) / base_d - 1.0) <= 0.2 or int(res["off"]["deaths"]) < 10, "Classic deaths within 20%% of today (%d vs %d)" % [int(res["classic"]["deaths"]), int(res["off"]["deaths"])])
	K.expect(f, float(res["calm"]["crimes"]) <= base_c * 1.05, "Calm crimes are not above today (%.2fx)" % (float(res["calm"]["crimes"]) / base_c))
	K.expect(f, float(res["chaotic"]["crimes"]) <= base_c * 1.9, "Chaotic crimes stay inside the capped band (%.2fx)" % (float(res["chaotic"]["crimes"]) / base_c))
	print("  per town-year: crimes off %.2f calm %.2f classic %.2f chaotic %.2f; deaths off %.2f calm %.2f classic %.2f chaotic %.2f" % [
		float(res["off"]["crimes"]) / years / seeds.size(), float(res["calm"]["crimes"]) / years / seeds.size(), float(res["classic"]["crimes"]) / years / seeds.size(), float(res["chaotic"]["crimes"]) / years / seeds.size(),
		float(res["off"]["deaths"]) / years / seeds.size(), float(res["calm"]["deaths"]) / years / seeds.size(), float(res["classic"]["deaths"]) / years / seeds.size(), float(res["chaotic"]["deaths"]) / years / seeds.size()])
	var years: float = float(days) / 28.0 * SEEDS.size()
	print("  per town-year: crimes off %.1f calm %.1f classic %.1f chaotic %.1f; deaths off %.2f calm %.2f classic %.2f chaotic %.2f" % [
		float(res["off"]["crimes"]) / years, float(res["calm"]["crimes"]) / years, float(res["classic"]["crimes"]) / years, float(res["chaotic"]["crimes"]) / years,
		float(res["off"]["deaths"]) / years, float(res["calm"]["deaths"]) / years, float(res["classic"]["deaths"]) / years, float(res["chaotic"]["deaths"]) / years])
	return f
