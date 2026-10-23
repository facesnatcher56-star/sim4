extends Node
## Task 61 review run (not a test): plays a solo start's first week and prints every line the player sees (NOTE ...), applies for a job,
## and saves shots of day 1 and the first week.
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- run=res://tools/start61_run.gd <out dir> bg=ex_con
var _out := "user://start61/"
var _bg := "nobody"
var _job := ""
var _iv := false
var m
var hud
var lv
var clk
var fid := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("bg="):
			_bg = a.substr(3)
		elif a.begins_with("job="):
			_job = a.substr(4)
		elif a == "iv":
			_iv = true
		elif a == "yes":
			(JobApps.cfg()["weights"] as Dictionary)["no_interview_base"] = 0.6          # the review run: a likely yes
		elif not a.begins_with("--") and not a.begins_with("run="):
			_out = a.trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(_out)
	TestFixture.isolate_user_files()
	var w := get_window()
	w.unfocusable = true
	w.size = Vector2i(1600, 900)
	m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	_go.call_deferred()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await _w(10)
	get_tree().root.get_texture().get_image().save_jpg(_out + n + ".jpg", 0.85)
	print("SHOT ", n)


func _note(text: String, kind: String) -> void:
	print("NOTE d%d %02d:%02d [%s] %s" % [clk.day(), clk.hour(), clk.minute(), kind, text])


## Advance the clock to day d, hour h, a few minutes per frame (the sim runs; the view keeps up), keeping the pawn fed and rested after day 1.
func _until(d: int, h: float) -> void:
	var target: int = (d - 1) * 1440 + int(h * 60.0)
	while clk.total_minutes < target:
		clk.advance_minutes(mini(6, target - clk.total_minutes))
		if clk.day() >= 2:
			var f = WorldIface.get_folk(fid)
			if f != null:
				for n in ["hunger", "energy", "bladder", "hygiene"]:
					if f.get_stat_value(n) < 0.0:
						f.add_to_stat(n, 40.0)
		await get_tree().process_frame


func _go() -> void:
	await _w(5)
	m.title.visible = false
	m.start_picker.select("solo")
	m.start_picker._emit_chosen()
	await _w(60)
	clk = get_tree().root.get_node("Clock")
	clk.set_speed(0)
	Events.notification.connect(_note)
	hud = m.hud
	lv = m.find_child("LotView", true, false)
	fid = Pawn.of()
	var spec: Dictionary = Creation.picks.get(fid, {})
	spec["background"] = _bg
	if _bg == "street_kid":
		for t in Story.alive_townies():
			if Story.stage_of(t) == "adult":
				spec["contact_id"] = int(t["id"])
				break
	Creation.picks[fid] = spec
	print("START bg=%s diff=%s coins=%d rent next_cycle=%d share=%s" % [_bg, Scenario.difficulty, Economy.balance(SoloHome.hid()), HousingRent.next_cycle,
		str(SoloHome.prop().get("first_rent_share", "-"))])
	lv.focus_on("folk", fid)
	lv.set_zoom(9.0)
	await _shot("d1_0800_start")
	await _until(1, 9.2)
	await _shot("d1_0910_landlord")
	await _until(1, 11.6)
	await _shot("d1_1135_neighbour")
	LifeHubPhone.app = ""
	hud.phone_dialog.show_for(fid)
	await _shot("d1_1140_phone")
	hud.phone_dialog.visible = false
	if _iv:
		(JobApps.cfg()["interview"] as Dictionary)["chance"] = 1.0          # the review run: always an interview
	var rows: Array = EduJobs.board_for(WorldIface.get_folk(fid)).filter(func(r): return bool(r["qualified"]) and (_job == "" or str(r["career"]) == _job))
	if rows.is_empty() and _job != "":
		EduState.board["openings"][_job] = 1
		rows = EduJobs.board_for(WorldIface.get_folk(fid)).filter(func(r): return str(r["career"]) == _job)
	if not rows.is_empty():
		var r: Dictionary = Commands.run({"folk_id": fid, "action": "life", "args": {"action": "job_apply", "args": {"career": rows[0]["career"]}}})
		print("APPLY %s -> %s" % [rows[0]["career"], str(r)])
	await _until(1, 22.0)
	await _shot("d1_2200_night")
	for d in range(2, 8):
		await _until(d, 12.0)
		print("CAL d%d %s" % [d, str(CalendarBook.entries(fid, 7).map(func(e): return "d%d %s" % [int(e["day"]), str(e["label"])]))])
		if d in [3, 4, 6]:
			LifeHubPhone.app = "calendar"
			hud.phone_dialog.show_for(fid)
			await _shot("d%d_calendar" % d)
			hud.phone_dialog.visible = false
			hud.career_dialog.show_for(fid)
			await _shot("d%d_work" % d)
			hud.career_dialog.visible = false
	await _until(8, 5.1)
	lv.focus_on("folk", fid)
	await _shot("d8_0505_work_note")
	hud.career_dialog.show_for(fid)
	await _shot("d8_0506_work_window")
	hud.career_dialog.visible = false
	await _until(8, 12.0)
	lv.focus_on("folk", fid)
	await _shot("d8_1200")
	print("END job=%s start_day=%s coins=%d" % [Careers.career_of(fid), str(Careers.jobs.get(fid, {}).get("start_day", "-")), Economy.balance(SoloHome.hid())])
	get_tree().quit(0)
