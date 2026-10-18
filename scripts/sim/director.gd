extends Node
## SimDirector: ticks every folk once per game minute (needs, buffs, interactions, autonomy).
## In the game it listens to Clock.minute_passed; tests can drive it directly with tick_minute().
## (No class_name: it is an autoload singleton named SimDirector.)

const IDLE_RETRY_MIN := 3

var enabled: bool = true
var autonomy_enabled: bool = true
var ticks: int = 0
## folk_id -> last autonomy choice dictionary (interaction_id, reason, score...)
var last_choice: Dictionary = {}

func _ready() -> void:
	connect_clock()

func connect_clock() -> void:
	var c = SimEnv.clock()
	if not c.minute_passed.is_connected(_on_minute):
		c.minute_passed.connect(_on_minute)

func _on_minute(_total: int) -> void:
	if enabled:
		tick_minute(1)

## Advance all folk by `minutes` (normally 1).
func tick_minute(minutes: int = 1) -> void:
	ticks += 1
	for f in WorldIface.all_folk():
		tick_folk(f, float(minutes))

func tick_folk(f: Folk, minutes: float = 1.0) -> void:
	f.tick_needs(minutes)
	f.tick_buffs(minutes)
	f.update_thresholds()
	f.refresh_mood()
	_check_emergencies(f)
	if f.current != null:
		f.current.tick(minutes)
	_fill(f)
	if ticks % 360 == 0:
		f.prune_memory()

## Player command: queue `interaction_id` on `target_id` (object id or folk id). Returns false if it cannot run.
func command(folk_id: int, interaction_id: String, target_id: int = -1) -> bool:
	var f = WorldIface.get_folk(folk_id)
	if f == null:
		return false
	var ir := Interaction.create(interaction_id, f, target_id, true)
	if ir == null or not ir.can_run(f, null, false):
		SimEnv.emit("notification", "That can't be done right now.", "warn")
		return false
	f.enqueue(ir)
	_fill(f)
	return true

var _emergency_src: Dictionary = {}
var _emergency_n: int = -1
var _emergency: Array = []        # [iid, def] of every interaction with an "emergency" condition

func _emergency_defs(defs: Dictionary) -> Array:
	if _emergency_n != defs.size() or not is_same(_emergency_src, defs):
		_emergency_src = defs
		_emergency_n = defs.size()
		_emergency = []
		for iid in defs:
			if (defs[iid] as Dictionary).has("emergency"):
				_emergency.append([str(iid), defs[iid]])
	return _emergency

func _check_emergencies(f: Folk) -> void:
	for e in _emergency_defs(SimEnv.data().interactions()):
		var iid: String = e[0]
		var d: Dictionary = e[1]
		if f.current != null and f.current.def_id == iid:
			continue
		var queued := false
		for q in f.queue:
			if (q as Interaction).def_id == iid:
				queued = true
		if queued:
			continue
		if Cond.check(d["emergency"], {"folk": f, "object": null, "target": null}):
			var ir := Interaction.create(iid, f, -1, false)
			if ir != null:
				f.enqueue(ir)

## Start the next queued interaction, or let autonomy pick one if the folk is idle.
func _fill(f: Folk) -> void:
	var guard := 0
	while f.current == null and not f.queue.is_empty() and guard < 8:
		guard += 1
		var ir: Interaction = f.queue.pop_front()
		SimEnv.emit("queue_changed", f.id)
		if ir.state != "queued":
			continue
		if ir.can_run(f, null, false) and ir.start():
			return
		if ir.player:
			SimEnv.emit("thought", f.id, "I can't do that right now.")
	if f.current != null or not f.queue.is_empty() or not autonomy_enabled:
		return
	var now := SimEnv.now_min()
	if now < f.idle_until_min:
		return
	var choice := Autonomy.choose(f)
	if choice.is_empty():
		f.idle_until_min = now + IDLE_RETRY_MIN
		NeighborhoodLots.stranded_home(f)          # nothing to do out on the street and a need is pressing: head home
		return
	var ir2 := Interaction.create(str(choice["interaction_id"]), f, int(choice["target_id"]), false)
	if ir2 == null or not ir2.start():
		f.idle_until_min = now + 1
		return
	last_choice[f.id] = choice
	SimEnv.emit("game_event", "autonomy_choice", {"folk_id": f.id, "interaction": choice["interaction_id"], "reason": choice["reason"]})
	SimEnv.emit("queue_changed", f.id)

## Per-folk snapshot for tests / debug UI.
func summary() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		var needs: Dictionary = {}
		for n in f.needs:
			needs[n] = snappedf((f.needs[n] as Stat).value, 0.1)
		out.append({"id": f.id, "name": f.name, "needs": needs, "mood": f.mood_name, "done": f.history_counts.duplicate(),
			"current": f.current.def_id if f.current != null else ""})
	return out
