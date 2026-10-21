extends SceneTree
## Screenshot helper for one-character play (not a test). Owner rule: windowed runs go on the SECOND monitor at 1080p, never the main one:
## powershell -File tools/quiet_godot.ps1 --script res://tools/solo_shot.gd -- <scene> out.png
## scenes: start | myself | homes | picker
var _frames := 0
var _main: Node = null
var _out := "user://solo.png"
var _scn := "start"

func _process(_d: float) -> bool:
	if _main == null:
		root.unfocusable = true          # never take the keyboard / mouse focus from the user's other apps
		var args := OS.get_cmdline_user_args()
		if args.size() > 0: _scn = args[0]
		if args.size() > 1: _out = args[1]
		GameSettings.path = "user://settings_shot.cfg"
		GameSettings.load_settings()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var sp = _main.start_picker
	if _frames == 5:
		UIPrefs.set_flag("tips_seen", false)
		_main.title.visible = false
		sp.open()
		sp.visible = true
		if _scn == "creator":
			sp.select("solo")
			sp._open_creator(false)
		elif _scn != "picker":
			sp.select("solo")
			sp._emit_chosen()
	if _frames == 60 and _scn == "myself":
		var hud = _main.hud
		var f = hud._resolve(hud.selected_folk_id)
		for c in hud.folk_row.get_children():
			if c.name == "myself_button":
				c.pressed.emit()
	if _frames == 60 and _scn == "selfdump":
		var hud3 = _main.hud
		var f3 = hud3._resolve(hud3.selected_folk_id)
		print("SELF selected=%d folk=%s" % [hud3.selected_folk_id, str(f3 != null)])
		var iq = load("res://scripts/ui/interaction_query.gd")
		for e in iq.self_entries(f3):
			print("SELF %s | %s | enabled=%s | %s" % [e["id"], e["label"], str(e["enabled"]), e["reason"]])
		quit(0)
	if _frames == 60 and _scn.begins_with("money_"):
		var h6 = _main.hud
		h6.money_hub.tab = _scn.substr(6)
		h6.money_hub.show_for(h6.selected_folk_id)
	if _frames == 60 and _scn in ["household", "council", "goals", "career", "settings", "casebd"]:
		var h7 = _main.hud
		var dd = {"household": h7.household_dialog, "council": h7.town_dialog, "goals": h7.goals_dialog, "career": h7.career_dialog, "settings": h7.settings_dialog, "casebd": h7.case_board}[_scn]
		dd.show_for(h7.selected_folk_id)
	if _frames == 60 and _scn == "buildmode":
		_main.hud.build_panel.set_active(true)
	if _frames == 60 and _scn == "family":
		var fp = _main.hud.folk_panel
		fp.show_folk(_main.hud._resolve(_main.hud.selected_folk_id))
		var tabs = fp.find_child("*", true, false)
		for c in fp.get_children():
			if c is TabContainer:
				c.current_tab = c.get_tab_idx_from_control(fp.family_box.get_parent()) if fp.family_box.get_parent() != null else 0
	if _frames == 60 and _scn == "court":
		JusticeCareers.staff_town()
		var tids: Array = Story.alive_townies().filter(func(t): return str(t.get("career", "")) == "").map(func(t): return int(t["id"]))
		var cc: Dictionary = CaseStore.create("assault", int(tids[0]), int(tids[1]), "street", {})
		cc["accused"] = Pawn.of()
		cc["witnesses"] = [int(tids[2])]
		Courthouse.open(cc)
		root.get_node("Events").selection_changed.emit("folk", Pawn.of())
		root.get_node("Clock").set_speed(2)
	if _frames == 60 and _scn == "walker":
		var pf = _main.hud._resolve(_main.hud.selected_folk_id)
		var vv = _main.find_child("VehicleView", true, false)
		var at: Vector3 = root.get_node("World").tile_to_pos(pf.tile)
		if vv != null:
			for k in 3:
				vv.walkers.add(Vector2(at.x - 2 + k, at.z + 3), Vector2(at.x + 6 + k, at.z + 3), 11 + k * 97)
		print("WALKER view=%s count=%d" % [str(vv != null), vv.walkers.count() if vv != null else -1])
	if _frames == 60 and _scn in ["jobs", "phone", "nophone", "messages"]:
		var hud5 = _main.hud
		var pid5: int = hud5.selected_folk_id
		if _scn == "nophone":
			PhoneOwn.lose(pid5, "stolen", "Your phone was taken as well.")
		load("res://scripts/ui/life_hub_phone.gd").set("app", {"jobs": "jobs", "messages": "messages"}.get(_scn, ""))
		hud5.phone_dialog.show_for(pid5)
	if _frames == 60 and _scn == "homes":
		var hud2 = _main.hud
		hud2.money_hub.tab = "homes"
		hud2.money_hub.show_for(hud2.selected_folk_id)
	if _scn == "skip":
		if _frames == 60:
			var hud4 = _main.hud
			var f4 = hud4._resolve(hud4.selected_folk_id)
			root.get_node("Clock").total_minutes = 22 * 60
			var r4: Dictionary = Commands.run({"player_id": 1, "folk_id": f4.id, "action": "interact", "args": {"interaction_id": "sleep_floor", "target_id": -1}})
			print("SKIP order sleep: %s" % str(r4))
			root.get_node("Clock").set_speed(3)
		if _frames > 170 and _frames < 190 and false:
			print("SKIPF %d total=%d active=%s blocker=%s why=%s dt=%.4f" % [_frames, root.get_node("Clock").total_minutes, str(TimeSkip.active), TimeSkip._blocker(), TimeSkip.why, _d])
		if _frames > 60 and _frames % 30 == 0:
			var f5 = _main.hud._resolve(_main.hud.selected_folk_id)
			var vis := []
			for d in [_main.hud.goals_dialog, _main.hud.career_dialog, _main.hud.money_hub, _main.hud.life_hub, _main.hud.town_dialog, _main.hud.household_dialog, _main.hud.help_dialog, _main.hud.pause_menu, _main.hud.settings_dialog, _main.hud.confirm_dialog, _main.hud.case_prompt, _main.hud.case_board]:
				if d != null and d.visible:
					vis.append(str(d.name))
			print("SKIP speed=%d dialogs=%s accum=%s coop=%s paused=%s procmode=%s" % [root.get_node("Clock").speed, str(vis), str(root.get_node("Clock")._accum), str(root.get_node("Clock").coop_rate), str(paused), str(root.get_node("Clock").process_mode)])
			print("SKIP frame %d clock=%d active=%s why=%s current=%s tile=%s" % [_frames, root.get_node("Clock").total_minutes, str(TimeSkip.active), TimeSkip.reason(), str(f5.current.def_id) if f5.current != null else "-", str(f5.tile)])
		if _frames >= 600:
			quit(0)
		return false
	if _scn == "court" and _frames == 880:
		var lvw = _main.find_child("LevelView", true, false)
		print("LEVELVIEW exists=%s building=%s viewed=%s active=%s nodes=%s" % [str(lvw != null), str(lvw.building) if lvw else "-", str(lvw.viewed) if lvw else "-", str(lvw.active()) if lvw else "-", str(lvw.level_nodes.keys()) if lvw else "-"])
		var pw = _main.hud._resolve(_main.hud.selected_folk_id)
		print("PAWNMETA away=%s info=%s tile=%s lvl=%d cur=%s" % [str(pw.has_meta("away")), str(Away.info(pw.id)), str(pw.tile), pw.level, str(pw.current.def_id) if pw.current else "-"])
		for k in (lvw.level_nodes if lvw else {}):
			print("  L%s objs=%d" % [str(k), (lvw.level_nodes[k]["objs"] as Dictionary).size()])
	if _frames == (900 if _scn == "court" else 100):
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
