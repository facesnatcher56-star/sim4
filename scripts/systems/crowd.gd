class_name Crowd
extends RefCounted
## Ambient NPCs of the venue lots: townies (with their Genetics appearance) who are tuned to the venue by their starting needs
## and a hidden "regular" buff, plus uniformed staff (barista, trainer, cashier...) that stand at their post. Every venue lot of
## the map has its own crowd (hard cap Venues.crowd_cap() per lot, staff excluded). A lot is only populated while a resident is
## within ACTIVE_RADIUS tiles of its rectangle; it is emptied again once everybody is farther than DROP_RADIUS (P4 replaces this
## with the real interest tiers). NPCs are Folk with household_id -1 and metas: visitor, townie_id, crowd (lot id, leave_min,
## leaving) / staff (role, staff_lot). Their activity AI lives in CrowdDrive.

const STAFF_ID_BASE := 5000
const ACTIVE_RADIUS := 40
const DROP_RADIUS := 64
const OUTDOOR_MAX_MIN := 20     # an NPC who has been outside its venue (on the street, walking) for longer than this heads home
const RECOVER_TO := 30.0        # inside a venue the venue serves its customers (eat, drink, rest, wash): needs below this are pulled up towards it ...
const RECOVER_BASE := 0.3       # ... by this much per minute, plus RECOVER_PER_HOUR per hour of the visit so far (capped at RECOVER_MAX)
const RECOVER_PER_HOUR := 0.15
const RECOVER_MAX := 1.0
const ARRIVE_MIN := -25.0       # a customer arrives with every need above this (the venue-tuned ones are low, never at the go-home floor)
const PICK_SAMPLE := 60           # townies examined per pick (a random window of the free townies)
const NEED_FLOOR := -35.0      # an NPC with a need below this goes home (needs are -100..100; they are re-rolled on the next visit by spawn_npc)

static var _last_check: Dictionary = {}     # lot_id -> game minute of the last full crowd update
static var _staff_seq: int = 0
static var _crowd_idx: Dictionary = {}      # lot id -> {folk id: Folk} of the customers / coworkers (maintained by Tiers.on_added / on_removed via index / unindex)
static var _staff_idx: Dictionary = {}      # lot id -> {folk id: Folk} of the staff
static var _all_crowd: Dictionary = {}      # folk id -> Folk of every crowd NPC (customers)
static var _where: Dictionary = {}          # folk id -> [kind, lot id] so unindex needs no meta

static func reset() -> void:
	_last_check.clear()
	_staff_seq = 0                 # staff ids / names / looks restart with each game (same seed => same town)
	_crowd_idx.clear()
	_staff_idx.clear()
	_all_crowd.clear()
	_where.clear()
	CrowdDrive.reset()

static func cfg() -> Dictionary:
	return Venues.cfg()

## Ambient visitors (all lots, or only `lot_id`).
## (Read from the incremental index: nobody scans the world for the crowd any more.)
static func crowd_folk(lot_id: String = "") -> Array:
	if lot_id == "":
		return _all_crowd.values()
	return (_crowd_idx.get(lot_id, {}) as Dictionary).values()

static func staff_folk(lot_id: String = "") -> Array:
	if lot_id != "":
		return (_staff_idx.get(lot_id, {}) as Dictionary).values()
	var out: Array = []
	for lid in _staff_idx:
		out.append_array((_staff_idx[lid] as Dictionary).values())
	return out

static func npc_ids() -> Array:
	var out: Array = _all_crowd.keys()
	for lid in _staff_idx:
		out.append_array((_staff_idx[lid] as Dictionary).keys())
	return out

## Index hooks (called by Tiers when a folk enters / leaves the world).
static func index(f) -> void:
	var id: int = int(f.id)
	if f.has_meta("crowd"):
		var lot: String = str(f.get_meta("crowd"))
		if not _crowd_idx.has(lot):
			_crowd_idx[lot] = {}
		(_crowd_idx[lot] as Dictionary)[id] = f
		_all_crowd[id] = f
		_where[id] = [0, lot]
	elif f.has_meta("staff"):
		var sl: String = str(f.get_meta("staff_lot", ""))
		if not _staff_idx.has(sl):
			_staff_idx[sl] = {}
		(_staff_idx[sl] as Dictionary)[id] = f
		_where[id] = [1, sl]

