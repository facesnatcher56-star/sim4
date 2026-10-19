class_name SystemsManager
extends Node
## Creates and ticks every gameplay system off Clock / Events. Install once from main.gd:
##     SystemsManager.install(self)           # adds the node as a child and starts listening
## then (for a new game)  SystemsManager.instance.new_game([household_id, ...])
## Everything is static-state under the hood (Economy, Careers, ...), so UI code can call e.g.
## `Goals.active_for(id)`, `Careers.info_for(id)`, `RelationshipBits.describe(a, b)` directly.

signal day_summary(day: int, lines: Array)

static var instance: SystemsManager = null

var autosave_enabled: bool = true
var enabled: bool = true
var _connected: bool = false
var _clock = null
var _events = null

static func install(parent: Node) -> SystemsManager:
	var m := SystemsManager.new()
	m.name = "SystemsManager"
	parent.add_child(m)
	m.setup()
	return m

func _ready() -> void:
	if not _connected:
		setup()

## Connect to Clock and the Events bus (idempotent). Also usable on a detached node in tests.
func setup() -> void:
	if _connected:
		return
	_connected = true
	instance = self
	_clock = SimEnv.clock()
	_events = SimEnv.events()
	_clock.minute_passed.connect(_on_minute)
	_clock.hour_passed.connect(_on_hour)
	_clock.day_passed.connect(_on_day)
	_events.interaction_started.connect(_on_interaction_started)
	_events.interaction_finished.connect(_on_interaction_finished)
	_events.relationship_changed.connect(_on_relationship_changed)
	_events.game_event.connect(_on_game_event)
	_events.buff_added.connect(_on_buff_added)
	_events.skill_changed.connect(_on_skill_changed)
	_events.folk_added.connect(_on_folk_added)
	_events.object_placed.connect(_on_object_placed)
	_events.object_removed.connect(_on_object_removed)
	SysContent.install_all()
	NeighborhoodService.install()
	MarketTick.install()           # task 13: BankInsurance is the Incidents.insurance_fn
	_hook_world()

func teardown() -> void:
	if not _connected:
		return
	_connected = false
	for pair in [[_clock, "minute_passed", _on_minute], [_clock, "hour_passed", _on_hour], [_clock, "day_passed", _on_day],
			[_events, "interaction_started", _on_interaction_started], [_events, "interaction_finished", _on_interaction_finished],
			[_events, "relationship_changed", _on_relationship_changed], [_events, "game_event", _on_game_event],
			[_events, "buff_added", _on_buff_added], [_events, "skill_changed", _on_skill_changed],
			[_events, "folk_added", _on_folk_added], [_events, "object_placed", _on_object_placed],
			[_events, "object_removed", _on_object_removed]]:
		var src = pair[0]
		if src != null and is_instance_valid(src) and src.is_connected(pair[1], pair[2]):
			src.disconnect(pair[1], pair[2])
	if instance == self:
		instance = null

## Route the World's build-mode coin hooks through the Economy (when the real World exposes them).
func _hook_world() -> void:
	var w = WorldIface.world()
	if w != null and "coin_spend" in w:
		w.coin_spend = Callable(Economy, "spend_cb")
		w.coin_refund = Callable(Economy, "refund_cb")

## Wipe all system state (new game / tests).
static func reset_all() -> void:
	Economy.reset()
	Careers.reset()
	RelationshipService.reset()
	Goals.reset()
	Aging.reset()
	Story.reset()
	Away.reset()
	Commute.reset()
	Family.reset()
	BabyCare.reset()
	Weather.reset()
	Neighborhood.reset()
	Scenario.reset()
	Incidents.reset()
	AccidentMarks.reset_cache()
	CrimeFlow.reset()
	Fire.reset()
	ShareState.reset()
	MarketTick.reset()
	LevelSystems.reset()
	AutonomyVariety.reset()
	MoodSwings.reset()
	StoryPacing.reset()

## Start a fresh game: reset systems, give every household starting funds, register all current folk, make townies.
func new_game(household_ids: Array = [], lifespan: String = "") -> void:
	reset_all()
	SysContent.install_all()
	NeighborhoodService.install()
	Weather.new_game()
	if lifespan != "":
		Aging.set_lifespan(lifespan)
	var hids: Array = household_ids if not household_ids.is_empty() else Economy.household_ids()
	for hid in hids:
		Economy.start_funds(int(hid))
	ensure_registered()
	Story.generate_townies()
	Economy.refresh_objects()
	MarketTick.new_game()

## Make sure every folk on the lot has aging / goals records (idempotent).
func ensure_registered() -> void:
	Aging.ensure_all()
	Genetics.ensure_all()
	Goals.ensure_all()
	Careers.enroll_school()

