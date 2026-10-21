extends SceneTree
## Dev probe (not a test): lists the courtroom objects of the courthouse lot. Godot --headless --path . --script res://tools/court_probe.gd
const Kit := preload("res://tests/start_kit.gd")
var _done := false
func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	Kit.new_game("solo", "normal", {}, -1, {"world_seed": 4242, "home_state": "empty"})
	JusticeCareers.staff_town()
	if "--cell" in OS.get_cmdline_user_args():
		var pf0 = SysUtil.folk(Pawn.of())
		print("COURT hold=%s" % str(JusticePlayer.hold(pf0, 120.0, "custody", "In custody")))
		for m in 8:
			Kit.run(10)
			print("COURT cell t+%d: tile=%s L%d cur=%s holding=%s" % [(m + 1) * 10, str(pf0.tile), pf0.level, str(pf0.current.def_id) if pf0.current else "-", str(PlaceHold.holding(pf0.id))])
		print("COURT order: %s" % str(Commands.run({"player_id": 1, "folk_id": pf0.id, "action": "go_home"})))
		JusticePlayer.release(pf0)
		Kit.run(20)
		print("COURT after release: tile=%s L%d holding=%s away=%s" % [str(pf0.tile), pf0.level, str(PlaceHold.holding(pf0.id)), str(Away.is_away(pf0.id))])
		Kit.teardown()
		quit(0)
		return true
	var tids: Array = Story.alive_townies().filter(func(t): return str(t.get("career", "")) == "" ).map(func(t): return int(t["id"]))
	var culprit: int = int(tids[0])
	var c: Dictionary = CaseStore.create("assault", culprit, int(tids[1]), "street", {})
	culprit = Pawn.of()
	c["accused"] = culprit
	c["witnesses"] = [int(tids[2])]
	Courthouse.open(c)
	print("COURT cast=%s juror ids=%s" % [str(c.get("court", {})), str(c.get("jurors", []))])
	for m in 14:
		Kit.run(15)
		for pm in JusticeState.pending.duplicate():
			if SysUtil.now() >= int(pm["due_min"]):
				JusticeState.pending.erase(pm)
				CrimeFlow.run_pending(pm)
		var rows := []
		var pf = SysUtil.folk(Pawn.of())
		rows.append("pawn %s L%d %s" % [str(pf.tile), int(pf.level), str(pf.current.def_id) if pf.current != null else "-"])
		for f in Crowd.crowd_folk():
			if str(f.get_meta("court", "")) != "":
				rows.append("%s %s L%d %s" % [str(f.get_meta("court")), str(f.tile), int(f.level), str(f.current.def_id) if f.current != null else "-"])
		print("COURT t+%dmin: %s" % [(m + 1) * 15, str(rows)])
	print("COURT verdict=%s" % str(c.get("verdict", "")))
	Kit.teardown()
	quit(0)
	return true