static func unindex(id: int) -> void:
	if not _where.has(id):
		return
	var w: Array = _where[id]
	_where.erase(id)
	if int(w[0]) == 0:
		if _crowd_idx.has(w[1]):
			(_crowd_idx[w[1]] as Dictionary).erase(id)
		_all_crowd.erase(id)
	elif _staff_idx.has(w[1]):
		(_staff_idx[w[1]] as Dictionary).erase(id)

static func count(lot_id: String = "") -> int:
	return crowd_folk(lot_id).size()

static func present_townie_ids() -> Array:
	var out: Array = []
	for f in crowd_folk():
		out.append(int(f.get_meta("townie_id", -1)))
	return out

# ------------------------------------------------------------------ lifecycle
## Remove the NPCs of one lot (or every lot).
static func clear_npcs(lot_id: String = "") -> void:
	for f in WorldIface.all_folk().duplicate():
		if f.has_meta("crowd") and (lot_id == "" or str(f.get_meta("crowd")) == lot_id):
			_remove(f)
		elif f.has_meta("staff") and (lot_id == "" or str(f.get_meta("staff_lot", "")) == lot_id):
			_remove(f)
	if lot_id == "":
		_last_check.clear()
	else:
		_last_check.erase(lot_id)

static func lowest_need(f) -> float:
	var low := 100.0
	for n in f.needs:
		low = minf(low, (f.needs[n] as Stat).value)
	return low

## Take one NPC out of the world right now (a townie who is needed elsewhere).
static func dismiss(f) -> void:
	_remove(f)

static func _remove(f) -> void:
	if f.has_meta("townie_id"):
		RelationshipService.sync_folk(f)
		TownSim.on_demoted(f)             # DEMOTION: needs / last place go back into the townie record
	f.current = null
	f.queue.clear()
	SysUtil.world_remove_folk(int(f.id))

## Per-minute entry point (cheap: the crowd of a lot is only re-balanced every crowd_check_min).
static var _pool_cache: Variant = null          # Story.free_townies() for the length of one update (several lots pick in one minute)
static var _res_cache: Variant = null

static func update(force: bool = false) -> void:
	var now: int = SimEnv.now_min()
	_pool_cache = null
	_res_cache = null
	var t := PerfProf.start()
	_step_leavers(now)
	PerfProf.stop("crowd/step_leavers", t)
	t = PerfProf.start()
	CrowdDrive.drive(now)
	PerfProf.stop("crowd/drive", t)
	t = PerfProf.start()
	# Lots near the anchors (task 17.3): the tier manager caches lot -> distance for every lot within DROP_RADIUS of a controlled, visible folk
	# (travellers parked in a holiday zone and folk away do not wake the town); nothing here loops all lots or all residents.
	var near_lots: Dictionary = Tiers.lot_distances(DROP_RADIUS)
	for lot_id in near_lots:
		if lot_id != Neighborhood.HOME and int(near_lots[lot_id]) <= ACTIVE_RADIUS:
			_update_lot(lot_id, now, force)
	for lot_id2 in _last_check.keys():
		if lot_id2 != Neighborhood.HOME and not near_lots.has(lot_id2):
			clear_npcs(lot_id2)
	PerfProf.stop("crowd/lots", t)

