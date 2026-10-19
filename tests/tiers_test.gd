extends RefCounted
## Tiers (task 17.3 stage 1): assignment by distance / lot / line of sight, hysteresis, the global cap, incremental sets, save / load.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _npc(id: int, tile: Vector2i, lot: String = "cafe"):
	var f := Folk.create("N%d" % id, [], id)
	f.household_id = -1
	f.set_meta("visitor", true)
	f.set_meta("crowd", lot)
	SysUtil.world_add_folk(f, tile)
	return f

func run() -> Array:
	fails = []
	HoodKit.teardown()
	var folk: Array = HoodKit.new_game("classic", 11, 11)
	var w = WorldIface.world()
	var me = folk[0]
	# plain world (no lots): everybody shares the home lot -> ACTIVE
	var a = _npc(9001, me.tile + Vector2i(30, 0))
	Tiers.refresh()
	_check(Tiers.of(me) == Tiers.ACTIVE, "household folk are ACTIVE")
	_check(Tiers.of(a) == Tiers.ACTIVE, "same (only) lot -> ACTIVE")
	# pure geometry on a synthetic map: street folk
	var c: Dictionary = Tiers.cfg()
	var anchors: Array = [{"tile": Vector2i(100, 100), "lot": ""}]
	_check(int(InterestArea.classify(Vector2i(110, 100), "", anchors, c)[0]) == Tiers.ACTIVE, "street 10 tiles away: ACTIVE")
	_check(int(InterestArea.classify(Vector2i(140, 100), "", anchors, c)[0]) == Tiers.NEAR, "street 40 tiles away: NEAR")
	_check(int(InterestArea.classify(Vector2i(200, 100), "", anchors, c)[0]) == Tiers.TOWN, "street 100 tiles away: TOWN")
	_check(int(InterestArea.classify(Vector2i(200, 100), "", [], c)[0]) == Tiers.ACTIVE, "no anchors: everybody ACTIVE")
	# counts and incremental sets
	var ct: Array = Tiers.counts()
	_check(int(ct[0]) == Tiers.set_of(Tiers.ACTIVE).size(), "counts follow the sets")
	var n0: int = Tiers.in_world_count()
	SysUtil.world_remove_folk(9001)
	_check(Tiers.in_world_count() == n0 - 1 and not Tiers.set_of(Tiers.ACTIVE).has(9001), "removal drops the person from the sets at once")
	Tiers.refresh()
	_check(Tiers.stats["resyncs"] <= 1, "no resync was needed (hooks keep the sets in step)")
	HoodKit.teardown()
	return fails
