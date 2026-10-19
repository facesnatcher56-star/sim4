class_name CrimeFlow
extends RefCounted
## The one door of the crime and justice track into the rest of the game. SystemsManager calls reset / on_minute / on_hour / on_day /
## on_game_event; everything else is routed from here so the hooks in shared files stay one line each.
## Queued events (JusticeState.pending) are dispatched by `run_pending`.

static func reset() -> void:
	JusticeState.reset()
	JusticePlayer.reset()
	_sync_key = []
	if sliced():
		for sl in _person_job.slots:
			(sl as Array).clear()
		_person_job.count = 0

static func install() -> void:
	JusticeCareers.install()
	CrimeTraits.install()

## Undo install() (new game / reset_all): the justice careers and crime traits are merged into the shared tables at the first midnight, so without
## this a second game in the same process would have them from minute 0 and play out differently from the first (determinism).
static func uninstall() -> void:
	var careers: Dictionary = Careers.cfg().get("careers", {})
	for cid in (JusticeState.sect("careers") as Dictionary):
		careers.erase(cid)
	var traits: Dictionary = SimEnv.data().traits()
	for id in CrimeTraits.IDS:
		traits.erase(id)

# ------------------------------------------------------------------ per-person daily dice, sliced over the day (task 17.3)
## The fraud and pressure dice (one roll per adult per day, each with a risk lookup) used to run for everybody inside the midnight tick (1-5 s at 200 townies).
## With a scheduler they are a BUCKETED daily job: every person is visited once a day at minute (id % 1440), same dice and rates, nothing at midnight.
## Without one (tests that call the on_day passes directly) the old all-in-one loops run.
static var _person_job: SimJob = null
static var _sync_key: Array = []

static func install_sliced(sched: SimScheduler, group: String) -> void:
	_person_job = sched.add_bucketed("CrimeFlow.person_day", "CrimeFlow", group, 1440, 305, SimScheduler.NORMAL, CrimeFlow.person_day,
		"TOWN / STATISTICAL townies and residents: fraud + pressure dice once a day, bucketed by id (no midnight lump)")
	sched.add("CrimeFlow.sync", "CrimeFlow", group, 1, 306, SimScheduler.NORMAL, CrimeFlow.sync_persons, "", Callable(CrimeFlow, "needs_sync"),
		"keeps the bucketed job's ids equal to the living townies and residents")
	_sync_key = []

static func sliced() -> bool:
	return _person_job != null and not _person_job.removed and _person_job.enabled

static func needs_sync() -> bool:
	return sliced() and _sync_key != [Story.townies.size(), Story.next_id, Economy.household_ids().size()]

static func sync_persons() -> void:
	if not sliced():
		return
	for tid in Story.townies:
		if bool(Story.townies[tid].get("alive", false)):
			_person_job.track(int(tid))
	for r in SysUtil.residents():
		_person_job.track(int(r.id))
	_sync_key = [Story.townies.size(), Story.next_id, Economy.household_ids().size()]

static func person_day(id: int, _elapsed: int = 1440) -> void:
	if not JusticeState.enabled:
		return
	var alive: bool = bool(Story.townies.get(id, {}).get("alive", false)) or SysUtil.folk(id) != null
	if not alive:
		_person_job.untrack(id)
		return
	CrimeFraud.person_day(id)
	CrimePressure.person_day(id)

# ------------------------------------------------------------------ clock
static func on_minute() -> void:
	if not JusticeState.pending.is_empty():
		Police.on_minute()

static func on_hour() -> void:
	if not JusticeState.enabled:
		return
	for pid in CrimePerson.everyone():
		CrimePlace.record_now(int(pid))
	CaseDiscovery.on_hour()

