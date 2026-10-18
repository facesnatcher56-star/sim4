class_name Crowd
extends RefCounted
## Ambient NPCs for the loaded venue: townies (with their Genetics appearance) who run the normal autonomy, tuned to
## the venue by their starting needs and a hidden "regular" buff (autonomy_mult by tag), plus uniformed staff (barista,
## trainer, cashier...) that stand at their post. Hard cap: Venues.crowd_cap() (default 6) ambient NPCs, staff excluded.
## NPCs are Folk with household_id -1 and metas: visitor, townie_id, crowd (leave_min, leaving) / staff (role).

const STAFF_ID_BASE := 5000

static var _last_check: int = -999
static var _staff_seq: int = 0
static var _acts: Array = []          # cached (object, interaction) activity pool of the loaded lot
static var _acts_key: String = ""
const SKIP_TAGS := ["chore", "repair", "clean", "sleep", "bed", "baby_care", "career", "staff"]
const NEVER := 1 << 30

static func reset() -> void:
	_last_check = -999
	_acts.clear()
	_acts_key = ""

static func cfg() -> Dictionary:
	return Venues.cfg()

static func crowd_folk() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("crowd"):
			out.append(f)
	return out

static func staff_folk() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("staff"):
			out.append(f)
	return out

static func npc_ids() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("crowd") or f.has_meta("staff"):
			out.append(int(f.id))
	return out

static func count() -> int:
	return crowd_folk().size()

static func present_townie_ids() -> Array:
	var out: Array = []
	for f in crowd_folk():
		out.append(int(f.get_meta("townie_id", -1)))
	return out

static func _cur_type() -> String:
	return Venues.type_of_lot(Neighborhood.current_lot)

# ------------------------------------------------------------------ lifecycle
static func clear_npcs() -> void:
	for f in WorldIface.all_folk().duplicate():
		if f.has_meta("crowd") or f.has_meta("staff"):
			_remove(f)

static func _remove(f) -> void:
	if f.has_meta("townie_id"):
		RelationshipService.sync_folk(f)
	f.current = null
	f.queue.clear()
	SysUtil.world_remove_folk(int(f.id))

## Called right after a lot has been loaded into the World.
static func on_lot_loaded(lot_id: String) -> void:
	_last_check = -999
	if lot_id == Neighborhood.HOME:
		WorldIface.coins.erase(-1)           # keep the pocket money of NPCs out of home saves
		return
	WorldIface.coins[-1] = 99999            # NPCs can pay for coffee (household -1)
	update_staff(lot_id)
	update(true)

## Per-minute entry point (cheap: real work only every crowd_check_min).
static func update(force: bool = false) -> void:
	if Neighborhood.current_lot == Neighborhood.HOME:
		return
	var now: int = SimEnv.now_min()
	_step_leavers(now)
	_drive(now)
	if not force and now - _last_check < int(cfg().get("crowd_check_min", 10)):
		return
	_last_check = now
	var lot_id: String = Neighborhood.current_lot
	var vtype := _cur_type()
	update_staff(lot_id)
	var target: int = Venues.crowd_target(vtype, SimEnv.hour_f())
	var here: Array = []
	for f in crowd_folk():
		if not f.has_meta("leaving"):
			here.append(f)
	# time is up for some
	for f2 in here.duplicate():
		if now >= int(f2.get_meta("leave_min", 0)):
			_start_leaving(f2)
			here.erase(f2)
	# too many (venue closing / quiet hours): oldest leave
	while here.size() > target:
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
	# too few: welcome new arrivals (at most 2 per check so the room fills gradually, all at once on lot load)
	var room: int = mini(target - here.size(), Venues.crowd_cap() - count())
	var spawn_max: int = room if force else mini(room, 2)
	for _i in spawn_max:
		var t: Dictionary = _pick_townie(lot_id, vtype)
		if t.is_empty():
			break
		spawn_npc(t, lot_id, vtype)

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