static func _update_lot(lot_id: String, now: int, force: bool) -> void:
	var first: bool = not _last_check.has(lot_id)
	if not force and not first and now - int(_last_check[lot_id]) < int(cfg().get("crowd_check_min", 10)):
		return
	_last_check[lot_id] = now
	WorldIface.coins[-1] = 99999            # NPCs can pay for coffee (household -1); never saved (Economy.to_dict)
	var vtype: String = Venues.type_of_lot(lot_id)
	var tp := PerfProf.start()
	update_staff(lot_id)
	PerfProf.stop("crowd/lot staff", tp)
	tp = PerfProf.start()
	CommuteTownies.update(lot_id, now, force or first)       # townies whose job is here (they are not part of the customer count)
	PerfProf.stop("crowd/lot commute", tp)
	tp = PerfProf.start()
	var target: int = Venues.crowd_target(vtype, SimEnv.hour_f())
	var here: Array = []
	for f in crowd_folk(lot_id):
		if not f.has_meta("leaving") and not f.has_meta("coworker"):
			here.append(f)
	for f2 in here.duplicate():      # time is up for some
		if now >= int(f2.get_meta("leave_min", 0)):
			start_leaving(f2)
			here.erase(f2)
	while here.size() > target:      # too many (venue closing / quiet hours): oldest leave
		var oldest = null
		for f3 in here:
			if f3.has_meta("meetup"):
				continue
			if oldest == null or int(f3.get_meta("leave_min", 0)) < int(oldest.get_meta("leave_min", 0)):
				oldest = f3
		if oldest == null:
			break
		start_leaving(oldest)
		here.erase(oldest)
	# too few: welcome new arrivals (at most 2 per check so the room fills gradually, all at once when the lot wakes up)
	var room: int = mini(target - here.size(), Venues.crowd_cap() - count(lot_id) + CommuteTownies.present(lot_id).size())
	var spawn_max: int = room if (force or first) else mini(room, 2)
	PerfProf.stop("crowd/lot balance", tp)
	for _i in spawn_max:
		tp = PerfProf.start()
		var t: Dictionary = _pick_townie(lot_id, vtype)
		PerfProf.stop("crowd/lot pick", tp)
		if t.is_empty():
			break
		tp = PerfProf.start()
		spawn_npc(t, lot_id, vtype, -1, not (force or first) and int(Tiers.lot_distances(DROP_RADIUS).get(lot_id, 999)) <= int(Tiers.cfg().get("active_radius", 24)))
		PerfProf.stop("crowd/lot spawn", tp)

static func _pick_townie(lot_id: String, vtype: String) -> Dictionary:
	var cands: Array = []
	var weights: Array = []
	if _pool_cache == null:
		_pool_cache = Story.free_townies()
	if _res_cache == null:
		_res_cache = SysUtil.residents()
	var pool: Array = _pool_cache
	var resident_only: bool = bool(Venues.type_def(vtype).get("crowd_residents", false))
	if resident_only:
		pool = Neighborhood.residents_of(lot_id)
	var res: Array = _res_cache
	# a window of the pool from a random start (PICK_SAMPLE people looked at, not all 200): the tier-aware picker for big towns
	var n_pool: int = pool.size()
	var start: int = SysUtil.rng.randi_range(0, maxi(n_pool - 1, 0))
	for pi in mini(n_pool, PICK_SAMPLE):
		var t: Dictionary = pool[(start + pi) % n_pool]
		var tid: int = int(t["id"])
		if _all_crowd.has(tid) or SysUtil.folk(tid) != null or CommuteTownies.busy_elsewhere(t, lot_id, SimEnv.now_min()):
			continue
		if Story.stage_of(t) in ["baby", "toddler"]:
			continue
		if not resident_only and Story.stage_of(t) == "child":
			continue
		var w: float = 1.0
		var sched: Dictionary = TownSim.where_cached(t, SimEnv.now_min())      # the cheap schedule: nobody asleep at the venue, regulars where they are expected
		if str(sched["act"]) == TownSim.SLEEP:
			continue
		if str(sched["lot"]) == lot_id:
			w += 3.0
		for r in res:
			if RelationshipService.knows(int(r.id), tid):
				w += 1.5
		cands.append(t)
		weights.append(w)
	var pick = SysUtil.pick_weighted(cands, weights)
	return pick if pick != null else {}

