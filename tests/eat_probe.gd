extends SceneTree
## Reviewer tool (not a test; the runner skips it): what a solo NPC-driven character does for 8 days (interaction counts, coins, hunger).
var _main: Node = null
var _frames := 0
var _zid := -1
var _ints: Dictionary = {}
var _trips: Dictionary = {}
func _process(_d: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var r := RandomNumberGenerator.new()
		r.seed = 310064332
		var h := HouseholdSetup.make_household("solo", r)
		_main.start_new_game(h, str(Scenario.def("solo").get("start_id", "small")), {"scenario": "solo", "difficulty": "normal", "world_seed": 310064332, "funds": Scenario.funds_for("solo", "normal")})
	if _frames == 15:
		Players.table.clear()
		_zid = int(SysUtil.residents()[0].id)
		root.get_node("Events").interaction_started.connect(func(fid, iid, _t):
			if int(fid) == _zid:
				_ints[str(iid)] = int(_ints.get(str(iid), 0)) + 1)
	if _frames > 15 and _frames <= 15 + 8 * 24:
		var c = root.get_node("Clock")
		for m in 60:
			c.advance_minutes(1)
		if (_frames - 15) % 24 == 0:
			var f = SysUtil.folk(_zid)
			print("EAT day %d coins %d hunger %.0f" % [c.day(), WorldIface.get_coins(int(f.household_id)), f.get_stat_value("hunger")])
		return false
	if _frames == 16 + 8 * 24:
		var keys := _ints.keys()
		keys.sort_custom(func(a, b): return _ints[a] > _ints[b])
		for k in keys:
			print("EAT int %4d %s" % [_ints[k], k])
		print("EAT trips %s" % str(_trips))
		print("EAT placeauto stats %s last %s" % [str(PlaceAuto.stats), str(PlaceAuto.last)])
		quit(0)
	return false
