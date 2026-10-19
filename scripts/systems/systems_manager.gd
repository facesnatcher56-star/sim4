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
## false = the clock jobs of this manager are skipped (SimScheduler group switch).
var enabled: bool = true:
	set(v):
		enabled = v
		if _sched != null:
			_sched.set_group_enabled(SimRegistry.systems_group(self), v)
var _sched: SimScheduler = null
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
	_sched = SimScheduler.of(_clock)               # the clock jobs (minute / hour / day steps) are the rows of sim_registry.gd
	SimRegistry.install_systems(_sched, self)
	_sched.set_group_enabled(SimRegistry.systems_group(self), enabled)
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
	if _sched != null:
		_sched.remove_group(SimRegistry.systems_group(self))
		_sched = null
	for pair in [[_events, "interaction_started", _on_interaction_started], [_events, "interaction_finished", _on_interaction_finished],
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
	CrimeFlow.uninstall()
	Players.reset()
	SuccessionNobody.reset()
	Tiers.reset()
	DaySlices.reset()
	IncidentSlices.reset()
	ContentRules.reset()
	Commands.reset()
	var ml := Engine.get_main_loop()
	var dir = (ml as SceneTree).root.get_node_or_null("SimDirector") if ml is SceneTree else null
	if dir != null and dir.has_method("reset_state"):
		dir.reset_state()
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
	Vacation.reset()
	CityBudget.reset()
	CityState.reset()

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
	CityGov.ensure()                 # task 12: the first mayor and council come from the townies
	Economy.refresh_objects()
	MarketTick.new_game()

## Make sure every folk on the lot has aging / goals records (idempotent).
func ensure_registered() -> void:
	Aging.ensure_all()
	Genetics.ensure_all()
	Goals.ensure_all()
	Careers.enroll_school()

# ------------------------------------------------------------------ clock
## The per-minute / hourly / daily steps are rows in sim_registry.gd (systems_rows), run by the SimScheduler in that order.
## Their stopwatch is SimScheduler.stats() (tests/perf_probe.gd, tests/perf_scale.gd).

func autosave_active() -> bool:
	return autosave_enabled

func emit_systems_day(day: int) -> void:
	SysUtil.game_event("systems_day", {"day": day})

# ------------------------------------------------------------------ events
func _on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	if not enabled:
		return
	RelationshipService.on_interaction_started(folk_id, iid, target_id)
	AutonomyVariety.on_started(folk_id, iid, target_id)
	MoodSwings.on_started(folk_id, iid)
	Fire.on_interaction_started(folk_id, iid, target_id)
	Health.on_interaction_started(folk_id, iid, target_id)
	CityPolicy.on_interaction(SysUtil.folk(folk_id), iid)
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
	ChaosClock.on_game_event(ev_name, payload)
	MarketTick.on_game_event(ev_name, payload)
	MoodSwings.on_game_event(ev_name, payload)
	StoryPacing.on_game_event(ev_name, payload)
	Vacation.on_game_event(ev_name, payload)
	CityState.on_game_event(ev_name, payload)
	Pregnancy.on_game_event(ev_name, payload)
	PregnancyStage.on_game_event(ev_name, payload)
	PregnancyTell.on_game_event(ev_name, payload)
	Intimacy.on_game_event(ev_name, payload)
	Paternity.on_game_event(ev_name, payload)
	ClinicRoute.on_game_event(ev_name, payload)
	match ev_name:
		"order_groceries":
			var f = SysUtil.folk(int(payload.get("folk_id", -1)))
			if f != null:
				Economy.restock_fridge(int(f.household_id), int(payload.get("object_id", -1)))
		"pay_bills":
			BillPaying.on_pay_bills(int(payload.get("folk_id", -1)))
		"job_search":
			Careers.on_job_search(int(payload.get("folk_id", -1)))
		"try_for_baby":
			var res: Dictionary = Aging.try_for_baby(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
			if not bool(res["ok"]) and str(res["reason"]) == "no_luck":
				SysUtil.notify("No luck this time... maybe try again later.", "info")
			elif not bool(res["ok"]) and str(res["reason"]) in ["same_sex", "too_old"]:
				SysUtil.notify(Conception.why_not(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1))), "info")
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