## Create one ambient NPC from a townie record, at the lot's spawn tiles.
## `arrive`: the NPC appears at the lot's street gate and walks in to a spot inside (a lot waking up fills at once without it).
static func spawn_npc(t: Dictionary, lot_id: String, vtype: String, stay_override: int = -1, arrive: bool = false) -> Folk:
	var tid: int = int(t["id"])
	var vd: Dictionary = Venues.type_def(vtype)
	var entries: Array = NeighborhoodLots.spawns_of(lot_id)
	var tile: Vector2i = entries[SysUtil.rng.randi_range(0, entries.size() - 1)]
	var inside: Vector2i = tile
	if arrive:
		tile = NeighborhoodLots.gate_tile(lot_id)
	var keep_next: int = Folk._next_id
	var f := Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), tid, Sexes.of_townie(t))
	Folk._next_id = keep_next
	f.household_id = -1
	f.age_stage = Story.stage_of(t)
	f.appearance = Genetics.normalize(Genetics.ensure(t))
	f.set_meta("visitor", true)
	f.set_meta("townie_id", tid)
	var sr: Array = Venues.stay_range(vtype)
	var stay: int = stay_override if stay_override > 0 else SysUtil.rng.randi_range(int(sr[0]), int(sr[1]))
	f.set_meta("crowd", lot_id)
	f.set_meta("arrived_min", SimEnv.now_min())
	f.set_meta("leave_min", SimEnv.now_min() + stay)
	TownSim.apply_to_folk(f, t, SimEnv.now_min())          # PROMOTION: plausible needs from the townie's curves (same data as the hourly TOWN update)
	var cn: Dictionary = vd.get("crowd_needs", {})
	for n2 in cn:
		if f.needs.has(n2):
			(f.needs[n2] as Stat).set_value(maxf(float(cn[n2]) + SysUtil.rng.randf_range(-8.0, 8.0), ARRIVE_MIN))
	RelationshipService.restore_folk(f)
	SysUtil.world_add_folk(f, tile)
	Aging.apply_stage_buff(f)
	f.idle_until_min = CrowdDrive.NEVER          # NPCs are driven by CrowdDrive (cheap), never by the full Autonomy search
	f.set_meta("next_act", SimEnv.now_min() + SysUtil.rng.randi_range(1, 4))
	if arrive and tile != inside:
		var walk_in := Interaction.create_goto(f, inside, false)
		if walk_in != null:
			f.enqueue(walk_in)
	var cb: String = str(vd.get("crowd_buff", ""))
	if cb != "":
		f.add_buff(cb)
	return f

## Stand-in for what the customer does at the venue (eat, drink, chat, play): inside the lot the needs creep back up the longer the visit lasts,
## so a regular never sinks to rock bottom; outside it (street, walking) nothing serves them and after OUTDOOR_MAX_MIN they head home.
static func _serve(f, now: int, k: float = 1.0) -> void:
	var lot_id: String = str(f.get_meta("crowd"))
	if NeighborhoodLots.lot_at(f.tile) != lot_id:
		var since: int = int(f.get_meta("outside_since", now))
		f.set_meta("outside_since", since)
		if now - since > OUTDOOR_MAX_MIN:
			start_leaving(f)
		return
	f.remove_meta("outside_since")
	recover(f, float(now - int(f.get_meta("arrived_min", now))) / 60.0, k)

## The host feeds, rests and lets the stranger wash up: every need below RECOVER_TO creeps back up. `hours` = how long the visit has lasted.
## Also used for the guests of a household visit (StoryVisits) while they are inside a lot, so a visitor never leaves in a bad state.
static func recover(f, hours: float, k: float = 1.0) -> void:
	var rate: float = minf(RECOVER_MAX, RECOVER_BASE + RECOVER_PER_HOUR * hours)
	for n in f.needs:
		var st: Stat = f.needs[n]
		if st.value < RECOVER_TO:
			st.add(minf(rate * k, RECOVER_TO - st.value))

