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
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)          # and never sit on top of anything: the run is rendered minimized
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
		fp.tabs.current_tab = fp.tabs.get_tab_idx_from_control(fp.family_box.get_parent())
	if _frames == 60 and _scn == "court":
		JusticeCareers.staff_town()
		var tids: Array = Story.alive_townies().filter(func(t): return str(t.get("career", "")) == "").map(func(t): return int(t["id"]))
		var cc: Dictionary = CaseStore.create("assault", int(tids[0]), int(tids[1]), "street", {})
		cc["accused"] = Pawn.of()
		cc["witnesses"] = [int(tids[2])]
		Courthouse.open(cc)
		root.get_node("Events").selection_changed.emit("folk", Pawn.of())
		root.get_node("Clock").set_speed(2)
	if _scn == "click" and _frames >= 60:
		_click_script()
	if _scn == "tour" and _frames >= 60:
		_tour()
	if _frames == 60 and _scn == "audit":
		# for every object definition in the world: what the click menu shows the pawn (after the curation of data/menus.json)
		var pw = _main.hud._resolve(_main.hud.selected_folk_id)
		var iqa = load("res://scripts/ui/interaction_query.gd")
		var pea = load("res://scripts/ui/pie_entries.gd")
		var seen := {}
		for o in root.get_node("World").all_objects():
			var d: String = str(o.def_id)
			if seen.has(d):
				continue
			seen[d] = true
			var es: Array = iqa.entries_for(pw, "object", o.id)
			var cur: Dictionary = pea.curate(es, d)
			var en := 0
			for e in es:
				if e["enabled"]:
					en += 1
			var gc := 0
			for g in cur["groups"]:
				gc += (g["entries"] as Array).size()
			var why := ""
			if (cur["main"] as Array).is_empty() and (cur["groups"] as Array).is_empty():
				why = " BLOCKED: " + str((cur["blocked"] as Array).map(func(b): return "%s (%s)" % [b["label"], b["reason"]]))
			print("MENU %-20s all=%2d enabled=%2d | main=%d groups=%d(%d)  %s%s" % [d, es.size(), en, (cur["main"] as Array).size(), (cur["groups"] as Array).size(), gc, str((cur["main"] as Array).map(func(x): return x["label"])), why])
		var ses: Array = iqa.self_entries(pw)
		var scur: Dictionary = pea.curate(ses, "self")
		print("MYSELF all=%d main=%s groups=%s blocked=%s" % [ses.size(), str((scur["main"] as Array).map(func(x): return x["label"])), str((scur["groups"] as Array).map(func(g): return g["name"])), str((scur["blocked"] as Array).map(func(b): return b["label"] + ": " + b["reason"]))])
		quit(0)
	if _frames == 60 and _scn.begins_with("pie"):
		var hud9 = _main.hud
		var pawn9 = hud9._resolve(hud9.selected_folk_id)
		var want: String = _scn.substr(3) if _scn.length() > 3 else "mailbox"
		var target9 = null
		for o9 in root.get_node("World").all_objects():
			if str(o9.def_id) == want:
				target9 = o9
				break
		print("PIE target=%s" % str(target9.def_id) if target9 else "PIE none for %s" % want)
		if target9 != null:
			var iq9 = load("res://scripts/ui/interaction_query.gd")
			var es: Array = iq9.entries_for(pawn9, "object", target9.id)
			var en := 0
			for e9 in es:
				if e9["enabled"]:
					en += 1
			print("PIE entries=%d enabled=%d" % [es.size(), en])
			for e9 in es:
				print("  PIE %s | %s | %s | %s" % [e9["id"], e9["category"], str(e9["enabled"]), e9["reason"]])
			hud9.pie.open_for(pawn9, "object", target9.id, Vector2(700, 300))
			if _scn.ends_with("twice") or true:
				hud9.pie.close()
				hud9.pie.open_for(pawn9, "object", target9.id, Vector2(700, 300))
				print("PIE second open children=%d visible=%s" % [hud9.pie.box.get_child_count(), str(hud9.pie.visible)])
	if _frames == 60 and _scn == "door":
		var pw2 = _main.hud._resolve(_main.hud.selected_folk_id)
		var dl: String = ""
		for l in load("res://scripts/world/neighborhood.gd").lots():
			if str(l.get("type", "")) == "townie_home":
				dl = str(l["id"])
				break
		pw2.tile = NeighborhoodLots.street_tile(dl) + Vector2i(0, 1)
		root.get_node("Events").selection_changed.emit("folk", Pawn.of())
		DoorActs.arrive(pw2, dl)
	if _frames == 60 and _scn.begins_with("hiring"):          # 51: a "Help wanted" card in a shop window
		var pw3 = _main.hud._resolve(_main.hud.selected_folk_id)
		for lid in Neighborhood.lot_ids():
			if not JobLeads.hiring_at(str(lid)).is_empty() and not StaffPosts.front(str(lid)).is_empty():
				var fr: Dictionary = StaffPosts.front(str(lid))
				pw3.tile = Vector2i(fr["door"]) - Vector2i(fr["inward"]) * 4 - Vector2i(3, 0)
				print("HIRING shot at %s door=%s" % [lid, str(fr["door"])])
				break
		if _scn == "hiringnight":
			root.get_node("Clock").total_minutes = 21 * 60 + 30
		root.get_node("Events").selection_changed.emit("folk", Pawn.of())
	if _frames == 290 and _scn.begins_with("hiring"):
		var hv = _main.find_child("HelpWantedView", true, false)
		print("HIRING view=%s signs=%d" % [str(hv != null), hv.sign_count() if hv != null else -1])
		if hv != null:
			for c in hv.get_children():
				print("  sign at %s" % str(c.global_position))
	if _frames == 60 and _scn == "cell":
		JusticePlayer.hold(SysUtil.folk(Pawn.of()), 360.0, "custody", "In custody")
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
	if _frames == (900 if _scn in ["court", "cell"] else (300 if _scn in ["door", "hiring", "hiringnight"] else (100000 if _scn in ["click", "tour"] else 100))):
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false


