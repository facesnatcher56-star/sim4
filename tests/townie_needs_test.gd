extends RefCounted
## Townies, crowd NPCs and visitors that live in the full sim (loaded world) never sit there with a need at the floor:
## they go home / back to the statistical sim when a need gets low or their time is up, even when no resident is near.

const Kit = preload("res://tests/hood_kit.gd")
const FLOOR := -60.0          # needs run -100..100

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_crowd_and_visitor_days()
	_expired_npc_leaves()
	_loner_regular_stays_healthy()
	_stranger_outdoors_heads_home()
	Kit.teardown()
	return fails

## Non-resident, non-staff folk now in the world.
func _strangers() -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("visitor") and not f.has_meta("staff"):
			out.append(f)
	return out

func _crowd_and_visitor_days() -> void:
	var folk: Array = Kit.new_game("small")
	Incidents.set_level("off")                 # only neglect may kill here, not a rare event or old age
	for tid0 in Story.townies:
		Story.townies[tid0]["age_days"] = 102   # no townie is near the end of life in this window
	Kit.set_time(2, 8)
	Neighborhood.travel([folk[0].id], "cafe", {"instant": true, "free": true, "quiet": true})
	Kit.run(5)
	# an NPC who would stay for ever (so only the need check can send it home) and a visitor invited home
	var t: Dictionary = Story.alive_townies()[0]
	var npc: Folk = Crowd.spawn_npc(t, "park", "park", 100000)
	_check(npc != null, "spawned a long-staying park NPC")
	StoryVisits.invite_over(int(Story.alive_townies()[1]["id"]), int(folk[1].id), 300)
	var worst := 100.0
	var worst_who := ""
	var seen := 0
	for h in TestFixture.pick(48, 14):
		Kit.run(60)
		for f in _strangers():
			seen += 1
			var low: float = Crowd.lowest_need(f)
			if low < worst:
				worst = low
				worst_who = "%s (%s)" % [f.name, f.current.def_id if f.current != null else "-"]
		for tid in Story.townies:
			# a townie may legitimately MOVE OUT OF TOWN (Story daily roll, ~1%/day, alive=false + moved=true): that is not a death
			_check(bool(Story.townies[tid]["alive"]) or bool(Story.townies[tid].get("moved", false)), "townie %d did not die of neglect" % int(tid))
		if not fails.is_empty():
			break
	print("  [townie_needs] %d stranger-samples, lowest need %d (%s)" % [seen, int(worst), worst_who])
	_check(seen > 0, "there were strangers (crowd / visitors) to watch")
	_check(worst > FLOOR, "no townie / NPC / visitor drops to the floor: %d at %s" % [int(worst), worst_who])
	if is_instance_valid(npc) and SysUtil.folk(npc.id) == npc:
		_check(npc.has_meta("leaving") or Crowd.lowest_need(npc) > FLOOR, "the long-staying NPC is fine or leaving")

func _expired_npc_leaves() -> void:
	var folk: Array = Kit.new_game("small")
	Kit.set_time(2, 12)
	var npc: Folk = Crowd.spawn_npc(Story.alive_townies()[0], "park", "park", 30)
	Kit.run(70)
	_check(SysUtil.folk(npc.id) != npc, "an NPC whose time is up is gone (not stuck in the park)")

## A loner who stays at the park for days (the venue serves them: Crowd._serve) never ends with a need at rock bottom (> 0 for the basics).
func _loner_regular_stays_healthy() -> void:
	var folk: Array = Kit.new_game("small")
	Incidents.set_level("off")
	for tid0 in Story.townies:
		Story.townies[tid0]["age_days"] = 102
	Kit.set_time(2, 8)
	Neighborhood.travel([folk[0].id], "park", {"instant": true, "free": true, "quiet": true})
	Kit.run(5)
	var t: Dictionary = Story.alive_townies()[0]
	var npc: Folk = Crowd.spawn_npc(t, "park", "park", 100000)
	if not npc.has_trait("loner"):
		npc.traits.append("loner")
	var worst := {"hunger": 100.0, "bladder": 100.0, "social": 100.0, "fun": 100.0}
	for step in TestFixture.pick(48, 16) * 6:
		Kit.run(10)
		if SysUtil.folk(npc.id) != npc:
			_check(float(worst["hunger"]) > 0.0, "the loner did not leave the park hungry (%d)" % int(worst["hunger"]))
			break                                 # went home when the visit ended: fine, checked up to there
		if step < 36:
			continue                              # the first 6 hours may still carry the venue's tuned starting needs
		for n in worst:
			worst[n] = minf(float(worst[n]), npc.get_stat_value(n))
	for n2 in worst:
		_check(float(worst[n2]) > 0.0 or float(worst[n2]) == 100.0, "a long-staying loner at the park keeps %s above 0 (%d)" % [n2, int(worst[n2])])

## A stranger caught on the street (not in a venue) for more than OUTDOOR_MAX_MIN heads home instead of wandering for days.
func _stranger_outdoors_heads_home() -> void:
	var folk: Array = Kit.new_game("small")
	Kit.set_time(2, 12)
	Neighborhood.travel([folk[0].id], "park", {"instant": true, "free": true, "quiet": true})
	Kit.run(3)
	var npc: Folk = Crowd.spawn_npc(Story.alive_townies()[0], "park", "park", 100000)
	npc.tile = NeighborhoodLots.gate_tile("park")
	npc.current = null
	npc.queue.clear()
	if NeighborhoodLots.lot_at(npc.tile) == "park":
		return                                    # the gate tile is inside this map's lot rect: nothing to test
	Kit.run(Crowd.OUTDOOR_MAX_MIN + 5)
	_check(SysUtil.folk(npc.id) != npc or npc.has_meta("leaving"), "a stranger outside the venue for a while heads home")