## An NPC whose time is up walks to the lot's door (one route, computed once by the go_here interaction) and is removed there.
static func start_leaving(f) -> void:
	if f.has_meta("leaving"):
		return
	if Tiers.of(f) != Tiers.ACTIVE and not f.has_meta("meetup") and not f.has_meta("coworker"):
		_remove(f)               # NEAR / TOWN people are off screen: they leave at once (no walk to the door, no path query)
		return
	f.set_meta("leaving", SimEnv.now_min() + int(cfg().get("leave_walk_min", 12)))
	f.cancel_current("leaving")
	f.clear_queue()
	var ir := Interaction.create_goto(f, NeighborhoodLots.entry_tile(str(f.get_meta("crowd"))), false)
	if ir != null:
		f.enqueue(ir)

## Cheap per-minute check: nobody path-finds here any more. Gone once at the door (or when the walk-out time is up).
static func _step_leavers(now: int) -> void:
	for f in crowd_folk():
		var per: int = Tiers.period_of(int(f.id))      # NEAR / TOWN people are looked at every few minutes, with the elapsed minutes applied
		if per > 1 and (now + int(f.id)) % per != 0:
			continue
		if not f.has_meta("leaving"):
			if now >= int(f.get_meta("leave_min", 0)) or lowest_need(f) < NEED_FLOOR:      # time is up (also far from the player) or a need is low: go home
				start_leaving(f)
			else:
				_serve(f, now, float(per))
			continue
		if f.tile == NeighborhoodLots.entry_tile(str(f.get_meta("crowd"))) or now >= int(f.get_meta("leaving")) or (f.current == null and f.queue.is_empty()):
			_remove(f)

# ------------------------------------------------------------------ staff
static func update_staff(lot_id: String) -> void:
	var staff_defs: Array = LotLoader.template(Neighborhood.template_of(lot_id)).get("staff", [])
	var origin: Vector2i = NeighborhoodLots.rect_of(lot_id).position
	var vtype := Venues.type_of_lot(lot_id)
	var open: bool = Venues.is_open_type(vtype)
	var h: float = SimEnv.hour_f()
	var have: Dictionary = {}
	for f in staff_folk(lot_id):
		have[str(f.get_meta("staff"))] = f
	for sd in staff_defs:
		var role: String = str(sd["role"])
		var hrs: Array = sd.get("hours", [])
		var on_duty: bool = open and (hrs.is_empty() or (h >= float(hrs[0]) and h < float(hrs[1])))
		if on_duty and not have.has(role):
			_spawn_staff(role, Vector2i(int(sd["tile"][0]), int(sd["tile"][1])) + origin, lot_id)
		elif not on_duty and have.has(role):
			_remove(have[role])
	for sf in staff_folk(lot_id):           # staff never get hungry or tired
		for n in sf.needs:
			(sf.needs[n] as Stat).set_value(60.0)

static func _spawn_staff(role: String, tile: Vector2i, lot_id: String) -> Folk:
	_staff_seq += 1
	var nr := RandomNumberGenerator.new()
	nr.seed = _staff_seq * 7919 + role.length()
	var nm: String = "%s (%s)" % [Names.pick_first([], nr), role.capitalize()]
	var keep_next: int = Folk._next_id
	var f := Folk.create(nm, [], STAFF_ID_BASE + _staff_seq)
	Folk._next_id = keep_next
	f.household_id = -1
	f.age_stage = "adult"
	var sg := RandomNumberGenerator.new()
	sg.seed = nm.hash()
	f.appearance = FolkOutfits.for_role(role, GeneticsUnique.registry(), sg)      # role uniform, distinct from everyone in town
	f.set_meta("visitor", true)
	f.set_meta("staff", role)
	f.set_meta("staff_lot", lot_id)
	for n in f.needs:
		(f.needs[n] as Stat).set_value(60.0)
	SysUtil.world_add_folk(f, tile)
	Aging.apply_stage_buff(f)
	var ir := Interaction.create("sys_staff", f, -1, false)
	if ir != null:
		f.enqueue(ir)
	return f