# ------------------------------------------------------------------ clock
## Per-minute steps, in order (a list so tests/perf_probe.gd can time each one: `prof_on` + `prof`).
var _minute_steps: Array = []
var prof_on: bool = false
var prof: Dictionary = {}          # label -> [usec, calls]

func _on_minute(_total: int) -> void:
	if not enabled:
		return
	if _minute_steps.is_empty():
		_minute_steps = [["NeighborhoodService.before", NeighborhoodService.before_minute], ["CareerShifts", CareerShifts.on_minute],
			["Away", Away.on_minute], ["StoryVisits", StoryVisits.on_minute], ["BabyCare", BabyCare.on_minute],
			["AccidentMarks", AccidentMarks.on_minute], ["Incidents", Incidents.on_minute], ["CrimeFlow", CrimeFlow.on_minute],
			["Fire", Fire.on_minute], ["DisasterClock", DisasterClock.on_minute],
			["NeighborhoodService.after", NeighborhoodService.after_minute], ["WeatherFolk", WeatherFolk.on_minute], ["LevelSystems", LevelSystems.on_minute]]
	for s in _minute_steps:
		var t0 := Time.get_ticks_usec() if prof_on else 0
		(s[1] as Callable).call()
		if prof_on:
			var rec: Array = prof.get(s[0], [0, 0])
			rec[0] += Time.get_ticks_usec() - t0
			rec[1] += 1
			prof[s[0]] = rec

## One step of the hourly / daily lists done: record it under `label` (PerfProf, only while profiling) and restart the stopwatch.
static func _lap(label: String, t0: int) -> int:
	PerfProf.stop(label, t0)
	return PerfProf.start()

func _on_hour(hour: int) -> void:
	if not enabled:
		return
	ensure_registered()
	var t := PerfProf.start()          # opt-in per-step timing for tests/perf_scale.gd (a boolean test when off)
	WeatherWorld.on_hour(hour)
	t = _lap("hour/WeatherWorld.on_hour", t)
	Holidays.on_hour()
	t = _lap("hour/Holidays.on_hour", t)
	Goals.on_hour()
	t = _lap("hour/Goals.on_hour", t)
	Story.on_hour(hour)
	t = _lap("hour/Story.on_hour", t)
	Family.on_hour()
	t = _lap("hour/Family.on_hour", t)
	AccidentMarks.on_hour(hour)
	t = _lap("hour/AccidentMarks.on_hour", t)
	Incidents.on_hour()
	t = _lap("hour/Incidents.on_hour", t)
	AccidentMarks.after_hour()
	t = _lap("hour/AccidentMarks.after_hour", t)
	CrimeFlow.on_hour()
	t = _lap("hour/CrimeFlow.on_hour", t)
	DisasterClock.on_hour(hour)
	t = _lap("hour/DisasterClock.on_hour", t)

func _on_day(day: int) -> void:
	if not enabled:
		return
	ensure_registered()
	var t := PerfProf.start()
	Holidays.on_day(day)
	t = _lap("day/Holidays.on_day", t)
	Aging.on_day(day)
	t = _lap("day/Aging.on_day", t)
	Family.on_day(day)
	t = _lap("day/Family.on_day", t)
	Careers.on_day(day)
	t = _lap("day/Careers.on_day", t)
	WeatherWorld.on_day(day)
	t = _lap("day/WeatherWorld.on_day", t)
	Economy.on_day(day)
	t = _lap("day/Economy.on_day", t)
	RelationshipService.on_day(day)
	t = _lap("day/RelationshipService.on_day", t)
	Story.on_day(day)
	t = _lap("day/Story.on_day", t)
	Fire.on_day(day)
	t = _lap("day/Fire.on_day", t)
	Incidents.on_day()
	t = _lap("day/Incidents.on_day", t)
	CrimeFlow.on_day(day)
	t = _lap("day/CrimeFlow.on_day", t)
	DisasterClock.on_day(day)
	MarketTick.on_day(day)
	t = _lap("day/DisasterClock.on_day", t)
	StoryPacing.on_day(day)
	t = _lap("day/StoryPacing.on_day", t)
	SysUtil.game_event("systems_day", {"day": day})
	if autosave_enabled:
		SaveLoad.autosave()

# ------------------------------------------------------------------ events
func _on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	if not enabled:
		return
	RelationshipService.on_interaction_started(folk_id, iid, target_id)
	AutonomyVariety.on_started(folk_id, iid, target_id)
	MoodSwings.on_started(folk_id, iid)
	Fire.on_interaction_started(folk_id, iid, target_id)
	Health.on_interaction_started(folk_id, iid, target_id)
	var rec: Dictionary = Away.on_started(folk_id, iid)
	if not rec.is_empty():
		var f = SysUtil.folk(folk_id)
		if f != null and str(rec["reason"]) in ["work", "school"]:
			CareerShifts.on_left(f, rec)

