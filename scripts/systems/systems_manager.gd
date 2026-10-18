class_name SystemsManager
extends Node
## Creates and ticks every gameplay system off Clock / Events. Install once from main.gd:
##     SystemsManager.install(self)           # adds the node as a child and starts listening
## then (for a new game)  SystemsManager.instance.new_game([household_id, ...])
## Everything is static-state under the hood (Economy, Careers, ...), so UI code can call e.g.
## `Goals.active_for(id)`, `Careers.info_for(id)`, `RelationshipService.describe(a, b)` directly.

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
	SysContent.install()
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

## Start a fresh game: reset systems, give every household starting funds, register all current folk, make townies.
func new_game(household_ids: Array = [], lifespan: String = "") -> void:
	reset_all()
	SysContent.install()
	if lifespan != "":
		Aging.set_lifespan(lifespan)
	var hids: Array = household_ids if not household_ids.is_empty() else Economy.household_ids()
	for hid in hids:
		Economy.start_funds(int(hid))
	ensure_registered()
	Story.generate_townies()
	Economy.refresh_objects()

## Make sure every folk on the lot has aging / goals records (idempotent).
func ensure_registered() -> void:
	Aging.ensure_all()
	Goals.ensure_all()
	Careers.enroll_school()

# ------------------------------------------------------------------ clock
func _on_minute(_total: int) -> void:
	if not enabled:
		return
	Careers.on_minute()
	Away.on_minute()
	Story.on_minute()

func _on_hour(hour: int) -> void:
	if not enabled:
		return
	ensure_registered()
	Goals.on_hour()
	Story.on_hour(hour)

func _on_day(day: int) -> void:
	if not enabled:
		return
	ensure_registered()
	Aging.on_day(day)
	Careers.on_day(day)
	Economy.on_day(day)
	RelationshipService.on_day(day)
	Story.on_day(day)
	SysUtil.game_event("systems_day", {"day": day})
	if autosave_enabled:
		SaveLoad.autosave()

# ------------------------------------------------------------------ events
func _on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	if not enabled:
		return
	RelationshipService.on_interaction_started(folk_id, iid, target_id)
	var rec: Dictionary = Away.on_started(folk_id, iid)
	if not rec.is_empty():
		var f = SysUtil.folk(folk_id)
		if f != null and str(rec["reason"]) in ["work", "school"]:
			Careers.on_left(f, rec)

func _on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if not enabled:
		return
	var rec: Dictionary = Away.on_finished(folk_id, iid, success)
	if not rec.is_empty():
		var f = SysUtil.folk(folk_id)
		if f != null:
			match str(rec["reason"]):
				"work", "school":
					Careers.on_returned(f, rec)
				"party":
					Story.on_party_return(f, rec)
		return
	var f2 = SysUtil.folk(folk_id)
	if f2 == null:
		return
	if success:
		Economy.note_usage(int(f2.household_id), iid)
	Careers.on_interaction(folk_id, iid, success)
	RelationshipService.on_interaction_finished(folk_id, iid, success)
	Story.on_interaction(folk_id, iid, success)
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
		Goals.ensure_profile(f)

func _on_object_placed(object_id: int) -> void:
	Economy.on_object_placed(object_id)

func _on_object_removed(object_id: int) -> void:
	Economy.on_object_removed(object_id)

## Generic bus: route systems-level game events and feed Goals.
func _on_game_event(ev_name: String, payload: Dictionary) -> void:
	if not enabled:
		return
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
			var out: String = RelationshipService.propose(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
			SysUtil.notify("%s" % {"accepted": "They said yes!", "declined": "They said no...", "too_soon": "'It's too soon,' they said.", "no_bond": "They barely know each other."}.get(out, out), "relationship")
		"social_done":
			Story.on_social_done(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)), str(payload.get("interaction", "")))
	# feed goals for the acting folk (and the other party, for relationship events)
	var f2 = SysUtil.folk(int(payload.get("folk_id", -1)))
	if f2 != null and SysUtil.is_resident(f2):
		Goals.feed(f2, {"type": "game_event", "name": ev_name, "payload": payload})
