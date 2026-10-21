class_name Interaction
extends RefCounted
## Runtime instance of an interaction definition from data/interactions.json.
## Lifecycle: queued -> walking -> running -> finished | cancelled.

const WALK_MIN_PER_TILE := 0.3     # game minutes per tile (3.3 tiles per game minute): home -> cafe (89 tiles) ~ 27 min, next lot ~ 10 min; FolkView speeds up to keep pace
const PRIORITY := {"low": 0, "normal": 1, "high": 2, "urgent": 3}
const PLAYER_BONUS := 10

var def_id: String = ""
var actor_id: int = -1
## Object id when target_kind == "object", folk id when "folk", -1 otherwise.
var target_id: int = -1
var target_kind: String = "none"   # object | folk | none
var elapsed_min: float = 0.0
var state: String = "queued"
var player: bool = false           # true = explicit player command (beats autonomy)
var slot_idx: int = -1
var success: bool = false
var cancel_reason: String = ""
var path: Array = []               # tiles to walk; UI may animate along it
var travel_total: float = 0.0
var travel_left: float = 0.0
var def: Dictionary = {}
var params: Dictionary = {}        # free-form extras (UI/systems)
var goto_tile: Vector2i = Vector2i(-1, -1)   # "go_here" destination
var goto_level: int = 0                      # level of the "go_here" destination (multi-floor)
var path3: Array[Vector3i] = []              # multi-floor route (x, y, level), empty on the ground; `path` then holds its tiles
var level_extra_min: float = 0.0             # waiting for a lift on the route (game minutes, already in travel_total)
var actor: Folk = null
var obj = null
var target_folk: Folk = null
var _bad: float = 0.0

## Build an instance. Returns null for an unknown definition id.
static func create(p_def_id: String, p_actor: Folk, p_target_id: int = -1, p_player: bool = false) -> Interaction:
	var d: Dictionary = SimEnv.data().interaction_def(p_def_id)
	if d.is_empty():
		return null
	var i := Interaction.new()
	i.def_id = p_def_id
	i.def = d
	i.actor = p_actor
	i.actor_id = p_actor.id
	i.player = p_player
	i.target_id = p_target_id
	i.target_kind = str(d.get("target", "object"))
	if i.target_kind == "self":
		i.target_kind = "none"
		i.target_id = -1
	elif i.target_kind == "folk":
		i.target_folk = WorldIface.get_folk(p_target_id)
	else:
		i.target_kind = "object"
		i.obj = WorldIface.get_object(p_target_id)
	return i

## Player 'Go here' command: walk to a free tile (UI right-click on bare ground).
static func create_goto(p_actor: Folk, tile: Vector2i, p_player: bool = true, level: int = 0) -> Interaction:
	var i := create("go_here", p_actor, -1, p_player)
	if i != null:
		i.goto_tile = tile
		i.goto_level = level
	return i

func label() -> String:
	return str(def.get("label", def_id))

func duration() -> float:
	return float(def.get("duration_min", 10.0))

## How far along a running timed action is, 0..1 (a pure read for the progress ring and the queue chip: it changes nothing). -1 while walking to it or when it has no length.
func progress() -> float:
	if state != "running":
		return -1.0
	var d := duration()
	if d <= 0.0:
		return -1.0
	return clampf(elapsed_min / d, 0.0, 1.0)

func effective_priority() -> int:
	return int(PRIORITY.get(str(def.get("priority", "normal")), 1)) + (PLAYER_BONUS if player else 0)

func is_interruptible() -> bool:
	return bool(def.get("interruptible", true))

func decay_mult_for(need: String) -> float:
	return float((def.get("need_decay_mult", {}) as Dictionary).get(need, 1.0))

func memory_key() -> String:
	match target_kind:
		"object":
			return "obj:%d" % target_id
		"folk":
			return "folk:%d" % target_id
	return "int:%s" % def_id

func note_bad_outcome(amount: float) -> void:
	_bad += amount

func ctx_for(folk: Folk) -> Dictionary:
	return {"folk": folk, "object": obj, "target": target_folk}

