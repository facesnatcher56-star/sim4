class_name CrimeFlow
extends RefCounted
## The one door of the crime and justice track into the rest of the game. SystemsManager calls reset / on_minute / on_hour / on_day /
## on_game_event; everything else is routed from here so the hooks in shared files stay one line each.
## Queued events (JusticeState.pending) are dispatched by `run_pending`.

static func reset() -> void:
	JusticeState.reset()
	JusticePlayer.reset()

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
	CrimeTraits.roll_townies()
	CrimeRate.on_day()
	JusticeCareers.on_day()
	CrimePressure.on_day()
	CrimeFraud.on_day()
	CrimeBlackmail.on_day()
	CrimeRevenge.on_day()
	CrimeMurder.on_day()
	CrimeAssault.on_day()
	JusticeOrders.on_day()
	CrimeChildAbuse.on_day()
	ChildServices.on_day()
	CrimeSerial.on_day()
	CaseDiscovery.on_day()
	CaseInvestigation.on_day()
	Prison.on_day()
	JusticeSentence.on_day()
	JusticeAppeal.on_day()
	JusticeCivil.on_day()

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