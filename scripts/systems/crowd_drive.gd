class_name CrowdDrive
extends RefCounted
## "Autonomy-lite" of the ambient NPCs (see Crowd). Autonomy.choose() path-finds to every candidate (~30 ms on a busy lot), far
## too much for ambient extras, so crowd NPCs pick their next activity here: a random sample of the usable (object,
## interaction) pairs OF THEIR OWN LOT scored by the same need urgency x advertised strength, multiplied by their hidden
## venue-regular buff (autonomy_mult by tag/need). They idle a few minutes between activities and sometimes chat with a
## nearby resident or another NPC.

const NEVER := 1 << 30
const SKIP_TAGS := ["chore", "repair", "clean", "sleep", "bed", "baby_care", "career", "staff"]

static var _acts: Dictionary = {}      # lot_id -> {"key": String, "list": Array} cached (object, interaction) pool

static func reset() -> void:
	_acts.clear()

static func drive(now: int) -> void:
	var w = WorldIface.world()
	if w == null:
		return
	var gap: Array = Venues.cfg().get("npc_idle_gap", [4, 12])
	for f in Crowd.crowd_folk():
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
			if Crowd.lowest_need(f) < -30.0:       # nothing to do here and getting needy: head home
				Crowd.start_leaving(f)
			continue
		var ir := Interaction.create(str(pick["iid"]), f, int(pick["oid"]), false)
		if ir != null and ir.can_run(f, null, false):
			f.enqueue(ir)

static func _acts_of(lot_id: String, w) -> Array:
	var key: String = str(w.objects.size())
	var c: Dictionary = _acts.get(lot_id, {})
	if c.get("key", "") == key:
		return c["list"]
	var list: Array = []
	var idefs: Dictionary = SimEnv.data().interactions()
	for o in w.all_objects():
		if o.is_wall_mounted() or o.is_floor_layer() or NeighborhoodLots.lot_at(o.tile) != lot_id:
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
			list.append({"oid": int(o.id), "iid": str(iid), "adv": adv, "tags": tags})
	_acts[lot_id] = {"key": key, "list": list}
	return list

static func _pick_activity(f, w) -> Dictionary:
	var acts: Array = _acts_of(str(f.get_meta("crowd")), w)
	if acts.is_empty():
		return {}
	var mult_tags: Dictionary = {}
	for b in f.buffs:
		var am: Dictionary = SimEnv.data().buff_def(str(b["id"])).get("autonomy_mult", {})
		for k in am:
			mult_tags[k] = float(mult_tags.get(k, 1.0)) * float(am[k])
	var best: Array = []
	var weights: Array = []
	for _i in 14:
		var c: Dictionary = acts[SysUtil.rng.randi_range(0, acts.size() - 1)]
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
	var lot_id: String = str(f.get_meta("crowd"))
	for r in SysUtil.residents():
		if SysUtil.is_away(r) or NeighborhoodLots.lot_at(r.tile) != lot_id:
			continue
		if absi(r.tile.x - f.tile.x) + absi(r.tile.y - f.tile.y) <= 9:
			targets.append(r)
	for n in Crowd.crowd_folk(lot_id):
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