## Create one ambient NPC from a townie record.
static func spawn_npc(t: Dictionary, lot_id: String, vtype: String, stay_override: int = -1) -> Folk:
	var tid: int = int(t["id"])
	var vd: Dictionary = Venues.type_def(vtype)
	var entries: Array = Neighborhood._entry_tiles()
	var tile: Vector2i = entries[SysUtil.rng.randi_range(0, entries.size() - 1)]
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
	f.idle_until_min = NEVER          # NPCs are driven by _drive() (cheap), never by the full Autonomy search
	f.set_meta("next_act", SimEnv.now_min() + SysUtil.rng.randi_range(1, 4))
	var cb: String = str(vd.get("crowd_buff", ""))
	if cb != "":
		f.add_buff(cb)
	return f

static func _start_leaving(f) -> void:
	if f.has_meta("leaving"):
		return
	f.set_meta("leaving", SimEnv.now_min() + int(cfg().get("leave_walk_min", 12)))
	f.cancel_current("leaving")
	f.clear_queue()
	var ir := Interaction.create("sys_staff", f, -1, false)      # a no-op that keeps autonomy quiet while they walk out
	if ir != null:
		f.enqueue(ir)

static func _step_leavers(now: int) -> void:
	var w = WorldIface.world()
	if w == null:
		return
	var entry: Vector2i = Neighborhood.entry_tile()
	for f in crowd_folk():
		if not f.has_meta("leaving"):
			continue
		if f.tile == entry or now >= int(f.get_meta("leaving")):
			_remove(f)
			continue
		var path: Array = w.find_path(f.tile, entry)
		if path.is_empty():
			_remove(f)
			continue
		f.tile = path[mini(1, path.size() - 1)]
		if f.tile == entry:
			_remove(f)

# ------------------------------------------------------------------ staff
static func update_staff(lot_id: String) -> void:
	var tid: String = Neighborhood.template_of(lot_id)
	var staff_defs: Array = LotLoader.template(tid).get("staff", [])
	var vtype := Venues.type_of_lot(lot_id)
	var open: bool = Venues.is_open_type(vtype)
	var h: float = SimEnv.hour_f()
	var have: Dictionary = {}
	for f in staff_folk():
		have[str(f.get_meta("staff"))] = f
	for sd in staff_defs:
		var role: String = str(sd["role"])
		var hrs: Array = sd.get("hours", [])
		var on_duty: bool = open and (hrs.is_empty() or (h >= float(hrs[0]) and h < float(hrs[1])))
		if on_duty and not have.has(role):
			_spawn_staff(role, Vector2i(int(sd["tile"][0]), int(sd["tile"][1])))
		elif not on_duty and have.has(role):
			_remove(have[role])
	for sf in staff_folk():           # staff never get hungry or tired
		for n in sf.needs:
			(sf.needs[n] as Stat).set_value(60.0)

static func _spawn_staff(role: String, tile: Vector2i) -> Folk:
	var c: Dictionary = Story.cfg()
	var names: Array = c.get("first_names", ["Sam"])
	_staff_seq += 1
	var nm: String = "%s (%s)" % [str(names[(_staff_seq * 7 + role.length()) % names.size()]), role.capitalize()]
	var keep_next: int = Folk._next_id
	var f := Folk.create(nm, [], STAFF_ID_BASE + _staff_seq)
	Folk._next_id = keep_next
	f.household_id = -1
	f.age_stage = "adult"
	f.set_meta("visitor", true)
	f.set_meta("staff", role)
	for n in f.needs:
		(f.needs[n] as Stat).set_value(60.0)
	SysUtil.world_add_folk(f, tile)
	Aging.apply_stage_buff(f)
	var ir := Interaction.create("sys_staff", f, -1, false)
	if ir != null:
		f.enqueue(ir)
	return f