## Do the tests allow `folk` to run this on the given target? (Contract: can_run(folk, obj).)
## check_refusal: also apply trait refusals (autonomy does; explicit player commands do not).
func can_run(p_folk: Folk = null, p_obj = null, check_refusal: bool = false) -> bool:
	var f: Folk = p_folk if p_folk != null else actor
	var o = p_obj if p_obj != null else obj
	if not def_runnable(def, f, o, target_folk):
		return false
	if check_refusal and Autonomy.refuses(f, def_id, def, o):
		return false
	return true

## can_run for a bare definition (no instance needed; autonomy calls this for every candidate). Enforces the target
## kind rules, the actor's `tests`, the target's `target_tests` and the social `requires` of folk-to-folk interactions.
static func def_runnable(d: Dictionary, f: Folk, o, target: Folk) -> bool:
	var kind: String = str(d.get("target", "object"))
	if kind != "self" and kind != "folk":
		kind = "object"
	if kind == "object":
		if o == null:
			return false
		var only: Array = d.get("objects", [])
		if not only.is_empty() and not only.has(str(o.def_id)):
			return false
		if not bool(d.get("works_when_broken", false)) and bool(WorldIface.state_get(o, "broken", false)):
			return false
		if not WorldIface.has_free_slot(o, f.id):
			return false
		if WorldIface.bathroom_locked(o, f.id):
			return false                       # the shower or bath of this bathroom is taken: wait outside
	elif kind == "folk":
		if target == null or target.id == f.id:
			return false
		if WorldIface.private_use(target):
			return false                       # nobody chats to somebody in the shower
		var ttests: Array = d.get("target_tests", [])
		if SocialFit.player_controlled(f):
			ttests = SocialFit.hard_tests(ttests)          # the player may try anything that is possible; the other person's reaction is the consequence (SocialReaction)
		if not Cond.check(ttests, {"folk": target, "object": null, "target": f}):
			return false
		if RomanceRules.is_romantic_def(d) and not RomanceRules.allowed(int(f.id), int(target.id)):
			return false
		var req: Array = (d.get("social", {}) as Dictionary).get("requires", [])
		if not req.is_empty() and SocialScoring.check_requires(int(f.id), int(target.id), req) != "":
			return false
	var atests: Array = d.get("tests", [])
	if kind == "folk" and SocialFit.player_controlled(f):
		atests = SocialFit.hard_tests(atests)
	elif SocialFit.player_controlled(f):
		atests = AttemptGates.hard_tests(d, atests)          # task 53: skill and coin gates become attempts (AttemptGates.resolve at the end)
	return Cond.check(atests, {"folk": f, "object": o, "target": target})

## Reserve, plan the walk, and begin. Returns false (and leaves no reservation) when impossible.
func start() -> bool:
	if state != "queued" or actor == null:
		return false
	var use_tile := actor.tile
	if target_kind == "object":
		if obj == null:
			return false
		slot_idx = WorldIface.reserve_any(obj, actor.id)
		if slot_idx < 0:
			return false
		use_tile = WorldIface.use_tile(obj, slot_idx)
	elif target_kind == "folk":
		if target_folk == null:
			return false
		use_tile = WorldIface.meet_tile(target_folk.tile, target_folk.level, actor.tile)      # a target on a seat or bed is met beside it, never on the furniture
	elif goto_tile.x >= 0:
		if goto_level == 0:
			goto_tile = WorldIface.meet_tile(goto_tile, 0, actor.tile)          # a go-here onto furniture or a wall lands beside it
		use_tile = goto_tile
	var n := 0                           # the real route is computed ONCE here; tick() only walks along it
	path = []
	path3 = []
	level_extra_min = 0.0
	var to_level := _dest_level()
	if actor.level != 0 and not WorldIface.level_valid(actor.tile, actor.level):
		actor.level = 0                  # a stale level (teleported / hidden trip): the folk is on the ground
	if actor.level != 0 or to_level != 0:
		n = _plan_levels(use_tile, to_level)            # stairs / lifts: multi-floor route
	elif use_tile != actor.tile:
		path = WorldIface.find_path(actor.tile, use_tile)
		n = path.size() if not path.is_empty() else WorldIface.path_length(actor.tile, use_tile)
	if n < 0:
		_release()
		return false
	travel_total = n * WALK_MIN_PER_TILE / (Health.speed_mult(actor) * Weather.walk_speed_mult()) + float(params.get("delay_min", 0.0))      # injured folk and snow / rain walk slower; delay_min = traffic wait (commutes)
	if params.has("ride_minutes"):
		travel_total = float(params["ride_minutes"])      # task 12: a bike, bus, taxi or car trip decided by TransportTrip
	travel_total += level_extra_min
	travel_left = travel_total
	actor.current = self
	SimEnv.emit("interaction_started", actor.id, def_id, target_id)
	var th: String = str(def.get("thought", ""))
	if th != "":
		actor.last_thought_min = SimEnv.now_min()
		SimEnv.emit("thought", actor.id, th)
	if n == 0:
		_arrive()
	else:
		state = "walking"
	return true