static func on_day(_day: int) -> void:
	if not JusticeState.enabled:
		return
	install()
	var _pt := 0
	_pt = PerfProf.start()
	CrimeTraits.roll_townies()
	PerfProf.stop("crimeday/CrimeTraits.roll_townies", _pt)
	_pt = PerfProf.start()
	CrimeRate.on_day()
	PerfProf.stop("crimeday/CrimeRate.on_day", _pt)
	_pt = PerfProf.start()
	JusticeCareers.on_day()
	PerfProf.stop("crimeday/JusticeCareers.on_day", _pt)
	_pt = PerfProf.start()
	if not sliced():                    # sliced: the bucketed daily job rolls these dice one person at a time
		CrimePressure.on_day()
	PerfProf.stop("crimeday/CrimePressure.on_day", _pt)
	_pt = PerfProf.start()
	if sliced():
		CrimeFraud.audit()
	else:
		CrimeFraud.on_day()
	PerfProf.stop("crimeday/CrimeFraud.on_day", _pt)
	_pt = PerfProf.start()
	CrimeBlackmail.on_day()
	PerfProf.stop("crimeday/CrimeBlackmail.on_day", _pt)
	_pt = PerfProf.start()
	CrimeRevenge.on_day()
	PerfProf.stop("crimeday/CrimeRevenge.on_day", _pt)
	_pt = PerfProf.start()
	CrimeMurder.on_day()
	PerfProf.stop("crimeday/CrimeMurder.on_day", _pt)
	_pt = PerfProf.start()
	CrimeAssault.on_day()
	PerfProf.stop("crimeday/CrimeAssault.on_day", _pt)
	_pt = PerfProf.start()
	JusticeOrders.on_day()
	PerfProf.stop("crimeday/JusticeOrders.on_day", _pt)
	_pt = PerfProf.start()
	CrimeChildAbuse.on_day()
	PerfProf.stop("crimeday/CrimeChildAbuse.on_day", _pt)
	_pt = PerfProf.start()
	ChildServices.on_day()
	PerfProf.stop("crimeday/ChildServices.on_day", _pt)
	_pt = PerfProf.start()
	CrimeSerial.on_day()
	PerfProf.stop("crimeday/CrimeSerial.on_day", _pt)
	_pt = PerfProf.start()
	CaseDiscovery.on_day()
	PerfProf.stop("crimeday/CaseDiscovery.on_day", _pt)
	_pt = PerfProf.start()
	CaseInvestigation.on_day()
	PerfProf.stop("crimeday/CaseInvestigation.on_day", _pt)
	_pt = PerfProf.start()
	Prison.on_day()
	PerfProf.stop("crimeday/Prison.on_day", _pt)
	_pt = PerfProf.start()
	JusticeSentence.on_day()
	PerfProf.stop("crimeday/JusticeSentence.on_day", _pt)
	_pt = PerfProf.start()
	JusticeAppeal.on_day()
	PerfProf.stop("crimeday/JusticeAppeal.on_day", _pt)
	_pt = PerfProf.start()
	JusticeCivil.on_day()
	PerfProf.stop("crimeday/JusticeCivil.on_day", _pt)

## Dispatch one due queued event.
static func run_pending(p: Dictionary) -> void:
	var c: Dictionary = CaseStore.get_case(int(p.get("case", -1)))
	match str(p.get("kind", "")):
		"police_arrive":
			if not c.is_empty():
				Police.arrive(c)
		"burgle_step":
			CrimeBurglary.step(p)
		"murder_due":
			CrimeMurder.due(p)
		"trial":
			if not c.is_empty():
				Courthouse.open(c)
		"verdict":
			if not c.is_empty():
				Courthouse.verdict_day(c)

# ------------------------------------------------------------------ events
static func on_game_event(ev: String, p: Dictionary) -> void:
	match ev:
		"argument":
			CrimeAssault.on_argument(int(p.get("folk_id", -1)), int(p.get("target_id", -1)), int(p.get("level", 0)))
		"admitted":
			ChildServices.on_treated(int(p.get("folk_id", -1)))
		"anger_course":
			CrimeAssault.on_course_done(int(p.get("folk_id", -1)))
		"confront_intruder":
			CrimeBurglary.on_confront(int(p.get("folk_id", -1)), int(p.get("target_id", -1)))
		"call_police":
			Police.call_police(int(p.get("folk_id", -1)))
		"work_case":
			JusticeCareers.on_work_case(int(p.get("folk_id", -1)))
		"blackmail_demand", "blackmail_pay", "blackmail_refuse", "blackmail_report", "blackmail_confront":
			CrimeBlackmail.on_event(ev, p)
		"start_watch":
			CrimeRate.start_watch(int(p.get("folk_id", -1)))
		"fire_started":
			CrimeFraud.on_fire_started(p)
		"apologize", "argument_resolved":
			var a: int = int(p.get("folk_id", -1))
			var b: int = int(p.get("target_id", -1))
			CrimeRevenge.on_apology(a, b)
			for pr in [[a, b], [b, a]]:
				var g: Dictionary = JusticeState.grudges.get(CrimeMurder.key(int(pr[0]), int(pr[1])), {})
				if not g.is_empty():
					g["rage"] = float(g["rage"]) * 0.7
		"accident_on_property", "divorced", "died":
			if ev == "died":
				CaseStore.on_death(int(p.get("folk_id", -1)))
			JusticeCivil.on_game_event(ev, p)
		"visit_prison":
			Prison.visit(int(p.get("folk_id", -1)), int(p.get("target_id", -1)))
		"appeal_case":
			JusticeAppeal.file(int(p.get("object_id", -1)))