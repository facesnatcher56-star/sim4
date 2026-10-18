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

static var _last_check: Dictionary = {}     # lot_id -> game minute of the last full crowd update
static var _staff_seq: int = 0

static func reset() -> void:
	_last_check.clear()
	CrowdDrive.reset()

static func cfg() -> Dictionary:
	return Venues.cfg()

## Ambient visitors (all lots, or only `lot_id`).
static func crowd_folk(lot_id: String = "") -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("crowd") and (lot_id == "" or str(f.get_meta("crowd")) == lot_id):
			out.append(f)
	return out

static func staff_folk(lot_id: String = "") -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("staff") and (lot_id == "" or str(f.get_meta("staff_lot", "")) == lot_id):
			out.append(f)
	return out

static func npc_ids() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("crowd") or f.has_meta("staff"):
			out.append(int(f.id))
	return out

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

## Take one NPC out of the world right now (a townie who is needed elsewhere).
static func dismiss(f) -> void:
	_remove(f)

static func _remove(f) -> void:
	if f.has_meta("townie_id"):
		RelationshipService.sync_folk(f)
	f.current = null
	f.queue.clear()
	SysUtil.world_remove_folk(int(f.id))

## Per-minute entry point (cheap: the crowd of a lot is only re-balanced every crowd_check_min).
static func update(force: bool = false) -> void:
	var now: int = SimEnv.now_min()
	_step_leavers(now)
	CrowdDrive.drive(now)
	for lot_id in Neighborhood.lot_ids():
		if lot_id == Neighborhood.HOME:
			continue
		if NeighborhoodLots.player_near(lot_id, ACTIVE_RADIUS):
			_update_lot(lot_id, now, force)
		elif _last_check.has(lot_id) and not NeighborhoodLots.player_near(lot_id, DROP_RADIUS):
			clear_npcs(lot_id)

static func _update_lot(lot_id: String, now: int, force: bool) -> void:
	var first: bool = not _last_check.has(lot_id)
	if not force and not first and now - int(_last_check[lot_id]) < int(cfg().get("crowd_check_min", 10)):
		return
	_last_check[lot_id] = now
	WorldIface.coins[-1] = 99999            # NPCs can pay for coffee (household -1); never saved (Economy.to_dict)
	var vtype: String = Venues.type_of_lot(lot_id)
	update_staff(lot_id)
	var target: int = Venues.crowd_target(vtype, SimEnv.hour_f())
	var here: Array = []
	for f in crowd_folk(lot_id):
		if not f.has_meta("leaving"):
			here.append(f)
	for f2 in here.duplicate():      # time is up for some
		if now >= int(f2.get_meta("leave_min", 0)):
			_start_leaving(f2)
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
		_start_leaving(oldest)
		here.erase(oldest)
	# too few: welcome new arrivals (at most 2 per check so the room fills gradually, all at once when the lot wakes up)
	var room: int = mini(target - here.size(), Venues.crowd_cap() - count(lot_id))
	var spawn_max: int = room if (force or first) else mini(room, 2)
	for _i in spawn_max:
		var t: Dictionary = _pick_townie(lot_id, vtype)
		if t.is_empty():
			break
		spawn_npc(t, lot_id, vtype, -1, not (force or first))

static func _pick_townie(lot_id: String, vtype: String) -> Dictionary:
	var present: Array = present_townie_ids()
	var cands: Array = []
	var weights: Array = []
	var pool: Array = Story.alive_townies()
	var resident_only: bool = bool(Venues.type_def(vtype).get("crowd_residents", false))
	if resident_only:
		pool = Neighborhood.residents_of(lot_id)
	var res: Array = SysUtil.residents()
	for t in pool:
		var tid: int = int(t["id"])
		if present.has(tid) or SysUtil.folk(tid) != null:
			continue
		if Story.stage_of(t) in ["baby", "toddler"]:
			continue
		if not resident_only and Story.stage_of(t) == "child":
			continue
		var w: float = 1.0
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
	var f := Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), tid)
	Folk._next_id = keep_next
	f.household_id = -1
	f.age_stage = Story.stage_of(t)
	f.appearance = Genetics.normalize(Genetics.ensure(t))
	f.set_meta("visitor", true)
	f.set_meta("townie_id", tid)
	var sr: Array = Venues.stay_range(vtype)
	var stay: int = stay_override if stay_override > 0 else SysUtil.rng.randi_range(int(sr[0]), int(sr[1]))
	f.set_meta("crowd", lot_id)
	f.set_meta("leave_min", SimEnv.now_min() + stay)
	for n in f.needs:
		(f.needs[n] as Stat).set_value(SysUtil.rng.randf_range(15.0, 65.0))
	var cn: Dictionary = vd.get("crowd_needs", {})
	for n2 in cn:
		if f.needs.has(n2):
			(f.needs[n2] as Stat).set_value(float(cn[n2]) + SysUtil.rng.randf_range(-8.0, 8.0))
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

## An NPC whose time is up walks to the lot's door (one route, computed once by the go_here interaction) and is removed there.
static func _start_leaving(f) -> void:
	if f.has_meta("leaving"):
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
		if not f.has_meta("leaving"):
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
	var c: Dictionary = Story.cfg()
	var names: Array = c.get("first_names", ["Sam"])
	_staff_seq += 1
	var nm: String = "%s (%s)" % [str(names[(_staff_seq * 7 + role.length()) % names.size()]), role.capitalize()]
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
