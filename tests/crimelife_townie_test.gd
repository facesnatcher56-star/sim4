extends RefCounted
## Task 21: townies run the same path statistically. A few drift in (pressure, no job, a record, a dishonest streak; the honest hardly ever), work their
## rank's jobs with the same odds and the same case records, get caught, quit, fence and heist - and stay a small share of the town.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_joining(f)
	_days(f)
	_player_excluded(f)
	_cases(f)
	_sliced(f)
	return f

func _joining(f: Array) -> void:
	var w := C.town(16)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	var c: int = int(ids[2])
	Story.townies[a]["traits"] = ["dishonest"]
	Story.townies[a].erase("career")
	Story.townies[a]["coins"] = 5
	Story.townies[b]["traits"] = ["honest"]
	Story.townies[b]["coins"] = 5
	Story.townies[c]["coins"] = 3000
	Story.townies[c]["career"] = "cook"
	var pa: float = CrimeLifeTownie.join_chance(a)
	var pb: float = CrimeLifeTownie.join_chance(b)
	var pc: float = CrimeLifeTownie.join_chance(c)
	K.expect(f, pa > pb * 10.0 and pa > pc * 3.0, "a broke, jobless, dishonest townie is far likelier than an honest or comfortable one (%.5f vs %.5f vs %.5f)" % [pa, pb, pc])
	K.teardown()

func _days(f: Array) -> void:
	var w := C.town(20)
	var ids: Array = C.adults()
	for tid in ids:
		Story.townies[tid]["traits"] = ["dishonest"]
		Story.townies[tid]["coins"] = 5
		Story.townies[tid].erase("career")
	var old_join: float = float(CrimeLifeState.sect("townie")["join_base"])
	CrimeLifeState.sect("townie")["join_base"] = 0.02             # accelerate: the real rate is checked in the long run
	var peak: float = 0.0
	for d in 120:
		K.set_time(5 + d, 12)
		CrimeLifeTownie.on_day_all()
		peak = maxf(peak, CrimeLifeTownie.member_share())
		JusticeState.inmates.clear()
		JusticeState.pending.clear()
	CrimeLifeState.sect("townie")["join_base"] = old_join
	var members: int = 0
	for pid in CrimeLifeState.members:
		if not CrimePerson.is_player(int(pid)):
			members += 1
	K.expect(f, members >= 2, "townies drift in (%d members)" % members)
	K.expect(f, peak <= float(CrimeLifeState.sect("townie").get("max_share", 0.12)) + 0.06, "but stay a small share of the adults (peak %.2f)" % peak)
	var jobs: int = 0
	for k in CrimeLifeState.counters:
		if str(k).begins_with("job_"):
			jobs += int(CrimeLifeState.counters[k])
	K.expect(f, jobs >= 2, "members work their jobs (%d)" % jobs)
	K.expect(f, CaseStore.in_state(["hidden", "open", "arrested", "charged", "trial", "closed", "cold"]).size() >= 1, "which leaves case records")
	K.teardown()

func _player_excluded(f: Array) -> void:
	var w := C.town(10)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "burglar"
	for d in 60:
		CrimeLifeTownie.person_day(1)
	K.expect(f, CrimeLifeState.counters.is_empty() or CrimeLifeState.counter("job_pickpocket") == 0, "the player's folk never acts on its own: only commands move it")
	K.expect(f, CrimeLifePath.member(1)["jobs"] == 0, "no jobs behind the player's back")
	K.teardown()

func _cases(f: Array) -> void:
	var w := C.town(14)
	var t: int = int(C.adults()[0])
	CrimeLifePath.join(t, "chose")
	CrimeLifePath.member(t)["rank"] = "burglar"
	CrimeLifePath.member(t)["jobs"] = 5
	CrimeLifePath.member(t)["skills"] = {"stealth": 2, "handiness": 2, "charisma": 2}
	var kinds: Dictionary = {}
	for i in 60:
		var r: Dictionary = CrimeLifeTownie.work(t)
		if r.has("case") and int(r["case"]) >= 0:
			kinds[str(CaseStore.get_case(int(r["case"]))["kind"])] = true
		JusticeState.inmates.clear()
		JusticeState.pending.clear()
	K.expect(f, kinds.size() >= 3, "a working burglar does several kinds of job: %s" % str(kinds.keys()))
	K.teardown()

## The sliced scheduler path (CrimeFlow.person_day) reaches the townie dice too.
func _sliced(f: Array) -> void:
	var w := C.town(12)
	var t: int = int(C.adults()[0])
	CrimeLifePath.join(t, "chose")
	var old_rates: Array = CrimeLifeState.sect("townie")["rank_daily"]
	CrimeLifeState.sect("townie")["rank_daily"] = [1.0]
	var before: int = 0
	for k in CrimeLifeState.counters:
		before += int(CrimeLifeState.counters[k])
	for i in 4:
		K.set_time(5 + i, 12)
		CrimeFlow.person_day(t)
		JusticeState.inmates.clear()
	CrimeLifeState.sect("townie")["rank_daily"] = old_rates
	var after: int = 0
	for k in CrimeLifeState.counters:
		after += int(CrimeLifeState.counters[k])
	K.expect(f, after > before, "the bucketed daily job runs the path for a townie")
	K.teardown()