func _on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if not enabled:
		return
	WeatherWorld.on_interaction_finished(folk_id, iid, success)
	MoodSwings.on_finished(folk_id, iid, success)
	AccidentMarks.on_interaction_finished(folk_id, iid, success)
	var rec: Dictionary = Away.on_finished(folk_id, iid, success)
	if not rec.is_empty():
		var f = SysUtil.folk(folk_id)
		if f != null:
			match str(rec["reason"]):
				"work", "school":
					CareerShifts.on_returned(f, rec)
				"party":
					StoryVisits.on_party_return(f, rec)
				"hospital":
					Hospital.on_returned(f, rec)
				"custody", "jail", "prison", "court", "service", "prison_visit":
					Prison.on_returned(f, rec)
		return
	var f2 = SysUtil.folk(folk_id)
	if f2 == null:
		return
	NeighborhoodService.on_interaction_finished(folk_id, iid, success)
	if success:
		Economy.note_usage(int(f2.household_id), iid)
	CareerProgress.on_interaction(folk_id, iid, success)
	MarketTick.on_interaction_finished(folk_id, iid, success)
	RelationshipService.on_interaction_finished(folk_id, iid, success)
	StoryVisits.on_interaction(folk_id, iid, success)
	if success:
		var d: Dictionary = SimEnv.data().interaction_def(iid)
		Goals.feed(f2, {"type": "interaction", "id": iid, "tags": d.get("tags", [])})

func _on_relationship_changed(a: int, b: int, track: String, _value: float = 0.0) -> void:
	if not enabled:
		return
	RelationshipService.on_relationship_changed(a, b, track)

func _on_buff_added(folk_id: int, buff_id: String) -> void:
	if not enabled:
		return
	var f = SysUtil.folk(folk_id)
	if f != null and SysUtil.is_resident(f):
		Goals.feed(f, {"type": "buff", "id": buff_id})

func _on_skill_changed(folk_id: int, _skill: String, _level: int) -> void:
	if not enabled:
		return
	var f = SysUtil.folk(folk_id)
	if f != null and SysUtil.is_resident(f):
		Goals.feed(f, {"type": "poll"})

func _on_folk_added(folk_id: int) -> void:
	if not enabled:
		return
	var f = SysUtil.folk(folk_id)
	if f != null and SysUtil.is_resident(f):
		Aging.register(f)
		Genetics.ensure(f)
		Goals.ensure_profile(f)
	if f != null:
		WeatherFolk.on_folk_added(f)

func _on_object_placed(object_id: int) -> void:
	Economy.on_object_placed(object_id)

func _on_object_removed(object_id: int) -> void:
	Economy.on_object_removed(object_id)

## Generic bus: route systems-level game events and feed Goals.
func _on_game_event(ev_name: String, payload: Dictionary) -> void:
	if not enabled:
		return
	Family.on_event(ev_name, payload)
	NeighborhoodService.on_game_event(ev_name, payload)
	WeatherWorld.on_game_event(ev_name, payload)
	Graves.on_game_event(ev_name, payload)
	Health.on_game_event(ev_name, payload)
	ChronicleHook.on_game_event(ev_name, payload)
	CrimeFlow.on_game_event(ev_name, payload)
	Fire.on_game_event(ev_name, payload)
	DisasterClock.on_game_event(ev_name, payload)
	MarketTick.on_game_event(ev_name, payload)
	MoodSwings.on_game_event(ev_name, payload)
	StoryPacing.on_game_event(ev_name, payload)
	match ev_name:
		"order_groceries":
			var f = SysUtil.folk(int(payload.get("folk_id", -1)))
			if f != null:
				Economy.restock_fridge(int(f.household_id), int(payload.get("object_id", -1)))
		"job_search":
			Careers.on_job_search(int(payload.get("folk_id", -1)))
		"try_for_baby":
			var res: Dictionary = Aging.try_for_baby(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
			if not bool(res["ok"]) and str(res["reason"]) == "no_luck":
				SysUtil.notify("No luck this time... maybe try again later.", "info")
		"apologize":
			RelationshipService.on_apologize(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
		"propose":
			var out: String = FamilyMarriage.on_propose(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
			if out != "engaged":      # Family announces engagements itself
				SysUtil.notify("%s" % {"accepted": "They said yes!", "declined": "They said no...", "too_soon": "'It's too soon,' they said.", "no_bond": "They barely know each other.", "already_engaged": "They are already engaged.", "already_married": "They are already married."}.get(out, out), "relationship")
		"social_done":
			StoryVisits.on_social_done(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)), str(payload.get("interaction", "")))
	# feed goals for the acting folk (and the other party, for relationship events)
	var f2 = SysUtil.folk(int(payload.get("folk_id", -1)))
	if f2 != null and SysUtil.is_resident(f2):
		Goals.feed(f2, {"type": "game_event", "name": ev_name, "payload": payload})