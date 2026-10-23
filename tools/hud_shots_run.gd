extends Node
## Task 59: screenshots of the HUD and every window at one window size, for before / after review (not a test).
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- run=res://tools/hud_shots_run.gd <out dir> size=1280x720
var _out := "user://hud/"
var _size := Vector2i(1920, 1080)
var m
var hud
var fid := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			var p: PackedStringArray = a.substr(5).split("x")
			_size = Vector2i(int(p[0]), int(p[1]))
		elif not a.begins_with("--") and not a.begins_with("run="):
			_out = a.trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(_out)
	TestFixture.isolate_user_files()
	var w := get_window()
	w.unfocusable = true
	w.size = _size
	DisplayServer.window_set_size(_size)
	m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	_go.call_deferred()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await _w(6)
	get_tree().root.get_texture().get_image().save_png("%s%dx%d_%s.png" % [_out, _size.x, _size.y, n])


func _show(d, n: String) -> void:
	d.show_for(fid)
	await _shot(n)
	d.visible = false


func _go() -> void:
	await _w(5)
	await _shot("00_title")
	m.title.visible = false
	m.start_picker.open()
	m.start_picker.visible = true
	await _shot("01_start_picker")
	m.start_picker.select("solo")
	m.start_picker._open_creator(false)
	await _shot("02_creator")
	UIPrefs.set_flag("tips_seen", false)
	m.start_picker._emit_chosen()
	await _w(60)
	hud = m.hud
	fid = hud.selected_folk_id
	var f = hud._resolve(fid)
	var lv = m.find_child("LotView", true, false)
	lv.focus_tile(f.tile)
	lv.set_zoom(12.0)
	await _shot("03_first_screen")
	hud.tips.visible = false
	var clk = get_tree().root.get_node("Clock")
	clk.set_speed(1)
	await _w(120)
	await _shot("04_hud_day")
	for d in [["goals", hud.goals_dialog], ["career", hud.career_dialog], ["household", hud.household_dialog], ["help", hud.help_dialog],
			["casebook", hud.case_board], ["share", hud.share_hub], ["holidays", hud.vacation_dialog], ["council", hud.town_dialog], ["pause", hud.pause_menu]]:
		await _show(d[1], "w_" + str(d[0]))
	for t in LifeHub.TABS:
		hud.life_hub.tab = t[0]
		await _show(hud.life_hub, "town_" + str(t[0]))
	for t in BankHub.TABS:
		hud.money_hub.tab = t[0]
		await _show(hud.money_hub, "money_" + str(t[0]))
	for app in ["", "jobs", "contacts"]:
		LifeHubPhone.app = app
		await _show(hud.phone_dialog, "phone_" + (app if app != "" else "home"))
	LifeHubPhone.app = ""
	for t in GameSettings.TABS:
		hud.settings_dialog.tab = t[0]
		await _show(hud.settings_dialog, "settings_" + str(t[0]))
	hud.build_panel.set_active(true)
	await _shot("build")
	hud.build_panel.set_active(false)
	# the click menus
	var obj = null
	for o in World.all_objects():
		if str(o.def_id) == "mailbox" and NeighborhoodLots.lot_at(o.tile) == NeighborhoodLots.lot_at(f.tile):
			obj = o
	if obj != null:
		var sp: Vector2 = lv.screen_pos("object", int(obj.id)) if lv.screen_pos("object", int(obj.id)) is Vector2 else Vector2(700, 400)
		hud.pie.open_for(f, "object", int(obj.id), sp)
		await _shot("menu_object")
		hud.pie.close()
	hud.pie.open_with_entries(f, "self", -1, InteractionQuery.self_entries(f), Vector2(500, 500))
	await _shot("menu_self")
	hud.pie.close()
	var other = null
	for o in WorldIface.all_folk():
		if int(o.household_id) != int(f.household_id) and str(o.age_stage) == "adult":
			other = o
			break
	if other != null:
		f.tile = other.tile + Vector2i(1, 0)
		Neighborhood.refresh_view(f.id)
		lv.focus_tile(other.tile)
		await _w(20)
		hud.pie.open_for(f, "folk", int(other.id), Vector2(_size.x * 0.5, _size.y * 0.45))
		await _shot("menu_person")
		hud.pie.close()
		# toasts and balloons next to each other
		UIU.notify("You bought a bike for 140 coins.", "good")
		UIU.notify("The rent is overdue. Pay it, or the landlord starts eviction.", "warn")
		UIU.notify("It has started to rain.", "weather")
		SimEnv.emit("speech", int(other.id), "Have you tried the new place on Elm Court?", int(f.id))
		SimEnv.emit("thought", int(f.id), "Not yet. Is it any good?")
		await _w(30)
		await _shot("toasts_balloons_day")
		clk.total_minutes = clk.day() * 1440 + 30
		await _w(60)
		SimEnv.emit("speech", int(other.id), "Late night again?", int(f.id))
		SimEnv.emit("thought", int(f.id), "Time for bed.")
		await _w(30)
		await _shot("balloons_night")
	# a timed action (progress ring) and low needs
	f.add_to_stat("hunger", -85.0)
	f.add_to_stat("energy", -70.0)
	for o in World.all_objects():
		if str(o.def_id) == "mailbox" and NeighborhoodLots.lot_at(o.tile) == Neighborhood.lot_of(f):
			UIU.enqueue(f, "odd_job", int(o.id))
			break
	clk.total_minutes = clk.day() * 1440 + 14 * 60
	lv.focus_tile(f.tile)
	await _w(240)
	await _shot("hud_busy_low_needs")
	get_tree().quit(0)