# ------------------------------------------------------------------ NPC behaviour ("autonomy-lite")
## Autonomy.choose() path-finds to every candidate (~30 ms on a busy lot), far too much for ambient extras, so crowd
## NPCs pick their next activity here: a random sample of the lot's usable (object, interaction) pairs scored by the
## same need urgency x advertised strength, multiplied by their hidden venue-regular buff (autonomy_mult by tag/need).
## They idle a few minutes between activities and sometimes chat with a nearby resident or another NPC.
static func _drive(now: int) -> void:
	var w = WorldIface.world()
	if w == null:
		return
	var gap: Array = Venues.cfg().get("npc_idle_gap", [4, 12])
	for f in crowd_folk():
		if f.has_meta("leaving"):
			continue
		f.idle_until_min = NEVER
		if f.current != null or not f.queue.is_empty():
			continue
		if now < int(f.get_meta("next_act", 0)):
			continue
		f.set_meta("next_act", now + SysUtil.rng.randi_range(int(gap[0]), int(gap[1])))
		if SysUtil.chance(0.22) and _try_chat(f):
			continue
		var pick: Dictionary = _pick_activity(f, w)
		if pick.is_empty():
			continue
		var ir := Interaction.create(str(pick["iid"]), f, int(pick["oid"]), false)
		if ir != null and ir.can_run(f, null, false):
			f.enqueue(ir)

static func _build_acts(w) -> void:
	var key: String = "%s:%d" % [Neighborhood.current_lot, w.objects.size()]
	if key == _acts_key:
		return
	_acts_key = key
	_acts.clear()
	var idefs: Dictionary = SimEnv.data().interactions()
	for o in w.all_objects():
		if o.is_wall_mounted() or o.is_floor_layer():
			continue
		for iid in o.def.get("interactions", []):
			var d: Dictionary = idefs.get(iid, {})
			if d.is_empty() or not bool(d.get("autonomous", true)) or str(d.get("target", "object")) != "object":
				continue
			var tags: Array = d.get("tags", [])
			var skip := false
			for t in SKIP_TAGS:
				if tags.has(t):
					skip = true
			if skip or str(iid).begins_with("sys_") or str(iid).begins_with("repair") or str(iid).begins_with("clean"):
				continue
			var adv: Dictionary = d.get("advertises", o.def.get("advertises", {}))
			_acts.append({"oid": int(o.id), "iid": str(iid), "adv": adv, "tags": tags})

static func _pick_activity(f, w) -> Dictionary:
	_build_acts(w)
	if _acts.is_empty():
		return {}
	var mult_tags: Dictionary = {}
	for b in f.buffs:
		var am: Dictionary = SimEnv.data().buff_def(str(b["id"])).get("autonomy_mult", {})
		for k in am:
			mult_tags[k] = float(mult_tags.get(k, 1.0)) * float(am[k])
	var best: Array = []
	var weights: Array = []
	for _i in 14:
		var c: Dictionary = _acts[SysUtil.rng.randi_range(0, _acts.size() - 1)]
		if f.on_cooldown(str(c["iid"])) or w.free_slot(int(c["oid"])) == -1:
			continue
		var score: float = 0.4
		for need in c["adv"]:
			if f.needs.has(need):
				var st: Stat = f.needs[need]
				var u: float = pow((st.max - st.value) / maxf(st.max - st.min, 1.0), 2.0) * 10.0
				score += u * float(c["adv"][need]) * float(mult_tags.get(need, 1.0))
		for t in c["tags"]:
			score *= float(mult_tags.get(t, 1.0))
		best.append(c)
		weights.append(score)
	var pick = SysUtil.pick_weighted(best, weights)
	return pick if pick != null else {}

static func _try_chat(f) -> bool:
	var targets: Array = []
	for r in SysUtil.residents():
		if r.has_meta("offlot") or SysUtil.is_away(r) or Neighborhood.where(int(r.id)) != Neighborhood.current_lot:
			continue
		if absi(r.tile.x - f.tile.x) + absi(r.tile.y - f.tile.y) <= 9:
			targets.append(r)
	for n in crowd_folk():
		if n != f and not n.has_meta("leaving") and absi(n.tile.x - f.tile.x) + absi(n.tile.y - f.tile.y) <= 6:
			targets.append(n)
	var t = SysUtil.pick(targets)
	if t == null:
		return false
	var ir := Interaction.create("chat", f, int(t.id), false)
	if ir == null or not ir.can_run(f, null, false):
		return false
	f.enqueue(ir)
	return true
