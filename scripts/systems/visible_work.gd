class_name VisibleWork
extends RefCounted
## A visible job (task 11, a few careers): the folk works ON the lot during the shift - walks to a station object of the workplace
## (cafe counter, gym machines, library desk) and does the career's `work_*` interaction (data/commute.json), instead of vanishing.
## The shift is an Away record flagged visible (Away.begin_visible): pay, performance and events are identical to a hidden shift.
## Idle gaps between jobs are short, autonomy is held off, needs follow the same slow rates as the Away rabbit hole, and a player
## command (or a collapsing need) ends the shift early like a recalled one.

## Station objects of a lot that accept the career's work interaction.
static func stations(lot_id: String, career_id: String) -> Array:
	var iid: String = Workplace.visible_job(career_id)
	var kinds: Array = SimEnv.data().interaction_def(iid).get("objects", [])
	var out: Array = []
	var w = WorldIface.world()
	if w == null or iid == "":
		return out
	for o in w.all_objects():
		if kinds.has(o.def_id) and NeighborhoodLots.lot_at(o.tile) == lot_id:
			out.append(o)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out

## Where the worker first stands: next to its station (one per folk, so coworkers spread out), else the lot's staff post, else the door.
static func post_tile(f, lot_id: String, career_id: String) -> Vector2i:
	var st: Array = stations(lot_id, career_id)
	if not st.is_empty():
		var o = st[int(f.id) % st.size()]
		var t: Vector2i = WorldIface.use_tile(o, 0)
		if WorldIface.world().is_walkable(t):
			return t
	var sp: Vector2i = Workplace.staff_tile(lot_id)
	return sp if sp.x >= 0 else NeighborhoodLots.entry_tile(lot_id)

static func step(f, t: Dictionary, now: int) -> void:
	var fid: int = int(f.id)
	var rec: Dictionary = Away.active.get(fid, {})
	if rec.is_empty():
		return
	if now >= int(rec["until_min"]):
		Commute.finish_visible(f, true)
		return
	if CareerShifts.player_busy(f) or CareerShifts.is_critical(f):
		Commute.finish_visible(f, false)
		return
	var rates: Dictionary = SimEnv.data().interaction_def(Away.IID).get("per_min", {})      # the same slow need drift as the rabbit hole
	for n in rates:
		f.add_to_stat(str(n), float(rates[n]))
	f.idle_until_min = now + 5
	if f.current != null or not f.queue.is_empty():
		return
	if now < int(t.get("next_job", 0)):
		return
	var gap: Array = (Workplace.cfg().get("visible", {}) as Dictionary).get("gap_min", [1, 4])
	t["next_job"] = now + SysUtil.rng.randi_range(int(gap[0]), int(gap[1]))
	var career: String = str(t["career"])
	var iid: String = Workplace.visible_job(career)
	var free: Array = []
	var w = WorldIface.world()
	for o in stations(str(t["lot"]), career):
		if w.free_slot(int(o.id)) != -1:
			free.append(o)
	var o2 = SysUtil.pick(free)
	if o2 == null:
		return
	var ir := Interaction.create(iid, f, int(o2.id), false)
	if ir != null and ir.can_run(f, null, false):
		ir.params["visible_job"] = true
		f.enqueue(ir)
