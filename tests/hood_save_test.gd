extends RefCounted
## Neighbourhood persistence: the stash of unloaded lots, current lot id, who is where, off-lot (stay) folk, pantry
## and funds survive SaveLoad.snapshot -> JSON -> SaveLoad.restore, and the restored game keeps running and travelling.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	var W: Node = Kit.world()
	_check(Economy.balance(1) == 5000, "small start has 5000 funds (%d)" % Economy.balance(1))
	var small_objs: int = W.objects.size()
	var mira: Folk = folk[0]
	var tobin: Folk = folk[1]
	Kit.set_time(2, 11)
	Kit.run(5)
	var r: Dictionary = Neighborhood.travel([mira.id], "park", {"quiet": true})
	_check(bool(r["ok"]), "travel ok")
	Neighborhood.pantry = 4
	Kit.run(int(r["minutes"]) + 20)
	var park_objs: int = W.objects.size()
	var coins: int = Economy.balance(1)
	var snap: Dictionary = SaveLoad.snapshot("hood")
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	_check(parsed is Dictionary, "snapshot survives JSON")
	var nb: Dictionary = (parsed as Dictionary)["systems"].get("neighborhood", {})
	_check(str(nb.get("current", "")) == "park" and (nb.get("stash", {}) as Dictionary).has("home"), "neighborhood block saved with the home stash")
	# a different game in between
	Kit.new_game("large")
	_check(Neighborhood.current_lot == "home" and Neighborhood.stash.is_empty(), "new game resets the neighbourhood")
	var ok: bool = SaveLoad.restore(parsed)
	_check(ok, "restore returned true")
	_check(Neighborhood.current_lot == "park", "current lot restored (%s)" % Neighborhood.current_lot)
	_check(Neighborhood.stash.has("home"), "home stash restored")
	_check(W.objects.size() == park_objs, "park objects restored (%d vs %d)" % [W.objects.size(), park_objs])
	_check(Neighborhood.pantry == 4, "pantry restored")
	_check(Economy.balance(1) == coins, "funds restored (%d vs %d)" % [Economy.balance(1), coins])
	var f2 = SysUtil.folk(tobin.id)
	_check(f2 != null and f2.has_meta("offlot"), "stay-at-home folk restored off-lot")
	_check(Neighborhood.where(tobin.id) == "home" and Neighborhood.where(mira.id) == "park", "locations restored")
	_check(Away.active.has(tobin.id) and str(Away.info(tobin.id).get("reason", "")) == "stay", "stay interaction restored through Away")
	var m2 = SysUtil.folk(mira.id)
	_check(m2 != null and not m2.has_meta("offlot"), "traveller is on the park lot")
	Kit.run(120)
	_check(f2.get_stat_value("hunger") > -50.0, "restored off-lot folk are still looked after")
	var back: Dictionary = Neighborhood.go_home()
	_check(bool(back["ok"]) and Neighborhood.current_lot == "home", "can travel home after loading")
	_check(W.objects.size() == small_objs, "small home restored from the saved stash (%d vs %d)" % [W.objects.size(), small_objs])
	Kit.run(60)
	_check(not f2.has_meta("offlot"), "folk are back on the lot")
	Kit.teardown()
	return fails
