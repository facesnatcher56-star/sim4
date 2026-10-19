extends RefCounted
## Level of detail on the real map (task 17.3): tier assignment by lot / distance / line of sight, hysteresis (no flapping), promotion on the spot,
## the ACTIVE cap, sets maintained incrementally, the director ticking by tier, TownSim promotion / demotion, save / load of the tier state.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

var _next := 9000

func _npc(tile: Vector2i, lot: String = "cafe"):
	_next += 1
	var f := Folk.create("N%d" % _next, [], _next)
	f.household_id = -1
	f.set_meta("visitor", true)
	f.set_meta("staff", "tester")                      # tiered like the crowd, but nothing in the crowd code touches it
	f.set_meta("staff_lot", lot)
	SysUtil.world_add_folk(f, tile)
	f.idle_until_min = CrowdDrive.NEVER
	return f

func _far_tile(from: Vector2i, min_dist: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := -1
	for lot_id in Neighborhood.lot_ids():
		var rc := NeighborhoodLots.rect_of(lot_id)
		if rc.size == Vector2i.ZERO:
			continue
		var t := rc.position + rc.size / 2
		var d := InterestArea.cheb(t, from)
		if d > bd:
			bd = d
			best = t
	return best if bd >= min_dist else Vector2i(-1, -1)

func _step(minutes: int) -> void:
	for i in minutes:
		SimEnv.clock().advance_minutes(1)

func run() -> Array:
	fails = []
	HoodKit.teardown()
	var folk: Array = HoodKit.new_game("classic", 21, 21)
	var me = folk[0]
	Tiers.refresh()
	var home_rect := NeighborhoodLots.rect_of(Neighborhood.HOME)
	_check(Tiers.of(me) == Tiers.ACTIVE, "household folk are ACTIVE")
	_check(not Tiers.anchors.is_empty(), "the household is the anchor")
	# --- assignment: same lot, street nearby, a closed lot elsewhere, a far lot
	var inside = _npc(home_rect.position + Vector2i(3, 3), "home")
	var street_tile := Vector2i(home_rect.end.x + 2, home_rect.position.y + 5)
	var street = _npc(street_tile)
	var far_t := _far_tile(me.tile, 70)
	var far = _npc(far_t if far_t.x >= 0 else Vector2i(1, 1))
	var closed_lot := ""
	for lot_id in Neighborhood.lot_ids():
		var vt := Venues.type_of_lot(lot_id)
		if lot_id != Neighborhood.HOME and vt in ["cafe", "market", "gym", "library"] and NeighborhoodLots.distance_to(me.tile, lot_id) <= 40:
			closed_lot = lot_id
			break
	var in_closed = null
	if closed_lot != "":
		in_closed = _npc(NeighborhoodLots.rect_of(closed_lot).position + NeighborhoodLots.rect_of(closed_lot).size / 2, closed_lot)
	Tiers.refresh()
	_check(Tiers.of(inside) == Tiers.ACTIVE, "someone in the household's lot is ACTIVE")
	_check(Tiers.of(street) == Tiers.ACTIVE, "a person on the street right outside is ACTIVE (%s)" % Tiers.NAMES[Tiers.of(street)])
	if in_closed != null:
		_check(Tiers.of(in_closed) == Tiers.NEAR, "a person inside another closed building is NEAR (line of sight blocked): %s" % Tiers.NAMES[Tiers.of(in_closed)])
	if far_t.x >= 0:
		_check(Tiers.of(far) in [Tiers.NEAR, Tiers.TOWN], "a person across the map is not ACTIVE (%s)" % Tiers.NAMES[Tiers.of(far)])
	# --- hysteresis: promote at once, demote only after demote_min minutes
	var walker = _npc(far_t if far_t.x >= 0 else Vector2i(1, 1))
	Tiers.refresh()
	var t0: int = Tiers.of(walker)
	_check(t0 != Tiers.ACTIVE, "the walker starts off screen")
	walker.tile = home_rect.position + Vector2i(2, 2)
	Tiers.refresh()
	_check(Tiers.of(walker) == Tiers.ACTIVE, "promotion is immediate")
	var seen: Array = []
	var lis := func(id, old, new_t, _f): if id == int(walker.id): seen.append([old, new_t])
	Tiers.add_listener(lis)
	walker.tile = far_t if far_t.x >= 0 else Vector2i(1, 1)
	for m in 8:
		_step(1)
		Tiers.refresh()
	_check(Tiers.of(walker) == Tiers.ACTIVE, "8 minutes out of range: still ACTIVE (hysteresis)")
	walker.tile = home_rect.position + Vector2i(2, 2)
	Tiers.refresh()
	walker.tile = far_t if far_t.x >= 0 else Vector2i(1, 1)
	for m in 8:
		_step(1)
		Tiers.refresh()
	_check(Tiers.of(walker) == Tiers.ACTIVE, "popping back in resets the demotion timer (no flapping)")
	_step(4)
	Tiers.refresh()
	_check(Tiers.of(walker) != Tiers.ACTIVE, "after demote_min minutes out of range: demoted (%s)" % Tiers.NAMES[Tiers.of(walker)])
	_check(seen.size() == 1, "after the promotion the walker changed tier once only (the final demotion): %s" % str(seen))
	# --- sets are incremental: nobody moved => the classification is reused
	var classified0: int = int(Tiers.stats["classified"])
	Tiers.refresh()
	_check(int(Tiers.stats["classified"]) == classified0, "nobody moved: the cached classification is reused (no rescan)")
	var n_world: int = Tiers.in_world_count()
	SysUtil.world_remove_folk(int(inside.id))
	_check(Tiers.in_world_count() == n_world - 1 and not Tiers.set_of(Tiers.ACTIVE).has(int(inside.id)), "removal leaves the sets at once")
	# --- the director ticks by tier: NEAR people are visited every near_period minutes with the elapsed minutes
	var nears: Array = []
	for i in 10:
		var nf = _npc(far_t if far_t.x >= 0 else Vector2i(1, 1))
		nears.append(nf)
	for k in 12:
		_step(1)
		Tiers.refresh()
	var near_n: int = Tiers.set_of(Tiers.NEAR).size() + Tiers.set_of(Tiers.TOWN).size()
	_check(near_n >= 10, "the ten far people are NEAR / TOWN (%d)" % near_n)
	var dir = HoodKit.root().get_node("SimDirector")
	dir.prof.clear()
	dir.prof_on = true
	var visited := 0
	for k2 in 20:
		dir.tick_minute(1)
	dir.prof_on = false
	for key in dir.prof:
		if str(key).begins_with("other"):
			visited += int((dir.prof[key] as Array)[1])
	var others_expected: int = int(Tiers.set_of(Tiers.NEAR).size() + Tiers.set_of(Tiers.TOWN).size() + Tiers.set_of(Tiers.ACTIVE).size() - 3)
	_check(visited > 0 and visited < 20 * (near_n + others_expected) / 2, "NEAR / TOWN people are not ticked every minute (%d visits over 20 minutes for %d people)" % [visited / 3, near_n])
	# --- the ACTIVE cap: surplus goes to NEAR by distance, stable
	var cap_save = Tiers.cfg().get("active_cap", 60)
	Tiers.cfg()["active_cap"] = 6
	var crowd_here: Array = []
	for i2 in 14:
		crowd_here.append(_npc(home_rect.position + Vector2i(2 + i2 % 5, 2 + i2 / 5), "home"))
	Tiers.refresh()
	var act_n: int = Tiers.set_of(Tiers.ACTIVE).size()
	_check(act_n <= 6, "ACTIVE cap holds (%d <= 6)" % act_n)
	var ch1: int = int(Tiers.stats["changes"])
	Tiers.refresh()
	Tiers.refresh()
	_check(int(Tiers.stats["changes"]) == ch1, "the cap does not flap between refreshes")
	Tiers.cfg()["active_cap"] = cap_save
	Tiers.refresh()
	_check(Tiers.set_of(Tiers.ACTIVE).size() > act_n, "lifting the cap promotes the capped people again")
	# --- save / load of the tier state keeps the hysteresis
	walker.tile = home_rect.position + Vector2i(2, 2)
	Tiers.refresh()
	walker.tile = far_t if far_t.x >= 0 else Vector2i(1, 1)
	_step(3)
	Tiers.refresh()
	var snap: Dictionary = Tiers.to_dict()
	_check(snap["tiers"].has(str(int(walker.id))), "the saved block lists the tiered people")
	_check(Tiers.of(walker) == Tiers.ACTIVE, "the walker is still ACTIVE before the save")
	Tiers.from_dict(snap)
	_check(Tiers.of(walker) == Tiers.ACTIVE, "loading the block keeps it ACTIVE")
	Tiers.remove_listener(lis)
	HoodKit.teardown()
	return fails