# ---- scripted mouse input for the "click" scene: real InputEvents into the viewport (the user's own mouse is never touched)
func _click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	root.push_input(mm, true)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = pos
		e.global_position = pos
		e.button_index = button
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		root.push_input(e, true)

func _screen_of(def_id: String) -> Vector2:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var pawn = _main.hud._resolve(_main.hud.selected_folk_id)
	var best = null
	var bd: float = 1e9
	for o in root.get_node("World").all_objects():
		if str(o.def_id) == def_id:
			var d: float = Vector2(o.tile).distance_to(Vector2(pawn.tile))
			if d < bd:
				bd = d
				best = o
	if best == null:
		return Vector2(-1, -1)
	return cam.unproject_position(root.get_node("World").tile_to_pos(best.tile) + Vector3(0, 0.25, 0))

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("coord/shots/ui50/%s.png" % name)

func _click_script() -> void:
	var hud = _main.hud
	var pie = hud.pie
	var pawn = hud._resolve(hud.selected_folk_id)
	var mb: Vector2 = _screen_of("mailbox")
	match _frames:
		60:
			root.get_node("Clock").set_speed(1)
			root.get_node("Events").selection_changed.connect(func(k, i): print("CLICK event selection %s %d" % [k, i]))
			var lvv = _main.find_child("LotView", true, false)
			lvv.tile_clicked.connect(func(t, b): print("CLICK tile_clicked %s %d" % [str(t), b]))
			print("CLICK mailbox at %s pick=%s" % [str(mb), str(lvv.pick(mb))])
			_click(mb)
		75:
			print("CLICK1 pie visible=%s children=%d buttons=%d" % [str(pie.visible), pie.box.get_child_count(), pie.entry_buttons.size()])
			_shot("click_1_mailbox")
		80:
			_click(Vector2(1200, 800))          # away: closes the menu (and the click is swallowed by the menu)
		95:
			print("CLICK2 pie visible=%s" % str(pie.visible))
			_click(mb)
		110:
			print("CLICK3 (mailbox again) pie visible=%s children=%d buttons=%d" % [str(pie.visible), pie.box.get_child_count(), pie.entry_buttons.size()])
			_shot("click_2_mailbox_again")
			_click(Vector2(1200, 800))
		125:
			print("CLICK4 menu closed=%s" % str(not pie.visible))
			print("CLICK4 before ground click: tile=%s queue=%s current=%s" % [str(pawn.tile), str(pawn.queue.map(func(q): return "%s->%s" % [q.def_id, str(q.goto_tile)])), str(pawn.current.def_id) if pawn.current else "-"])
			_click(Vector2(1200, 800))
		140:
			print("CLICK5 after ground click: tile=%s queue=%s current=%s" % [str(pawn.tile), str(pawn.queue.map(func(q): return "%s->%s" % [q.def_id, str(q.goto_tile)])), str(pawn.current.def_id) if pawn.current else "-"])
			_click(Vector2(1000, 700), MOUSE_BUTTON_RIGHT)
		155:
			print("CLICK6 right-click ground: pie visible=%s buttons=%d panel=%s" % [str(pie.visible), pie.entry_buttons.size(), str(pie.panel.get_global_rect())])
		165:
			_shot("click_3_ground_menu")
			_click(_screen_of("mailbox"), MOUSE_BUTTON_RIGHT)
		185:
			_shot("click_4_mailbox_rightclick")
			quit(0)