## Level the walk ends on: the object's / the other folk's / the go-here target's.
func _dest_level() -> int:
	if target_kind == "object" and obj != null:
		return int(obj.level) if "level" in obj else 0
	if target_kind == "folk" and target_folk != null:
		return target_folk.level
	return goto_level if goto_tile.x >= 0 else actor.level

## Multi-floor walk: route over stairs / lifts. Returns its length in tile units (stairs and lifts count), -1 if unreachable.
func _plan_levels(use_tile: Vector2i, to_level: int) -> int:
	var from3 := Vector3i(actor.tile.x, actor.tile.y, actor.level)
	var to3 := Vector3i(use_tile.x, use_tile.y, to_level)
	if from3 == to3:
		return 0
	var smult := WorldIface.stair_mult(actor)
	var r := WorldIface.find_route(from3, to3, smult)
	if r.is_empty():
		return -1
	path3 = r
	path = LPos.tiles_of(r)
	level_extra_min = WorldIface.book_route(r, actor.id, WALK_MIN_PER_TILE)
	return int(ceil(WorldIface.route_cost(r, smult)))

func _arrive() -> void:
	state = "running"
	if target_kind == "object" and obj != null:
		actor.tile = WorldIface.use_tile(obj, slot_idx)
		actor.level = _dest_level()
	elif target_kind == "folk" and target_folk != null:
		actor.tile = WorldIface.meet_tile(target_folk.tile, target_folk.level, actor.tile)
		actor.level = target_folk.level
	elif goto_tile.x >= 0:
		actor.tile = goto_tile
		actor.level = goto_level
	actor.posture = str(def.get("posture", "stand"))

func tick(minutes: float) -> void:
	var left := minutes
	if state == "walking":
		var step := minf(left, travel_left)
		travel_left -= step
		left -= step
		if not path.is_empty() and travel_total > 0.0:
			var frac := 1.0 - travel_left / travel_total
			var idx := clampi(int(frac * path.size()) - 1, -1, path.size() - 1)
			if idx >= 0:
				actor.tile = path[idx]
				if not path3.is_empty():
					actor.level = path3[idx].z
		if travel_left <= 0.0001:
			_arrive()
		else:
			return
	if state != "running":
		return
	if not _still_valid():
		return
	if left <= 0.0:
		return
	var run_m := minf(left, maxf(duration() - elapsed_min, 0.0))
	_apply_rates(run_m)
	elapsed_min += run_m
	if elapsed_min >= duration() - 0.0001:
		finish(true)
	elif def.has("end_when") and Cond.check(def["end_when"], ctx_for(actor)):
		finish(true)

func _still_valid() -> bool:
	if target_kind == "object":
		var cur = WorldIface.get_object(target_id)
		if cur == null:
			cancel("object_removed")
			return false
		if not bool(def.get("works_when_broken", false)) and bool(WorldIface.state_get(cur, "broken", false)):
			cancel("broken")
			return false
	elif target_kind == "folk":
		if WorldIface.get_folk(target_id) == null:
			cancel("target_gone")
			return false
	return true

