extends Node
## SimDirector: ticks every folk once per game minute (needs, buffs, interactions, autonomy).
## In the game the SimScheduler runs it every minute (registered by connect_clock, row in sim_registry.gd); tests can drive it directly with tick_minute().
## (No class_name: it is an autoload singleton named SimDirector.)

const IDLE_RETRY_MIN := 3

var enabled: bool = true
var autonomy_enabled: bool = true
var ticks: int = 0
## folk_id -> last autonomy choice dictionary (interaction_id, reason, score...)
var last_choice: Dictionary = {}
## Profiling (tests/perf_probe.gd): label -> [usec, calls] while prof_on.
var prof_on: bool = false
var prof: Dictionary = {}

func _prof(label: String, t0: int) -> void:
	var rec: Array = prof.get(label, [0, 0])
	rec[0] += Time.get_ticks_usec() - t0
	rec[1] += 1
	prof[label] = rec

var _sched: SimScheduler = null

## New game / test reset: the tick counter and the strangers' owed-minutes table feed the stranger cadence ((ticks + id) % STRANGER_PERIOD), so they
## must restart with each game for the same seed to give the same game.
func reset_state() -> void:
	ticks = 0
	_stranger_acc.clear()
	_last_tick.clear()
	_clock = 0
	last_choice.clear()

func _ready() -> void:
	connect_clock()

## Register this director's per-minute tick in the scheduler of the current Clock (idempotent; rebinds when SimEnv swapped the Clock).
func connect_clock() -> void:
	var s := SimScheduler.of(SimEnv.clock())
	if s != _sched or not s.has_group(SimRegistry.director_group(self)):
		disconnect_clock()
		_sched = s
		SimRegistry.install_director(s, self)

func disconnect_clock() -> void:
	if _sched != null:
		_sched.remove_group(SimRegistry.director_group(self))
		_sched = null

func _exit_tree() -> void:
	disconnect_clock()

func _on_minute(_total: int) -> void:
	if enabled:
		tick_minute(1)

## Advance the folk by `minutes` (normally 1) by TIER (task 17.3): the ACTIVE set (household, visitors, responders and the ambient people near the
## household) every minute; the NEAR / TOWN sets only when their turn comes ((ticks + id) % period), with the elapsed minutes applied. Nothing here
## scans the world: the sets are maintained by the Tiers manager.
func tick_minute(minutes: int = 1) -> void:
	ticks += 1
	_clock += minutes
	Tiers.ensure_sync()
	for f in (Tiers.set_of(Tiers.ACTIVE) as Dictionary).values():
		tick_folk(f, float(minutes))
	for tier in [Tiers.NEAR, Tiers.TOWN]:
		var st: Dictionary = Tiers.set_of(tier)
		if st.is_empty():
			continue
		for id in st.keys():
			if Tiers.due(int(id), ticks):
				_tick_tiered(st[id], int(id))

var _clock: int = 0                         # game minutes advanced through tick_minute (feeds the elapsed minutes of the NEAR / TOWN ticks)
var _last_tick: Dictionary = {}             # folk id -> _clock at its last full tick

func _tick_tiered(f: Folk, id: int) -> void:
	var elapsed: float = float(_clock - int(_last_tick.get(id, _clock - Tiers.period_of(id))))
	_last_tick[id] = _clock
	if _last_tick.size() > 4000:
		_last_tick.clear()
	tick_folk(f, maxf(elapsed, 1.0))

## Strangers (crowd NPCs, townies, visitors: household_id <= 0 and meta "visitor") decay needs / buffs / mood once per STRANGER_PERIOD minutes, with
## the elapsed minutes (decay is linear, so the result is the same up to the clamp and the threshold buffs lagging a few minutes).
## Their interactions, emergencies and autonomy still run every minute. Household members are always ticked every minute.
const STRANGER_PERIOD := 5
var _stranger_acc: Dictionary = {}       # folk id -> minutes not yet applied to needs / buffs / mood

func _tick_stranger(f: Folk, minutes: float) -> void:
	var owed: float = float(_stranger_acc.get(f.id, 0.0)) + minutes
	if (ticks + int(f.id)) % STRANGER_PERIOD == 0:
		_stranger_acc.erase(f.id)
		tick_folk(f, minutes, owed)
	else:
		_stranger_acc[f.id] = owed
		tick_folk(f, minutes, 0.0)

## `passive_minutes` = minutes of need decay / buff ageing to apply (default: `minutes`; 0 = skip them this time).
func tick_folk(f: Folk, minutes: float = 1.0, passive_minutes: float = -1.0) -> void:
	var t0 := Time.get_ticks_usec() if prof_on else 0
	var hh := ("household " if prof_on and int(f.household_id) > 0 and not f.has_meta("visitor") else "other ")
	var pm: float = minutes if passive_minutes < 0.0 else passive_minutes
	if pm > 0.0:
		f.tick_needs(pm)
		f.tick_buffs(pm)
		f.update_thresholds()
		f.refresh_mood()
	if prof_on:
		_prof(hh + "needs/buffs/mood", t0)
		t0 = Time.get_ticks_usec()
	if pm > 0.0 or passive_minutes < 0.0:           # emergencies follow the needs: strangers look at them when their needs change (every STRANGER_PERIOD)
		_check_emergencies(f)
	if f.current != null:
		f.current.tick(minutes)
	if prof_on:
		_prof(hh + "emergency+interaction tick", t0)
		t0 = Time.get_ticks_usec()
	_fill(f)
	if prof_on:
		_prof(hh + "fill (autonomy)", t0)
	if ticks % 360 == 0:
		f.prune_memory()

## Task 58: a player order starts in the frame it is given (not on the next minute tick): the head of the queue begins now if nothing is running.
func start_now(f: Folk) -> void:
	if f == null or f.current != null or f.queue.is_empty():
		return
	_fill(f)
	var clk := get_node_or_null("/root/Clock")
	var part: float = float(clk.get("_accum")) if clk != null and int(clk.get("speed")) > 0 else 0.0
	if f.current != null and str(f.current.state) == "walking" and part > 0.0:
		# started part-way through a game minute: the next tick credits that whole minute, so the walk is that much longer
		# (it still arrives on time) and the view counts from the click (params.lead_in, FolkMotion._lead_walk)
		f.current.travel_total += part
		f.current.travel_left += part
		f.current.params["lead_in"] = part

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
			ThoughtVoice.urgent(f.id, "I can't do that right now.")
			SimEnv.emit("game_event", "order_refused", {"folk_id": f.id, "interaction": ir.def_id, "target_id": ir.target_id, "why": ir.fail_reason})
	if f.current != null or not f.queue.is_empty() or not autonomy_enabled:
		return
	if Pawn.is_pawn(f):          # zero autonomy for the player's character
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