# ---- "tour": open every window of the game in turn and save a shot of each (tools: look through them for anything that is not game-like)
const TOUR := ["map", "money_town", "money_shops", "money_business", "money_homes", "money_bank", "town_life_places", "town_life_study", "town_life_health", "town_life_news", "council", "household", "goals", "career", "help", "settings", "pause", "saveload", "details", "myself", "build", "phone", "casebd", "folkmenu"]
func _tour() -> void:
	var hud = _main.hud
	var idx: int = (_frames - 60) / 14
	var phase: int = (_frames - 60) % 14
	if idx >= TOUR.size():
		quit(0)
		return
	var name: String = TOUR[idx]
	var fid: int = hud.selected_folk_id
	if phase == 0:
		for d in [hud.goals_dialog, hud.career_dialog, hud.money_hub, hud.life_hub, hud.phone_dialog, hud.town_dialog, hud.household_dialog, hud.help_dialog, hud.pause_menu, hud.settings_dialog, hud.case_board]:
			if d != null:
				d.visible = false
		hud.save_menu.visible = false
		hud.pie.close()
		if hud.travel_panel.is_open():
			hud.travel_panel.close_panel()
		if hud.build_panel.active:
			hud.build_panel.set_active(false)
		match name:
			"map": hud.travel_panel.toggle()
			"money_town", "money_shops", "money_business", "money_homes", "money_bank":
				hud.money_hub.tab = name.substr(6)
				hud.money_hub.show_for(fid)
			"town_life_places", "town_life_study", "town_life_health", "town_life_news":
				hud.life_hub.tab = name.substr(10)
				hud.life_hub.show_for(fid)
			"council": hud.town_dialog.show_for(fid)
			"household": hud.household_dialog.show_for(fid)
			"goals": hud.goals_dialog.show_for(fid)
			"career": hud.career_dialog.show_for(fid)
			"help": hud.help_dialog.show_for(fid)
			"settings": hud.settings_dialog.show_for(fid)
			"pause": hud.pause_menu.show_for(-1)
			"saveload":
				hud._refresh_save_menu()
				hud.save_menu.visible = true
			"details": hud.folk_panel.set_expanded(true)
			"myself":
				var me = hud._resolve(fid)
				hud.pie.open_with_entries(me, "self", -1, load("res://scripts/ui/interaction_query.gd").self_entries(me), Vector2(300, 700))
			"build": hud.build_panel.set_active(true)
			"phone":
				load("res://scripts/ui/life_hub_phone.gd").set("app", "")
				hud.phone_dialog.show_for(fid)
			"casebd": hud.case_board.show_for(fid)
			"folkmenu":
				var me2 = hud._resolve(fid)
				for f2 in root.get_node("World").all_folk():
					if int(f2.id) != int(me2.id):
						hud.pie.open_for(me2, "folk", int(f2.id), Vector2(600, 400))
						break
	elif phase == 10:
		print("TOUR %s" % name)
		_shot("tour_%02d_%s" % [idx, name])