func _apply_rates(m: float) -> void:
	var pm: Dictionary = def.get("per_min", {})
	var sleep_q: float = 1.0
	if (def.get("tags", []) as Array).has("sleep"):
		sleep_q = maxf(1.0 + Creation.add(actor.id, "sleep_quality"), 0.2)          # task 55: insomniac, heavy / light sleeper
	for k in pm:
		var v: float = float(pm[k]) * m
		if str(k) == "energy" and v > 0.0:
			v *= sleep_q
		actor.add_to_stat(str(k), v)
	var xp: Dictionary = def.get("skill_xp_per_min", {})
	for s in xp:
		actor.add_skill_xp(str(s), float(xp[s]) * m)
	var pool: Dictionary = def.get("skill_xp_pool", {})
	if not pool.is_empty():
		var shares: Dictionary = SkillInterest.pool_shares(actor, str(pool.get("pool", "")))
		for s2 in shares:
			actor.add_skill_xp(str(s2), float(pool.get("per_min", 0.0)) * m * float(shares[s2]))
	if target_folk != null:
		var tpm: Dictionary = def.get("target_per_min", {})
		for k in tpm:
			target_folk.add_to_stat(str(k), float(tpm[k]) * m)

func finish(p_success: bool = true) -> void:
	if state == "finished" or state == "cancelled":
		return
	success = p_success
	state = "finished" if p_success else "cancelled"
	var ctx := ctx_for(actor)
	ctx["reason"] = str(def.get("label", def_id))          # ledger text for any coins this interaction moves (Loot coins_add)
	if p_success:
		match AttemptGates.resolve(self):
			"refused":
				pass          # nothing bought, nothing paid
			"poor":
				Loot.apply(AttemptGates.poor_effects(def_id), ctx)
			_:
				Loot.apply(def.get("on_finish", []), ctx)
	else:
		Loot.apply(def.get("on_cancel", []), ctx)
	_step_off_seat()
	_release()
	# Memory of how it went.
	var key := memory_key()
	var broke := target_kind == "object" and obj != null and bool(WorldIface.state_get(obj, "broken", false))
	if broke:
		actor.remember(key, -0.4)
	elif p_success:
		actor.remember(key, -_bad if _bad > 0.0 else 0.08)
	else:
		match cancel_reason:
			"broken":
				actor.remember(key, -0.4)
			"interrupted":
				actor.remember(key, -0.15)
			"preempted":
				actor.remember(key, -0.05)
	if p_success:
		actor.history_counts[def_id] = int(actor.history_counts.get(def_id, 0)) + 1
		Routine.mark_done(actor, def_id)
		var cd := int(def.get("cooldown_min", 0))
		if cd > 0:
			actor.cooldowns[def_id] = SimEnv.now_min() + cd
	actor.history.append(def_id)
	if actor.history.size() > 30:
		actor.history.pop_front()
	if actor.current == self:
		actor.current = null
	actor.posture = "stand"
	actor.refresh_mood()
	SimEnv.emit("interaction_finished", actor.id, def_id, p_success)
	if not p_success and def_id == "go_here" and params.has("lot"):
		NeighborhoodLots.on_walk_cut(actor, cancel_reason, str(params["lot"]))      # a trip cut short by something urgent is resumed afterwards
	SimEnv.emit("queue_changed", actor.id)

## Stop early. reason: "interrupted" | "preempted" | "broken" | "object_removed" | "player" | ...
func cancel(reason: String = "interrupted") -> void:
	if state == "finished" or state == "cancelled":
		return
	if state == "queued":
		state = "cancelled"
		cancel_reason = reason
		return
	cancel_reason = reason
	finish(false)

## Getting up from a seat or bed that sits on the object's own tile: step to the exit tile first, so the next walk and the view never start inside furniture.
func _step_off_seat() -> void:
	if target_kind != "object" or obj == null or slot_idx < 0:
		return
	var st := WorldIface.use_tile(obj, slot_idx)
	if actor.tile != st:
		return
	actor.tile = WorldIface.exit_tile(obj, slot_idx)

func _release() -> void:
	if target_kind == "object" and obj != null and slot_idx >= 0:
		WorldIface.release(obj.id, slot_idx, actor.id)
	slot_idx = -1
