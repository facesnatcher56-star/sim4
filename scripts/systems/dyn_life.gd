class_name DynLife
extends RefCounted
## Task 32c: more dynamic behaviour for residents. Builds on Autonomy (utility AI), AutonomyVariety (boredom), Routine (data/routines.json: weekday /
## weekend / mood / trait routines), Circadian and PlaceAuto (outings); adds spontaneous plans (DynPlans), reactions to events (DynReact) and
## household initiative (DynSocial). Content: data/content_dynamic.json (idle interactions, reactions, plan buffs). Tuning: data/dynamic_life.json.
## Tiers: ACTIVE / NEAR residents get real things to do; far-off residents (STATISTICAL) get a small stat nudge instead. Nothing runs per minute;
## the dice are stateless (master seed + folk + hour + plan), so nothing here is saved and a loaded game rolls the same dice.
static var off: bool = false          # tests / debugging: switch the whole thing off

const IDLE_SLICES := 12            # a decision looks at one twelfth of the idle fillers, rotating every 5 minutes (cheap, and more variety)

## May the folk be given an idle filler now? Nothing pressing (no need above urgency 3), nothing queued, on the home lot, in the day phase.
static func idle_ok(f) -> bool:
	if off or not f.queue.is_empty():
		return false
	for n in f.needs:
		if Autonomy.urgency(f, str(n)) > 3.0:
			return false
	return Circadian.in_phase(f, "day") and (WorldIface.stub != null or WorldIface.world() == null or NeighborhoodLots.lot_at(f.tile) == PlayerLots.home_of(f))

static func cfg() -> Dictionary:
	return SysUtil.table("dynamic_life")

static func enabled() -> bool:
	return not off and bool(cfg().get("enabled", true))

static func install() -> void:
	ContentMerge.install(SimEnv.data().get_table("content_dynamic"))

## Stateless dice in [0, 1): the same (folk, moment, salt) always rolls the same.
static func dice(a: int, b: int, c: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(Storyteller.master_seed), a, b, c])
	return r.randf()

static func is_weekend() -> bool:
	return SysUtil.weekday() >= 5

## Product of the factors of the traits the folk has.
static func trait_factor(f, table: Dictionary) -> float:
	var m := 1.0
	for t in table:
		if f.has_trait(str(t)):
			m *= float(table[t])
	return m

static func in_hours(hours: Array, h: float) -> bool:
	for w in hours:
		if h >= float(w[0]) and h < float(w[1]):
			return true
	return false

static func awake(f) -> bool:
	if f == null or SysUtil.is_away(f):
		return false
	if f.current != null:
		for t in f.current.def.get("tags", []):
			if t == "sleep":
				return false
	return true

static func at_home(f) -> bool:
	var l: String = Neighborhood.lot_of(f)
	var h: String = PlayerLots.home_of(f)
	return l == h or (l == "" and WorldIface.world() == null)

## Residents whose day the dice shape, in a stable order.
static func people() -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if SysUtil.is_away(f) or JusticeState.inmates.has(int(f.id)) or Hospital.is_in(int(f.id)):
			continue
		out.append(f)
	return out

## Queue an interaction at the front of the folk's day. Returns true when it was accepted.
static func queue(f, iid: String, target_id: int = -1) -> bool:
	var ir := Interaction.create(iid, f, target_id, false)
	if ir == null or not ir.can_run(f, null, false):
		return false
	f.enqueue(ir)
	return true

## Somebody who must not be pulled away: a walk (a trip, a commute), an order of the player, a high-priority job, sleep, work, an emergency, the toilet.
static func busy_with_must(f) -> bool:
	if not f.queue.is_empty():
		return true
	if f.current == null:
		return false
	if str(f.current.def_id) == "go_here" or f.current.player or f.current.effective_priority() >= 2:
		return true
	for t in f.current.def.get("tags", []):
		if t in ["sleep", "emergency", "work", "toilet"]:
			return true
	return false

# ------------------------------------------------------------------ clock / event hooks (SimRegistry, SystemsManager)
static func on_hour(hour: int) -> void:
	if not enabled():
		return
	var abs_hour: int = (SysUtil.day() - 1) * 24 + hour
	var ppl := people()
	for f in ppl:
		if awake(f) and not busy_with_must(f):
			DynPlans.roll(f, abs_hour)
	DynSocial.on_hour(ppl, abs_hour)

static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	if enabled():
		DynReact.on_event(ev_name, payload)

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if success and iid == "call_friend" and enabled():
		DynPlans.finish_call(folk_id)
