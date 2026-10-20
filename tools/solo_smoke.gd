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
	if "--rough" in OS.get_cmdline_user_args():
		_rough(f, Kit)
		Kit.teardown()
		quit(0)
		return true
	if "--ladder" in OS.get_cmdline_user_args():
		_ladder(f, Kit)
		Kit.teardown()
		quit(0)
		return true
	for h in 24 * days:
		Kit.run(60)
	print("SMOKE housing: rung=%s homeless=%s lot_here=%s shelter_nights=%d" % [SoloHome.rung, str(SoloHome.homeless), Neighborhood.lot_of(f), SoloHome.shelter_nights])
	print("SMOKE end: alive=%s coins=%d hunger=%.0f energy=%.0f day=%d current=%s bills=%d" % [str(SysUtil.folk(f.id) != null), Economy.balance(f.household_id), f.get_stat_value("hunger"), f.get_stat_value("energy"), Kit.clock().day(), str(f.current.def_id) if f.current != null else "-", Economy.outstanding(f.household_id).size()])
	Kit.teardown()
	quit(0)
	return true

## Targeted check of the housing code: buy something, move to the bedsit and back, give the flat up, play two days on the street.
func _ladder(f: Folk, Kit) -> void:
	Economy.deposit(f.household_id, 600, "smoke money")
	var sofa: int = WorldIface.world().place_object("sofa_bed", NeighborhoodLots.entry_tile("home") + Vector2i(-3, -3), 0)
	print("SMOKE sofa placed id=%d" % sofa)
	if sofa >= 0:
		Economy.owner[sofa] = f.household_id
	for step in ["bedsit", "starter", "better"]:
		var r: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "move", "rung": step}})
		print("SMOKE move %s -> %s | home lot=%s phys=%s pawn at lot=%s tile=%s coins=%d" % [step, str(r), Neighborhood.label_of("home"), str(SoloHome.phys), Neighborhood.lot_of(f), str(f.tile), Economy.balance(f.household_id)])
		Kit.run(60 * 30)
		print("SMOKE after 30h: alive=%s lot=%s hunger=%.0f rung=%s" % [str(SysUtil.folk(f.id) != null), Neighborhood.lot_of(f), f.get_stat_value("hunger"), SoloHome.rung])
	var g: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "give_up_home"}})
	print("SMOKE give up -> %s | lot=%s tile=%s homeless=%s" % [str(g), Neighborhood.lot_of(f), str(f.tile), str(SoloHome.homeless)])
	var t: Dictionary = Neighborhood.travel([f.id], "home")
	print("SMOKE travel home while homeless -> %s" % str(t.get("reason", "")))
	var sh: Dictionary = Neighborhood.travel([f.id], "shelter", {"instant": true})
	print("SMOKE travel to shelter -> ok=%s lot=%s" % [str(sh.get("ok")), Neighborhood.lot_of(f)])
	Kit.run(60 * 24)
	var sr: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "interact", "args": {"interaction_id": "sleep_rough", "target_id": -1}})
	print("SMOKE sleep_rough order -> %s current=%s" % [str(sr), str(f.current.def_id) if f.current != null else "-"])
	Kit.run(60 * 24)
	print("SMOKE end ladder: alive=%s coins=%d day=%d rough_nights=%d" % [str(SysUtil.folk(f.id) != null), Economy.balance(f.household_id), Kit.clock().day(), SoloHome.rough_nights])

## Targeted check of the Kiln Quarter: move to the bedsit, run broke, answer the crew offers "yes", force a drive-by, play a week.
func _rough(f: Folk, Kit) -> void:
	Economy.deposit(f.household_id, 300, "smoke money")
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "move", "rung": "bedsit"}})
	print("SMOKE move bedsit -> %s district=%s roughness=%.2f" % [str(r.get("ok")), SoloDistricts.district_of("home"), SoloDistricts.roughness_of("kiln")])
	Economy.spend(f.household_id, maxi(Economy.balance(f.household_id) - 40, 0), "smoke spend")
	JusticePlayer.auto = "yes"
	for d in 8:
		if d == 3:
			SoloCrews.due_abs = (Kit.clock().day() - 1) * 24 + Kit.clock().hour() + 2
			SoloCrews.district_id = "kiln"
			print("SMOKE forcing a drive-by at abs hour %d" % SoloCrews.due_abs)
		Kit.run(60 * 24)
		print("SMOKE day %d: coins=%d member=%s heat=%.0f refusals=%d records=%d burglary_mult=%.1f robbery_mult=%.1f" % [Kit.clock().day(), Economy.balance(f.household_id), str(SoloPressure.member), SoloPressure.heat, SoloPressure.refusals, (JusticeState.records.get(f.id, []) as Array).size(), SoloDistricts.mult("home", "burglary"), SoloDistricts.mult("home", "robbery")])
