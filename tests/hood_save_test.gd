extends RefCounted
## Neighbourhood persistence on the one map: the whole map (every lot, regions) is in the world dict, the neighbourhood block
## keeps pantry / visits / meetups / loc / walks. Who is where, funds and the pantry survive SaveLoad.snapshot -> JSON ->
## SaveLoad.restore, the restored game keeps running and travelling, and old (pre-map) saves are refused politely.

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
	var all_objs: int = W.objects.size()
	var mira: Folk = folk[0]
	var tobin: Folk = folk[1]
	Kit.set_time(2, 11)
	Kit.run(5)
	var r: Dictionary = Neighborhood.travel([mira.id], "park", {"quiet": true, "fast": true})
	_check(bool(r["ok"]), "travel ok")
	Neighborhood.pantry = 4
	Kit.run(int(r["minutes"]) + 20)
	var coins: int = Economy.balance(1)
	var where_before: Array = [Neighborhood.where(tobin.id), Neighborhood.where(mira.id)]       # residents on their own may be walking somewhere by now: what must hold is that a load puts them where they were
	var snap: Dictionary = SaveLoad.snapshot("hood")
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	_check(parsed is Dictionary, "snapshot survives JSON")
	var nb: Dictionary = (parsed as Dictionary)["systems"].get("neighborhood", {})
	_check(str(nb.get("home_template", "")) == "small" and not nb.has("stash") and not nb.has("current"), "neighborhood block: bookkeeping only, no stash")
	_check(int(nb.get("pantry", 0)) == 4 and (nb.get("visits", {}) as Dictionary).has("park"), "pantry and visits saved")
	var wd: Dictionary = (parsed as Dictionary)["world"]
	_check(wd.has("regions") and (wd["regions"]["regions"] as Array).size() >= 22, "the world dict carries the regions")
	# a different game in between
	Kit.new_game("large")
	_check(Neighborhood.pantry == 0 and Neighborhood.visits.is_empty(), "new game resets the neighbourhood")
	var ok: bool = SaveLoad.restore(parsed)
	_check(ok, "restore returned true")
	_check(Neighborhood.home_template == "small", "home template restored (%s)" % Neighborhood.home_template)
	_check(W.objects.size() == all_objs, "every lot restored (%d vs %d objects)" % [W.objects.size(), all_objs])
	_check(Neighborhood.pantry == 4, "pantry restored")
	_check(Economy.balance(1) == coins, "funds restored (%d vs %d)" % [Economy.balance(1), coins])
	_check(not (SaveLoad.snapshot("x")["systems"]["economy"]["funds"] as Dictionary).has("-1"), "NPC pocket money is not saved")
	var f2 = SysUtil.folk(tobin.id)
	_check(f2 != null and not f2.has_meta("away"), "folk at home are not hidden")
	_check([Neighborhood.where(tobin.id), Neighborhood.where(mira.id)] == where_before, "locations restored from the tiles (%s, was %s)" % [str([Neighborhood.where(tobin.id), Neighborhood.where(mira.id)]), str(where_before)])
	var m2 = SysUtil.folk(mira.id)
	_check(m2 != null and not m2.has_meta("away"), "traveller is at the park")
	Kit.run(120)
	_check(f2.get_stat_value("hunger") > -50.0, "restored folk are still looked after")
	var back: Dictionary = Neighborhood.go_home([], {"fast": true})
	_check(bool(back["ok"]), "can travel home after loading")
	Kit.run(int(back["minutes"]) + 5)
	_check(Neighborhood.where(mira.id) == "home", "back home")
	_check(int(Neighborhood.visits.get("park", 0)) == 1, "visits survived")
	# old saves
	var old: Dictionary = {"format": "sim4", "version": 2, "folk": [], "world": {}}
	_check(SaveLoad.is_old(old) and not SaveLoad.restore(old) and SaveLoad.last_error == SaveLoad.OLD_SAVE_MSG, "old save refused with a clear message")
	Kit.teardown()
	return fails
