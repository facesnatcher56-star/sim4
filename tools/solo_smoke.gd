extends SceneTree
## "It runs" check of one-character play (not a test suite): boot, start a new solo game through the real NewGame path, play one in-game day
## (the pawn is ordered to do a few things), print a few facts. Any script error in the output is the failure.
##   Godot --headless --path . --script res://tools/solo_smoke.gd [-- days]
const Kit := preload("res://tests/start_kit.gd")
var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var days := 1
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			days = int(a)
	var folk: Array = Kit.new_game("solo", "normal", {}, -1, {"world_seed": 4242, "home_state": "empty"})
	var f: Folk = folk[0]
	var verbose := "--toasts" in OS.get_cmdline_user_args()
	if verbose:
		SimEnv.events().notification.connect(func(text, kind): print("  [d%d %02d:00 %s] %s" % [Kit.clock().day(), Kit.clock().hour(), kind, text]))
	print("SMOKE start: folk=%d pawn=%s coins=%d rung=%s homeless=%s day=%d hour=%d" % [folk.size(), str(Pawn.is_pawn(f)), Economy.balance(f.household_id), SoloHome.rung, str(SoloHome.homeless), Kit.clock().day(), Kit.clock().hour()])
	for h in 24 * days:
		Kit.run(60)
	print("SMOKE housing: rung=%s homeless=%s lot_here=%s shelter_nights=%d" % [SoloHome.rung, str(SoloHome.homeless), Neighborhood.lot_of(f), SoloHome.shelter_nights])
	print("SMOKE end: alive=%s coins=%d hunger=%.0f energy=%.0f day=%d current=%s bills=%d" % [str(SysUtil.folk(f.id) != null), Economy.balance(f.household_id), f.get_stat_value("hunger"), f.get_stat_value("energy"), Kit.clock().day(), str(f.current.def_id) if f.current != null else "-", Economy.outstanding(f.household_id).size()])
	Kit.teardown()
	quit(0)
	return true
