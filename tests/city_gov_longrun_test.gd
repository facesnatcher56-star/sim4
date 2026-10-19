extends RefCounted
## Task 12.4 long run (slow tier): who wins elections when the town is happy or angry, how many candidates stand, and the budget over many years.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

const TRIALS := 300

func _incumbent_wins(mood: float) -> int:
	var inc: int = int(CityGov.mayor["id"])
	var wins: int = 0
	for i in TRIALS:
		CityElection.reset()
		CityGov.mood_now = mood
		CityGov.mayor["term_end"] = SysUtil.day()
		CityElection.start_campaign()
		if not CityElection.is_candidate(inc):
			CityElection._add_candidate(inc, false)
		CityElection.hold()
		if int(CityGov.mayor["id"]) == inc:
			wins += 1
		else:
			CityGov.mayor["id"] = inc            # the next trial starts again with the same incumbent
			CityGov.mayor["name"] = CrimePerson.name_of(inc)
	return wins

func run() -> Array:
	var f: Array = []
	C.setup()
	K.set_time(5, 10)
	Story.generate_townies()
	CityGov.install()
	CityGov.ensure()
	var happy: int = _incumbent_wins(0.8)
	var angry: int = _incumbent_wins(-0.8)
	var mid: int = _incumbent_wins(0.0)
	K.expect(f, happy > TRIALS * 7 / 10, "a happy town re-elects the mayor: %d of %d" % [happy, TRIALS])
	K.expect(f, angry < TRIALS * 3 / 10, "an angry town throws the mayor out: the mayor won %d of %d" % [angry, TRIALS])
	K.expect(f, mid > angry and mid < happy, "and a lukewarm one is in between: %d of %d" % [mid, TRIALS])
	# the budget over 30 years of weeks with an ever-changing tax
	CityGov.reset()
	CityGov.install()
	CityGov.ensure()
	var lo: float = 9.0
	var hi: float = 0.0
	for week in 30 * 52:
		K.set_time(5 + week * 7, 10)
		if week % 26 == 0:
			CityGov.set_tax(0.6 + float(CityState.rng.randi_range(0, 10)) / 10.0)
		CityGov.budget_week(false)
		for d in CityGov.funding_now:
			lo = minf(lo, float(CityGov.funding_now[d]))
			hi = maxf(hi, float(CityGov.funding_now[d]))
	K.expect(f, lo >= 0.4 - 0.001 and hi <= 1.8 + 0.001, "funding always stays within its limits (%.2f .. %.2f)" % [lo, hi])
	K.expect(f, is_finite(CityGov.treasury) and CityGov.treasury > -100000.0, "the treasury stays sane (%.0f)" % CityGov.treasury)
	K.teardown()
	return f
